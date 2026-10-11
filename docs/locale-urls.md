# Locale in URLs (Decidim 0.31 and 0.32)

Audit for civora-org/civora-platform#183. Read from the decidim-core sources of v0.31.7 and v0.32.1 and pinned by `spec/requests/locale_urls_spec.rb`, which runs on both lines of the CI matrix.

## What the two lines do

| | Decidim 0.31 | Decidim 0.32 |
|---|---|---|
| `default_url_options` (`Decidim::LocaleSwitcher`) | `{}` for the default locale, else `{ locale: "xx" }` | `{ locale: "xx" }` always, except when the request's script name already starts with a locale |
| Core routes | `/search?locale=sk` | `/sk/search`; legacy `/search` is redirected by `Decidim::Routes::LocaleRedirects#locale_redirector` (query string kept, `locale` param dropped) |
| Component engines in a space | mounted at `/processes/:slug/f/:id` | mounted inside `scope "/:locale"`, so the script name carries the locale |
| `<link rel="alternate" hreflang>` in the layout head | `current_url(request.parameters.merge(locale:))`, i.e. `?locale=` | `canonical_url(request.url, locale)`, which **prefixes the path**: `/sk/<path>` |
| Language chooser (`LocalesController#create`) | redirects to the referer with `?locale=` | redirects to `canonical_url(referer, locale)`, again path-prefixed |

An engine route has no `:locale` segment, so on a mount without a locale scope the locale reaches an engine URL as a query parameter (`/zmluvy/5?locale=sk`). The engine reads it through `switch_locale`.

## What the engine emits

| URL | Rule | Both lines |
|---|---|---|
| Open data `url` column (CSV, JSON) | `contract_url(id: placeholder, locale: nil)` | no locale parameter |
| Atom entry and feed `alternate` links | `locale: nil` | no locale parameter |
| Atom `rel="self"` and the head/button feed links | explicit `locale: I18n.locale` | `?locale=` (deliberate: the English page gives the English feed) |
| Sitemap `<loc>` | `locale: nil` (**fixed in #183**: 0.32 would have added `?locale=` to every entry) | no locale parameter |
| `og:url` of the catalogue, a contract, a supplier, the statistics page and the in-space list | `locale: nil` (**fixed in #183**, same reason) | no locale parameter |
| Alert e-mails (confirm, unsubscribe, digest, `List-Unsubscribe`) | built outside a request through `decidim_contracts_sk`, with the subscriber's `locale:` and the organization's host | `?locale=sk` on an un-prefixed mount, `/sk/<mount>/...` on a locale-scoped one |
| Admin notification link (`ContractTransitionEvent#resource_url`) | no locale; the admin opens in the user's own locale | no locale parameter |
| CRZ handoff PDF | carries only the external `crz_url`; it has no link back into the engine | n/a |
| `canonical_url` for `hreflang` alternates and the language chooser | `Decidim::ContractsSk::ApplicationController#canonical_url` (**added in #183**) | `?locale=` on an un-prefixed mount (0.32's path prefix would 404); Decidim's own answer on a locale-scoped mount |

Everything else (page links, forms, pagination) goes through the route helpers and follows whatever `default_url_options` the line returns. Nothing in the engine hard-codes a path.

## Mounting on 0.32

Both mount styles work. The choice decides what the visitor sees:

- **Un-prefixed** (`mount Decidim::ContractsSk::Engine, at: "/contracts"`, the 0.31 shape). Legacy links, bookmarks and stored open-data URLs keep working untouched: the paths resolve directly. Page links carry `?locale=sk` (on 0.32 even for the default locale). The hreflang alternates are correct because of the engine's `canonical_url`. **Known limit:** the header's language chooser posts to `Decidim::LocalesController`, a core controller the engine cannot override, which redirects to the path-prefixed `/sk/contracts/...`. That URL does not exist on an un-prefixed mount, so switching the language from an engine page ends in a 404. Switching from any core page is fine.
- **Locale-scoped** (recommended on 0.32 for a host that wants the language chooser to work on engine pages). Mount inside Decidim's locale scope and redirect the legacy paths, the way decidim-core does for `/search` or `/pages`:

  ```ruby
  # config/routes.rb of the host
  Rails.application.routes.draw do
    extend Decidim::Routes::LocaleRedirects

    scope "/:locale", **locale_scope_options do
      mount Decidim::ContractsSk::Engine, at: "/contracts"
    end

    get "/contracts", to: redirect(&locale_redirector("/contracts"))
    # format: false keeps the extension of a stored link (/contracts/export.csv);
    # without it the glob swallows ".csv" and the redirect lands on /export.
    get "/contracts/*rest", format: false, to: redirect { |params, request|
      locale_redirect(params, request, "/contracts/#{params[:rest]}")
    }

    mount Decidim::Core::Engine => "/"
  end
  ```

  The redirects are permanent (301) and keep the query string. Declare them **before** the mount of the core engine. The dummy app of the specs draws exactly this on 0.32 (`spec/dummy/config/routes.rb`) and the spec asserts the redirect, the preserved `.csv` and filters, and that every emitted URL resolves.

Third parties that stored an un-prefixed URL (feed readers, open-data consumers, the CRZ handoff) keep working in both styles: directly in the first, through the 301 in the second. A consumer that follows redirects needs nothing; the sitemap and the `url` column are the canonical form either way.

The host's recommended pin is Decidim 0.32.1 or later.
