# Decidim component (civora-org/civora-platform#89)

The engine registers a Decidim component, `contracts_sk`, so contracts can appear **inside participatory spaces** (processes, assemblies) next to the standalone catalogue. Registration is purely additive: the mounted engine, its routes and its catalogue do not depend on it and need no participatory space.

## What it is

A **presentation lens**, not a data owner. A `Contract` carries no component or space reference (ADR-009: no `decidim_component_id` column), so the component shows the organization's **published** contracts: the same records, through the same published-only, organization-scoped read (`PublicCatalogue#published_contracts`), as the catalogue. "Relevant to the space" therefore means "published, of the space's organization", nothing narrower. Administration (create, review, publish) stays organization-scoped in the mounted engine's admin; the component has no admin engine.

## Surface

- **List** (`GET <component root>`): the component's own name as the heading, the translated announcement setting, the shared register rows (same partial as the catalogue), 25 per page. It reads only the `page` parameter: no search, filters, sorting, open-data block, or statistics switch.
- **Detail** (`GET <component root>/contracts/:id`): the catalogue's detail view rendered as is (one view stack), so facts, parties, documents, linked results, CRZ provenance and the published version history cannot drift. A contractor's name renders as plain text (supplier pages are routed only by the mounted engine).
- **Not in a space:** the admin namespace, the open-data export, the Atom feed, the sitemap, supplier pages and statistics. They live only in the mounted engine.
- **Settings:** `announcement` (translated text) in the global and the step scope.

## Code map

| File | Role |
|---|---|
| `lib/decidim/contracts_sk/component.rb` | `Decidim.register_component(:contracts_sk)` (required once from the `decidim_contracts_sk.component` initializer) |
| `lib/decidim/contracts_sk/space_component/engine.rb` | the second, minimal engine Decidim mounts under `.../f/:component_id`; two routes and a `root` |
| `app/controllers/decidim/contracts_sk/space_component/` | `ApplicationController < Decidim::Components::BaseController`, `ContractsController` |
| `app/views/decidim/contracts_sk/space_component/contracts/` | `index` (minimal), `show` (renders the shared detail template) |
| `config/locales/{en,sk}.yml` (`decidim.components.contracts_sk`) | the name and settings labels Decidim's admin looks up by manifest name |

## Decisions

- **Second engine, not a re-mount.** The standalone engine's route table carries the whole admin and the export/feed/sitemap routes; mounting it in a space would expose them there. The component engine shares the gem root but switches off migrations, tasks, seeds and the root `config/routes.rb` (the pattern of decidim-pages' admin engine).
- **`published` only, not `PUBLIC_STATES`.** The catalogue's Gate-1 scope pins `published` (archived visibility is a separate, later decision); the component reuses it, so both surfaces show the same records. The permission table (`published` and `archived` are publicly readable) is checked on the detail page as defence in depth and stays the wider of the two.
- **The permission class is wired and live.** The manifest names `Decidim::ContractsSk::Permissions`; the detail action calls `enforce_permission_to :read, :contract`. Decidim's own component permissions (`:read`/`:update`/`:share` of `:component`) are left unset by the class, so the core decides them.
- **No icon file.** `icon` must name an SVG in the host's compiled bundle, and a missing entry raises in the admin component list; Decidim falls back to its generic icon. Only `icon_key` is set.
- **No exports, stats, seeds, hooks, API type, data-portability or newsletter entries.** The component owns no data; see the audit below. Open data stays the engine's own `/export` surface (CRZ mirrors are never re-published, ADR-008).
- **No `register_resource`.** ADR-009 chose the engine-owned link join over native `Decidim::ResourceLink`.

## Host verification

Add the component to a participatory process in the host admin and open it (steps below). What the offline specs cannot prove: the space layout and breadcrumbs, the space-visibility and component-published gates of Decidim's real base controller, the core announcement partial's markup, Decidim's real permission chain, and that the inline `.cs-` styles reach `<head>` through the space layout.

Live check, as a Decidim admin: Admin > Participatory processes > pick a process > Components > Add component > "Contracts" (name it, optionally write an announcement) > Publish. Then open the process on the public site: the component appears in the process menu and its page lists the organization's published contracts; open a row for the detail page. Compare with the mounted catalogue (`/zmluvy`): the same records.

## Decidim call-site audit

Every consumer of the component manifest in the pinned 0.31.7 gems, and whether this component covers it or deliberately does not support it (paths are relative to the gem directory).

| # | Consumer (pinned 0.31.7 gem path:line) | What it reads from the manifest | Status |
|---|---|---|---|
| 1 | decidim-core `lib/decidim/core.rb:841-843`, `:893-895`, `:910-912`, `:935-937` | `register_component`, `component_manifests`, `find_component_manifest`, `component_registry` | Covered: the `decidim_contracts_sk.component` initializer registers once; the spec asserts a single registration |
| 2 | decidim-core `lib/decidim/manifest_registry.rb:15` | `manifest.validate!` (name presence) | Covered: `valid?` asserted on the registered manifest |
| 3 | decidim-participatory_processes `lib/.../engine.rb:33-39`, decidim-assemblies `lib/.../engine.rb:32-38` | `manifest.engine` mounted at `/` under `.../f/:component_id` | Covered: `SpaceComponent::Engine`, route table pinned (root + `contracts/:id`) |
| 4 | decidim-core `app/helpers/decidim/component_path_helper.rb:11-14` | `EngineRouter.main_proxy(component).root_path` (needs a named `root`) | Covered: `root` route, spec-pinned |
| 5 | decidim-participatory_processes `lib/.../admin_engine.rb:111-115`, decidim-assemblies `lib/.../admin_engine.rb:101-105` | `manifest.admin_engine` mount | Deliberately unsupported: `nil` (nothing to manage per component; admin stays org-scoped in the mounted engine) |
| 6 | decidim-core `component_path_helper.rb:42-44`, decidim-admin `components/_actions.html.erb:17,73`, `_component_row.html.erb:7`, PP `menu.rb:104`, assemblies `menu.rb:82`, admin `application_helper.rb:32` | `admin_engine` presence, `admin_engine.try(...)` | Safe on `nil`: the "Manage" entries are hidden, `try` returns nil |
| 7 | decidim-core `app/controllers/decidim/components/base_controller.rb:56-63` | `permissions_class` first in the public permission chain | Covered: `Decidim::ContractsSk::Permissions`; detail action enforces `:read, :contract`; unset for `:component` subjects (spec) |
| 8 | decidim-core `app/permissions/decidim/permissions.rb:52-58,181`, decidim-admin `app/permissions/decidim/admin/permissions.rb:270`, decidim-api `lib/decidim/api/graphql_permissions.rb:108-111` | `permissions_class.new(...).permissions` for `:component` actions | Covered: the class leaves `:component` actions unset (fail-closed pass-through), spec-pinned in both scopes |
| 9 | decidim-admin `app/controllers/decidim/admin/components_controller.rb:14,34,198-204` | the add-component list, `component_form_class`, `decidim.components.contracts_sk.name` | Covered: stock `ComponentForm`; `name` locale key in en + sk, spec-pinned |
| 10 | decidim-admin `components/_settings_fields.html.erb:1-7`, `commands/update_component.rb:81`, decidim-core `lib/decidim/has_settings.rb:17` | `settings(:global/:step)` attributes + `decidim.components.contracts_sk.settings.<scope>.<attr>` labels | Covered: `announcement` in both scopes (the core partial reads both), labels in en + sk, real schema built in specs |
| 11 | decidim-core `app/views/decidim/shared/_component_announcement.html.erb:1` | `current_settings.announcement` and `component_settings.announcement` | Covered: both scopes declared (a missing `:step` raises `NoMethodError`) |
| 12 | decidim-admin `commands/create_component.rb:16`, `publish_component.rb:22`, `unpublish_component.rb:21`, `update_component_permissions.rb:75`, PP `duplicate_participatory_process.rb:102`, assemblies `duplicate_assembly.rb:84`; decidim-core `component_manifest.rb:112-118` | `run_hooks` (create/publish/unpublish/permission_update/duplicate) | Deliberately unsupported: no hooks; `run_hooks` returns nil when none (nothing to create, index or copy; a destroyed or duplicated component touches no contract) |
| 13 | decidim-admin `components/_actions.html.erb:85` | `actions.any?` (the permissions screen) | Deliberately unsupported: no actions, screen hidden (read-only component) |
| 14 | decidim-core `app/models/decidim/component.rb:20-23,74,79,128` | registered-manifest default scope, `form_class`, `primary_stat`, `serializes_specific_data?` | Covered: registered; no stats so `primary_stat` is nil; `serializes_specific_data` false |
| 15 | decidim-core `app/serializers/decidim/exporters/participatory_space_components_serializer.rb:31`, `importers/participatory_space_components_importer.rb:57` | space export/import specific data | Deliberately unsupported: guarded by `serializes_specific_data?` (false) |
| 16 | decidim-core `app/controllers/decidim/open_data_controller.rb:28-30`, `app/services/decidim/open_data_exporter.rb:45,226`, `app/jobs/decidim/export_job.rb:11`, decidim-admin `exports/_dropdown.html.erb:13` | `export_manifests` (admin and open-data exports) | Deliberately unsupported: no export manifests; open data stays the engine's own `/export` (ADR-008: CRZ mirrors are never re-published) |
| 17 | decidim-admin `imports/_dropdown.html.erb:12`, `forms/import_form.rb:83`, `controllers/imports_controller.rb:78` | `import_manifests` | Deliberately unsupported: none (import goes through the engine's admin, org-scoped) |
| 18 | decidim-core `lib/decidim/download_your_data_serializers.rb:17` ("Download your data") | `data_portable_entities` | Deliberately unsupported: `[]` (contracts are organization records, not a user's data; the concatenation tolerates the empty list) |
| 19 | decidim-admin `app/queries/decidim/admin/newsletter_recipients.rb:110-112` | `newsletter_participant_entities` | Deliberately unsupported: `[]` (no participants) |
| 20 | decidim-core `app/presenters/decidim/stats_presenter.rb:42-43`, `app/queries/decidim/stats_followers_count.rb:18` | `stats` | Deliberately unsupported: no stats registered (the registry is created empty on demand) |
| 21 | decidim-core `lib/decidim/seeds.rb:148-150`, `component_manifest.rb:138-143` | `seed!(space)` | Deliberately unsupported: no seeds block, `seed!` is a no-op (records are organization-level, seeded by `decidim_contracts_sk:seed_demo`) |
| 22 | decidim-core `lib/decidim/api/interfaces/component_interface.rb:24`, decidim-api `lib/decidim/api.rb:68` | `query_type` constantized | Covered by default: `Decidim::Core::ComponentType` exists (`lib/decidim/api/types/component_type.rb:5`); no contract data in GraphQL |
| 23 | decidim-core `app/helpers/decidim/icon_helper.rb:26-31`, `layout_helper.rb:83-96` | `icon` (asset-pack lookup via `asset_pack_path` -> `Shakapacker::Manifest#lookup!`, raises on a missing entry) | Deliberately unsupported: no `icon` (generic fallback); `icon_key` only |
| 24 | decidim-core `lib/decidim/upgrade/wysiwyg_migrator.rb:127-136` | `settings(type).attributes` with `editor` | Covered by Decidim itself: the attribute is a standard translated editor text |
| 25 | decidim-core `ResourceLocatorPresenter`, search, follows, comments, links | `register_resource` | Deliberately unsupported: no resource registered (ADR-009 chose the engine-owned join over `Decidim::ResourceLink`) |
