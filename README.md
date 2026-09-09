# Decidim::ContractsSk

A [Decidim](https://decidim.org) engine for Slovak public contracts workflow and catalogue — a structured workflow for drafting, reviewing and publishing public contract records, together with a public catalogue for Slovak municipalities and public-sector organisations.

Part of the [Civora](https://github.com/civora-org) platform, usable independently as a standalone Decidim module.

## Status

**v1.0.0** — first stable release (Milestone 02 complete). In place:

- Engine registration — isolated `Decidim::ContractsSk` namespace, `en`/`sk` locales;
- Routes — public contracts catalogue (`index`/`show`) and an admin CRUD namespace;
- Base controllers — public base (no forced authentication) and admin base (sign-in required);
- Base helper and abstract `ApplicationRecord` with the `decidim_contracts_sk_` table prefix;
- Contract lifecycle state machine — states and transition rules in [`docs/contract-lifecycle.md`](docs/contract-lifecycle.md);
- Roles and permissions — engine-logical `editor`/`reviewer` roles with a config-time resolver ([`docs/roles-and-permissions.md`](docs/roles-and-permissions.md));
- `Contract` model and migration — lifecycle-validated `state` enum, per-organization `reference` uniqueness, and manual CRZ-handoff provenance columns (rationale in [`docs/contracts-domain-notes.md`](docs/contracts-domain-notes.md));
- `Party` and `Document` models and migrations — contract-scoped parties with an `object`/`contractor` role enum and documents with a `contract`/`crz_export`/`annex`/`other` kind enum, real FK constraints onto the contracts table, and nullable file-metadata columns (populated by upload wiring);
- Document upload and storage wiring — engine-side ActiveStorage `has_one_attached :file` on `Document` with the metadata columns synced from the blob as the display source of truth; admin attach/replace/destroy nested under each contract (`admin/contracts/:contract_id/documents`, editor-gated on an editable-state contract), and download links in the public detail page for published contracts (the engine ships no storage-table migration — the host app owns the ActiveStorage schema). Upload safety is enforced at the form boundary — content-type allowlist, 10 MB size cap and filename sanitization on every stored name (civora-org/civora-platform#64);
- CRZ handoff export — a generated, always-regenerable PDF handoff aid for the clerical CRZ record (ADR-002 metadata export; labelled on the page as an aid, never a legal publication), stored as the contract's single `crz_export` document: generate/regenerate is `editor`-gated on an editable-state contract, download is `editor`-gated on any lifecycle state (civora-org/civora-platform#74);
- `Amendment` and `AuditEvent` models and migrations — per-contract numbered amendments (unique `(contract, version)`; published amendments are immutable, see the amendment manager below) and an append-only audit trail with explicit organization/actor tenancy and a polymorphic target that outlives the contract (rationale in [`docs/contracts-domain-notes.md`](docs/contracts-domain-notes.md));
- Admin contracts CRUD — `index`/`new`/`create`/`edit`/`update` behind the engine permissions (`editor` role; `update` additionally gated on lifecycle editability), with a deliberately narrow title/reference form — lifecycle state, provenance, organization and author are never form-writable (civora-org/civora-platform#58);
- Admin party management — nested add/edit/remove pages under each contract (`admin/contracts/:contract_id/parties`), gated like `update` (`editor` role on an editable-state contract); multiple parties with the same role are legal (civora-org/civora-platform#76);
- Amendment manager and public version history — per-contract admin CRUD for draft amendments with an explicit publish step (`admin/contracts/:contract_id/amendments`, `editor`-gated: create on published contracts, update/destroy/publish on drafts; published amendments are immutable forever, ADR-006), and a public version-history section on the detail page — the record's live fields are the current version, above the frozen, published-only historical snapshots, newest first (civora-org/civora-platform#65);
- Public contracts catalogue — published-only index with a localized empty state and a public detail page with content fields, parties, document downloads and the version history; unpublished, archived, other-organization and nonexistent ids are indistinguishable 404s (civora-org/civora-platform#62, #63).
- Demo data and walkthrough — an idempotent seed task covering every lifecycle state for manual testing, with click-through scenarios documented in [`docs/manual-test-scenarios.md`](docs/manual-test-scenarios.md) (civora-org/civora-platform#68); the demo seed run was verified end-to-end live on a host stack.
- Concurrency doctrine — every admin command that writes a contract takes the contract row's lock and re-checks its lifecycle guard inside the lock, so a stale request can never write onto a record that left the editable states mid-flight (civora-org/civora-platform#69).
- CRZ import ETL — an idempotent mirror of already-public CRZ contract metadata from ekosystem.slovensko.digital (ADR-008): checksum-gated updates, mirrors land `published` with full provenance and an audit event, editorial collisions are never touched, malformed records quarantine without aborting the batch, and a failed sync never degrades prior data. Triggers: a host-scheduled rake task (`decidim_contracts_sk:crz_import:sync`) and an editor-gated admin single-record import; operations, scheduling and failure modes in [`docs/crz-import.md`](docs/crz-import.md) (civora-org/civora-platform#86).

## Requirements

- Decidim `0.31.x` (`decidim-core`, `decidim-admin`, floor `~> 0.31.5`)
- Ruby `>= 3.2`

## Installation

Add to your application's `Gemfile` (the gem is not yet published to RubyGems.org):

```ruby
gem "decidim-contracts_sk", github: "civora-org/decidim-contracts_sk"
```

Then:

```bash
bundle install
```

Mount the engine in your app's `config/routes.rb` (mount point is your choice):

```ruby
mount Decidim::ContractsSk::Engine, at: "/zmluvy"
```

> **Admin routes:** the engine declares an admin namespace (`/zmluvy/admin/contracts`) with a sign-in floor and engine-permission checks (`editor` role for create/edit; `update` additionally gated on lifecycle editability; lifecycle transitions gated to the role that owns each edge — see the [lifecycle table](docs/contract-lifecycle.md)). Full admin authorization hardening is tracked in `civora-org/civora-platform#45`.

## Usage

With the engine mounted at `/zmluvy`:

- **Public catalogue** — `GET /zmluvy/contracts` (list) and `GET /zmluvy/contracts/:id` (detail). Published records of the current organization only — no authentication required; anything else (draft, in-review, rejected, archived, another organization's, nonexistent) is an indistinguishable 404. The detail page also renders the public version history: the live fields are the current version, above the published amendments' frozen content snapshots (newest first, published-only — drafts are never publicly visible) (civora-org/civora-platform#65).
- **Admin** — `/zmluvy/admin/contracts` (list, create and edit contract records and drive lifecycle transitions — one POST action per event; sign-in plus an engine role required, each transition gated to the role that owns its edge in the [lifecycle table](docs/contract-lifecycle.md): `editor` for submit/publish/archive, `reviewer` for return/approve/reject; `update` only while the record's lifecycle state is editable). Each contract also has a nested party manager at `/zmluvy/admin/contracts/:contract_id/parties` — add/edit/remove the object/contractor parties, `editor`-gated and available only while the record's lifecycle state is editable. The contract edit page also hosts the document manager — attach/replace/remove files, `editor`-gated on an editable-state contract (civora-org/civora-platform#73) — and the CRZ handoff export: generate/regenerate the PDF aid (`editor`-gated on an editable-state contract) and download it (`editor`-gated on any lifecycle state); the PDF is labelled a handoff aid for the clerical CRZ record, never a legal publication (civora-org/civora-platform#74). Each contract also has a nested amendment manager at `/zmluvy/admin/contracts/:contract_id/amendments` — draft version-history entries published by one explicit POST per event: create is `editor`-gated on a published contract; update/destroy/publish are `editor`-gated on a draft amendment (publish additionally requires the contract still published); published amendments are immutable (civora-org/civora-platform#65).
- **Roles and permissions** — the engine-logical `editor`/`reviewer` roles map onto Decidim permissions via a config-time resolver; see [docs/roles-and-permissions.md](docs/roles-and-permissions.md).
- **CRZ import** — an editor-gated `POST /zmluvy/admin/contracts/import_crz` (form on the admin contracts index) pulls one CRZ record by its numeric id, and the host-scheduled `bin/rails "decidim_contracts_sk:crz_import:sync[<organization_id>,<SINCE ISO8601>]"` task mirrors updated records in batch (SINCE also via the `SINCE` env var). Mirrors land `published` with full provenance and an audit event; re-running is always safe. Operations, scheduling, failure modes and the manual collision resolution in [docs/crz-import.md](docs/crz-import.md).

Locales: English and Slovak.

## Configuration

The engine maps Decidim users onto its `editor`/`reviewer` roles through a single config-time seam: `Decidim::ContractsSk.role_resolver`, a callable receiving `(user, context)` and returning an array of engine-role symbols. The default grants every engine role to organization admins who have accepted the admin terms, and none to anyone else — there is no per-user role UI. Override it in an initializer:

```ruby
# config/initializers/contracts_sk.rb
Decidim::ContractsSk.role_resolver = ->(user, _context) { user&.admin? ? %i[editor reviewer] : [] }
```

Results are always intersected with the engine's role vocabulary, and the resolver is config-time only — never mutate it at request time. See [docs/roles-and-permissions.md](docs/roles-and-permissions.md).

## Known limitations and non-goals

- **CRZ integration is a metadata mirror, not a register replacement.** The import (ADR-008) mirrors already-public CRZ contract metadata from ekosystem.slovensko.digital; the clerical CRZ handoff stays a generated aid. Publishing to CRZ, mirroring documents (link-only via `crz_url`), importing currency/VAT (absent upstream) and the official nightly-ZIP fallback remain out of scope — see [docs/crz-import.md](docs/crz-import.md).
- **Per-editor ownership is not enforced.** Any user holding an engine role in the organization may act on any of the organization's records — there is no "my records" restriction (an explicit deferral; see [docs/contract-lifecycle.md](docs/contract-lifecycle.md)).
- **No ActiveStorage schema shipped.** The engine attaches files to documents but ships no storage-table migration — the host app owns the ActiveStorage schema.
- **Roles resolve at config time only.** Role assignment happens wherever the host decides, through the resolver seam above — the engine provides no per-user role management UI.

## Development

```bash
bin/setup              # install dependencies
bundle exec rspec      # run the test suite (deterministic, offline, no DB required)
bundle exec rubocop    # lint
bin/console            # experiment with the gem
```

The test suite boots a minimal, ActiveRecord-free Rails dummy app (`spec/dummy`) that mounts the engine at `/` and drives it with request specs — it still runs without a database or network. Opt-in DB-backed specs: `CONTRACTS_SK_DB=1 bundle exec rspec` additionally runs the `:db` groups against an in-memory SQLite adapter (needs the `sqlite3` dev gem); those groups are excluded from the default run. Lifecycle coverage is documented as sufficient for 1.0.0 — the state machine is pinned at the lifecycle-table, permissions, command and request layers, and the `:db` groups run in CI.

## Contributing

- Issues are tracked in [`civora-org/civora-platform`](https://github.com/civora-org/civora-platform), not in this repository.
- Pull requests target `main`; follow Conventional Commits (`feat:`, `fix:`, `docs:`, …). `CHANGELOG.md` is generated by [release-please](https://github.com/googleapis/release-please) — do not edit it manually.

## License

AGPL-3.0 — same license as Decidim.
