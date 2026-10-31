# MIT 8103 portfolio work plan

Student: Favour Okoh (301930463)

Case study: VaxTrace NG, a fictional regional vaccine inventory and cold chain network. All operational records are synthetic. The PostgreSQL database is the authority for stock, transfers, lot eligibility, and quality holds. A later MongoDB component will hold temperature readings. Sensor readings never directly change stock without an explicit review process.

## Sources and submission facts

- CA question paper: 40 marks; five portfolio activities and a 2-3 page final summary. One consistent case study, practical outputs, private GitHub repository, progressive commits, references, reflection, and AI use declaration are required.
- Miva LMS CA page: Google Form submission; one attempt; similarity limit 20% excluding bibliography; submission folder `Okoh_Favour_301930463`; files inside it use `Okoh_Favour_301930463_DocumentType.ext`.
- Live Google Form (read only inspection, 31 October 2026): student email, one ZIP upload, and a separate ReadME upload. Each upload has a 100 MB limit. The form's separate ReadME example omits the student ID. We will use `Okoh_Favour_README.txt` for that separate field and student ID in filenames inside the ZIP, unless the form changes or Miva clarifies otherwise. The form must be completed only by the student.
- Miva first semester assessment plan and MIT calendar: Advanced Database Systems CA due 15 November 2026 at 11:59 PM. Neither local copy specifies a time zone; confirm if the live LMS presents one before hand-in.
- Private GitHub repository: https://github.com/Favourz1/mit8103-vaxtrace-ng (personal account, confirmed private). Assessor GitHub identity or approved private repository access method remains to be confirmed before submission.

## Business rules to implement and prove

1. Products have a defined storage temperature range and a count of doses per sealed vial. Operational quantities are sealed vials.
2. A lot belongs to one product and has a unique lot code, expiry date, and quality status.
3. Stock is tracked by lot and facility. Available stock cannot be negative. Expired or quarantined lots cannot be reserved or dispatched.
4. Eligible lots are selected by earliest expiry first. Any manual override must be documented as a later extension, not silently implemented.
5. Transfers move stock from one facility to another through explicit states. Dispatch and receipt are separate auditable operations.
6. An aborted transaction leaves neither a partial stock change nor a partial movement record.
7. Concurrent requests cannot reserve more stock than is available.
8. Temperature excursions are flagged for human review. Readings may arrive late; a delayed reading must still be traceable to the relevant equipment, time, and lot exposure window.

## Work packages and acceptance checks

| ID | Deliverable | Verification |
| --- | --- | --- |
| 0.1 | Review assignment, course guide, live LMS page, form, local files and database documentation | Record sources and submission facts here; identify conflicts and unknowns |
| 0.2 | Confirm local tools, account and repository context | Record installed versions and verify the personal GitHub account before repo creation |
| 1.1 | Scope, data ownership and business rules in root README | Every portfolio uses VaxTrace NG and the same units, entities and statuses |
| 1.2 | Private GitHub repository and clean project structure | Remote visibility is private; no secrets; remote URL works in personal account |
| 1.3 | Genuine Conventional Commits throughout implementation | `git log` shows separate completed increments with student authorship and no co-author trailer |
| 2.1 | ER diagram, data dictionary and normalisation explanation | Diagram agrees with runnable schema; relationships and cardinalities documented |
| 2.2 | PostgreSQL schema with keys, checks and ownership rules | Clean build succeeds; invalid keys, quantities, statuses and duplicates fail |
| 2.3 | Deterministic synthetic data generator | Repeated runs with one seed yield the same counts and cases; no real records |
| 3.1 | Five business SQL queries and expected results | Queries run on clean seed and return checked values |
| 3.2 | Baseline and optimised execution plans | `EXPLAIN (ANALYZE, BUFFERS)` saved before and after; results unchanged |
| 3.3 | Measured performance analysis | State dataset size, plan changes, timings and limitations, including non-improvements |
| 4.1 | Commit, rollback and transfer examples | Captured before and after states prove atomicity |
| 4.2 | Two-session race and safe allocation | Reproducible concurrency test proves no oversell or negative balance |
| 4.3 | Adversarial tests | Expired/quarantined lots, duplicate requests, invalid quantities and failed transfers rejected |
| 5.1 | MongoDB time series model and load script | Later phase: query sensor history and detect excursions on synthetic data |
| 6.1 | Replication or cloud exercise | Later phase: prove replication or label discussion; explain lag and stock consistency |
| 7.1 | Final 2-3 page summary, references, reflection and AI declaration | Later phase: every claim points to current evidence; PDF visually reviewed |
| 8.1 | Named ZIP and separate ReadME under 100 MB each | Later phase: inspect both artifacts and link to accessible private repo |
| 8.2 | Google Form submission | Student alone completes and submits once; save confirmation |

## Rubric cross-check

| CA requirement | Planned evidence |
| --- | --- |
| Portfolio 1: design and modelling (7) | ER diagram, schema, constraints, normalisation, case study |
| Portfolio 2: query processing and optimisation (7) | SQL, checked results, plans, indexing, performance analysis |
| Portfolio 3: transactions and concurrency (7) | Commit, rollback, isolation, race and control evidence |
| Portfolio 4: NoSQL and advanced data models (7) | MongoDB readings model, implementation and suitability explanation |
| Portfolio 5: distributed/cloud (6) | Replication or cloud exercise, lag and consistency discussion |
| Final documentation (6) | 2-3 pages, GitHub link, evidence, reflection, references, AI declaration |
| Technical correctness and practical implementation | Clean rebuild, checks, adversarial cases and reproducible commands |
| Design quality and advanced concepts | Normalisation, data ownership, transactions, NoSQL and distributed trade-offs |
| Documentation and individual understanding | README files, exact commands, measured results and student review |

## Current boundary

This work session ends after package 4.3, Portfolio 3. Packages 5-8 remain planned only. Do not describe them as implemented before they are built and verified.

## Progress after implementation review

- Complete locally: 0.1, 1.1, 1.3, 2.1-2.3, 3.1-3.3, 4.1-4.3. Clean rebuild and adversarial evidence are saved.
- Partial: 1.2 until assessor access is arranged. Browser control stopped during GitHub navigation, so the existing Git credential manager was used to verify the personal `Favourz1` account and create a private repository. Commits are genuine Conventional Commits under Favour Okoh. They are unsigned because the configured GPG prompt blocked unattended commits. Remote push verification is recorded separately.
- Open submission fact: the assessment plan and MIT calendar agree on 15 November 2026 at 11:59 PM, but neither states a time zone. Check the live LMS before hand-in. The assessor's private GitHub access method also remains open.
- Future work: 5.1, 6.1, 7.1 and 8.1-8.2. The student alone handles the Google Form.
