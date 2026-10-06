# Decidim::ContractsSk

A [Decidim](https://decidim.org) engine for Slovak public contracts workflow and catalogue — a structured workflow for drafting, reviewing and publishing public contract records, together with a public catalogue for Slovak municipalities and public-sector organisations.

Part of the [Civora](https://github.com/civora-org) platform, usable independently as a standalone Decidim module.

## Status

**v1.5.0** — pilot release. Running in the Civora host ([`civora-org/civora-host`](https://github.com/civora-org/civora-host)) as the version offered to the first municipalities; v1.0.0 was the first stable release. Release notes per version are in [CHANGELOG.md](CHANGELOG.md). In place:

- Engine registration — isolated `Decidim::ContractsSk` namespace, `en`/`sk` locales;
- Routes — public contracts catalogue (`index`/`show`), the open-data export (`export.csv`/`export.json`) and an admin CRUD namespace;
- Base controllers — public base (no forced authentication) and admin base (sign-in required);
- Base helper and abstract `ApplicationRecord` with the `decidim_contracts_sk_` table prefix;
- Contract lifecycle state machine — states and transition rules in [`docs/contract-lifecycle.md`](docs/contract-lifecycle.md);
- Roles and permissions — engine-logical `editor`/`reviewer` roles with a config-time resolver ([`docs/roles-and-permissions.md`](docs/roles-and-permissions.md));
- Role assignment — organization admins grant and revoke the `editor`/`reviewer` roles per user in the admin (**Roles**, `/zmluvy/admin/user_roles`), audited, unioned with the admin default ([Assigning roles](docs/roles-and-permissions.md#assigning-roles-95));
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
- Workflow notifications — lifecycle transitions (`submit`, `return`, `approve`, `reject`, `publish`) fire Decidim events with role-based recipient discovery; recipients see notifications in the bell icon and email (user-controlled, host SMTP optional), the acting user never sees their own notifications, and archives are never notified — configuration and operations in [`docs/pilot-operations.md`](docs/pilot-operations.md) and test walkthroughs in [`docs/manual-test-scenarios.md`](docs/manual-test-scenarios.md) (civora-org/civora-platform#94).

## Requirements

- Decidim `0.31.x` (`decidim-core`, `decidim-admin`, floor `~> 0.31.5`)
- Ruby `>= 3.2`

## Installation

Add to your application's `Gemfile` (the gem is not yet published to RubyGems.org):

```ruby
gem "decidim-contracts_sk", github: "civora-org/decidim-contracts_sk", tag: "v1.5.0"
```

Pin a release tag: the host should always boot a reproducible engine version. Then:

```bash
bundle install
bin/rails decidim_contracts_sk:install:migrations
bin/rails db:migrate
```

The engine ships its tables as migrations (contracts, parties, documents, amendments, audit events, contract links; later additive migrations extend the contracts table, e.g. the submitter stamp behind the four-eyes rule and the CRZ filing confirmation columns `crz_filed_at`/`crz_published_on`/`crz_filing_reason`); `install:migrations` copies them into the host. It re-stamps their timestamps, which is fine for a new host. A host that already ran the engine migrations under their original timestamps should keep copying new ones verbatim instead — the reference host documents that procedure in its README ("Upgrading the engine"). The host owns the ActiveStorage schema (see *Known limitations*).

Mount the engine in your app's `config/routes.rb` (mount point is your choice; the reference host uses `/contracts`):

```ruby
mount Decidim::ContractsSk::Engine, at: "/zmluvy"
```

Optional, for demos and manual testing only — never on a production database: `bin/rails "decidim_contracts_sk:seed_demo[<organization_id>]"` seeds fictional contracts in every lifecycle state (see *Demo data and walkthrough* above).

> **Admin routes:** the engine declares an admin namespace (`/zmluvy/admin/contracts`) with a sign-in floor and engine-permission checks (`editor` role for create/edit; `update` additionally gated on lifecycle editability; lifecycle transitions gated to the role that owns each edge — see the [lifecycle table](docs/contract-lifecycle.md)). Full admin authorization hardening is tracked in `civora-org/civora-platform#45`.

## Usage

With the engine mounted at `/zmluvy`:

- **Public catalogue** — `GET /zmluvy` (list, with `q` free-text search, filters `amount_min`/`amount_max` (EUR), `published_from`/`published_to` (publication date: the real CRZ publication date where the record has one, else the date it entered the catalogue), `signed_from`/`signed_to`, `party` (name or exact 8-digit IČO) and `source` (`editorial`/`crz`), `sort` = `published_desc` (default) / `published_asc` / `amount_desc` / `amount_asc`, and pagination that carries every active filter; invalid values are ignored, a reversed range is swapped; civora-org/civora-platform#116, see [docs/contracts-domain-notes.md](docs/contracts-domain-notes.md#catalogue-filters-and-sorting-landed-in-116)) and `GET /zmluvy/:id` (detail). Published records of the current organization only — no authentication required; anything else (draft, in-review, rejected, archived, another organization's, nonexistent) is an indistinguishable 404. The list paginates at 25 records per page. The detail page also renders the public version history: the live fields are the current version, above the published amendments' frozen content snapshots (newest first, published-only — drafts are never publicly visible) (civora-org/civora-platform#65). When the record carries project/result links, a "Links" section renders them (labelled and URL'd live through the [link target resolver](#configuration)); dangling or unresolvable targets are hidden, and the section disappears entirely when nothing renderable remains (civora-org/civora-platform#87).
- **Discoverability** — every public page carries a title, a meta description, Open Graph/Twitter tags and `og:site_name` through Decidim's meta-tag helpers (contract descriptions name only contractors with an IČO; CRZ mirrors are labelled "Externally confirmed"), and `GET /zmluvy/sitemap.xml` lists the published own records (mirrors excluded). Host follow-up: reference the sitemap from `robots.txt`; details in [docs/public-ui.md](docs/public-ui.md) (civora-org/civora-platform#122).
- **Open data export** — `GET /zmluvy/export.csv` (UTF-8 with BOM; `?profile=excel` for `;` and decimal commas) and `GET /zmluvy/export.json`: the organization's own published records (CRZ mirrors are never exported) with a fixed, documented field list, the catalogue's filters, id-ascending order and a streamed, batched body with an `ETag`. The catalogue carries a "Download data" block, which also links the Atom feed of newly published contracts (`GET /zmluvy/feed.atom`, newest 50, same scope and filters, announced in the page head; civora-org/civora-platform#120). Field table, party rule, CSV formula-injection handling, licence guidance and the host's Open Data page sentence: [docs/open-data.md](docs/open-data.md) (civora-org/civora-platform#119).
- **Decidim component** (civora-org/civora-platform#89) — the engine registers a `contracts_sk` component, so a space admin can add "Contracts" to a participatory process or assembly (Admin > Components > Add component). The component page lists the organization's published contracts (25 per page, no search or filters) and links to an in-space detail page that renders the same view as the catalogue's; the component's only setting is a translated announcement (global and per step). Additive: the mounted engine, its routes and the `/zmluvy` catalogue are unchanged and need no participatory space; the component's own route table is the list and the detail page only. Details, decisions and the Decidim call-site audit: [docs/decidim-component.md](docs/decidim-component.md).
- **E-mail alerts** — an anonymous, double-opt-in subscription to a catalogue search (`POST /zmluvy/subscriptions`; the form sits under the catalogue's "Download data" block): a confirmation e-mail first, then a digest of the organization's own newly published matching contracts, with an unsubscribe link and `List-Unsubscribe` headers in every mail. Only the address, the normalized search, the locale and the consent and delivery stamps are stored; unconfirmed requests expire after 48 hours and unsubscribing deletes the row. The host schedules `bin/rails decidim_contracts_sk:subscriptions:deliver` once a day; privacy design, operations and the DPIA input in [docs/search-alerts.md](docs/search-alerts.md) (civora-org/civora-platform#121).
- **Statistics page** — `GET /zmluvy/statistics`, linked from the catalogue header: totals (this month, this year, all time, own-records share), the last 12 months and a per-year table by signing date, the top suppliers by value (per currency) and by number of contracts (by IČO, linking to the supplier pages) and, when CRZ mirrors exist, the own-versus-CRZ split. Amounts are never added across currencies; the figures are cached for an hour as data under a key derived from the data itself. Indexable (no `noindex`), no filters; see [docs/contracts-domain-notes.md](docs/contracts-domain-notes.md#statistics-page-landed-in-118) (civora-org/civora-platform#118).
- **Supplier pages** — `GET /zmluvy/suppliers/<8-digit IČO>`: every published contract of one counterparty (the contractor role only), with the supplier's name (its most recent spelling), the contract count, the total value per currency, a per-year tally by signing date and the contracts newest first, 25 per page. CRZ mirrors are included and carry their provenance badge. An IČO with nothing to show (unknown, drafts only, another organization's, object role only) is a plain 404; a value that is not exactly eight digits is not routed. The contract detail page links each contractor that has a well-formed IČO to its page. The pages carry `noindex` because a counterparty may be a sole trader; see [docs/contracts-domain-notes.md](docs/contracts-domain-notes.md#supplier-pages-landed-in-117) (civora-org/civora-platform#117).
- **Provenance and freshness for CRZ mirrors** — records mirrored from the CRZ register (`source: "crz"`) are labelled externally confirmed, never presented as a legal publication (ADR-002 rule 1, ADR-008 decisions 4/6): the catalogue list shows the "Externally confirmed" badge with the mirror date on each imported record's card, and the detail page adds a provenance block with the badge, the mirror date and the preserved attribution note (data via ekosystem.slovensko.digital; informational only; the canonical record lives at crz.gov.sk). When a mirror is stale, the detail page additionally warns readers to verify the canonical record: a mirror counts as stale when its `imported_at` is older than `Decidim::ContractsSk.stale_after` (default 48 h — twice the recommended nightly sync cadence), when its last import was stamped `failed`, or when it carries no import timestamp at all (freshness cannot be proven). The stale indicator is detail-only; cards stay lean (civora-org/civora-platform#88).
- **Admin overview** — `/zmluvy/admin` (civora-org/civora-platform#126), the landing page for role holders and the target of the Decidim admin sidebar entry: "waiting for my review" (`reviewer`: in-review records you did not submit — four-eyes — or all of them under `allow_self_review`), "returned to me" (`editor`: your submissions a reviewer sent back), "approved, ready to publish" (`editor`, with a "redaction not confirmed" flag), the CRZ deadline watch (overdue / due within 14 days, every role), counts per lifecycle state and the last 10 audit events. Role-specific blocks render only when the permission layer lets the user perform the event the block is about (no separate role logic); every list is a 10-row preview with a "Show all (N)" link to the matching filtered contracts index (`?state=in_review&submitter=others`, `?state=returned&submitter=me`, `?state=approved`, `?deadline=overdue|due_soon`), and each block has its own empty state. Gate: any engine role (the contracts index's `:read`). The contracts index gained a `submitter=me|others` filter (others includes records with no submitter stamp) and both it and the audit trail link back to the overview.
- **Admin** — `/zmluvy/admin/contracts` (list, create and edit contract records and drive lifecycle transitions — one POST action per event; sign-in plus an engine role required, each transition gated to the role that owns its edge in the [lifecycle table](docs/contract-lifecycle.md): `editor` for submit/publish/archive, `reviewer` for return/approve/reject, and the person who last submitted a record can never return, approve or reject it themselves (four-eyes rule, civora-org/civora-platform#123, [docs/roles-and-permissions.md](docs/roles-and-permissions.md)); `update` only while the record's lifecycle state is editable; publish additionally requires the record's privacy-redaction confirmation, below). The reviewer `return`/`reject` decisions carry a mandatory decision reason (up to 1000 characters) through an inline form on the index row — the reason and its timestamp render as a "Reviewer decision" banner on the record's edit page until resubmission clears them, and any other transition refuses a passed reason (civora-org/civora-platform#90). The index paginates at 25 records per page and filters by lifecycle state, provenance source (`crz` import vs. `editorial`) and a case-insensitive title/reference search — GET params preserved across page links, unknown values falling back to the defaults (civora-org/civora-platform#86b). The index header also renders per-state counter chips — one grouped query over the unfiltered tenant scope, so the counts are honest navigation that ignore the active filter, each chip linking to its `state=` filter while preserving the others — and a distinct no-matches empty state with a clear-filters link when active filters return zero rows (civora-org/civora-platform#93). It also tracks the CRZ publication deadline (§ 47a OZ, civora-org/civora-platform#124): every editorial record not yet confirmed as filed in CRZ (`crz_filed_at` empty — the verified filing confirmation of civora-org/civora-platform#125, replacing the interim `crz_url` proxy; nothing is backfilled) gets a deadline badge in the index (overdue / days left, `signed_on` + 3 months, computed never stored), a `deadline` filter (due within 14 days / overdue) and two counters next to the state chips, and the edit page shows the deadline line (or "deadline unknown — add signing date") — an aid, not legal advice; see [docs/contract-lifecycle.md](docs/contract-lifecycle.md#crz-publication-deadline-124). The CRZ round trip (civora-org/civora-platform#125): a published, unfiled editorial record offers **Record CRZ filing** on its index row (`GET`/`POST /zmluvy/admin/contracts/:id/crz_filing`, `editor`-gated) — the editor names the CRZ id, the engine fetches the official record read-only from the ekosystem feed (which may lag the CRZ by about a day), compares reference, supplier IČO and amount side by side, and confirms the filing on a match (any difference needs a stored, audited reason; hard refusals for another organization's record, a cancelled/withdrawn record or an unconfigured IČO). The record stays editorial and becomes the linked record of the CRZ id: the sync then neither mirrors nor flags it (`linked`), a pristine mirror already holding the id is absorbed, and the public detail page says "Published in CRZ on <date>" with the official link; see [docs/crz-import.md](docs/crz-import.md). Each contract also has a nested party manager at `/zmluvy/admin/contracts/:contract_id/parties` — add/edit/remove the object/contractor parties, `editor`-gated and available only while the record's lifecycle state is editable. The contract edit page also hosts the document manager — attach/replace/remove files, `editor`-gated on an editable-state contract (civora-org/civora-platform#73) — and the CRZ handoff export: generate/regenerate the PDF aid (`editor`-gated on an editable-state contract) and download it (`editor`-gated on any lifecycle state); the PDF is labelled a handoff aid for the clerical CRZ record, never a legal publication (civora-org/civora-platform#74). Each contract also has a nested amendment manager at `/zmluvy/admin/contracts/:contract_id/amendments` — draft version-history entries published by one explicit POST per event: create is `editor`-gated on a published contract; update/destroy/publish are `editor`-gated on a draft amendment (publish additionally requires the contract still published); published amendments are immutable (civora-org/civora-platform#65). The contract edit page also hosts the project/result link manager — add/remove links to platform-level entities (`editor`-gated on an editable-state contract; create/destroy only — links have no editable content), with an explicit flag next to links whose target no longer resolves so editors can clean them up (civora-org/civora-platform#87). The contract edit page also hosts the privacy-redaction confirmation gate (ADR-007, civora-org/civora-platform#91): before the record may be published, an editor must confirm the localized redaction checklist — personal names/addresses of natural persons, bank/account details, amounts tying the contract to identifiable persons, sensitive content inside attached documents — through one required-checkbox POST whose affirmation value is consumed server-side (`POST /zmluvy/admin/contracts/:contract_id/confirm_redaction`, `editor`-gated on a confirmable contract — the editable states plus `approved`, so a reviewer-approved record can still be stamped right before publish; the publish transition refuses while the stamp is missing, and amendment publication backstops on the same stamp for editorial records — CRZ mirrors are exempt, their content being already-public upstream data per ADR-008). Once confirmed, the edit page shows the confirmation stamp line instead of the checkbox form. The contract edit page also links to the read-only audit trail — `/zmluvy/admin/audit_events` (civora-org/civora-platform#92), a paginated, newest-first listing of the organization's append-only audit events (lifecycle transitions, the privacy-redaction confirmation, amendment publications, CRZ filing confirmations and CRZ-import actions), optionally filtered to one contract through `?contract_id=<id>`; every engine role may consult it, each row shows the localized action, the target record (dangling targets render a "record no longer exists" label — the trail outlives what it observed), the acting user and the date and time, plus the reviewer decision reason for records sitting in a decision state.
- **Roles and permissions** — the engine-logical `editor`/`reviewer` roles map onto Decidim permissions via a config-time resolver; see [docs/roles-and-permissions.md](docs/roles-and-permissions.md) Organization admins assign them per user at `/zmluvy/admin/user_roles` (sidebar **Roles**; user search of at least 3 characters, at most 20 hits, emails matched but never shown; grants and revokes audited) — see [Assigning roles](docs/roles-and-permissions.md#assigning-roles-95).
- **Navigation** — a "Contracts / Zmluvy" entry in Decidim's main menu (and its mobile menu twin) pointing at the public catalogue, and a "Contracts" entry in the Decidim admin sidebar pointing at the admin overview (`/zmluvy/admin`, from where the contracts index and the audit trail are one click away; it stays highlighted on every engine admin page) — the sidebar entry renders only for users holding an engine role. Engine role holders who are **not** Decidim admins cannot open Decidim's own `/admin` dashboard, so they get a "Contracts administration / Správa zmlúv" link in the account-area menu (`Decidim.menu :user_menu`, shown on `/account`), and a refused admin action sends them to the engine admin overview instead of Decidim's `/admin` (a 404 for them); a user with no engine role lands on the public catalogue (civora-org/civora-platform#161). Both main entries sit at position 2.4, next to the other content modules; hosts can re-order, override or remove them per Decidim menu conventions (`Decidim.menu :menu do |menu| menu.move :contracts_sk, ... end`, `menu.remove_item :contracts_sk`) (civora-org/civora-platform#86c).
- **CRZ import** — an editor-gated `POST /zmluvy/admin/contracts/import_crz` (form on the admin contracts index) pulls one CRZ record by its numeric id, and the host-scheduled `bin/rails "decidim_contracts_sk:crz_import:sync[<organization_id>,<SINCE ISO8601>]"` task mirrors updated records in batch (SINCE also via the `SINCE` env var). Mirrors land `published` with full provenance and an audit event; re-running is always safe. Operations, scheduling, failure modes and the manual collision resolution in [docs/crz-import.md](docs/crz-import.md).

Locales: English and Slovak.

## Configuration

The engine maps Decidim users onto its `editor`/`reviewer` roles through a single config-time seam: `Decidim::ContractsSk.role_resolver`, a callable receiving `(user, context)` and returning an array of engine-role symbols. The default grants every engine role to organization admins who have accepted the admin terms, and, to everyone else, the roles an admin granted them in the **Roles** admin screen (stored per user, [Assigning roles](docs/roles-and-permissions.md#assigning-roles-95)). A host override replaces this default, including the stored roles. Override it in an initializer:

```ruby
# config/initializers/contracts_sk.rb
Decidim::ContractsSk.role_resolver = ->(user, _context) { user&.admin? ? %i[editor reviewer] : [] }
```

Results are always intersected with the engine's role vocabulary, and the resolver is config-time only — never mutate it at request time. See [docs/roles-and-permissions.md](docs/roles-and-permissions.md).

Workflow notifications (civora-org/civora-platform#94) use a second config-time seam, `Decidim::ContractsSk.notification_candidates`: a callable `(organization) -> users` listing who may be notified about a submission. The candidates are then narrowed through `role_resolver` (only holders of the `reviewer` role are notified), so the seam bounds the users that are asked and never grants a role. The default is the organization's confirmed, available admins plus confirmed, available users holding a stored `reviewer` `UserRole` — enough for the default resolver. A host whose resolver grants roles to non-admins overrides it to cover every user that can hold `reviewer`; the acting user is never notified about their own action:

```ruby
Decidim::ContractsSk.notification_candidates = ->(organization) { Decidim::User.where(organization: organization).available.confirmed.where(my_role: "reviewer") }
```

The four-eyes rule (civora-org/civora-platform#123) forbids the person who last submitted a contract to return, approve or reject it, so a deployment needs at least two people holding engine roles. One-person municipalities can opt out with `Decidim::ContractsSk.allow_self_review = true` (default `false`, config-time only); every such self-judgment is then audited as `contract.<event>_self`:

```ruby
Decidim::ContractsSk.allow_self_review = true
```

A host that runs its own two-factor authentication (ADR-010, civora-org/civora-platform#164) can require it before the engine admin is reachable through two more config-time seams (civora-org/civora-platform#165): `Decidim::ContractsSk.second_factor_satisfied`, a callable `(user, session) -> boolean` (default: always `true`, so nothing changes unless set), and `Decidim::ContractsSk.second_factor_redirect_path`, a callable `(controller) -> path` (default: the Decidim root). When the first returns falsey, every engine admin request is redirected to the second's path with a flash alert. The guard covers the engine admin only: not the public catalogue, the in-space component, nor Decidim's `/admin` and `/system`. The engine implements no enrolment or challenge; those are host concerns:

```ruby
Decidim::ContractsSk.second_factor_satisfied = ->(user, session) { session[:totp_verified_user_id] == user&.id }
Decidim::ContractsSk.second_factor_redirect_path = ->(controller) { controller.main_app.new_totp_challenge_path }
```

The freshness threshold behind the catalogue's stale indicator is configurable the same way (`Decidim::ContractsSk.stale_after`): assign Integer seconds or an `ActiveSupport::Duration`. The default is 172_800 seconds (48 h — twice the recommended nightly sync cadence); it only decides when the stale notice appears (see the provenance bullet under Usage), never implying real-time accuracy:

```ruby
# config/initializers/contracts_sk.rb
Decidim::ContractsSk.stale_after = 12.hours
```

The CRZ publication window behind the admin deadline badges (§ 47a OZ, civora-org/civora-platform#124) is `Decidim::ContractsSk.crz_deadline`. It must be a positive `ActiveSupport::Duration` — an Integer or anything else raises `ArgumentError` at assignment, because the calendar semantics (month-end clamping) live in the Duration. The default is `3.months`, the statutory window; config-time only, like the other settings:

```ruby
# config/initializers/contracts_sk.rb
Decidim::ContractsSk.crz_deadline = 3.months
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
- **Roles resolve through one config-time seam.** The default resolver unions the admin roles with the per-user roles granted in the admin; a host that overrides `role_resolver` takes over fully and must union stored roles itself if it wants them.
- **The component is a read-only lens, not a data owner.** Contracts carry no component or participatory-space reference (ADR-009), so the registered component lists the organization's published contracts, the same records as the mounted catalogue, in every space it is added to; administration stays organization-scoped in the mounted engine's admin. See [docs/decidim-component.md](docs/decidim-component.md).
- **Related contracts are embedded by the host.** The engine ships the reverse lookup (`Decidim::ContractsSk.related_contracts_for(resource)`) and a partial that lists the published, same-organization contracts linked to a result or project, but Decidim 0.31 has no view hook on those pages, so the host overrides two view files to render it — see [docs/related-contracts.md](docs/related-contracts.md) (civora-org/civora-platform#131).

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

- Issues and pull requests are welcome in this repository. References such as `civora-org/civora-platform#64` in this README, the docs and the changelog point to the project's internal planning tracker, which is not public.
- Pull requests target `main` and need the CI checks (`Ruby 3.3.4`, `bundler-audit`) to pass. Follow Conventional Commits (`feat:`, `fix:`, `docs:`, …). `CHANGELOG.md` is generated by [release-please](https://github.com/googleapis/release-please), so don't edit it by hand.

## Security

Please report vulnerabilities privately to denys@civora.sk instead of opening a public issue.

## License

AGPL-3.0 — same license as Decidim. Full text in [LICENSE-AGPLv3.txt](LICENSE-AGPLv3.txt).
