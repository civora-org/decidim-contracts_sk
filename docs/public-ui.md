# Public UI: catalogue and contract detail

How the two public pages (`contracts/index`, `contracts/show`) are built and styled, and the rules that keep them from regressing. Read this before touching any public view.

## Styling rule: the engine owns its layout CSS

**Do not lay out public views with Tailwind utility classes that only the engine uses.**

The host compiles its CSS once, at image build time (`bin/shakapacker` in the Docker build), from the classes its Tailwind content scan sees then. A utility that only a newer engine release uses is silently missing from the shipped bundle: no build error, no runtime error, just unstyled markup. Most layout utilities these pages need (`lg:grid-cols-12`, `lg:col-span-4`, `min-w-0`, `tabular-nums`, `border-y`, `sm:flex`, …) are absent from the Decidim 0.31 bundle. That is how the pre-2026-10 pages shipped with headings flush against the breadcrumb bar and a broken key/value grid.

What the pages use instead:

| Layer | Source | Use for |
|---|---|---|
| Decidim component classes | host bundle (always present) | `layout-1col cols-10`, `title-decorator`, `decorator`, `h3`, `label`, `label warning`, `button button__sm button__secondary`, `form-defaults` |
| Engine stylesheet | `app/views/decidim/contracts_sk/shared/_public_styles.html.erb` | everything layout-specific, under the `.cs-` prefix |
| Engine icons | `contracts_icon(:search \| :information \| :document)` in `ApplicationHelper` | inline Remix Icon SVGs; no dependency on Decidim's icon registry or the host's sprite |

The stylesheet is delivered through Decidim's `:css_content` slot, which the core layout yields in `<head>` right after `decidim_core.css`. Decidim's default CSP allows inline styles (`style-src 'self' 'unsafe-inline'`). Each public view renders the partial once at the top.

Colours are Decidim's palette: the organisation's `var(--secondary)` for links, and the core gray-2 `#3e4c5c` (secondary text), gray-3 `#e1e5ef` (rules) and background-2 `#fafbfc` (panels).

If you add a Decidim component class, check it exists in the live bundle first:

```bash
curl -s http://localhost:3000/contracts | grep -o '/decidim-packs/css/decidim_core[^"]*\.css'
curl -s http://localhost:3000/decidim-packs/css/decidim_core-<hash>.css | grep -c '\.label\.warning'
```

## Catalogue filter form (civora-org/civora-platform#116)

One GET form (`role="search"`) above the register; the state lives in the URL and every pagination link carries every active filter (`CatalogueQuery::PARAM_KEYS` is the `filter_keys` of `shared/_pagination`).

- **Always visible:** the `q` search field and its button.
- **Behind a native `<details class="cs-filters">` ("More filters"):** amount from/to (EUR), publication date from/to ("Published in the catalogue"), signing date from/to, party (name or 8-digit IČO, with a hint tied via `aria-describedby`), source (any / the organisation's own records / mirrored from CRZ) and the sort. The block is open whenever a non-`q` filter or a non-default sort is active. No JavaScript: `<details>` is keyboard- and screen-reader-operable.
- **Labels above fields**, each from/to pair in a `<fieldset>` with a `<legend>`. Amounts are `type="text" inputmode="decimal"` (so "10 000,50" works on a Slovak keyboard); dates are `type="date"` and the server also accepts `d.m.yyyy`.
- **Prefilled from the normalized query**, not the raw params: a swapped range shows swapped, an invalid value shows empty.
- **Active-filters summary and "Clear filters"** (links to the bare catalogue, clearing `q` too) appear when anything is active. The empty state turns into the "no match" variant.
- **CSS:** `.cs-filters*` in `shared/_public_styles`: one column below 640px, two from 640px, four from 1024px; inputs `width:100%; min-width:0`; a visible focus ring on the summary; the form and the details block are hidden in print (the active-filters summary prints).

## Open-data download block (civora-org/civora-platform#119)

A `<section class="cs-opendata">` between the filter form and the register: heading "Stiahnuť dáta", one sentence, and four `button button__sm button__secondary` links (CSV, CSV pre Excel, JSON, Atom kanál). Each link carries the active filters (`query.to_params` minus `sort`). When the source filter is `crz` the links are replaced by a note and a link to crz.gov.sk, because mirrored records are never exported (see [open-data.md](open-data.md)). `.cs-opendata*` lives in `shared/_public_styles`; hidden in print. The downloads themselves are not HTML pages. The same filters (no sort) feed the page head's `<link rel="alternate" type="application/atom+xml">` (civora-org/civora-platform#120), emitted through `content_for :header_snippets` (decidim-core's `_head` yields it) and omitted for `source=crz`, whose own-records feed would be empty.

## Supplier page (civora-org/civora-platform#117)

`suppliers/show.html.erb`, reached from the contractor names on the detail page (`supplier_link_or_name`, a `cs-link` only for a contractor with an 8-digit IČO; plain text otherwise). Structure: a "Back to the catalogue" link, one `h1` (the supplier name) with the IČO below, a "Summary" `h2` holding a `dl` (contract count, total value per currency, per-year tally as a list with a "Date unknown" bucket) and a note that a contract present both editorially and as a CRZ mirror counts twice, then a "Contracts" `h2` and the register. The rows are the catalogue's own partial (`contracts/_row.html.erb`), so the provenance badge comes along; pagination is the shared partial with no carried params. `.cs-supplier*` and `.cs-years` live in `shared/_public_styles` (Decidim classes plus engine CSS only; the facts form one column on phones and three from 640px). The head carries `<meta name="robots" content="noindex">` through `content_for :header_snippets`.

## Heading decorators need room below

`.title-decorator` and `.decorator` draw a 0.25rem bar at `top: calc(100% + 0.25rem)`, below the heading's box. The bar takes no space in the layout, so the next element must keep at least ~0.75rem of clearance or the bar strikes through it. The engine stylesheet gives decorated headings their own bottom margin (`.cs-page .title-decorator`, `.cs-main .decorator`). Never place a meta line directly under a decorated heading without that margin.

## Page structure

**Catalogue** (`cols-10`): title, one-line intro, search (label above; field and button in one row from 640px), the filter form (see below), then the register. One row per contract: title link, `reference · date`, the CRZ provenance label for mirrored records, and the amount right-aligned in tabular numerals from 768px.

**Detail** (`cols-10`): title and identity line (reference, publication date). Below it, a two-column grid from 1024px: the main column (subject matter, CRZ provenance notice, parties, documents, links, version history) and the "Údaje o zmluve" facts panel on the right (amount as the headline figure, reference, dates, CRZ link). The facts panel comes first in the DOM, so phones read it before the long sections.

Rules that hold across both pages:

- **Every label/value pair has its own wrapper** (`<div><dt/><dd/></div>`), so a long value can never drift into a neighbouring pair's grid cell.
- **Optional fields are guarded** (civora-org/civora-platform#80): no empty `dd`, no dangling currency.
- **Dates and amounts go through `format_date` / `format_datetime` / `format_amount`** (civora-org/civora-platform#81).
- **Parties are rows, not a table**: a four-column table cannot fit a phone.
- **Meta-line separators are CSS** (`.cs-meta > * + *::before`), so a wrapped line starts with the dot instead of ending on it.
- **Long strings break** (`overflow-wrap: anywhere`; URLs `word-break: break-all`). The pages have no horizontal scroll at 375px.

## Admin audit trail

`admin/audit_events/index` stays on Decidim admin's own classes. `table-list--selectable` is the admin modifier that left-aligns the second column (the record titles); plain `table-list` centres every column after the first. Rows show date **and** time (`format_datetime`, application time zone), and an empty decision reason renders as a muted `—`.

## Admin overview

`admin/dashboard/show` (civora-org/civora-platform#126) is built from Decidim admin's own classes only: `card` / `card-section`, `item_show__header`, `table-list table-list--selectable`, `label warning` (redaction not confirmed) and `button button__sm button__secondary` links. Every block is one `card-section` with a heading, a one-line hint, either the table or its own empty state, and a "Show all (N)" link; the audit block reuses the audit trail's table partial (`admin/audit_events/_table`). No engine-only Tailwind utilities, per the build-time rule above.

### Admin layout classes

The admin pages (overview, contracts index, audit trail) lay out their button rows with engine-owned classes from `shared/_admin_styles` (the admin counterpart of the public stylesheet; the admin layout has no `:css_content` slot, so the block is added to Decidim's `:head` snippets once per request):

- `.cs-admin-actions` — header actions: side by side, no wrap, pushed right, never shrunk by `.item_show__header`;
- `.cs-admin-chips` — wrapping chip/filter button rows with a gap;
- `.cs-admin-more` — space above a "show all" button;
- `.cs-admin-hint` — small top margin for a hint line under a button row.

Override points: (1) host or other modules can restyle the classes from their own CSS — selectors are single classes, no ids, no `!important`; (2) a host app can replace the whole partial by placing a file at `app/views/decidim/contracts_sk/shared/_admin_styles.html.erb` (host views win over engine views).

## Admin CRZ deadline badges

The admin index's CRZ deadline badges (civora-org/civora-platform#124) use Decidim's own `label` modifiers (`label`, `label warning`, `label alert`) — the same build-time rule applies to admin views: no engine-only Tailwind utilities, the host bundle would silently drop them.

## Verifying a change

1. `bundle exec rspec` and `bundle exec rubocop` (the request specs pin the user-visible strings, the empty states and the guards).
2. Against the running host: the dev container runs `RAILS_ENV=production` with no code reloading. After editing a view, locale or helper, hot-restart puma: `docker exec civora-host-app-1 sh -c 'kill -USR2 $(pgrep -f "puma 6" | head -1)'`.
3. Check `/contracts` and a CRZ-mirrored detail page at 1440px and 375px: no horizontal scroll, decorator bars clear of the following text, search field and button the same height.

Marketing screenshots for civora.sk (`civora-org/civora-site`, `img/`) are captured logged out at 1440×900 on demo data. Recapture them when these pages change.
