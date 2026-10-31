# Portfolio 4: NoSQL document model

VaxTrace NG records cold-chain observations in MongoDB. PostgreSQL remains the authority for products, lots, facilities, stock balances and transfers. The document model stores equipment, sensor readings and equipment-to-lot exposure windows. A temperature excursion is a review signal; it does not automatically quarantine a lot or alter stock.

## Model and ownership

| Collection | Document key | Main fields | Purpose |
| --- | --- | --- | --- |
| `equipment` | Stable equipment code | Facility code, minimum and maximum Celsius | Sensor identity and permitted range |
| `sensor_readings` | Device reading ID | Equipment code, observation time, receipt time, Celsius | Append-only telemetry ingested from devices |
| `lot_exposures` | Exposure ID | Equipment code, product SKU, lot code, start and end | Snapshot of which lot occupied equipment during a time window |

The equipment code and observation time have a unique compound index, preventing duplicate samples for the same instant. The same index serves the equipment history query in timestamp order. JSON Schema validators reject missing required fields and temperatures outside a physically plausible range. The ingestion function checks equipment existence and rejects receipt times before observation times. The exposure's product and lot codes are references to PostgreSQL business identities, not a second stock record. Cross-database foreign keys do not exist. The separate cross-store check compares the two exposure references with PostgreSQL's lot catalog.

This is a document model rather than a MongoDB time series collection. The small portfolio needs strict duplicate rejection on the equipment and observation pair, schema validation, and a simple reproducible query. A time series collection could improve storage efficiency at higher ingest volume, subject to its index and update restrictions.

## Build and query

Install the pinned Python dependency with `python -m pip install -r portfolio-4-nosql/requirements.txt`. Start a disposable local MongoDB server on `127.0.0.1:27018`, then run:

```powershell
python portfolio-4-nosql/01_load_and_verify.py --reset
python portfolio-4-nosql/01_load_and_verify.py
python portfolio-4-nosql/02_verify_postgres_refs.py
```

`--reset` drops only the local `vaxtrace_portfolio` database and recreates its collections. The script rejects remote and authenticated URIs. The second command verifies the existing database without changing it. The seed has three pieces of equipment, two exposure windows and 288 readings at 15-minute intervals. The lot exposure query filters readings by equipment and **observation** time. It reports two depot excursions for `VX-001 / LOT-000001`. The 06:30 reading arrives at 11:00 but still belongs to the correct exposure window. The clinic control lot has no excursion.

The verification checks the query plan uses `equipment_observed_unique`, then attempts duplicate IDs, duplicate equipment/timestamp pairs, missing and invalid temperatures, unknown equipment and reversed timestamps. Rejected writes leave the document count unchanged. See `evidence/mongo-clean-build.txt`, `mongo-verification.txt` and `cross-store-references.txt` for actual output.

This model does not implement an automated quality-review or stock-hold workflow. A reviewer would assess the exposure and use an authorised PostgreSQL operation to change lot quality status where warranted.

References: MongoDB, [Schema Validation](https://www.mongodb.com/docs/manual/core/schema-validation/specify-json-schema/); MongoDB, [PyMongo Indexes](https://www.mongodb.com/docs/languages/python/pymongo-driver/current/indexes/); MongoDB, [Time Series Collection Considerations](https://www.mongodb.com/docs/manual/core/timeseries/timeseries-considerations/).
