# Portfolio 5: distributed database exercise

VaxTrace NG uses PostgreSQL as the authority for stock and transfer decisions. This exercise creates a local PostgreSQL streaming standby from a base backup of the primary. The standby provides read-only copies of the same database. It is a replication demonstration, not a cloud deployment or an automatic failover system.

## Reproduce

The primary must be an isolated PostgreSQL 18 test cluster on `127.0.0.1:55432`, with `wal_level=replica`, a replication connection permitted from loopback, and a disposable `vaxtrace_verify` database populated by the root rebuild script. Run:

```powershell
python portfolio-5-distributed-cloud/01_replication_demo.py --data-dir work/standby_run1
```

The data directory must be a **new, empty** subdirectory of the repository's ignored `work/` directory. The script never deletes a standby directory. It creates a base backup with `pg_basebackup -R`, starts a standby on `127.0.0.1:55433`, checks streaming state and its 3,000 stock balances, and proves it rejects a write. It then pauses WAL replay, commits a unique probe on the primary, verifies that the probe is absent on the standby, resumes replay, and waits until the probe appears. The script stops the standby when finished, including after a failed assertion.

## Consistency and limits

The paused replay is a **controlled lag demonstration**. It shows why a replica read can be stale; it does not measure ordinary network or disk lag. Inventory reservation, dispatch, receipt, and quality decisions must read and write on the primary in this design. Read-only historical reports can use the standby if they tolerate lag or first check replay position. Asynchronous replication does not guarantee that a just-committed transaction is immediately visible on the standby. This exercise does not implement failover, synchronous replication, sharding or cloud hosting.

The evidence in `evidence/replication-run1.txt` and `replication-run2.txt` records separate base backups and the primary/standby checks. The LSN values show that replay advanced after the pause; they are not latency measurements. The probe table is in the disposable `vaxtrace_verify` database, and no stock quantity is changed by the exercise.

Reference: PostgreSQL, [Log-Shipping Standby Servers](https://www.postgresql.org/docs/18/warm-standby.html), including streaming replication and standby operation.
