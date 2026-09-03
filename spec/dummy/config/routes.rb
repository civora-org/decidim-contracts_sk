# frozen_string_literal: true

# Dummy-app routes: the engine IS the whole public surface of the dummy app.
# Drawn post-initialize from application.rb; RouteSet#draw clears first, so
# re-evaluation is idempotent.
DummyApp.routes.draw do
  mount Decidim::ContractsSk::Engine, at: "/"
end
