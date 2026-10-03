# Decidim::ContractsSk

A [Decidim](https://decidim.org) engine for Slovak public contracts workflow and catalogue — a structured workflow for drafting, reviewing and publishing public contract records, together with a public catalogue for Slovak municipalities and public-sector organisations.

Part of the [Civora](https://github.com/civora-org) platform, usable independently as a standalone Decidim module.

## Status

**v1.3.0** — pilot release. Running in the Civora host ([`civora-org/civora-host`](https://github.com/civora-org/civora-host)) as the version offered to the first municipalities; v1.0.0 was the first stable release (Milestone 02 complete). In place:

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
- Contract↔project/result links — per-contract links to platform-level entities, managed on the contract edit page (`admin/contracts/:contract_id/links`): create/remove only (links have no editable content), `editor`-gated on an editable-state contract, with display info resolved through a config-time host resolver; dangling targets stay flagged in admin and hidden publicly, and the public detail page renders a "Links" section only when something renderable remains (civora-org/civora-platform#87).
- Public catalogue and detail redesign (v1.3.0) — the catalogue is a register (title, reference · date, CRZ provenance label, amount right-aligned) with a labelled search; the detail page has a "Contract details" facts panel, a CRZ provenance notice with a warning label for stale mirrors, party rows that fit a phone and a version history; the admin audit trail shows date and time. The pages carry their own scoped stylesheet instead of engine-only Tailwind utilities — see [docs/public-ui.md](docs/public-ui.md).
- Reviewer decision reasons — the `reviewer` return/reject decisions carry a mandatory decision reason (up to 1000 characters), captured through an inline form on the admin index; the reason and its timestamp render as a "Reviewer decision" banner on the record's edit page until resubmission clears them, and any other transition fails closed when a reason is passed — the judgment vocabulary stays reviewer-only (civora-org/civora-platform#90).

## Requirements

- Decidim `0.31.x` (`decidim-core`, `decidim-admin`, floor `~> 0.31.5`)
- Ruby `>= 3.2`

## Installation

Add to your application's `Gemfile` (the gem is not yet published to RubyGems.org):

```ruby
gem "decidim-contracts_sk", github: "civora-org/decidim-contracts_sk", tag: "v1.3.0"
```

Pin a release tag: the host should always boot a reproducible engine version. Then:

```bash
bundle install
bin/rails decidim_contracts_sk:install:migrations
bin/rails db:migrate
```

The engine ships its tables as migrations (contracts, parties, documents, amendments, audit events, contract links; later additive migrations extend the contracts table, e.g. the submitter stamp behind the four-eyes rule); `install:migrations` copies them into the host. It re-stamps their timestamps, which is fine for a new host. A host that already ran the engine migrations under their original timestamps should keep copying new ones verbatim instead — the reference host documents that procedure in its README ("Upgrading the engine"). The host owns the ActiveStorage schema (see *Known limitations*).

Mount the engine in your app's `config/routes.rb` (mount point is your choice; the reference host uses `/contracts`):

```ruby
mount Decidim::ContractsSk::Engine, at: "/zmluvy"
```

Optional, for demos and manual testing only — never on a production database: `bin/rails "decidim_contracts_sk:seed_demo[<organization_id>]"` seeds fictional contracts in every lifecycle state (see *Demo data and walkthrough* above).

> **Admin routes:** the engine declares an admin namespace (`/zmluvy/admin/contracts`) with a sign-in floor and engine-permission checks (`editor` role for create/edit; `update` additionally gated on lifecycle editability; lifecycle transitions gated to the role that owns each edge — see the [lifecycle table](docs/contract-lifecycle.md)). Full admin authorization hardening is tracked in `civora-org/civora-platform#45`.

## Usage

With the engine mounted at `/zmluvy`:

- **Public catalogue** — `GET /zmluvy` (list, with a `q` free-text filter and pagination) and `GET /zmluvy/:id` (detail). Published records of the current organization only — no authentication required; anything else (draft, in-review, rejected, archived, another organization's, nonexistent) is an indistinguishable 404. The list paginates at 25 records per page. The detail page also renders the public version history: the live fields are the current version, above the published amendments' frozen content snapshots (newest first, published-only — drafts are never publicly visible) (civora-org/civora-platform#65). When the record carries project/result links, a "Links" section renders them (labelled and URL'd live through the [link target resolver](#configuration)); dangling or unresolvable targets are hidden, and the section disappears entirely when nothing renderable remains (civora-org/civora-platform#87).
- **Provenance and freshness for CRZ mirrors** — records mirrored from the CRZ register (`source: "crz"`) are labelled externally confirmed, never presented as a legal publication (ADR-002 rule 1, ADR-008 decisions 4/6): the catalogue list shows the "Externally confirmed" badge with the mirror date on each imported record's card, and the detail page adds a provenance block with the badge, the mirror date and the preserved attribution note (data via ekosystem.slovensko.digital; informational only; the canonical record lives at crz.gov.sk). When a mirror is stale, the detail page additionally warns readers to verify the canonical record: a mirror counts as stale when its `imported_at` is older than `Decidim::ContractsSk.stale_after` (default 48 h — twice the recommended nightly sync cadence), when its last import was stamped `failed`, or when it carries no import timestamp at all (freshness cannot be proven). The stale indicator is detail-only; cards stay lean (civora-org/civora-platform#88).
- **Admin** — `/zmluvy/admin/contracts` (list, create and edit contract records and drive lifecycle transitions — one POST action per event; sign-in plus an engine role required, each transition gated to the role that owns its edge in the [lifecycle table](docs/contract-lifecycle.md): `editor` for submit/publish/archive, `reviewer` for return/approve/reject, and the person who last submitted a record can never return, approve or reject it themselves (four-eyes rule, civora-org/civora-platform#123, [docs/roles-and-permissions.md](docs/roles-and-permissions.md)); `update` only while the record's lifecycle state is editable; publish additionally requires the record's privacy-redaction confirmation, below). The reviewer `return`/`reject` decisions carry a mandatory decision reason (up to 1000 characters) through an inline form on the index row — the reason and its timestamp render as a "Reviewer decision" banner on the record's edit page until resubmission clears them, and any other transition refuses a passed reason (civora-org/civora-platform#90). The index paginates at 25 records per page and filters by lifecycle state, provenance source (`crz` import vs. `editorial`) and a case-insensitive title/reference search — GET params preserved across page links, unknown values falling back to the defaults (civora-org/civora-platform#86b). The index header also renders per-state counter chips — one grouped query over the unfiltered tenant scope, so the counts are honest navigation that ignore the active filter, each chip linking to its `state=` filter while preserving the others — and a distinct no-matches empty state with a clear-filters link when active filters return zero rows (civora-org/civora-platform#93). Each contract also has a nested party manager at `/zmluvy/admin/contracts/:contract_id/parties` — add/edit/remove the object/contractor parties, `editor`-gated and available only while the record's lifecycle state is editable. The contract edit page also hosts the document manager — attach/replace/remove files, `editor`-gated on an editable-state contract (civora-org/civora-platform#73) — and the CRZ handoff export: generate/regenerate the PDF aid (`editor`-gated on an editable-state contract) and download it (`editor`-gated on any lifecycle state); the PDF is labelled a handoff aid for the clerical CRZ record, never a legal publication (civora-org/civora-platform#74). Each contract also has a nested amendment manager at `/zmluvy/admin/contracts/:contract_id/amendments` — draft version-history entries published by one explicit POST per event: create is `editor`-gated on a published contract; update/destroy/publish are `editor`-gated on a draft amendment (publish additionally requires the contract still published); published amendments are immutable (civora-org/civora-platform#65). The contract edit page also hosts the project/result link manager — add/remove links to platform-level entities (`editor`-gated on an editable-state contract; create/destroy only — links have no editable content), with an explicit flag next to links whose target no longer resolves so editors can clean them up (civora-org/civora-platform#87). The contract edit page also hosts the privacy-redaction confirmation gate (ADR-007, civora-org/civora-platform#91): before the record may be published, an editor must confirm the localized redaction checklist — personal names/addresses of natural persons, bank/account details, amounts tying the contract to identifiable persons, sensitive content inside attached documents — through one required-checkbox POST whose affirmation value is consumed server-side (`POST /zmluvy/admin/contracts/:contract_id/confirm_redaction`, `editor`-gated on a confirmable contract — the editable states plus `approved`, so a reviewer-approved record can still be stamped right before publish; the publish transition refuses while the stamp is missing, and amendment publication backstops on the same stamp for editorial records — CRZ mirrors are exempt, their content being already-public upstream data per ADR-008). Once confirmed, the edit page shows the confirmation stamp line instead of the checkbox form. The contract edit page also links to the read-only audit trail — `/zmluvy/admin/audit_events` (civora-org/civora-platform#92), a paginated, newest-first listing of the organization's append-only audit events (lifecycle transitions, the privacy-redaction confirmation, amendment publications and CRZ-import actions), optionally filtered to one contract through `?contract_id=<id>`; every engine role may consult it, each row shows the localized action, the target record (dangling targets render a "record no longer exists" label — the trail outlives what it observed), the acting user and the date and time, plus the reviewer decision reason for records sitting in a decision state.
- **Roles and permissions** — the engine-logical `editor`/`reviewer` roles map onto Decidim permissions via a config-time resolver; see [docs/roles-and-permissions.md](docs/roles-and-permissions.md).
- **Navigation** — a "Contracts / Zmluvy" entry in Decidim's main menu (and its mobile menu twin) pointing at the public catalogue, and a "Contracts" entry in the Decidim admin sidebar pointing at the admin contracts index — the sidebar entry renders only for users holding an engine role. Both sit at position 2.4, next to the other content modules; hosts can re-order, override or remove them per Decidim menu conventions (`Decidim.menu :menu do |menu| menu.move :contracts_sk, ... end`, `menu.remove_item :contracts_sk`) (civora-org/civora-platform#86c).
- **CRZ import** — an editor-gated `POST /zmluvy/admin/contracts/import_crz` (form on the admin contracts index) pulls one CRZ record by its numeric id, and the host-scheduled `bin/rails "decidim_contracts_sk:crz_import:sync[<organization_id>,<SINCE ISO8601>]"` task mirrors updated records in batch (SINCE also via the `SINCE` env var). Mirrors land `published` with full provenance and an audit event; re-running is always safe. Operations, scheduling, failure modes and the manual collision resolution in [docs/crz-import.md](docs/crz-import.md).

Locales: English and Slovak.

## Configuration

The engine maps Decidim users onto its `editor`/`reviewer` roles through a single config-time seam: `Decidim::ContractsSk.role_resolver`, a callable receiving `(user, context)` and returning an array of engine-role symbols. The default grants every engine role to organization admins who have accepted the admin terms, and none to anyone else — there is no per-user role UI. Override it in an initializer:

```ruby
# config/initializers/contracts_sk.rb
Decidim::ContractsSk.role_resolver = ->(user, _context) { user&.admin? ? %i[editor reviewer] : [] }
```

Results are always intersected with the engine's role vocabulary, and the resolver is config-time only — never mutate it at request time. See [docs/roles-and-permissions.md](docs/roles-and-permissions.md).

The four-eyes rule (civora-org/civora-platform#123) forbids the person who last submitted a contract to return, approve or reject it, so a deployment needs at least two people holding engine roles. One-person municipalities can opt out with `Decidim::ContractsSk.allow_self_review = true` (default `false`, config-time only); every such self-judgment is then audited as `contract.<event>_self`:

```ruby
Decidim::ContractsSk.allow_self_review = true
```

The freshness threshold behind the catalogue's stale indicator is configurable the same way (`Decidim::ContractsSk.stale_after`): assign Integer seconds or an `ActiveSupport::Duration`. The default is 172_800 seconds (48 h — twice the recommended nightly sync cadence); it only decides when the stale notice appears (see the provenance bullet under Usage), never implying real-time accuracy:

```ruby
# config/initializers/contracts_sk.rb
Decidim::ContractsSk.stale_after = 12.hours
```

The CRZ import only mirrors the organization's own contracts — records where its IČO is one of the two parties — so it needs to know that IČO (`Decidim::ContractsSk.crz_organization_ico_resolver`, a callable receiving the `Decidim::Organization`). The default resolves nothing and the import fails closed: without an IČO the sync refuses to run instead of mirroring the whole national register. Answers are normalized to 8 digits (spaces ignored); anything else, or a raising resolver, counts as unconfigured. See [docs/crz-import.md](docs/crz-import.md) (civora-org/civora-platform#145):

```ruby
# config/initializers/contracts_sk.rb
Decidim::ContractsSk.crz_organization_ico_resolver = ->(organization) { ENV["CRZ_ICO_ORG_#{organization.id}"] }
```

Contract↔project/result links resolve their display info through two config-time seams (`Decidim::ContractsSk.supported_link_target_types` and `Decidim::ContractsSk.link_target_resolver`). The defaults are deliberately inert — an empty supported-type whitelist and a resolver that resolves nothing — so the standalone engine links nothing. A host enables linking by whitelisting target class names and assigning a callable that receives a link and returns `{ label:, url: }` display info (`url` optional; nil hides the link publicly). The resolution whitelists the target type, tolerates dangling targets (a link whose target row is gone stays flagged in admin, hidden publicly) and fails closed — a raising resolver can never break a public page:

```ruby
# config/initializers/contracts_sk.rb
Decidim::ContractsSk.supported_link_target_types = %w[Decidim::Accountability::Result]
Decidim::ContractsSk.link_target_resolver = lambda do |link|
  result = Decidim::Accountability::Result.find_by(id: link.target_id)
  next nil unless result

  { label: result.title, url: Decidim::Accountability::ResultPrinter.new(result).result_url }
end
```

Organization-scoping the target lookup is the host resolver's responsibility — the link's organization is reachable via `link.contract.organization` — so a bare `target_id` lookup like the illustrative one above can never be relied on to respect tenant boundaries on its own.

Both settings are config-time only — never mutate them at request time.

## Known limitations and non-goals

- **CRZ integration is a metadata mirror, not a register replacement.** The import (ADR-008) mirrors already-public CRZ contract metadata from ekosystem.slovensko.digital; the clerical CRZ handoff stays a generated aid. Publishing to CRZ, mirroring documents (link-only via `crz_url`), importing currency/VAT (absent upstream) and the official nightly-ZIP fallback remain out of scope — see [docs/crz-import.md](docs/crz-import.md).
- **Per-editor ownership is not enforced.** Any user holding an engine role in the organization may act on any of the organization's records — there is no "my records" restriction (an explicit deferral; see [docs/contract-lifecycle.md](docs/contract-lifecycle.md)).
- **No ActiveStorage schema shipped.** The engine attaches files to documents but ships no storage-table migration — the host app owns the ActiveStorage schema.
- **Roles resolve at config time only.** Role assignment happens wherever the host decides, through the resolver seam above — the engine provides no per-user role management UI.
- **No Decidim component registration yet.** The catalogue is a mounted engine; registering it as a Decidim component is planned (civora-org/civora-platform#89), not implemented.

## Development

```bash
bin/setup              # install dependencies
bundle exec rspec      # run the test suite (deterministic, offline, no DB required)
bundle exec rubocop    # lint
bin/console            # experiment with the gem
```

The test suite boots a minimal, ActiveRecord-free Rails dummy app (`spec/dummy`) that mounts the engine at `/` and drives it with request specs — it still runs without a database or network. Opt-in DB-backed specs: `CONTRACTS_SK_DB=1 bundle exec rspec` additionally runs the `:db` groups against an in-memory SQLite adapter (needs the `sqlite3` dev gem); those groups are excluded from the default run. Lifecycle coverage is documented as sufficient for 1.0.0 — the state machine is pinned at the lifecycle-table, permissions, command and request layers, and the `:db` groups run in CI.

Public views (catalogue and detail) carry their own scoped stylesheet instead of engine-only Tailwind utilities, because the host compiles its CSS at image build time and silently drops classes it did not see then. The styling rule, page structure and how to verify a change against a running host are in [docs/public-ui.md](docs/public-ui.md).

## Contributing

- Issues are tracked in [`civora-org/civora-platform`](https://github.com/civora-org/civora-platform), not in this repository.
- Pull requests target `main`; follow Conventional Commits (`feat:`, `fix:`, `docs:`, …). `CHANGELOG.md` is generated by [release-please](https://github.com/googleapis/release-please) — do not edit it manually.

## License

AGPL-3.0 — same license as Decidim. Full text in [LICENSE-AGPLv3.txt](LICENSE-AGPLv3.txt).
