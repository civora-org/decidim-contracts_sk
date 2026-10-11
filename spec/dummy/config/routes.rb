# frozen_string_literal: true

# Dummy-app routes: the standalone engine IS the whole public surface of the
# dummy app. Drawn post-initialize from application.rb; RouteSet#draw clears
# first, so re-evaluation is idempotent.
DummyApp.routes.draw do
  # The in-space component engine (civora-org/civora-platform#89), mounted the
  # way decidim-participatory_processes mounts every component engine
  # (engine.rb:33-39): under a space component scope, behind a constraint
  # that exposes the current component. Declared before the standalone mount
  # (at "/", whose /:id catch-all must never see these paths).
  scope "/spaces/:participatory_process_slug/f/:component_id" do
    constraints DummySpaceHarness.constraint do
      mount Decidim::ContractsSk::SpaceComponent::Engine, at: "/", as: "dummy_space_contracts_sk"
    end
  end

  # Decidim 0.32 (civora-org/civora-platform#183) puts the locale into the
  # PATH of every route it owns (`/sk/processes/...`) and mounts component
  # engines inside `scope "/:locale"`, so a request's SCRIPT_NAME carries the
  # locale and Decidim::LocaleSwitcher#default_url_options returns {}. The
  # dummy mirrors both mount styles on that line only, next to the unprefixed
  # mounts (which stay: they are the shape of a 0.31 host, and of any 0.32
  # host that keeps mounting the engine without a locale scope):
  #
  # * the standalone catalogue at /:locale/zmluvy, plus the legacy
  #   un-prefixed /zmluvy paths redirecting to it through Decidim's own
  #   Routes::LocaleRedirects (decidim-core config/routes.rb does the same
  #   for /search, /pages, /profiles, ...);
  # * the in-space component at /:locale/spaces/:slug/f/:component_id, the
  #   way decidim-participatory_processes mounts component engines
  #   (v0.32.1 engine.rb:20-39).
  #
  # Declared before the mount at "/", whose /:id catch-all must not see them.
  if DummyDecidimLine.locale_prefixed?
    extend Decidim::Routes::LocaleRedirects

    scope "/:locale", **locale_scope_options do
      mount Decidim::ContractsSk::Engine, at: "/zmluvy", as: "prefixed_contracts_sk"

      scope "/spaces/:participatory_process_slug/f/:component_id" do
        constraints DummySpaceHarness.constraint do
          mount Decidim::ContractsSk::SpaceComponent::Engine, at: "/", as: "prefixed_dummy_space_contracts_sk"
        end
      end
    end

    get "/zmluvy", to: redirect(&locale_redirector("/zmluvy"))
    # format: false is load-bearing: the glob would otherwise swallow the
    # extension of a stored open-data link (/zmluvy/export.csv -> /export).
    get "/zmluvy/*rest", format: false, to: redirect { |params, request|
      locale_redirect(params, request, "/zmluvy/#{params[:rest]}")
    }
  end

  mount Decidim::ContractsSk::Engine, at: "/"
end
