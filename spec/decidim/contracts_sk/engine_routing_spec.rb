# frozen_string_literal: true

# ---------------------------------------------------------------------------
# Stage 0 of the staged test-harness strategy (civora-org/civora-platform#45,
# item 2): dummy-free routing-contract specs for the engine.
#
# Loading pattern (deterministic, offline, no dummy Rails app):
#
#   1. `require "logger"` before ActiveSupport loads (activesupport 6.1.x on
#      Ruby >= 3.3 references ::Logger, which is no longer a default gem -
#      same workaround as the other spec files in this suite);
#   2. `require "action_controller/railtie"` defines Rails, which the engine
#      require depends on;
#   3. the engine, required directly as "decidim/contracts_sk/engine". A
#      plain `require "decidim/contracts_sk"` is NOT sufficient here:
#      spec_helper already required that file while Rails was still
#      undefined, so its conditional engine require was skipped, and a
#      repeat `require` would be a $LOADED_FEATURES no-op (verified - the
#      engine would never load). The engine file itself has not been
#      required yet, so requiring it is deterministic in every load order;
#   4. `load` of the engine's config/routes.rb, which evaluates
#      `Decidim::ContractsSk::Engine.routes.draw do ... end` and draws the
#      route table. RouteSet#draw clears the table first, so a repeated
#      `load` stays idempotent (verified).
#
# This load pattern is TEMPORARY: Stage 1 (minimal dummy harness, bound to
# the public ContractsController milestone) will draw these routes naturally
# via the mounted dummy app, at which point the manual loading above and
# this note go away.
#
# Assertion style: `route_to` / `recognize_path` are intentionally NOT used.
# They constantize the mapped controller class, which does not exist yet,
# and raise ActionController::RoutingError ("A route matches ..., but
# references missing controller: Decidim::ContractsSk::ContractsController"
# - verified). Only url_helpers and route-table introspection are used here.
# ---------------------------------------------------------------------------

require "spec_helper"

# Workaround for activesupport 6.1.x on Ruby >= 3.3: ActiveSupport references
# ::Logger, which is no longer a default gem. Must load before ActiveSupport.
require "logger"

require "action_controller/railtie"

# See header comment, item 3: unlike "decidim/contracts_sk" itself (already
# required by spec_helper with Rails undefined), the engine file is safe to
# require here and loads the engine.
require "decidim/contracts_sk/engine"

# Draws the engine routes into the (never-initialized) engine route set.
load File.expand_path("../../../config/routes.rb", __dir__)

# Shared vocabulary and route-table introspection for the example groups
# below. Kept in a plain module (not inside a describe block) so that its
# constants stay lint-clean and its helpers can be included where needed.
module EngineRoutingContract
  PUBLIC_CONTROLLER = "decidim/contracts_sk/contracts"
  ADMIN_CONTROLLER = "decidim/contracts_sk/admin/contracts"

  # The exact verb/path -> controller#action contract of config/routes.rb.
  # Note: Rails maps the `resources` update action to BOTH a PATCH and a
  # PUT route entry, so the admin CRUD block counts 8 routes, not 7.
  EXPECTED_ROUTES = [
    ["GET", "/contracts(.:format)", "#{PUBLIC_CONTROLLER}#index"],
    ["GET", "/contracts/:id(.:format)", "#{PUBLIC_CONTROLLER}#show"],
    ["GET", "/admin/contracts(.:format)", "#{ADMIN_CONTROLLER}#index"],
    ["POST", "/admin/contracts(.:format)", "#{ADMIN_CONTROLLER}#create"],
    ["GET", "/admin/contracts/new(.:format)", "#{ADMIN_CONTROLLER}#new"],
    ["GET", "/admin/contracts/:id/edit(.:format)", "#{ADMIN_CONTROLLER}#edit"],
    ["GET", "/admin/contracts/:id(.:format)", "#{ADMIN_CONTROLLER}#show"],
    ["PATCH", "/admin/contracts/:id(.:format)", "#{ADMIN_CONTROLLER}#update"],
    ["PUT", "/admin/contracts/:id(.:format)", "#{ADMIN_CONTROLLER}#update"],
    ["DELETE", "/admin/contracts/:id(.:format)", "#{ADMIN_CONTROLLER}#destroy"]
  ].freeze

  # Normalized [verb, path, controller#action] triples for every route the
  # engine declares, straight from the drawn route table.
  def route_triples
    Decidim::ContractsSk::Engine.routes.routes.map do |route|
      endpoint = "#{route.defaults[:controller]}##{route.defaults[:action]}"
      [route.verb.to_s, route.path.spec.to_s, endpoint]
    end
  end

  def public_routes
    route_triples.select { |_, _, endpoint| endpoint.start_with?("#{PUBLIC_CONTROLLER}#") }
  end

  def admin_routes
    route_triples.select { |_, _, endpoint| endpoint.start_with?("#{ADMIN_CONTROLLER}#") }
  end

  # Distinct controller strings used by the given routes, sorted.
  def controllers_of(routes)
    routes.map { |_, _, endpoint| endpoint.split("#", 2).first }.uniq.sort
  end
end

RSpec.describe "engine route table" do
  include EngineRoutingContract

  it "declares exactly the public read-only routes and the admin CRUD routes" do
    expect(route_triples.sort).to eq(EngineRoutingContract::EXPECTED_ROUTES.sort)
  end
end

RSpec.describe "public URL helpers" do
  let(:url_helpers) { Decidim::ContractsSk::Engine.routes.url_helpers }

  it "generates /contracts for contracts_path" do
    expect(url_helpers.contracts_path).to eq("/contracts")
  end

  it "generates /contracts/1 for contract_path(1)" do
    expect(url_helpers.contract_path(1)).to eq("/contracts/1")
  end
end

RSpec.describe "admin URL helpers" do
  let(:url_helpers) { Decidim::ContractsSk::Engine.routes.url_helpers }

  it "generates /admin/contracts for admin_contracts_path" do
    expect(url_helpers.admin_contracts_path).to eq("/admin/contracts")
  end

  it "generates /admin/contracts/7/edit for edit_admin_contract_path(7)" do
    expect(url_helpers.edit_admin_contract_path(7)).to eq("/admin/contracts/7/edit")
  end

  it "exposes admin_contracts_path as the POST-able helper for create" do
    expect(url_helpers).to respond_to(:admin_contracts_path)
    expect(url_helpers.admin_contracts_path).to eq("/admin/contracts")
  end
end

RSpec.describe "public surface restriction" do
  include EngineRoutingContract

  it "exposes only the index and show actions on the public controller" do
    actions = public_routes.map { |_, _, endpoint| endpoint.split("#", 2).last }.uniq.sort

    expect(actions).to eq(%w[index show])
  end

  it "does not map GET /contracts/new to the public controller" do
    expect(public_routes)
      .not_to include(["GET", "/contracts/new(.:format)", "decidim/contracts_sk/contracts#new"])
  end

  it "does not map DELETE /contracts/:id to the public controller" do
    expect(public_routes)
      .not_to include(["DELETE", "/contracts/:id(.:format)", "decidim/contracts_sk/contracts#destroy"])
  end

  it "keeps new and destroy inside the admin namespace" do
    expect(admin_routes).to include(
      ["GET", "/admin/contracts/new(.:format)", "decidim/contracts_sk/admin/contracts#new"],
      ["DELETE", "/admin/contracts/:id(.:format)", "decidim/contracts_sk/admin/contracts#destroy"]
    )
  end
end

RSpec.describe "admin/public route separation" do
  include EngineRoutingContract

  it "routes only the two engine controllers, distinct by the admin/ segment" do
    expect(controllers_of(route_triples))
      .to eq(["decidim/contracts_sk/admin/contracts", "decidim/contracts_sk/contracts"])
  end

  it "maps no admin-prefixed path to the public controller" do
    admin_prefixed = route_triples.select { |_, path, _| path.start_with?("/admin/") }

    expect(controllers_of(admin_prefixed)).to eq(["decidim/contracts_sk/admin/contracts"])
  end

  it "maps no non-admin path to the admin controller" do
    non_admin = route_triples.reject { |_, path, _| path.start_with?("/admin/") }

    expect(controllers_of(non_admin)).to eq(["decidim/contracts_sk/contracts"])
  end
end
