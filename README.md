# decidim-contracts_sk

A [Decidim](https://decidim.org) engine for Slovak public contracts. It provides:

- a **workflow** for drafting, reviewing and publishing public contract records, with role separation and an audit trail;
- a **public catalogue** of the published records, with search, filters, statistics, supplier pages and open-data downloads.

The engine is built for Slovak municipalities and other public-sector organisations. It is part of the [Civora](https://github.com/civora-org) platform but works as a standalone Decidim module.

**Status:** pilot. The latest release is [v1.7.1](https://github.com/civora-org/decidim-contracts_sk/releases). It runs in the reference host, [civora-org/civora-host](https://github.com/civora-org/civora-host). The gem is not published to RubyGems; hosts install it from the Git tag. Release notes are in [CHANGELOG.md](CHANGELOG.md).

## Requirements

| Item | Supported |
|---|---|
| Decidim | `0.31.x` and `0.32.x` (`decidim-core` and `decidim-admin`, `>= 0.31.5`, `< 0.33`) |
| Ruby | `>= 3.3` (CI runs Ruby 3.3.4 with Decidim 0.31 and Ruby 3.4.7 with Decidim 0.32) |
| Database | The reference host runs PostgreSQL. The default test suite needs no database |

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
- **Two triggers**: a scheduled rake task and an editor-gated single-record import in the admin.
- **Labelled, never passed off as legal publication**: mirrors show an "Externally confirmed" badge with the mirror date. A mirror is marked stale when its import is older than `stale_after`, when its last import failed, or when it has no import timestamp.
- **CRZ filing confirmation**: an editor links a published editorial record to its CRZ id. The engine fetches the official record read-only, compares reference, IČO and amount, and records the filing (with an audited reason for any difference). The public page then shows "Published in CRZ on <date>".
- **CRZ handoff PDF**: a generated, always-regenerable PDF that helps with the clerical CRZ filing. It is labelled an aid, not a legal publication.

### Admin workflow

Admin pages sit under `<mount>/admin`. The overview is at `<mount>/admin`.

| Area | What it does |
|---|---|
| Overview | Work waiting for the current user (reviews, returned records, records ready to publish), the CRZ deadline watch, counts per state and the last audit events |
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
| Templates | Organisation-level templates. Starting a contract from one is a prefill on the new-contract form |
| Spreadsheet import | Imports a CSV of existing contracts as drafts. Shows a dry-run preview first. The import is all-or-nothing and re-importing the same file is refused. Excel `.xlsx` files are not read. See [docs/spreadsheet-import.md](docs/spreadsheet-import.md) |
| CRZ import | Single-record import by CRZ id (editor-gated), plus the rake task for batch sync |
| Roles | Organisation admins grant and revoke the `editor` and `reviewer` roles per user. Changes are audited |
| Audit trail | Read-only, append-only listing of lifecycle transitions, redaction, amendments, filings, imports and role changes. Filterable by contract |
| Notifications | Lifecycle events notify the users with the reviewer role (in-app and e-mail, user-controlled) |

Roles and permissions are described in [docs/roles-and-permissions.md](docs/roles-and-permissions.md). The lifecycle states and transitions are in [docs/contract-lifecycle.md](docs/contract-lifecycle.md).

## Installation in a host

Add the gem to the host `Gemfile`, pinned to a release tag:

```ruby
gem "decidim-contracts_sk", github: "civora-org/decidim-contracts_sk", tag: "v1.7.1"
```

Use the latest tag from [Releases](https://github.com/civora-org/decidim-contracts_sk/releases). Pinning a tag keeps the host reproducible.

Then install the migrations and migrate:

```bash
bundle install
bin/rails decidim_contracts_sk:install:migrations
bin/rails db:migrate
```

`install:migrations` copies the engine's tables and later additive migrations into the host. It re-stamps their timestamps, which is fine for a new host. A host that already ran the engine migrations under their original timestamps should copy only the new ones, verbatim. The reference host describes that procedure under "Upgrading the engine" in its [README](https://github.com/civora-org/civora-host#upgrading-the-engine).

Mount the engine in `config/routes.rb`. The mount point is your choice; the examples in this README use `/zmluvy`, and the reference host uses `/contracts`:

```ruby
mount Decidim::ContractsSk::Engine, at: "/zmluvy"
```

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
| [crz-import.md](docs/crz-import.md) | CRZ mirror: triggers, scheduling, failure modes, collisions |
| [open-data.md](docs/open-data.md) | CSV and JSON export, Atom feed, field list, licence |
| [search-alerts.md](docs/search-alerts.md) | E-mail alerts: privacy design and operations |
| [spreadsheet-import.md](docs/spreadsheet-import.md) | CSV import format and rules |
| [decidim-component.md](docs/decidim-component.md) | The `contracts_sk` participatory-space component |
| [related-contracts.md](docs/related-contracts.md) | Related-contracts block for result and project pages |
| [public-ui.md](docs/public-ui.md) | Public page structure and styling rule |
| [pilot-operations.md](docs/pilot-operations.md) | Pilot runbook (in Slovak) |
| [manual-test-scenarios.md](docs/manual-test-scenarios.md) | Demo data and click-through scenarios |
| [qa-checklist.md](docs/qa-checklist.md) | Manual accessibility and UX checklist |
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
