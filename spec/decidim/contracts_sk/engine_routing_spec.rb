# frozen_string_literal: true

# Engine route-table specs, backed by the Stage-1 dummy harness
# (spec/dummy; civora-org/civora-platform#61): the dummy app mounts the
# engine at "/", so the engine's route table is drawn naturally at boot —
# no manual loading pattern is needed anymore. The assertions use only
# url_helpers and route-table introspection (never route_to /
# recognize_path, which constantize the mapped controllers).

require "spec_helper"

# Shared vocabulary and route-table introspection for the example groups
# below. Kept in a plain module (not inside a describe block) so that its
# constants stay lint-clean and its helpers can be included where needed.
module EngineRoutingContract
  PUBLIC_CONTROLLER = "decidim/contracts_sk/contracts"
  ADMIN_CONTROLLER = "decidim/contracts_sk/admin/contracts"

  # The exact verb/path -> controller#action contract of config/routes.rb.
  # The public surface is the mount point itself: the catalogue index sits
  # at "/" and a single /:id catch-all serves show. The admin surface is
  # create/edit plus the lifecycle-transition member POSTs (each POST entry
  # is derived from the ContractLifecycle transition table in routes.rb —
  # see the derivation guard below): no :show (admin records are edited, not
  # displayed) and no :destroy (deletion is not part of the workflow yet).
  # Note: Rails' `root` helper adds NO optional format segment (path is
  # exactly "/", not "/(.:format)" - unlike a plain `get`), and it maps the
  # `resources` update action to BOTH a PATCH and a PUT route entry, so the
  # admin CRUD block counts 6 route entries, not 5.
  EXPECTED_ROUTES = [
    ["GET", "/", "#{PUBLIC_CONTROLLER}#index"],
    ["GET", "/:id(.:format)", "#{PUBLIC_CONTROLLER}#show"],
    ["GET", "/admin/contracts(.:format)", "#{ADMIN_CONTROLLER}#index"],
    ["POST", "/admin/contracts(.:format)", "#{ADMIN_CONTROLLER}#create"],
    ["GET", "/admin/contracts/new(.:format)", "#{ADMIN_CONTROLLER}#new"],
    ["POST", "/admin/contracts/:id/approve(.:format)", "#{ADMIN_CONTROLLER}#approve"],
    ["POST", "/admin/contracts/:id/archive(.:format)", "#{ADMIN_CONTROLLER}#archive"],
    ["GET", "/admin/contracts/:id/edit(.:format)", "#{ADMIN_CONTROLLER}#edit"],
    ["POST", "/admin/contracts/:id/publish(.:format)", "#{ADMIN_CONTROLLER}#publish"],
    ["POST", "/admin/contracts/:id/reject(.:format)", "#{ADMIN_CONTROLLER}#reject"],
    ["POST", "/admin/contracts/:id/return(.:format)", "#{ADMIN_CONTROLLER}#return"],
    ["POST", "/admin/contracts/:id/submit(.:format)", "#{ADMIN_CONTROLLER}#submit"],
    ["PATCH", "/admin/contracts/:id(.:format)", "#{ADMIN_CONTROLLER}#update"],
    ["PUT", "/admin/contracts/:id(.:format)", "#{ADMIN_CONTROLLER}#update"]
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

RSpec.describe Decidim::ContractsSk::Engine do
  describe "engine route table" do
    include EngineRoutingContract

    it "declares exactly the public read-only routes and the admin create/edit routes" do
      expect(route_triples.sort).to eq(EngineRoutingContract::EXPECTED_ROUTES.sort)
    end
  end

  describe "public URL helpers" do
    let(:url_helpers) { described_class.routes.url_helpers }

    it "generates / for contracts_path" do
      expect(url_helpers.contracts_path).to eq("/")
    end

    it "generates /1 for contract_path(1)" do
      expect(url_helpers.contract_path(1)).to eq("/1")
    end
  end

  describe "admin URL helpers" do
    let(:url_helpers) { described_class.routes.url_helpers }

    it "generates /admin/contracts for admin_contracts_path" do
      expect(url_helpers.admin_contracts_path).to eq("/admin/contracts")
    end

    it "generates /admin/contracts/7/edit for edit_admin_contract_path(7)" do
      expect(url_helpers.edit_admin_contract_path(7)).to eq("/admin/contracts/7/edit")
    end

    it "exposes admin_contracts_path as the POST-able helper for create" do
      # public_send keeps the old respond_to semantics in a single
      # expectation: it proves the helper is publicly callable (NameError
      # fails this example) and generates the POST target for create.
      expect(url_helpers.public_send(:admin_contracts_path)).to eq("/admin/contracts")
    end
  end

  describe "public surface restriction" do
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

    it "keeps the editorial actions inside the admin namespace" do
      expect(admin_routes).to include(
        ["GET", "/admin/contracts/new(.:format)", "decidim/contracts_sk/admin/contracts#new"],
        ["GET", "/admin/contracts/:id/edit(.:format)", "decidim/contracts_sk/admin/contracts#edit"]
      )
    end

    it "exposes only the CRUD and lifecycle-transition actions on the admin controller (no show, no destroy)" do
      actions = admin_routes.map { |_, _, endpoint| endpoint.split("#", 2).last }.uniq.sort

      expect(actions).to eq(%w[approve archive create edit index new publish reject return submit update])
    end
  end

  describe "lifecycle transition member routes" do
    include EngineRoutingContract

    it "derives the route event set exactly from the lifecycle transition table, in both directions" do
      aggregate_failures do
        expect(route_transition_events).to eq(table_transition_events)
        expect(table_transition_events).to eq(route_transition_events)
      end
    end

    it "names each event helper <event>_admin_contract_path (the view's derivation target)" do
      aggregate_failures do
        expect(url_helpers.submit_admin_contract_path(7)).to eq("/admin/contracts/7/submit")
        expect(url_helpers.return_admin_contract_path(7)).to eq("/admin/contracts/7/return")
      end
    end

    private

    def url_helpers
      described_class.routes.url_helpers
    end

    # The member POSTs under /admin/contracts/:id, read back from the drawn
    # route table.
    def route_transition_events
      admin_routes
        .select { |verb, path, _| verb == "POST" && path.start_with?("/admin/contracts/:id/") }
        .map { |_, _, endpoint| endpoint.split("#", 2).last.to_sym }
        .sort
    end

    # The same derivation routes.rb performs on the lifecycle table.
    def table_transition_events
      Decidim::ContractsSk::ContractLifecycle::TRANSITIONS.values
                                                          .flat_map(&:keys)
                                                          .uniq.sort
    end
  end

  describe "admin/public route separation" do
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
end
