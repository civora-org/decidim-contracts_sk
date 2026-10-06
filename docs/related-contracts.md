# Related contracts on result and project pages

The engine ships a host-embeddable "Related contracts" block (civora-org/civora-platform#131, epic #142): on a Decidim accountability result or budgets project page it lists the published contracts linked to that resource, so a resident can follow *project, result, contract* from the participation side. It is the reverse of the contract detail page's "Links" section and uses the same engine-owned join (ADR-009), so it needs no migration and no Decidim core change.

## What it shows

Per contract, newest published first (at most 25, `Decidim::ContractsSk::CONTRACTS_PER_PAGE`): title linking to the contract detail on the engine mount, reference, the contractor's name (linked to its supplier page) when the contractor has an 8-digit IČO, the amount, and for a CRZ mirror the "Externally confirmed" badge with the mirror date. When nothing qualifies the block renders nothing: no heading, no empty state, no stylesheet.

Rules, enforced in `RelatedContractsQuery` and pinned by `spec/decidim/contracts_sk/related_contracts_query_spec.rb`:

- only `published` contracts;
- only contracts of the resource's own organization (`resource.organization`), however the link was created;
- only links whose target is exactly this resource (type and id), and only when the resource's class is on `Decidim::ContractsSk.supported_link_target_types`, the whitelist that already gates link creation; an unsupported or unsaved resource yields an empty result, never an error;
- no personal data beyond what the detail page shows: a party without an IČO and the object party are never rendered;
- a constant number of queries however many contracts match (the contracts with the join as an inline sub-select, and one preload of the parties).

## Host API

```ruby
# A relation of Decidim::ContractsSk::Contract, parties preloaded, newest first.
Decidim::ContractsSk.related_contracts_for(result)              # or a Decidim::Budgets::Project
Decidim::ContractsSk.related_contracts_for(result, limit: 5)
```

The view piece is the partial `decidim/contracts_sk/related_contracts/list` (locals: `resource`, optional `limit`). It is self-contained: it does not need the engine's helpers included in the host view, and it links through the `decidim_contracts_sk` route proxy that `mount Decidim::ContractsSk::Engine, at: "/zmluvy"` defines. It reaches the page's `<head>` through Decidim's `:css_content` slot.

It is a partial rather than a Decidim cell on purpose: a cell needs `Decidim::ViewModel` and the full Decidim view stack, which the engine's spec harness cannot boot, and the engine's rule is to ship nothing it cannot test offline.

## Decidim extension points (decidim 0.31.7)

There is **no view hook** on the result or project show pages. The checked facts:

- `Decidim.view_hooks` is the registry (`decidim-core/lib/decidim/core.rb:997`); `ViewHooks#register` is `decidim-core/lib/decidim/view_hooks.rb:50`, `#render` is `:77`; the view helper is `render_hook` (`decidim-core/app/helpers/decidim/view_hooks_helper.rb:11`).
- Hooks that are actually rendered by core views: `:user_profile_bottom` (`decidim-core/app/cells/decidim/profile/details.erb:23`) and the per-item card-metadata hooks (`decidim-core/app/cells/decidim/card_metadata/show.erb:3`).
- The only hook the accountability module registers is `:participatory_space_highlighted_elements` (`decidim-accountability/lib/decidim/accountability/engine.rb:34-38`); budgets registers none and renders none.
- The result page: `results/show.html.erb:19` renders the partial `results/_project.html.erb`, which wraps everything in `layouts/decidim/shared/layout_item` (`_project.html.erb:1`) and fills the `:aside` (`:9`) and `:item_footer` (`:23`) slots.
- The project page: `projects/show.html.erb:28` uses the same layout, with `:aside` at `:88` and `:item_footer` at `:115`; its tab panels come from `ProjectsController#items` (`decidim-budgets/app/controllers/decidim/budgets/projects_controller.rb:67-95`), not extensible without patching the controller.

So the host wires the block by **overriding two view files** (host views win over gem views), each a one-line addition. Decidim also offers cells, whose view paths are registered at boot (`decidim-core/lib/decidim/core/engine.rb:506-510`, `decidim-accountability/lib/decidim/accountability/engine.rb:46`), but they only help when the page already renders a cell you could extend.

## Host wiring (civora-host, #130 / #131 host part)

1. Whitelist the target types and resolve them tenant-safely (#130; the reverse lookup also requires the whitelist):

```ruby
# config/initializers/contracts_sk.rb
Decidim::ContractsSk.supported_link_target_types = %w[
  Decidim::Accountability::Result Decidim::Budgets::Project
]
```

2. Copy `decidim-accountability-0.31.7/app/views/decidim/accountability/results/_project.html.erb` to the host's `app/views/decidim/accountability/results/_project.html.erb` and add one line after the tags cell:

```erb
<%= cell("decidim/tags", result) %>
<%= render partial: "decidim/contracts_sk/related_contracts/list", locals: { resource: result } %>
```

3. Copy `decidim-budgets-0.31.7/app/views/decidim/budgets/projects/show.html.erb` to the host's `app/views/decidim/budgets/projects/show.html.erb` and add after `<%= cell("decidim/tags", project) %>` (line 78):

```erb
<%= render partial: "decidim/contracts_sk/related_contracts/list", locals: { resource: project } %>
```

An overridden copy does not follow Decidim upgrades: on each Decidim bump, diff the two files against the gem and re-apply the line. The engine's `Decidim::ContractsSk.related_contracts_for` is the stable seam if the host prefers its own markup.

## Styling

Markup uses Decidim's `h4 decorator` heading and `label` badge plus the engine's `.cs-related*` classes (`app/views/decidim/contracts_sk/shared/_related_contracts_styles.html.erb`), never Tailwind utilities the host bundle may lack; see [public-ui.md](public-ui.md). The stylesheet is deliberately separate from the catalogue's `_public_styles`, so a host result page only receives the few rules it needs.

## Files

- `lib/decidim/contracts_sk/related_contracts.rb`: `Decidim::ContractsSk.related_contracts_for`
- `app/queries/decidim/contracts_sk/related_contracts_query.rb` and `related_contracts_query/item.rb`
- `app/views/decidim/contracts_sk/related_contracts/_list.html.erb`
- `app/views/decidim/contracts_sk/shared/_related_contracts_styles.html.erb`
- `config/locales/{en,sk}.yml`: `decidim.contracts_sk.related_contracts.title`
