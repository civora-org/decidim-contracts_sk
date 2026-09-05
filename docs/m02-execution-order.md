# Milestone 02 — Contracts MVP Execution Order

Dependency-driven order for the M02 tasks tracked in [`civora-org/civora-platform`](https://github.com/civora-org/civora-platform) (milestone "02 Contracts MVP"). Parents: #6–#12; epic: #3. Terminal deliverable: **decidim-contracts_sk v1.0.0** (#69).

## Order

| # | Task | Depends on |
|---|------|------------|
| 1 | ✅ [#53](https://github.com/civora-org/civora-platform/issues/53) M02-01-A: lifecycle state machine + transition rules — **shipped (PR #24, v0.7.0)** | — |
| 2 | ✅ [#54](https://github.com/civora-org/civora-platform/issues/54) M02-01-B: roles → Decidim permissions mapping — **shipped (PR #26, v0.8.0)** | #53 |
| 3 | ✅ [#55](https://github.com/civora-org/civora-platform/issues/55) M02-02-A: Contract model + migration — **shipped (PR #28, v0.9.0)**; provenance columns + `ContractState` concern + `:db` spec toggle included | #53 |
| 3a | ✅ [#70](https://github.com/civora-org/civora-platform/issues/70) contracts data dictionary — **done**; lives in the platform repo at `docs/01-discovery/CONTRACTS-DATA-DICTIONARY.md` (pointer PR #30) | — |
| 3b | [#71](https://github.com/civora-org/civora-platform/issues/71) EPIC (V0.2 direction): CRZ import, Decidim component, project links — decompose after #70; consumes #55's provenance columns | #70 |
| 4 | ✅ [#56](https://github.com/civora-org/civora-platform/issues/56) M02-02-B: Party + Document models — **shipped**; real FKs onto contracts, role/kind vocabularies, nullable file metadata (validation deferred to #64) | #55 |
| 5 | ✅ [#57](https://github.com/civora-org/civora-platform/issues/57) M02-02-C: Amendment + AuditEvent models — **shipped**; append-only audit trail, unique `(contract, version)` amendments, shared `:db` spec support extracted | #55 |
| 6 | ✅ [#61](https://github.com/civora-org/civora-platform/issues/61) M02-04-A: Stage-1 dummy app harness + request specs — **shipped (PR #34, v0.11.0)** | — |
| 7 | ✅ [#58](https://github.com/civora-org/civora-platform/issues/58) M02-03-A: admin CRUD (editor scope) — **shipped (PR #36, v0.12.0)** | #54, #55, #61 |
| 8 | ✅ [#59](https://github.com/civora-org/civora-platform/issues/59) M02-03-B: admin lifecycle transitions — **shipped (PR #38, v0.13.0)**; six table-derived transitions, atomic state+audit writes | #58 |
| 8a | ✅ [#75](https://github.com/civora-org/civora-platform/issues/75) M02-02-D: contract content fields migration + admin form — **added by the 2026-09-04 v1.0.0 scope review**; the data dictionary's "Planned V0.1" fields (subject/amount/dates/`crz_url`/`published_at`) were owned by no downstream issue; deps already shipped → **shipped (PR #41, v0.14.0)** | #55, #58 |
| 8b | ✅ [#76](https://github.com/civora-org/civora-platform/issues/76) M02-03-D: admin party management — same review; the data-entry layer under #63's party rendering (model shipped in #56, form deliberately narrow in #58) — **shipped (PR #43, v0.15.0)** | #56, #58, #75 |
| 9 | 🔜 [#62](https://github.com/civora-org/civora-platform/issues/62) M02-04-B: public catalogue index — **in PR #45** (open); published-only, org-scoped (Gate-1 fold-in), localized empty state, no pagination | #55, #61 |
| 10 | 🔜 [#63](https://github.com/civora-org/civora-platform/issues/63) M02-04-C: public detail page — **in PR #45** (open); content fields + parties, indistinguishable 404 for unpublished/archived/foreign-org/missing ids; documents/amendments deferred to M02-05 | #62, #75, #76 |
| 10a | [#73](https://github.com/civora-org/civora-platform/issues/73) M02-05-A0: document upload + storage wiring — **added by the 2026-09-04 M02 consistency review**; the upload/storage/admin-UI layer between #56's metadata-only skeleton and #64's validation was unowned | #56, #58, #63 |
| 10b | [#74](https://github.com/civora-org/civora-platform/issues/74) M02-05-C: CRZ handoff export — generated prepared PDF for the manual CRZ handoff (ADR-002 "metadata export"); stored as `Document` kind `crz_export` | #73, #75 |
| 11 | [#60](https://github.com/civora-org/civora-platform/issues/60) M02-03-C: seeded end-to-end admin scenario | #59, #62 |
| 12 | [#64](https://github.com/civora-org/civora-platform/issues/64) M02-05-A: document attachment safe validation | #56, #73 |
| 13 | [#65](https://github.com/civora-org/civora-platform/issues/65) M02-05-B: amendments + public version history (scope clarified 2026-09-04: admin creation of amendments lives here) | #57, #63, #64 |
| 14 | [#66](https://github.com/civora-org/civora-platform/issues/66) M02-06-A: Slovak localization completeness | after feature freeze of #58–#65 and #73–#76 |
| 15 | [#67](https://github.com/civora-org/civora-platform/issues/67) M02-06-B: a11y/UX review + QA checklist | #66 |
| 16 | [#68](https://github.com/civora-org/civora-platform/issues/68) M02-07-A: demo seeds + walkthrough | #60, #63, #74 |
| 17 | [#69](https://github.com/civora-org/civora-platform/issues/69) M02-07-B: coverage sweep, docs + v1.0.0 release | everything above |

## Notes

- Parallelizable: #61 (harness) can start immediately alongside #53; model tasks (#55–#57) are independent of admin/public work once #53 lands.
- Process lesson applies: before planning model/admin tasks, diff task assumptions against the current tree and against `docs/00-product/` on the platform repo — the product boundary (ADR-002, manual CRZ handoff) lives there (see `docs/contracts-domain-notes.md`).
- Closing parents #6–#12 closes epic #3 and milestone "02 Contracts MVP"; #69 is the release gate.
