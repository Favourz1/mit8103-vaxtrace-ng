# Portfolio 1: database design and modelling

The model stores operational vaccine inventory in PostgreSQL. Quantities are **sealed vials**. A product records doses per vial for reporting, but stock transactions never mix doses with vials. Every lot belongs to one product. A stock balance represents one lot at one facility. Transfers reserve stock before dispatch and record receipt separately. `stock_movement` is an append-only audit ledger; each operation writes its balance change and movement in one transaction.

## Model

```mermaid
erDiagram
    FACILITY ||--o{ STOCK_BALANCE : holds
    PRODUCT ||--o{ LOT : has
    LOT ||--o{ STOCK_BALANCE : counted_at
    FACILITY ||--o{ TRANSFER : sends
    FACILITY ||--o{ TRANSFER : receives
    TRANSFER ||--o{ TRANSFER_LINE : contains
    LOT ||--o{ TRANSFER_LINE : moved_on
    FACILITY ||--o{ STOCK_MOVEMENT : records
    LOT ||--o{ STOCK_MOVEMENT : concerns
    TRANSFER |o--o{ STOCK_MOVEMENT : explains
```

The transfer header holds the source, destination, state and times. Transfer lines hold the lots and quantities. This avoids repeating header data when a transfer has several lines. Product attributes stay in `product`, lot attributes stay in `lot`, and facility attributes stay in `facility`. The balance key `(facility_id, lot_id)` determines both quantity columns. These dependencies keep the operational tables in third normal form. The balance is a deliberate materialisation of the movement ledger for fast allocation; reconciliation checks compare it with movement sums.

| Relation | Key and main references | Purpose |
| --- | --- | --- |
| `facility` | `facility_id` PK, `code` unique | Depot or clinic identity |
| `product` | `product_id` PK, `sku` unique | Product name, vial size and permitted storage range |
| `lot` | `lot_id` PK, `product_id` FK, `(product_id, lot_code)` unique | Batch identity, expiry and quality status |
| `stock_balance` | `(facility_id, lot_id)` PK and FKs | Current on-hand and reserved vials |
| `transfer` | `transfer_id` PK, `request_key` unique, two facility FKs | Shipment intent and state |
| `transfer_line` | `(transfer_id, lot_id)` PK and FKs | One lot and quantity within a transfer |
| `stock_movement` | `movement_id` PK; facility, lot and optional transfer FKs | Append-only changes to stock or reservation |

The database allows an empty transfer header during a transaction; the `request_transfer` function inserts its first line in the same atomic statement. Application operations use the functions. The database owner retains direct table access for setup and maintenance.

## Constraints and boundaries

- Primary and foreign keys reject missing references. Unique codes and request keys reject duplicate business identities.
- Checks enforce positive line quantities, nonnegative balances, `reserved <= on_hand`, distinct transfer endpoints, ordered timestamps and valid states.
- A lot's `quality_status` is explicit. A quarantined or disposed lot needs a quality note. Time-dependent eligibility, including expiry, is checked inside allocation functions because a static check constraint cannot depend on today's date.

## Rebuild

Run `01_schema.sql` against an empty or disposable PostgreSQL 18 database. It drops and recreates only the `vaxtrace` schema. Run `02_seed.sql`, `03_verify.sql` and `04_constraint_tests.sql` in order. The root `scripts/rebuild_and_verify.ps1` runs the complete sequence and saves clean-build evidence.

References: Miva Open University, *Advanced Database Systems*, Study Session One, section 1.1.7 on normalisation; PostgreSQL, [Data Definition](https://www.postgresql.org/docs/18/ddl.html); WHO, [vaccine supply and logistics](https://immunizationdata.who.int/global/wiise-detail-page/vaccine-supply-and-logistics).
