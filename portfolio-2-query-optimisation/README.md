# Portfolio 2: query processing and optimisation

The queries answer stock and audit questions for VaxTrace NG. `01_queries.sql` returns eligible depot lots, clinic stock, a named lot's latest movements, a clinic's latest movements, and transfer counts. The date in stock-eligibility reports is fixed at 2026-10-31 so that the seed has stable expected results. Operational allocation in Portfolio 3 uses the actual transaction date.

## Reproduce the comparison

Start from a clean build of Portfolio 1, with no secondary movement indexes. Run `ANALYZE vaxtrace.stock_movement`, then execute `02_benchmark.sql` five times and save the output. Run `03_indexes.sql`. Execute `02_benchmark.sql` another five times to isolate the effect of the indexes. Then execute `04_benchmark_optimised.sql` five times to measure the index and query-shape combination. Run `01_queries.sql` before and after indexing and compare the result files byte for byte.

The captured runs are in `evidence/`. Each `RUN` block is a separate invocation of `psql` on the same local PostgreSQL 18.6 server. The host was not otherwise isolated, so these are demonstration timings rather than production benchmarks.

## Measured results

The synthetic database held 203,000 stock movements and 3,000 stock balances. Median execution time over five runs, in milliseconds:

| Query | Baseline join, no secondary index | Same join, with indexes | Scalar lookup, with indexes |
| --- | ---: | ---: | ---: |
| Named lot, latest 50 movements | 186.677 | 1.170 | 0.298 |
| Named clinic, latest 50 movements | 181.999 | 40.393 | 0.294 |

The baseline plans used a parallel sequential scan of the movement table and a top-N sort. The lot index changed the lot query to a bitmap index scan, although the join still sorted its result. The clinic index reduced work but the join still fetched about 11,301 clinic rows and sorted them. The scalar lookup made the facility or product/lot ID an InitPlan result, allowing an ordered index scan to stop at 50 rows. The final plans show that both indexes were actually used. The full query output was identical before and after indexing (matching SHA-256: `242C836621A5FCD0079D8CF7106582ABEB4F5AC56284E7DD9BE2814F48E1D4B4`).

The movement table occupied about 27 MB. Each new index occupied about 8 MB in this build. These indexes improve the demonstrated read patterns but add storage and write maintenance. The timing includes cache and planner effects on one Windows laptop; it does not establish performance for other data distributions or hardware. The fixed test date and artificial historical cycles are part of the reproducible workload, not claims about actual vaccine operations.

## Evidence and references

- `evidence/baseline-plans.txt`: five baseline plans.
- `evidence/index-only-plans.txt`: five plans after indexes, with the original joins.
- `evidence/indexed-plans.txt`: five plans after indexes and scalar lookups.
- `evidence/query-results-before.txt` and `query-results-after.txt`: unchanged outputs.
- PostgreSQL, [Using EXPLAIN](https://www.postgresql.org/docs/18/using-explain.html).
- PostgreSQL, [Multicolumn Indexes](https://www.postgresql.org/docs/18/indexes-multicolumn.html).
- Miva Open University, *Advanced Database Systems*, Study Session Four, sections 4.1.2 and 4.1.3 on query optimisation and execution plans.
