# Decidim::ContractsSk

A [Decidim](https://decidim.org) engine for Slovak public contracts workflow and catalogue — a structured workflow for drafting, reviewing and publishing public contract records, together with a public catalogue for Slovak municipalities and public-sector organisations.

Part of the [Civora](https://github.com/civora-org) platform, usable independently as a standalone Decidim module.

## Status

**Early development** (Milestone 02 in progress). Currently in place:

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
- `Amendment` and `AuditEvent` models and migrations — per-contract numbered amendments (unique `(contract, version)`; immutability deferred to M02-05-B) and an append-only audit trail with explicit organization/actor tenancy and a polymorphic target that outlives the contract (rationale in [`docs/contracts-domain-notes.md`](docs/contracts-domain-notes.md));
- Admin contracts CRUD — `index`/`new`/`create`/`edit`/`update` behind the engine permissions (`editor` role; `update` additionally gated on lifecycle editability), with a deliberately narrow title/reference form — lifecycle state, provenance, organization and author are never form-writable (civora-org/civora-platform#58);
- Admin party management — nested add/edit/remove pages under each contract (`admin/contracts/:contract_id/parties`), gated like `update` (`editor` role on an editable-state contract); multiple parties with the same role are legal (civora-org/civora-platform#76);
- Public contracts catalogue — first real views: a published-only index with a localized empty state and a public detail page with content fields and parties; unpublished, archived, other-organization and nonexistent ids are indistinguishable 404s (civora-org/civora-platform#62, #63).

Admin contract record views are upcoming — see [Milestone 02 execution order](docs/m02-execution-order.md).

## Requirements

- Decidim `0.31.x` (`decidim-core`, `decidim-admin`)
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

- **Public catalogue** — `GET /zmluvy/contracts` (list) and `GET /zmluvy/contracts/:id` (detail). Published records of the current organization only — no authentication required; anything else (draft, in-review, rejected, archived, another organization's, nonexistent) is an indistinguishable 404.
- **Admin** — `/zmluvy/admin/contracts` (list, create and edit contract records and drive lifecycle transitions — one POST action per event; sign-in plus an engine role required, each transition gated to the role that owns its edge in the [lifecycle table](docs/contract-lifecycle.md): `editor` for submit/publish/archive, `reviewer` for return/approve/reject; `update` only while the record's lifecycle state is editable). Each contract also has a nested party manager at `/zmluvy/admin/contracts/:contract_id/parties` — add/edit/remove the object/contractor parties, `editor`-gated and available only while the record's lifecycle state is editable. The contract edit page also hosts the document manager — attach/replace/remove files, `editor`-gated on an editable-state contract (civora-org/civora-platform#73) — and the CRZ handoff export: generate/regenerate the PDF aid (`editor`-gated on an editable-state contract) and download it (`editor`-gated on any lifecycle state); the PDF is labelled a handoff aid for the clerical CRZ record, never a legal publication (civora-org/civora-platform#74).
- **Roles and permissions** — the engine-logical `editor`/`reviewer` roles map onto Decidim permissions via a config-time resolver; see [docs/roles-and-permissions.md](docs/roles-and-permissions.md).

Locales: English and Slovak.

## Development

```bash
bin/setup              # install dependencies
bundle exec rspec      # run the test suite (deterministic, offline, no DB required)
bundle exec rubocop    # lint
bin/console            # experiment with the gem
```

The test suite boots a minimal, ActiveRecord-free Rails dummy app (`spec/dummy`) that mounts the engine at `/` and drives it with request specs — it still runs without a database or network. Opt-in DB-backed specs: `CONTRACTS_SK_DB=1 bundle exec rspec` additionally runs the `:db` groups against an in-memory SQLite adapter (needs the `sqlite3` dev gem); those groups are excluded from the default run.

## Contributing

- Issues are tracked in [`civora-org/civora-platform`](https://github.com/civora-org/civora-platform), not in this repository.
- Pull requests target `main`; follow Conventional Commits (`feat:`, `fix:`, `docs:`, …). `CHANGELOG.md` is generated by [release-please](https://github.com/googleapis/release-please) — do not edit it manually.

## License

AGPL-3.0 — same license as Decidim.
