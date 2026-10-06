# M03-06-A spike: can non-admin engine-role holders use the engine admin?

Issue: civora-org/civora-platform#108 (parent #95). Spike only: no production code changed.
Pinned sources: decidim-admin 0.31.7, decidim-core 0.31.7, decidim-participatory_processes 0.31.7
(paths below are relative to each gem root). Engine paths are relative to this repo.

## Question

Can a signed-in user who is NOT a Decidim organization admin, but holds engine roles
(editor, reviewer) through `Decidim::ContractsSk.role_resolver`, reach and use the engine
admin under `/contracts/admin`?

## Answer

**Yes, with conditions.** Every engine admin page works for such a user on a real host:
dashboard, contracts index, new/create/edit, lifecycle transition, audit trail, sidebar
entry. No Decidim gate stops them. The conditions are three UX defects that sit around
the working core (none is a hard blocker):

1. **Denial redirect lands on a 404.** When the engine denies an action (reviewer opens
   "new", roleless user opens the index, a non-admin opens a future `user_roles` page),
   Decidim redirects to `/admin`, and `/admin` does not exist for non-admins (404).
2. **The Decidim layout's own "home" links (`/admin`) 404** for them: logo and breadcrumb
   home icon. Cosmetic, inside Decidim's layout.
3. **No entry point.** Nothing links a non-admin to `/contracts/admin`: Decidim's public
   admin bar is gated on `:read :admin_dashboard`, which they lack.

Conclusion in the issue's vocabulary: **A (works)**, with the three conditions above.
This is the opposite of what the issue feared ("not yet proven that Decidim's admin layout,
sidebar and gates let a non-admin through"): they do.

## Why it works (code, cited)

How a request travels, and where each candidate gate turns out to be absent or satisfied.

| # | Candidate gate | Finding | Citation |
|---|---|---|---|
| 1 | Route-level admin constraint | Applies only to routes **inside the Decidim admin engine** (`Decidim::Admin::Engine`, mounted at `/admin`). The host mounts the contracts engine itself, outside it, so the constraint never runs for `/contracts/admin`. The engine's own `before_action :authenticate_user!` is the only entry floor. | decidim-admin `config/routes.rb:4`; `lib/decidim/admin/engine.rb:23`; `app/constraints/decidim/admin/organization_dashboard_constraint.rb:18-20,36-41`; host `config/routes.rb:6-7`; engine `app/controllers/decidim/contracts_sk/admin/application_controller.rb:20` |
| 2 | `Decidim::Admin::ApplicationController` concerns | Includes `NeedsOrganization`, `NeedsPermission`, `NeedsPasswordChange`, `NeedsSnippets`, `NeedsAdminTosAccepted`, ... None is an "is admin" gate. There is no `ensure_admin_access` in 0.31.7 (grep finds none). Authorization is only what `enforce_permission_to` asks, per action. | decidim-admin `app/controllers/decidim/admin/application_controller.rb:6-21,44-61` |
| 3 | Admin terms of service | `tos_accepted_by_admin` returns early unless `user_has_any_role?(current_user, broad_check: true)`. That predicate is true only for admins, `user.roles.any?`, or a participatory process / assembly / conference user role. A plain participant holding only engine roles has none, so **no TOS redirect** (check 7: not redirected). Note the default resolver already requires `admin_terms_accepted?` only for admins. | decidim-admin `app/controllers/concerns/decidim/admin/needs_admin_tos_accepted.rb:16-21`; decidim-core `app/helpers/concerns/decidim/user_role_checker.rb:10-20` |
| 4 | Permission chain | Engine chain is `[ContractsSk::Permissions, *super]`; `super` resolves to `[Decidim::Admin::Permissions]` on the real host (verified: `Decidim.permissions_registry.chain_for(Decidim::Admin::ApplicationController)` returns exactly that). `Decidim::Admin::Permissions` only `disallow!`s when there is no user, and only `allow!`s its own subjects, so it neither blocks nor needs to allow the engine's subjects. The engine decides `:contract`, `:party`, ... and `:audit_event` purely from `role_resolver`. | engine `application_controller.rb:22-24`; engine `app/permissions/decidim/contracts_sk/permissions.rb:132-144,311-313`; decidim-admin `app/permissions/decidim/admin/permissions.rb:14-17,27,36-78`; decidim-core `app/controllers/concerns/decidim/needs_permission.rb:59-72` |
| 5 | Admin layout | Resolves by controller inheritance to `layouts/decidim/admin/application` (no engine layout). It needs only `current_organization` and `current_user` (title bar prints the email). It renders `main_menu_modules`, `main_menu`, title bar, breadcrumb; none requires an admin space or `admin_terms_accepted?`. | decidim-admin `app/views/layouts/decidim/admin/_application.html.erb:21,32-33,37`; `_title_bar.html.erb:31-33`; `app/helpers/decidim/admin/menu_helper.rb:8-25` |
| 6 | Sidebar / menus | Items are `if:`-gated per module. Core items use `allowed_to?` and are hidden for non-admins; the processes entry uses `allowed_to?(:enter, :space_area, ...)`. The engine's entry is gated by `Menu.holds_engine_role?`, a role-only check, so a role holder sees exactly one entry (**Contracts** / **Zmluvy**) and nothing else (verified on the live render). | decidim-admin `lib/decidim/admin/menu.rb:214-230`; decidim-participatory_processes `lib/decidim/participatory_processes/menu.rb:48,59`; engine `lib/decidim/contracts_sk/menu.rb:71-86,99-112` |

### How other Decidim modules admit non-admin roles (and why we need not copy it)

Decidim's mechanism is **the participatory space**, not the admin controller. `Decidim::Admin::Permissions`
answers `:enter :space_area` and `:read :admin_dashboard` by asking every space manifest's
`permissions_class` (`space_allows_admin_access_to_current_action?`), so a process valuator or
collaborator is admitted because the *processes* permissions say so
(`user_can_enter_processes_space_area?` -> `user.admin? || has_manageable_processes?`), and
the processes admin controllers are space-scoped. Citations: decidim-admin
`app/permissions/decidim/admin/permissions.rb:27,99,261-274`; decidim-participatory_processes
`app/permissions/decidim/participatory_processes/permissions.rb:6-8,140-160`.
This is also why such users pass the route constraint on `/admin` (it asks
`:read :admin_dashboard`, `constraint:36-41`), and why `tos_accepted_by_admin` sends them to the
TOS page: they hold a Decidim role.

The contracts engine is not a participatory space; it is a plain content module mounted outside
`Decidim::Admin::Engine`. It therefore sits on the **other** side of that mechanism: its own
`Permissions` decides, with no space registration, so non-admins pass the controllers without help.
The price is that the `/admin` dashboard (constraint) stays closed to them, which is the root of
defects 1 and 2.

## Live proof

The dummy harness cannot prove this: `spec/dummy/config/application.rb` replaces
`Decidim::Admin::ApplicationController` with a stand-in (the very gates in question) and
`Decidim::User` with an AR stand-in, so a request spec under `CONTRACTS_SK_DB=1` passes for any
stubbed user whatever Decidim does. A throwaway spec confirming that harness behaviour
(`GET /admin` 200, `GET /admin/contracts` 200 for a non-admin user with both roles) ran green and
is **not kept**: it adds no regression value, and the harness result says nothing about the
real gates. The existing admin request specs already pin the engine-side role rules.

The real proof ran on the real stack: the running `civora-host-app-1` host (Decidim 0.31.7,
engine v1.6.0, PostgreSQL), through `ActionDispatch::Integration::Session` with a Warden-signed-in
plain participant (`admin: false`, no Decidim roles), the role resolver swapped **in-process only**
to grant `[:editor, :reviewer]` (equivalent to the issue's initializer, without touching the host's
files), everything inside a transaction rolled back at the end (verified: 0 leftover users or
contracts). Results are in `tmp/evidence/108.md`.

| # | Check (signed in as non-admin role holder) | Result |
|---|---|---|
| 1 | `GET /contracts/admin/contracts` | 200, admin layout rendered |
| 1a | `GET /contracts/admin` (engine dashboard) | 200 |
| 2 | New form, `POST` create `MANUAL-2026-CLERK`, edit | 200 / 302 to index / 200; record created as `draft` |
| 3 | `POST .../submit` | 302 to index; state `draft` -> `in_review` |
| 4 | `GET /contracts/admin/audit_events` | 200 |
| 5 | `GET /admin` (Decidim dashboard) | 404 (route constraint), as expected |
| 6 | Sidebar | renders; the **only** modules entry is Contracts (`Zmluvy` in sk) -> `/contracts/admin` |
| 7 | `GET /admin/admin_terms/show` / TOS redirect | no redirect on any engine page; the TOS page itself is 404 for them |
| R | Reviewer-only user opens `GET .../contracts/new` (denied by the engine) | 302 -> `/admin/?locale=en` -> **404** |
| 0 | Roleless user opens the contracts index | 302 -> `/admin/?locale=en` -> **404** |

Caveats: HTTP-level evidence only (no screenshots); production-mode container whose engine
checkout is a sibling worktree at v1.6.0; one user, one organization.

## Blockers and defects

No hard blocker. Defects, with the line that causes each:

- **D1, denial redirect 404.** `Decidim::Admin::ApplicationController#user_has_no_permission_path`
  and `#user_not_authorized_path` return `decidim_admin.root_path` (decidim-admin
  `app/controllers/decidim/admin/application_controller.rb:47-53`); `NeedsPermission#user_has_no_permission`
  redirects there unless there is a referer (decidim-core `needs_permission.rb:22-32`).
  `/admin` is under the dashboard constraint (`config/routes.rb:4`, constraint `:36-41`), which
  fails for non-admins, so the redirect ends in a routing error rendered as 404. In a browser a
  referer usually exists (user bounces back to the previous page), so the 404 shows on direct URL
  entry and on bookmarks; the flash is still set.
- **D2, layout home links.** `_application.html.erb:21` (logo) and `_breadcrumb.html.erb:5` (home
  icon) link to `decidim_admin.root_path`. Inside Decidim's layout; fixable only by an override
  of the layout partials (not worth it).
- **D3, no entry point.** The public admin bar renders only if
  `allowed_to?(:read, :admin_dashboard)` (decidim-core `app/views/layouts/decidim/_wrapper.html.erb:19`),
  false for non-admins; the engine's public menu entry points at the catalogue only
  (engine `lib/decidim/contracts_sk/menu.rb:37-53`).
- **Note N1 (resolver context).** The admin menu calls `role_resolver.call(user, organization)`
  (`menu.rb:106`) while `Permissions` calls it with the permissions context Hash
  (`permissions.rb:311-313`). A resolver that reads `context` will see two shapes. The planned
  DB-backed default (#110) uses only `user`, so it is unaffected; keep it that way.

## Options

**Option 1, proceed as written + small denial-redirect fix (recommended).**
Do nothing to the gates; override `user_has_no_permission_path` and `user_not_authorized_path` in
`Decidim::ContractsSk::Admin::ApplicationController` to return the public catalogue
(`decidim_contracts_sk.contracts_path`), which every signed-in user can reach, and pin it with a
request spec (plus keep the existing dummy-harness assertions valid, since the stand-in returns
"/" today; the override changes that expectation in the denied-path specs).
Cost: about 6 lines + spec updates (the denied-path assertions in `spec/requests/admin/*` expect
`redirect_to("/")`). Risk: low; touches only denial redirects, authorization is unchanged. A
referer-less denial then lands on the catalogue instead of a 404.

**Option 2, open the Decidim admin to role holders.**
Register a permission class on `Decidim::Admin::ApplicationController` (or the chain) that allows
`:read :admin_dashboard` for engine role holders, so `/admin` works for them.
Cost: medium (permission class, registry wiring, specs, Decidim upgrade review).
Risk: high. It widens the Decidim admin dashboard (action logs, user counters) to a role that was
meant to be content-only, makes the public admin bar appear, and the `tos_accepted_by_admin` path
starts to apply. Rejected: it trades three cosmetic defects for a privilege escalation surface.

**Option 3, give the engine its own non-Decidim layout/base controller.**
Replace the inherited admin layout for the engine pages.
Cost: high (own layout, menu, assets, breadcrumb, ongoing drift against Decidim admin CSS, which
the host bundle compiles). Risk: medium-high; contradicts "Decidim extension patterns".
Rejected: nothing in the spike requires it.

Optional on top of Option 1 for D3: show a "Manage contracts" link in the public catalogue
header to engine role holders (`Menu.holds_engine_role?`), or document the URL for the pilot
(`docs/pilot-operations.md`). Cost: small view change + locale keys (both locales) + spec.

## Recommendation

Conclusion **A (works)**; proceed with #95. Take Option 1: one small prerequisite change (denial
redirect) before the role UI ships, because #95 adds exactly the users who hit it (non-admins
bouncing off `user_roles`, reviewer-only users on "new"). Leave D2 as a documented cosmetic
limitation. Decide on the D3 entry link separately; it is a product choice, not a technical need.

## Consequences for #109-#113

| Issue | Change | Detail |
|---|---|---|
| #108 | Report | Post conclusion A with the conditions D1-D3 and the check table. The "no engine code" rule holds; the fix below is a separate task. |
| #109 | none | Dependency on #108 satisfied (A). |
| #110 | note only | No code change. Add a line that the resolver must ignore `context` (N1): the menu passes an organization, `Permissions` passes a Hash. The step-1 lambda already does. |
| #111 | none | "Org admins only manage roles" is the right gate: role holders are admitted to the engine admin, so the permission is load-bearing, not redundant. |
| #112 | **scope change** | Its request spec "non-admin holding both engine roles: refused" must also assert where the refusal lands. Either depends on the new denial-redirect fix (Option 1) or it must accept redirect-to-`/admin`-then-404 and say so. Decide: a new prerequisite sub-issue (suggested: "M03-06-A2: engine admin denial redirect target"), or fold into #112. |
| #113 | **scope change** | Part 2 steps 4 and 6 expect the clerk to be "refused": on the real host this is a 302 to `/admin`, then 404 without the fix. Also the clerk has no link to `/contracts/admin` (D3): step 2 must give the URL, and the docs (`docs/roles-and-permissions.md`, `docs/pilot-operations.md`) must tell role holders how to reach the admin. Also: non-admin role holders never see the Decidim admin TOS page; the doc should say the engine does not require it of them. |

Decisions the human must make: (1) new prerequisite issue for the denial redirect vs fold into
#112; (2) whether to add the public-catalogue entry link (D3) to #95 scope or only document the URL;
(3) accept D2 (the `/admin` logo and breadcrumb home 404 for non-admins) as a known limitation.
