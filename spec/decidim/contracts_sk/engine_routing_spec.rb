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
  PARTIES_CONTROLLER = "decidim/contracts_sk/admin/parties"
  DOCUMENTS_CONTROLLER = "decidim/contracts_sk/admin/documents"
  AMENDMENTS_CONTROLLER = "decidim/contracts_sk/admin/amendments"

  # The exact verb/path -> controller#action contract of config/routes.rb.
  # The public surface is the mount point itself: the catalogue index sits
  # at "/" and a single /:id catch-all serves show. The admin surface is
  # create/edit plus the lifecycle-transition member POSTs (each POST entry
  # is derived from the ContractLifecycle transition table in routes.rb —
  # see the derivation guard below): no :show (admin records are edited, not
  # displayed) and no :destroy (deletion is not part of the workflow yet).
  # The CRZ-handoff pair (M02-05-C, civora-org/civora-platform#74) shares
  # one member path with two verbs and two explicit actions — declared
  # outside the lifecycle derivation (it is not a lifecycle event).
  # Parties (civora-org/civora-platform#76) hang off their contract through
  # the nested resource: an index plus the full add/edit/remove surface
  # (update maps to BOTH a PATCH and a PUT route entry, so the party block
  # counts 7 route entries, not 6). Documents (M02-05-A0,
  # civora-org/civora-platform#73) nest the same way but with no :index —
  # attach (new/create), replace (edit/update, both verbs) and remove
  # (destroy): 7 route entries. Amendments (M02-05-B,
  # civora-org/civora-platform#65) nest with the full version-history
  # surface (index/new/create/edit/update both verbs/destroy) PLUS one
  # explicit member POST per publish event — 9 route entries.
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
    ["GET", "/admin/contracts/:id/crz_handoff(.:format)", "#{ADMIN_CONTROLLER}#download_crz_handoff"],
    ["POST", "/admin/contracts/:id/crz_handoff(.:format)", "#{ADMIN_CONTROLLER}#generate_crz_handoff"],
    ["GET", "/admin/contracts/:id/edit(.:format)", "#{ADMIN_CONTROLLER}#edit"],
    ["POST", "/admin/contracts/:id/publish(.:format)", "#{ADMIN_CONTROLLER}#publish"],
    ["POST", "/admin/contracts/:id/reject(.:format)", "#{ADMIN_CONTROLLER}#reject"],
    ["POST", "/admin/contracts/:id/return(.:format)", "#{ADMIN_CONTROLLER}#return"],
    ["POST", "/admin/contracts/:id/submit(.:format)", "#{ADMIN_CONTROLLER}#submit"],
    ["PATCH", "/admin/contracts/:id(.:format)", "#{ADMIN_CONTROLLER}#update"],
    ["PUT", "/admin/contracts/:id(.:format)", "#{ADMIN_CONTROLLER}#update"],
    ["GET", "/admin/contracts/:contract_id/parties(.:format)", "#{PARTIES_CONTROLLER}#index"],
    ["POST", "/admin/contracts/:contract_id/parties(.:format)", "#{PARTIES_CONTROLLER}#create"],
    ["GET", "/admin/contracts/:contract_id/parties/new(.:format)", "#{PARTIES_CONTROLLER}#new"],
    ["GET", "/admin/contracts/:contract_id/parties/:id/edit(.:format)", "#{PARTIES_CONTROLLER}#edit"],
    ["PATCH", "/admin/contracts/:contract_id/parties/:id(.:format)", "#{PARTIES_CONTROLLER}#update"],
    ["PUT", "/admin/contracts/:contract_id/parties/:id(.:format)", "#{PARTIES_CONTROLLER}#update"],
    ["DELETE", "/admin/contracts/:contract_id/parties/:id(.:format)", "#{PARTIES_CONTROLLER}#destroy"],
    ["POST", "/admin/contracts/:contract_id/documents(.:format)", "#{DOCUMENTS_CONTROLLER}#create"],
    ["GET", "/admin/contracts/:contract_id/documents/new(.:format)", "#{DOCUMENTS_CONTROLLER}#new"],
    ["GET", "/admin/contracts/:contract_id/documents/:id/edit(.:format)", "#{DOCUMENTS_CONTROLLER}#edit"],
    ["PATCH", "/admin/contracts/:contract_id/documents/:id(.:format)", "#{DOCUMENTS_CONTROLLER}#update"],
    ["PUT", "/admin/contracts/:contract_id/documents/:id(.:format)", "#{DOCUMENTS_CONTROLLER}#update"],
    ["DELETE", "/admin/contracts/:contract_id/documents/:id(.:format)", "#{DOCUMENTS_CONTROLLER}#destroy"],
    ["GET", "/admin/contracts/:contract_id/amendments(.:format)", "#{AMENDMENTS_CONTROLLER}#index"],
    ["POST", "/admin/contracts/:contract_id/amendments(.:format)", "#{AMENDMENTS_CONTROLLER}#create"],
    ["GET", "/admin/contracts/:contract_id/amendments/new(.:format)", "#{AMENDMENTS_CONTROLLER}#new"],
    ["POST", "/admin/contracts/:contract_id/amendments/:id/publish(.:format)", "#{AMENDMENTS_CONTROLLER}#publish"],
    ["GET", "/admin/contracts/:contract_id/amendments/:id/edit(.:format)", "#{AMENDMENTS_CONTROLLER}#edit"],
    ["PATCH", "/admin/contracts/:contract_id/amendments/:id(.:format)", "#{AMENDMENTS_CONTROLLER}#update"],
    ["PUT", "/admin/contracts/:contract_id/amendments/:id(.:format)", "#{AMENDMENTS_CONTROLLER}#update"],
    ["DELETE", "/admin/contracts/:contract_id/amendments/:id(.:format)", "#{AMENDMENTS_CONTROLLER}#destroy"]
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

  def party_routes
    route_triples.select { |_, _, endpoint| endpoint.start_with?("#{PARTIES_CONTROLLER}#") }
  end

  def document_routes
    route_triples.select { |_, _, endpoint| endpoint.start_with?("#{DOCUMENTS_CONTROLLER}#") }
  end

  def amendment_routes
    route_triples.select { |_, _, endpoint| endpoint.start_with?("#{AMENDMENTS_CONTROLLER}#") }
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

    it "generates the nested party helpers (civora-org/civora-platform#76)" do
      aggregate_failures do
        expect(url_helpers.admin_contract_parties_path(7)).to eq("/admin/contracts/7/parties")
        expect(url_helpers.new_admin_contract_party_path(7)).to eq("/admin/contracts/7/parties/new")
        expect(url_helpers.edit_admin_contract_party_path(7, 3)).to eq("/admin/contracts/7/parties/3/edit")
      end
    end

    it "generates the nested document helpers (civora-org/civora-platform#73)" do
      aggregate_failures do
        expect(url_helpers.admin_contract_documents_path(7)).to eq("/admin/contracts/7/documents")
        expect(url_helpers.new_admin_contract_document_path(7)).to eq("/admin/contracts/7/documents/new")
        expect(url_helpers.edit_admin_contract_document_path(7, 3)).to eq("/admin/contracts/7/documents/3/edit")
      end
    end

    # The helper-name example carries four related expectations per design;
    # the dense-assertion budget doesn't fit a helper contract pinned
    # one-per-example.
    # rubocop:disable RSpec/ExampleLength
    it "generates the nested amendment helpers (M02-05-B, civora-org/civora-platform#65)" do
      aggregate_failures do
        expect(url_helpers.admin_contract_amendments_path(7)).to eq("/admin/contracts/7/amendments")
        expect(url_helpers.new_admin_contract_amendment_path(7)).to eq("/admin/contracts/7/amendments/new")
        expect(url_helpers.edit_admin_contract_amendment_path(7, 3)).to eq("/admin/contracts/7/amendments/3/edit")
        expect(url_helpers.publish_admin_contract_amendment_path(7, 3)).to eq("/admin/contracts/7/amendments/3/publish")
      end
    end
    # rubocop:enable RSpec/ExampleLength
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

    it "exposes exactly the CRUD + transition + CRZ-handoff actions (no show, no destroy)" do
      actions = admin_routes.map { |_, _, endpoint| endpoint.split("#", 2).last }.uniq.sort

      expect(actions).to eq(%w[
                              approve archive create download_crz_handoff edit generate_crz_handoff
                              index new publish reject return submit update
                            ])
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
    # route table. The CRZ-handoff POST shares the member path shape but is
    # declared explicitly (not a lifecycle event), so it is excluded here —
    # the derivation equality guards the lifecycle-derived set only.
    def route_transition_events
      admin_routes
        .select { |verb, path, _| verb == "POST" && path.start_with?("/admin/contracts/:id/") }
        .reject { |_, _, endpoint| endpoint == "#{EngineRoutingContract::ADMIN_CONTROLLER}#generate_crz_handoff" }
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

  describe "CRZ-handoff member routes (M02-05-C, civora-org/civora-platform#74)" do
    include EngineRoutingContract

    let(:url_helpers) { described_class.routes.url_helpers }

    # The full-table equality example and the helper-name example carry
    # several related expectations per design; the dense-assertion budget
    # doesn't fit a route-table contract pinned pair-by-pair.
    # rubocop:disable RSpec/ExampleLength
    it "shares one member path between the download (GET) and generate (POST) actions" do
      aggregate_failures do
        expect(admin_routes).to include(
          ["GET", "/admin/contracts/:id/crz_handoff(.:format)",
           "#{EngineRoutingContract::ADMIN_CONTROLLER}#download_crz_handoff"],
          ["POST", "/admin/contracts/:id/crz_handoff(.:format)",
           "#{EngineRoutingContract::ADMIN_CONTROLLER}#generate_crz_handoff"]
        )
      end
    end

    it "names the helpers download_crz_handoff_admin_contract_path and generate_crz_handoff_admin_contract_path" do
      aggregate_failures do
        expect(url_helpers.download_crz_handoff_admin_contract_path(7)).to eq("/admin/contracts/7/crz_handoff")
        expect(url_helpers.generate_crz_handoff_admin_contract_path(7)).to eq("/admin/contracts/7/crz_handoff")
      end
    end
    # rubocop:enable RSpec/ExampleLength

    it "keeps the handoff routes outside the lifecycle transition derivation" do
      expect(Decidim::ContractsSk::ContractLifecycle::TRANSITIONS.values
                                                                  .flat_map(&:keys)
                                                                  .uniq).not_to include(:crz_handoff)
    end
  end

  describe "nested document routes (civora-org/civora-platform#73)" do
    include EngineRoutingContract

    # The full-table equality example and the PATCH/PUT/DELETE mapping carry
    # several related expectations per design; the dense-assertion budget
    # doesn't fit a route-table contract pinned triple-by-triple.
    # rubocop:disable RSpec/ExampleLength
    it "exposes exactly the new/create/edit/update/destroy actions on the document controller (no index)" do
      actions = document_routes.map { |_, _, endpoint| endpoint.split("#", 2).last }.uniq.sort

      expect(actions).to eq(%w[create destroy edit new update])
    end

    it "nests every document route under its contract" do
      aggregate_failures do
        expect(document_routes).to all(include(a_string_starting_with("/admin/contracts/:contract_id/documents")))
        expect(document_routes.map { |_, path, _| path }).not_to include("/admin/documents(.:format)")
      end
    end

    it "maps replace to PATCH and PUT on the nested document member, and remove to DELETE" do
      aggregate_failures do
        expect(document_routes).to include(
          ["PATCH", "/admin/contracts/:contract_id/documents/:id(.:format)",
           "#{EngineRoutingContract::DOCUMENTS_CONTROLLER}#update"],
          ["PUT", "/admin/contracts/:contract_id/documents/:id(.:format)",
           "#{EngineRoutingContract::DOCUMENTS_CONTROLLER}#update"],
          ["DELETE", "/admin/contracts/:contract_id/documents/:id(.:format)",
           "#{EngineRoutingContract::DOCUMENTS_CONTROLLER}#destroy"]
        )
        # No :index route — the collection path carries only the POST
        # (create); the contract's edit page lists the documents.
        collection = document_routes.select { |_, path, _| path == "/admin/contracts/:contract_id/documents(.:format)" }

        expect(collection).to contain_exactly(
          ["POST", "/admin/contracts/:contract_id/documents(.:format)",
           "#{EngineRoutingContract::DOCUMENTS_CONTROLLER}#create"]
        )
      end
    end
    # rubocop:enable RSpec/ExampleLength
  end

  describe "nested party routes (civora-org/civora-platform#76)" do
    include EngineRoutingContract

    it "exposes exactly the index/new/create/edit/update/destroy actions on the party controller" do
      actions = party_routes.map { |_, _, endpoint| endpoint.split("#", 2).last }.uniq.sort

      expect(actions).to eq(%w[create destroy edit index new update])
    end

    it "nests every party route under its contract" do
      aggregate_failures do
        expect(party_routes).to all(include(a_string_starting_with("/admin/contracts/:contract_id/parties")))
        expect(party_routes.map { |_, path, _| path }).not_to include("/admin/parties(.:format)")
      end
    end

    it "maps destroy to DELETE on the nested party member" do
      expect(party_routes).to include(
        ["DELETE", "/admin/contracts/:contract_id/parties/:id(.:format)",
         "#{EngineRoutingContract::PARTIES_CONTROLLER}#destroy"]
      )
    end
  end

  describe "nested amendment routes (M02-05-B, civora-org/civora-platform#65)" do
    include EngineRoutingContract

    # The full-table equality example, the PATCH/PUT/DELETE mapping and the
    # publish-member split carry several related expectations per design;
    # the dense-assertion budget doesn't fit a route-table contract pinned
    # entry-by-entry.
    # rubocop:disable RSpec/ExampleLength
    it "exposes exactly the index/new/create/edit/update/destroy + publish actions on the amendment controller" do
      actions = amendment_routes.map { |_, _, endpoint| endpoint.split("#", 2).last }.uniq.sort

      expect(actions).to eq(%w[create destroy edit index new publish update])
    end

    it "nests every amendment route under its contract" do
      aggregate_failures do
        expect(amendment_routes).to all(include(a_string_starting_with("/admin/contracts/:contract_id/amendments")))
        expect(amendment_routes.map { |_, path, _| path }).not_to include("/admin/amendments(.:format)")
      end
    end

    it "maps the publish event to a single member POST, update to PATCH and PUT, remove to DELETE" do
      aggregate_failures do
        expect(amendment_routes).to include(
          ["POST", "/admin/contracts/:contract_id/amendments/:id/publish(.:format)",
           "#{EngineRoutingContract::AMENDMENTS_CONTROLLER}#publish"],
          ["PATCH", "/admin/contracts/:contract_id/amendments/:id(.:format)",
           "#{EngineRoutingContract::AMENDMENTS_CONTROLLER}#update"],
          ["PUT", "/admin/contracts/:contract_id/amendments/:id(.:format)",
           "#{EngineRoutingContract::AMENDMENTS_CONTROLLER}#update"],
          ["DELETE", "/admin/contracts/:contract_id/amendments/:id(.:format)",
           "#{EngineRoutingContract::AMENDMENTS_CONTROLLER}#destroy"]
        )
      end
    end

    it "carries an index (unlike the documents) — the version history has its own page" do
      collection = amendment_routes.select { |_, path, _| path == "/admin/contracts/:contract_id/amendments(.:format)" }

      expect(collection).to contain_exactly(
        ["GET", "/admin/contracts/:contract_id/amendments(.:format)",
         "#{EngineRoutingContract::AMENDMENTS_CONTROLLER}#index"],
        ["POST", "/admin/contracts/:contract_id/amendments(.:format)",
         "#{EngineRoutingContract::AMENDMENTS_CONTROLLER}#create"]
      )
    end
    # rubocop:enable RSpec/ExampleLength
  end

  describe "admin/public route separation" do
    include EngineRoutingContract

    # The controller-list example spans several lines by design (the exact
    # controller vocabulary pinned in full).
    # rubocop:disable RSpec/ExampleLength
    it "routes only the engine's five controllers, distinct by the admin/ segment" do
      controllers = %w[
        decidim/contracts_sk/admin/amendments decidim/contracts_sk/admin/contracts
        decidim/contracts_sk/admin/documents decidim/contracts_sk/admin/parties
        decidim/contracts_sk/contracts
      ].sort

      expect(controllers_of(route_triples)).to eq(controllers)
    end
    # rubocop:enable RSpec/ExampleLength

    it "maps no admin-prefixed path to the public controller" do
      admin_prefixed = route_triples.select { |_, path, _| path.start_with?("/admin/") }

      expect(controllers_of(admin_prefixed))
        .to eq(["decidim/contracts_sk/admin/amendments", "decidim/contracts_sk/admin/contracts",
                "decidim/contracts_sk/admin/documents", "decidim/contracts_sk/admin/parties"])
    end

    it "maps no non-admin path to the admin controllers" do
      non_admin = route_triples.reject { |_, path, _| path.start_with?("/admin/") }

      expect(controllers_of(non_admin)).to eq(["decidim/contracts_sk/contracts"])
    end
  end
end
