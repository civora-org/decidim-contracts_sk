# Milestone 02 — Contracts MVP Execution Order

Dependency-driven order for the M02 tasks tracked in [`civora-org/civora-platform`](https://github.com/civora-org/civora-platform) (milestone "02 Contracts MVP"). Parents: #6–#12; epic: #3. Terminal deliverable: **decidim-contracts_sk v1.0.0** (#69).

## Order

| # | Task | Depends on |
|---|------|------------|
| 1 | [#53](https://github.com/civora-org/civora-platform/issues/53) M02-01-A: lifecycle state machine + transition rules | — |
| 2 | [#54](https://github.com/civora-org/civora-platform/issues/54) M02-01-B: roles → Decidim permissions mapping | #53 |
| 3 | ✅ [#55](https://github.com/civora-org/civora-platform/issues/55) M02-02-A: Contract model + migration — **shipped (PR #28, v0.9.0)**; provenance columns + `ContractState` concern + `:db` spec toggle included | #53 |
| 3a | [#70](https://github.com/civora-org/civora-platform/issues/70) contracts data dictionary (fills the #20 spike placeholder) | — (before #56/#58 field work) |
| 3b | [#71](https://github.com/civora-org/civora-platform/issues/71) EPIC (V0.2 direction): CRZ import, Decidim component, project links — decompose after #70; consumes #55's provenance columns | #70 |
| 4 | ✅ [#56](https://github.com/civora-org/civora-platform/issues/56) M02-02-B: Party + Document models — **shipped**; real FKs onto contracts, role/kind vocabularies, nullable file metadata (validation deferred to #64) | #55 |
| 5 | [#57](https://github.com/civora-org/civora-platform/issues/57) M02-02-C: Amendment + AuditEvent models | #55 |
| 6 | [#61](https://github.com/civora-org/civora-platform/issues/61) M02-04-A: Stage-1 dummy app harness + request specs | — (early, unblocks request specs) |
| 7 | [#58](https://github.com/civora-org/civora-platform/issues/58) M02-03-A: admin CRUD (editor scope) | #54, #55, #61 |
| 8 | [#59](https://github.com/civora-org/civora-platform/issues/59) M02-03-B: admin lifecycle transitions | #58 |
| 9 | [#62](https://github.com/civora-org/civora-platform/issues/62) M02-04-B: public catalogue index | #55, #61 |
| 10 | [#63](https://github.com/civora-org/civora-platform/issues/63) M02-04-C: public detail page | #62 |
| 11 | [#60](https://github.com/civora-org/civora-platform/issues/60) M02-03-C: seeded end-to-end admin scenario | #59, #62 |
| 12 | [#64](https://github.com/civora-org/civora-platform/issues/64) M02-05-A: document attachment safe validation | #56 |
| 13 | [#65](https://github.com/civora-org/civora-platform/issues/65) M02-05-B: amendments + public version history | #57, #63, #64 |
| 14 | [#66](https://github.com/civora-org/civora-platform/issues/66) M02-06-A: Slovak localization completeness | after feature freeze of #58–#65 |
| 15 | [#67](https://github.com/civora-org/civora-platform/issues/67) M02-06-B: a11y/UX review + QA checklist | #66 |
| 16 | [#68](https://github.com/civora-org/civora-platform/issues/68) M02-07-A: demo seeds + walkthrough | #60, #63 |
| 17 | [#69](https://github.com/civora-org/civora-platform/issues/69) M02-07-B: coverage sweep, docs + v1.0.0 release | everything above |

## Notes

- Parallelizable: #61 (harness) can start immediately alongside #53; model tasks (#55–#57) are independent of admin/public work once #53 lands.
- Process lesson applies: before planning model/admin tasks, diff task assumptions against the current tree and against `docs/00-product/` on the platform repo — the product boundary (ADR-002, manual CRZ handoff) lives there (see `docs/contracts-domain-notes.md`).
- Closing parents #6–#12 closes epic #3 and milestone "02 Contracts MVP"; #69 is the release gate.
