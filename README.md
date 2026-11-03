# decidim-contracts_sk

A [Decidim](https://decidim.org) engine for Slovak public contracts. It provides:

- a **workflow** for drafting, reviewing and publishing public contract records, with role separation and an audit trail;
- a **public catalogue** of the published records, with search, filters, statistics, supplier pages and open-data downloads.

The engine is built for Slovak municipalities and other public-sector organisations. It is part of the [Civora](https://github.com/civora-org) platform but works as a standalone Decidim module.

**Status:** pilot. The latest release is [v1.11.0](https://github.com/civora-org/decidim-contracts_sk/releases/latest). <!-- x-release-please-version --> It runs in the reference host, [civora-org/civora-host](https://github.com/civora-org/civora-host). The gem is not published to RubyGems; hosts install it from the Git tag. Release notes are in [CHANGELOG.md](CHANGELOG.md).

## Requirements

| Item | Supported |
|---|---|
| Decidim | `0.31.x` and `0.32.x` (`decidim-core` and `decidim-admin`, `>= 0.31.5`, `< 0.33`) |
| Ruby | `>= 3.3` (CI runs Ruby 3.3.4 with Decidim 0.31 and Ruby 3.4.7 with Decidim 0.32) |
| Database | The reference host runs PostgreSQL. The default test suite needs no database |
| Runtime gems | Installed with the engine: `prawn ~> 2.5.0`, `csv ~> 3.0`, `nokogiri >= 1.15, < 2`, `pdf-reader ~> 2.12`, `rubyzip >= 2.3, < 3`, `sablon ~> 0.4.3` (the last three read, fill and check Word contract templates) |
| LibreOffice Writer (headless) | Needed on the host only for the PDF output of contract templates. The `soffice` command must be on the `PATH` of the app process. Without it, generating a contract from a template stops with a message and stores nothing (the Word file is not produced alone). Everything else works. A host can replace the converter with `Decidim::ContractsSk.pdf_converter=` (any callable taking `.docx` bytes and returning PDF bytes) |
| Active Record encryption keys | Needed for contract templates: the personal-data values of a generated contract are stored in the encrypted `personal_values` column of `contract_template_entries`. Decidim does not set the keys. Without them, generating stops with a message and stores nothing. See [docs/contract-templates.md](docs/contract-templates.md) |

The engine does not ship an ActiveStorage schema. The host app owns it (see [Known limitations](#known-limitations)).

## Features

### Public

- **Catalogue** (`/<mount>`): published records of the organisation only, with free-text search, filters (amount, publication and signing dates, party by name or 8-digit IČO, source), sorting and 25 records per page. Filters are kept across pagination.
- **Contract detail**: contract facts, parties, document downloads, version history (published amendments), project/result links and a provenance notice for CRZ mirrors.
- **Open data**: CSV (`export.csv`, with an Excel profile) and JSON (`export.json`) exports and an Atom feed of new contracts (`feed.atom`). Field list and licence guidance are in [docs/open-data.md](docs/open-data.md).
- **E-mail alerts**: an anonymous, double-opt-in subscription to a catalogue search. A daily digest sends newly published matches. See [docs/search-alerts.md](docs/search-alerts.md).
- **Statistics** (`statistics`): totals, a 12-month series, a per-year table, top suppliers by value and by count, and the own-versus-CRZ split. Amounts are never added across currencies.
- **Supplier pages** (`suppliers/<IČO>`): every published contract of one counterparty, with the contract count and totals per currency. These pages are `noindex`.
- **Discoverability**: meta tags, Open Graph and Twitter tags, and an XML sitemap (`sitemap.xml`) of the organisation's own published records.
- **Decidim component**: a `contracts_sk` component that a space admin can add to a participatory process or assembly. It lists the organisation's published contracts. See [docs/decidim-component.md](docs/decidim-component.md).
- **Related contracts**: a partial and a reverse lookup for result and project pages. The host embeds them. See [docs/related-contracts.md](docs/related-contracts.md).

### CRZ import and provenance

- **Mirror of public CRZ records**: an idempotent import of already-public contract metadata from the CRZ register, through ekosystem.slovensko.digital (ADR-008). Mirrors are published with full provenance and an audit event. Checksums gate updates, malformed records are quarantined, and a failed sync never degrades existing data.
- **Effectiveness status**: a contract that must be published in the CRZ is shown as "zatiaľ neúčinná" (not yet effective) until the CRZ filing is confirmed and the effective date has come: the day after the CRZ publication, or the optional agreed later date (`agreed_effective_on`), whichever is later. The status is derived, never stored, and is an aid, not legal advice.
- **Two triggers**: a scheduled rake task and an editor-gated single-record import in the admin.
- **Labelled, never passed off as legal publication**: mirrors show an "Externally confirmed" badge with the mirror date. A mirror is marked stale when its import is older than `stale_after`, when its last import failed, or when it has no import timestamp.
- **CRZ filing confirmation**: an editor links a published editorial record to its CRZ id. The engine fetches the official record read-only, compares reference, IČO and amount, and records the filing (with an audited reason for any difference). The public page then shows "Published in CRZ on <date>".
- **CRZ handoff PDF**: a generated, always-regenerable PDF that helps with the clerical CRZ filing. It is labelled an aid, not a legal publication.

### Admin workflow

Admin pages sit under `<mount>/admin`. The overview is at `<mount>/admin`.

| Area | What it does |
|---|---|
| Home ("What needs doing today") | A short list of actions for the signed-in person only, by urgency: CRZ deadlines, records to review, returned drafts, records to publish, filings to confirm, missing data; one sentence and one button each. Counts per state and recent changes are one click away |
| Contract page | One read-only page per record: a five-step progress indicator (draft, check, approved, published, filed in the CRZ), whose turn it is, the next step as buttons, the facts |
| Contracts | Create, edit and list records; filter by state, source and submitter; search by title or reference |
| Lifecycle | One POST per transition: submit, return, approve, reject, publish, archive. Each transition is gated to the role that owns it |
| Four-eyes review | The person who last submitted a record cannot return, approve or reject it. Hosts with one person can opt out |
| Reviewer decisions | Return and reject require a reason (up to 1000 characters), shown on the record until it is resubmitted |
| Redaction confirmation | Before publishing, an editor confirms a redaction checklist (personal data, bank details, identifying amounts, sensitive content in documents) |
| CRZ deadline | Tracks the publication window (`signed_on` plus 3 months by default). Shows overdue and due-soon badges, and a filter |
| Parties | Object and contractor parties, with an IČO for contractors. Several parties can share a role |
| Documents | Attach, replace and remove files (content-type allowlist, 10 MB limit, sanitised file names) |
| Amendments | Numbered version-history entries. Drafts are edited and then published; published amendments are immutable |
| Links | Links to platform-level entities (for example accountability results or budget projects), resolved by a host resolver. Dangling links are flagged in admin and hidden publicly |
| Notes | An internal, append-only review thread per record. Notes are never shown publicly |
| Contract templates | An editor starts a contract from an organisation's Word (`.docx`) template: a form built from the template's merge fields, with the amount written in words, a numbered internal reference (`reference_pattern`, default `{N}/{YYYY}`) and the organisation header filled in. Generating produces an internal Word and PDF copy (editors only, with the personal data) and a publication copy with every personal value replaced. A redaction check refuses to store a publication copy that still contains a personal value. When an editor confirms redaction, the current publication PDF becomes the contract's publishable document. Regenerating clears the confirmation. Generated files are admin-only and never served by a public route. Organisation admins keep the header (**Hlavička obce**) and own the template permission; templates are loaded by an operator with a rake task. See [docs/contract-templates.md](docs/contract-templates.md) |
| Prefill templates | Organisation-level contract skeletons. Starting a contract from one is a prefill on the new-contract form (a separate, older feature) |
| Spreadsheet import | Imports a CSV of existing contracts as drafts. Shows a dry-run preview first. The import is all-or-nothing and re-importing the same file is refused. Excel `.xlsx` files are not read. See [docs/spreadsheet-import.md](docs/spreadsheet-import.md) |
| CRZ import | Single-record import by CRZ id (editor-gated), plus the rake task for batch sync |
| Roles | Organisation admins grant and revoke the `editor` and `reviewer` roles per user. Changes are audited |
| Audit trail | Read-only, append-only listing of lifecycle transitions, redaction, amendments, filings, imports and role changes. Filterable by contract |
| Notifications | Lifecycle events notify the users with the reviewer role (in-app and e-mail, user-controlled) |
| CRZ deadline digest | A morning e-mail to the confirmed admins and editors of an organisation, listing the contracts that are not yet effective and whose CRZ deadline is overdue or near. Nothing due, nothing sent. Run by a rake task that the host schedules (see [Rake tasks](#rake-tasks)) |

Template roles: organisation admins manage templates and the header; editors generate, regenerate and download the internal copy; any engine role holder can download the publication PDF. Details are in [docs/roles-and-permissions.md](docs/roles-and-permissions.md).

Roles and permissions are described in [docs/roles-and-permissions.md](docs/roles-and-permissions.md). The lifecycle states and transitions are in [docs/contract-lifecycle.md](docs/contract-lifecycle.md).

## Installation in a host

Add the gem to the host `Gemfile`, pinned to a release tag:

<!-- x-release-please-start-version -->
```ruby
gem "decidim-contracts_sk", github: "civora-org/decidim-contracts_sk", tag: "v1.11.0"
```
<!-- x-release-please-end -->

Use the latest tag from [Releases](https://github.com/civora-org/decidim-contracts_sk/releases). Pinning a tag keeps the host reproducible.

Then install the migrations and migrate:

```bash
bundle install
bin/rails decidim_contracts_sk:install:migrations
bin/rails db:migrate
```

`install:migrations` copies the engine's tables and later additive migrations into the host. It re-stamps their timestamps, which is fine for a new host. A host that already ran the engine migrations under their original timestamps should copy only the new ones, verbatim. The reference host describes that procedure under "Upgrading the engine" in its [README](https://github.com/civora-org/civora-host#upgrading-the-engine).

Contract templates need two more things on the host: Active Record encryption keys and LibreOffice (see [Upgrading to 1.10](#upgrading-to-110)).

Mount the engine in `config/routes.rb`. The mount point is your choice; the examples in this README use `/zmluvy`, and the reference host uses `/contracts`:

```ruby
mount Decidim::ContractsSk::Engine, at: "/zmluvy"
```

On Decidim 0.32 the locale also becomes part of core URLs (`/sk/...`); see [docs/locale-urls.md](docs/locale-urls.md) for the two mount styles and the legacy-path redirects.

### Upgrading to 1.10

1. **Bump the tag** in the host `Gemfile` to `v1.10.0` and run `bundle install`.
2. **Copy the new migrations verbatim**, keeping their original timestamps (see above; do not run `install:migrations` on a host that already has the engine's tables). Eight additive migrations, none touches an existing row:

   | Timestamp | Change |
   |---|---|
   | `20261013020000` | `agreed_effective_on` date column on contracts (optional agreed later effective date) |
   | `20261020100001` | `contract_templates` |
   | `20261020100002` | `contract_template_fields` |
   | `20261020100003` | `contract_organization_profiles` |
   | `20261020100004` | `contract_template_entries` (with the encrypted `personal_values`) |
   | `20261020100005` | `generated_documents` |
   | `20261020100006` | `reference_counters` |
   | `20261103000001` | `group_label` column on `contract_template_fields` |

   Then run `bin/rails db:migrate`.
3. **Set the Active Record encryption keys** in the host (`bin/rails db:encryption:init` generates values; keep them in the secret store, separate from database backups, and never lose them: stored personal values cannot be read without them). Which settings and how to rotate: [docs/contract-templates.md](docs/contract-templates.md#host-requirements-active-record-encryption).
4. **Install LibreOffice Writer** (headless) in the host image so that `soffice` is on the `PATH`, or set `Decidim::ContractsSk.pdf_converter` to your own callable.
5. **Schedule the CRZ deadline digest**: `bin/rails decidim_contracts_sk:crz_deadline_digest` once a day on working days (for example 07:30). The host's cron or job runner starts it, not the engine. It needs working SMTP.
6. **Fill in the organisation header** at `<mount>/admin/organization_profile` (an organisation admin), then have an operator load the first template with `decidim_contracts_sk:templates:import`.

No new role or configuration setting is needed: the template permissions reuse the existing roles and the organisation admin (see [docs/roles-and-permissions.md](docs/roles-and-permissions.md)). The public pages take a town accent colour from the organisation's primary colour automatically, see [docs/public-ui.md](docs/public-ui.md).

Then review the [configuration seams](#configuration). A host should set at least the CRZ IČO resolver (if it runs the import) and its own role resolver, if the default does not fit.

## Configuration

All settings are config-time. Set them in an initializer such as `config/initializers/contracts_sk.rb` and never change them at request time.

| Setting | Default | Purpose |
|---|---|---|
| `role_resolver` | Admins get both roles; other users get the roles granted in the admin | Maps a user to `editor` and `reviewer` (callable `(user, context)`) |
| `notification_candidates` | Confirmed, available admins and users with a stored `reviewer` role | Limits who can be notified about a submission. It never grants a role |
| `allow_self_review` | `false` | Disables the four-eyes rule for single-person organisations. Each such action is audited as `contract.<event>_self` |
| `second_factor_satisfied` | Always `true` | Callable `(user, session) -> boolean`. Falsey redirects engine admin requests to the second factor |
| `second_factor_redirect_path` | Decidim root | Callable `(controller) -> path` for the second-factor challenge |
| `crz_organization_ico_resolver` | Resolves nothing (the import refuses to run) | Callable `(organization) -> IČO`. Limits the CRZ import to the organisation's own records |
| `stale_after` | 48 hours | Age after which a CRZ mirror is marked stale (Integer seconds or `ActiveSupport::Duration`) |
| `crz_deadline` | `3.months` | Publication window behind the deadline badges. Must be a positive `ActiveSupport::Duration` |
| `supported_link_target_types` | Empty (no linking) | Whitelist of target class names for contract links |
| `link_target_resolver` | Resolves nothing | Callable `(link) -> { label:, url: }` (or `nil`). It must scope lookups to the organisation itself |

### Public look and the Civora credit

The public pages read the host's Civora theme tokens (`--civora-*`: paper, cream, ink, rule, radius, display font) and fall back to the engine's own colours on a host without them, so no setting is needed. They end with a small Civora credit. It is hidden automatically when the host layout already renders a `.civora-sign` signature; any other host can hide it by putting `data-cs-credit="off"` on an element in its layout, for example `<body data-cs-credit="off">`. Details: [public UI](docs/public-ui.md).

Example for a host that grants roles to admins only:

```ruby
Decidim::ContractsSk.role_resolver = ->(user, _context) { user&.admin? ? %i[editor reviewer] : [] }
```

Example for a host that links accountability results. The resolver receives a link and must scope the lookup to the link's organisation itself (`link.contract.organization`); a bare `target_id` lookup is not tenant-safe:

```ruby
Decidim::ContractsSk.supported_link_target_types = %w[Decidim::Accountability::Result]
Decidim::ContractsSk.link_target_resolver = lambda do |link|
  result = Decidim::Accountability::Result.find_by(id: link.target_id)
  next nil unless result

  { label: result.title, url: Decidim::Accountability::ResultPrinter.new(result).result_url }
end
```

The override replaces the default role resolver completely, including stored roles. A host that wants stored roles must union them itself.

Details: [roles and permissions](docs/roles-and-permissions.md), [CRZ import](docs/crz-import.md), [search alerts](docs/search-alerts.md) and [public UI](docs/public-ui.md).

## Rake tasks

Run from the host root. Replace `<organization_id>` with the Decidim organisation id.

| Task | Purpose |
|---|---|
| `decidim_contracts_sk:crz_import:sync[<organization_id>,<SINCE>]` | Mirror CRZ records updated since `SINCE` (ISO 8601; also read from the `SINCE` env variable). Needs the organisation's IČO resolver. Uses the first admin who accepted the admin terms as the audit actor, or the account in `ACTOR_EMAIL`. Schedule nightly |
| `decidim_contracts_sk:crz_import:prune_out_of_scope[<organization_id>]` | Lists mirrors that are not the organisation's own records. A dry run unless `CONFIRM=1`, which deletes them |
| `decidim_contracts_sk:crz_import:backfill_published_on[<organization_id>]` | Fetches the CRZ publication date for mirrors that lack it. A dry run unless `CONFIRM=1`. Paced by `PAUSE` (default 1.1 s) to respect the upstream rate limit |
| `decidim_contracts_sk:crz_deadline_digest[<organization_id>]` | Send the morning CRZ deadline digest to the organisation's admins and editors. Omit the id to run for all organisations. Output is counts only. Schedule once a day on working days. Needs SMTP |
| `decidim_contracts_sk:templates:import[<organization_id>,<path>,<lineage_key>,<name>]` | Load a Word contract template: lints and sanitises the `.docx`, reads the optional `<path>.fields.yml` sidecar and activates it. A second import with the same `lineage_key` creates the next version |
| `decidim_contracts_sk:subscriptions:deliver[<organization_id>]` | Send the daily search-alert digests. Omit the id to run for all organisations. Schedule once a day |
| `decidim_contracts_sk:subscriptions:purge_expired` | Delete unconfirmed subscriptions older than 48 hours |
| `decidim_contracts_sk:seed_demo[<organization_id>]` | Seed fictional contracts in every lifecycle state. Demo and manual testing only; never on a production database |

The demo seed and its walkthroughs are in [docs/manual-test-scenarios.md](docs/manual-test-scenarios.md).

## Known limitations

- **CRZ import is a metadata mirror.** It does not replace the register. Publishing to CRZ, mirroring documents, importing currency or VAT (absent upstream) and a nightly-ZIP fallback are out of scope. See [docs/crz-import.md](docs/crz-import.md).
- **No ownership per record.** Any user with an engine role in the organisation can act on any of its records. See [docs/contract-lifecycle.md](docs/contract-lifecycle.md).
- **The host owns the ActiveStorage schema.** The engine attaches files but ships no storage-table migration.
- **One role-resolver seam.** Overriding `role_resolver` replaces the default completely.
- **The component is a read-only lens.** Contracts carry no participatory-space reference, so the component lists the same published records as the catalogue in every space it is added to.
- **Related contracts need host views.** The engine provides the partial and lookup, but on Decidim 0.31 the host overrides two view files to render them. See [docs/related-contracts.md](docs/related-contracts.md).

## Documentation

| Document | Covers |
|---|---|
| [contract-lifecycle.md](docs/contract-lifecycle.md) | States, transitions, role per transition, deadline |
| [roles-and-permissions.md](docs/roles-and-permissions.md) | Role mapping, four-eyes rule, assigning roles |
| [contracts-domain-notes.md](docs/contracts-domain-notes.md) | Domain decisions and the statistics, supplier and filter designs |
| [contract-templates.md](docs/contract-templates.md) | Contract templates: schema, encryption keys, generation, header screen, publication copy, roles, template author guide |
| [contract-template-services.md](docs/contract-template-services.md) | Template service objects: linter, sanitiser, filler, PDF converter seam, redaction verifier |
| [crz-import.md](docs/crz-import.md) | CRZ mirror: triggers, scheduling, failure modes, collisions |
| [open-data.md](docs/open-data.md) | CSV and JSON export, Atom feed, field list, licence |
| [locale-urls.md](docs/locale-urls.md) | Locale in URLs on Decidim 0.31 and 0.32: what the engine emits, mount styles, legacy redirects |
| [search-alerts.md](docs/search-alerts.md) | E-mail alerts: privacy design and operations |
| [spreadsheet-import.md](docs/spreadsheet-import.md) | CSV import format and rules |
| [decidim-component.md](docs/decidim-component.md) | The `contracts_sk` participatory-space component |
| [related-contracts.md](docs/related-contracts.md) | Related-contracts block for result and project pages |
| [public-ui.md](docs/public-ui.md) | Public page structure and styling rule |
| [pilot-operations.md](docs/pilot-operations.md) | Pilot runbook (in Slovak) |
| [manual-test-scenarios.md](docs/manual-test-scenarios.md) | Demo data and click-through scenarios |
| [qa-checklist.md](docs/qa-checklist.md) | Manual accessibility and UX checklist |
| [spikes/contract-templates-toolchain.md](docs/spikes/contract-templates-toolchain.md) | Toolchain findings behind the template feature (LibreOffice, sablon) |
| [pilot-feedback-log.md](docs/pilot-feedback-log.md) | Template for pilot feedback |
| [docs/spikes/](docs/spikes) | Design spikes (for example the Decidim upgrade path) |

## Development

```bash
bin/setup              # bundle install
bundle exec rspec      # test suite: deterministic and offline, no database
bundle exec rubocop    # lint
bin/console            # load the gem in IRB
```

The suite boots a minimal, ActiveRecord-free dummy app (`spec/dummy`) that mounts the engine and runs request specs. Database-backed specs are opt-in:

```bash
CONTRACTS_SK_DB=1 bundle exec rspec
```

This runs the `:db` groups against an in-memory SQLite adapter and needs the `sqlite3` gem. CI runs these groups.

To test against a Decidim line, set `DECIDIM_VERSION`. Without it, the gemspec range resolves to the newest line that the local Ruby supports:

```bash
DECIDIM_VERSION=0.31 bundle install   # Ruby 3.3
DECIDIM_VERSION=0.32 bundle install   # Ruby 3.4
```

The engine does not commit `Gemfile.lock`, so CI resolves fresh dependencies on every run.

Public views carry their own stylesheet. Hosts compile their CSS at image build time and silently drop classes the engine uses. See [docs/public-ui.md](docs/public-ui.md).

## Contributing

- **Issues** are tracked in the Civora platform repository, [civora-org/civora-platform](https://github.com/civora-org/civora-platform). References such as `civora-org/civora-platform#64` in this repository point there.
- **Pull requests** target `main`. CI must pass for both Decidim lines and `bundler-audit`. Use Conventional Commits (`feat:`, `fix:`, `docs:`).
- **Changelog**: `CHANGELOG.md` is generated by [release-please](https://github.com/googleapis/release-please) from commit messages. Do not edit it by hand.

## Security

Report vulnerabilities privately to denys@civora.sk. Do not open a public issue.

## License

AGPL-3.0, the same licence as Decidim. See [LICENSE-AGPLv3.txt](LICENSE-AGPLv3.txt).
