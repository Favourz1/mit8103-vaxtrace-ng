"""Build and verify VaxTrace NG's synthetic cold-chain document model."""

from __future__ import annotations

import argparse
import json
from datetime import datetime, timedelta, timezone
from urllib.parse import urlparse

from pymongo import ASCENDING, DESCENDING, MongoClient
from pymongo.errors import DuplicateKeyError, OperationFailure


DB_NAME = "vaxtrace_portfolio"
DAY = datetime(2026, 10, 31, tzinfo=timezone.utc)


def check_local_uri(uri: str) -> None:
    parsed = urlparse(uri)
    if parsed.scheme != "mongodb" or parsed.hostname not in {"127.0.0.1", "localhost"}:
        raise ValueError("Only a local mongodb://127.0.0.1 or localhost server is allowed")
    if parsed.username or parsed.password or "," in parsed.netloc:
        raise ValueError("This disposable demonstration accepts one local server without credentials")


def make_collections(db) -> None:
    db.create_collection("equipment", validator={"$jsonSchema": {
        "bsonType": "object", "required": ["_id", "facility_code", "minimum_c", "maximum_c"],
        "properties": {
            "_id": {"bsonType": "string"}, "facility_code": {"bsonType": "string"},
            "minimum_c": {"bsonType": "double"}, "maximum_c": {"bsonType": "double"},
        },
    }}, validationAction="error")
    db.create_collection("lot_exposures", validator={"$jsonSchema": {
        "bsonType": "object", "required": ["_id", "equipment_id", "product_sku", "lot_code", "from_at", "to_at"],
        "properties": {
            "_id": {"bsonType": "string"}, "equipment_id": {"bsonType": "string"},
            "product_sku": {"bsonType": "string"}, "lot_code": {"bsonType": "string"},
            "from_at": {"bsonType": "date"}, "to_at": {"bsonType": "date"},
        },
    }}, validationAction="error")
    db.create_collection("sensor_readings", validator={"$jsonSchema": {
        "bsonType": "object", "required": ["_id", "equipment_id", "observed_at", "received_at", "temperature_c"],
        "properties": {
            "_id": {"bsonType": "string"}, "equipment_id": {"bsonType": "string"},
            "observed_at": {"bsonType": "date"}, "received_at": {"bsonType": "date"},
            "temperature_c": {"bsonType": "double", "minimum": -40.0, "maximum": 60.0},
        },
    }}, validationAction="error")
    db.sensor_readings.create_index(
        [("equipment_id", ASCENDING), ("observed_at", ASCENDING)],
        name="equipment_observed_unique", unique=True,
    )
    db.lot_exposures.create_index(
        [("equipment_id", ASCENDING), ("from_at", ASCENDING)],
        name="equipment_window",
    )


def ingest(db, reading: dict) -> None:
    if db.equipment.count_documents({"_id": reading["equipment_id"]}, limit=1) != 1:
        raise ValueError("unknown equipment")
    if reading["received_at"] < reading["observed_at"]:
        raise ValueError("receipt cannot precede observation")
    db.sensor_readings.insert_one(reading)


def add_exposure(db, exposure: dict) -> None:
    if db.equipment.count_documents({"_id": exposure["equipment_id"]}, limit=1) != 1:
        raise ValueError("unknown exposure equipment")
    if exposure["from_at"] >= exposure["to_at"]:
        raise ValueError("exposure window must have positive duration")
    db.lot_exposures.insert_one(exposure)


def load_seed(db) -> None:
    db.equipment.insert_many([
        {"_id": "DEPOT-COLD-01", "facility_code": "DEPOT", "minimum_c": 2.0, "maximum_c": 8.0},
        {"_id": "CLINIC01-COLD-01", "facility_code": "CLINIC01", "minimum_c": 2.0, "maximum_c": 8.0},
        {"_id": "CLINIC02-COLD-01", "facility_code": "CLINIC02", "minimum_c": 2.0, "maximum_c": 8.0},
    ])
    add_exposure(db, {"_id": "EXP-001", "equipment_id": "DEPOT-COLD-01",
        "product_sku": "VX-001", "lot_code": "LOT-000001", "from_at": DAY,
        "to_at": DAY + timedelta(hours=12)})
    add_exposure(db, {"_id": "EXP-002", "equipment_id": "CLINIC01-COLD-01",
        "product_sku": "VX-002", "lot_code": "LOT-000002", "from_at": DAY,
        "to_at": DAY + timedelta(days=1)})
    for equipment in db.equipment.find():
        for slot in range(96):
            observed = DAY + timedelta(minutes=15 * slot)
            received = observed + timedelta(minutes=2)
            temperature = 4.0 + (slot % 5) * 0.2
            if equipment["_id"] == "DEPOT-COLD-01" and slot in (26, 28):
                temperature = 8.8 if slot == 26 else 9.2
            if equipment["_id"] == "DEPOT-COLD-01" and slot == 26:
                received = DAY + timedelta(hours=11)
            ingest(db, {
                "_id": f"{equipment['_id']}-{slot:03d}",
                "equipment_id": equipment["_id"], "observed_at": observed,
                "received_at": received, "temperature_c": float(temperature),
            })


def expect_rejection(label: str, operation, errors: tuple[type[Exception], ...]) -> None:
    try:
        operation()
    except errors:
        print(f"PASS {label}: rejected")
        return
    raise AssertionError(f"{label}: invalid write succeeded")


def verify(db) -> None:
    counts = {name: db[name].count_documents({}) for name in
              ("equipment", "lot_exposures", "sensor_readings")}
    assert counts == {"equipment": 3, "lot_exposures": 2, "sensor_readings": 288}, counts
    print("COUNTS", json.dumps(counts, sort_keys=True))

    exposure = db.lot_exposures.find_one({"_id": "EXP-001"})
    equipment = db.equipment.find_one({"_id": exposure["equipment_id"]})
    query = {"equipment_id": equipment["_id"], "observed_at": {
        "$gte": exposure["from_at"], "$lt": exposure["to_at"]}}
    history = list(db.sensor_readings.find(query).sort("observed_at", ASCENDING))
    assert len(history) == 48, len(history)
    excursions = list(db.sensor_readings.aggregate([
        {"$match": query},
        {"$lookup": {"from": "equipment", "localField": "equipment_id",
                     "foreignField": "_id", "as": "equipment"}},
        {"$unwind": "$equipment"},
        {"$match": {"$expr": {"$or": [
            {"$lt": ["$temperature_c", "$equipment.minimum_c"]},
            {"$gt": ["$temperature_c", "$equipment.maximum_c"]},
        ]}}},
        {"$sort": {"observed_at": 1}},
    ]))
    assert [(r["observed_at"].hour, r["observed_at"].minute) for r in excursions] == [(6, 30), (7, 0)]
    print("LOT EXPOSURE", exposure["product_sku"], exposure["lot_code"],
          "readings", len(history), "excursions", len(excursions))
    for reading in excursions:
        print("EXCURSION", reading["_id"], reading["observed_at"].isoformat(),
              reading["received_at"].isoformat(), reading["temperature_c"])
    delayed = next(r for r in excursions if r["_id"].endswith("-026"))
    assert delayed["observed_at"] == DAY + timedelta(hours=6, minutes=30)
    assert delayed["received_at"] == DAY + timedelta(hours=11)
    assert delayed["received_at"] > exposure["to_at"] - timedelta(hours=1, minutes=1)
    print("PASS delayed arrival: matched by observation time, received 4h30m later")
    late = list(db.sensor_readings.aggregate([
        {"$match": query},
        {"$match": {"$expr": {"$gt": [
            {"$subtract": ["$received_at", "$observed_at"]}, 3600000,
        ]}}},
    ]))
    assert [r["_id"] for r in late] == ["DEPOT-COLD-01-026"]
    print("PASS late-arrival query: one reading exceeded one hour")
    other = db.lot_exposures.find_one({"_id": "EXP-002"})
    other_equipment = db.equipment.find_one({"_id": other["equipment_id"]})
    other_readings = list(db.sensor_readings.find({"equipment_id": other_equipment["_id"],
        "observed_at": {"$gte": other["from_at"], "$lt": other["to_at"]}}))
    assert len(other_readings) == 96
    assert all(other_equipment["minimum_c"] <= r["temperature_c"] <= other_equipment["maximum_c"]
               for r in other_readings)
    print("PASS control lot: 96 readings, no excursion")

    plan = db.sensor_readings.find(query).sort("observed_at", ASCENDING).explain()
    plan_text = json.dumps(plan["queryPlanner"]["winningPlan"], default=str)
    assert "equipment_observed_unique" in plan_text, plan_text
    print("QUERY PLAN", plan_text)

    existing = db.sensor_readings.find_one({"_id": "DEPOT-COLD-01-026"})
    expect_rejection("duplicate reading id", lambda: db.sensor_readings.insert_one(existing),
                     (DuplicateKeyError,))
    second_id = dict(existing, _id="new-id")
    expect_rejection("duplicate equipment and observation", lambda: db.sensor_readings.insert_one(second_id),
                     (DuplicateKeyError,))
    invalid = dict(existing, _id="invalid-temp", observed_at=DAY + timedelta(days=2),
                   received_at=DAY + timedelta(days=2, minutes=2), temperature_c=200.0)
    expect_rejection("invalid temperature", lambda: db.sensor_readings.insert_one(invalid),
                     (OperationFailure,))
    missing = dict(invalid, _id="missing-temp")
    del missing["temperature_c"]
    expect_rejection("missing temperature", lambda: db.sensor_readings.insert_one(missing),
                     (OperationFailure,))
    unknown = dict(existing, _id="unknown-equipment", equipment_id="UNKNOWN",
                   observed_at=DAY + timedelta(days=2), received_at=DAY + timedelta(days=2, minutes=2))
    expect_rejection("unknown equipment", lambda: ingest(db, unknown), (ValueError,))
    reversed_time = dict(existing, _id="reversed-time", observed_at=DAY + timedelta(days=2),
                         received_at=DAY + timedelta(days=1))
    expect_rejection("receipt before observation", lambda: ingest(db, reversed_time), (ValueError,))
    bad_exposure = dict(exposure, _id="bad-exposure", equipment_id="UNKNOWN")
    expect_rejection("unknown exposure equipment", lambda: add_exposure(db, bad_exposure), (ValueError,))
    reversed_exposure = dict(exposure, _id="reversed-exposure", from_at=DAY + timedelta(days=1))
    expect_rejection("reversed exposure window", lambda: add_exposure(db, reversed_exposure), (ValueError,))
    assert db.sensor_readings.count_documents({}) == 288
    assert db.lot_exposures.count_documents({}) == 2
    print("PASS final document count unchanged after rejected writes")
    print("PASS no stock mutation: MongoDB collections contain telemetry and exposure references only")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--uri", default="mongodb://127.0.0.1:27018/")
    parser.add_argument("--reset", action="store_true", help="drop only the disposable local portfolio database")
    args = parser.parse_args()
    check_local_uri(args.uri)
    with MongoClient(args.uri, serverSelectionTimeoutMS=5000, tz_aware=True) as client:
        info = client.server_info()
        print("MongoDB", info["version"])
        db = client[DB_NAME]
        if args.reset:
            client.drop_database(DB_NAME)
            make_collections(db)
            load_seed(db)
        verify(db)
    print("PASS document model verification")


if __name__ == "__main__":
    main()
