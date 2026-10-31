# VaxTrace NG

**MIT 8103 Advanced Database Systems portfolio**  
**Favour Okoh · 301930463**

VaxTrace NG is a fictional regional vaccine inventory and cold chain network. A depot supplies clinics, staff track sealed vaccine vials by lot and expiry date, and quality reviewers investigate temperature excursions. The system is a teaching case study; its records are synthetic and it is not used for clinical decisions.

PostgreSQL owns operational stock and transfers. The first three portfolio activities are implemented and tested. A planned MongoDB component will hold equipment readings, and a planned distributed database exercise will examine replication and read lag. See [PLAN.md](PLAN.md) for the full deliverables and current boundary.

## What is implemented

- [Portfolio 1](portfolio-1-database-design/README.md): ER model, normalised schema, constraints, deterministic synthetic seed and reconciliation checks.
- [Portfolio 2](portfolio-2-query-optimisation/README.md): five business queries, saved results, repeated execution plans, two indexes and measured analysis.
- [Portfolio 3](portfolio-3-transactions-concurrency/README.md): reserve, dispatch, receive, cancel, rollback, adversarial tests and two-session concurrency proof.

The seed creates 13 facilities, 20 fictional products, 1,000 lots, 3,000 stock balances and 203,000 movements. Each movement count and balance is checked after a clean build. Current stock quantities are sealed vials, never doses. Expired, quarantined and disposed lots remain visible in history but cannot be allocated or dispatched.

## Reproduce the work

Tested on Windows with PostgreSQL 18.6 and Python 3.11. Create a **disposable** database named `vaxtrace_clean` on an isolated local PostgreSQL instance. The supplied `scripts/rebuild_and_verify.ps1` drops and recreates only the `vaxtrace` schema in that database, then loads the seed, indexes and transfer functions and runs all functional tests. It refuses database names outside `vaxtrace_dev`, `vaxtrace_clean`, `vaxtrace_test` and `vaxtrace_verify`.

Example using a local PostgreSQL 18 installation and a test cluster bound to `127.0.0.1:55432`:

```powershell
$pgBin = 'C:\Program Files\PostgreSQL\18\bin'
$cluster = Join-Path $env:TEMP 'vaxtrace_pgdata'
& "$pgBin\initdb.exe" -D $cluster -U vaxtrace -A trust --encoding=UTF8
& "$pgBin\pg_ctl.exe" -D $cluster -o '-p 55432 -c listen_addresses=127.0.0.1' start
& "$pgBin\createdb.exe" -h 127.0.0.1 -p 55432 -U vaxtrace vaxtrace_clean
& .\scripts\rebuild_and_verify.ps1
```

Run `initdb` only if the chosen cluster directory does not already exist. The local test cluster used trust authentication while listening only on loopback. It is an isolated teaching setup, not a deployment configuration. If PostgreSQL is installed elsewhere, pass `-PsqlPath`, `-DbHost`, `-DbPort`, `-DbUser` and `-DbName` to the script. It requires `python` on `PATH` for the two-session test.

For the measured optimisation comparison, start again from a clean schema and seed before creating the two movement indexes. The exact sequence and recorded results are in the Portfolio 2 README. The test server and its data files are local working assets and are not part of this repository.

## Project status and hand-in

The repository is local while GitHub access is being resolved. No GitHub URL or remote access is claimed yet. Portfolio 4, Portfolio 5, the 2-3 page final summary and the Google Form submission remain open. The student will complete the Google Form personally. The form requires a ZIP folder and a separate ReadME upload, each at most 100 MB.

AI assistance was used to draft and test the code and documentation for this working portfolio. Favour must independently review the outputs, understand the design and record what was checked in the final AI Use Declaration. This README does not claim that personal review has happened yet.

## Source material

- Miva Open University, *MIT 8103 Advanced Database Systems: First Semester Continuous Assessment*, September cohort 2026.
- Miva Open University, *Advanced Database Systems* course material.
- Miva Open University, *MIT September 2026 Cohort First Semester Assessment Plan*.
- PostgreSQL Global Development Group, [PostgreSQL 18 documentation](https://www.postgresql.org/docs/18/).
- World Health Organization, [vaccine supply and logistics](https://immunizationdata.who.int/global/wiise-detail-page/vaccine-supply-and-logistics).
- GS1, [EPCIS overview](https://support.gs1.org/support/solutions/articles/43000755325-what-is-electronic-product-code-information-services-epcis-).

Technical references also appear beside the relevant implementation. The fictional products and records are generated for this case study; no external dataset is copied into the database.
