"""Check MongoDB exposure identifiers against PostgreSQL's authoritative lot catalog."""

from __future__ import annotations

import argparse
import subprocess
from pathlib import Path

from pymongo import MongoClient


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--psql", type=Path, default=Path(r"C:\Program Files\PostgreSQL\18\bin\psql.exe"))
    parser.add_argument("--mongo-uri", default="mongodb://127.0.0.1:27018/")
    parser.add_argument("--pg-port", default="55432")
    args = parser.parse_args()
    if args.mongo_uri != "mongodb://127.0.0.1:27018/":
        raise ValueError("This check is limited to the isolated local MongoDB instance")
    statement = ("SELECT p.sku, l.lot_code FROM vaxtrace.lot AS l "
                 "JOIN vaxtrace.product AS p USING (product_id) ORDER BY p.sku, l.lot_code")
    result = subprocess.run([str(args.psql), "-X", "-A", "-t", "-F", "|",
        "-v", "ON_ERROR_STOP=1", "-h", "127.0.0.1", "-p", args.pg_port,
        "-U", "vaxtrace", "-d", "vaxtrace_verify", "-c", statement],
        capture_output=True, text=True, check=True, timeout=30)
    authoritative = {tuple(line.split("|", 1)) for line in result.stdout.splitlines()}
    with MongoClient(args.mongo_uri, serverSelectionTimeoutMS=5000) as client:
        db = client.vaxtrace_portfolio
        exposures = list(db.lot_exposures.find({}, {"product_sku": 1, "lot_code": 1}))
    assert len(exposures) == 2
    for exposure in exposures:
        key = (exposure["product_sku"], exposure["lot_code"])
        assert key in authoritative, f"unknown PostgreSQL lot reference: {key}"
        print("PASS exposure reference", *key)
    print("PASS both MongoDB exposure references match PostgreSQL lots")


if __name__ == "__main__":
    main()
