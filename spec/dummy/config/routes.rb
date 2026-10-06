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

  mount Decidim::ContractsSk::Engine, at: "/"
end
