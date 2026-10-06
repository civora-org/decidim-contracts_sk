# frozen_string_literal: true

# ---------------------------------------------------------------------------
# Offline specs for the Decidim component registration (civora-org/civora-
# platform#89): the registered manifest, the in-space engine's route table
# and its isolation from the standalone engine, and the fail-closed
# permission contract of the class the manifest wires in.
#
# The manifest under test is the REAL Decidim::ComponentManifest registered
# by the engine's own initializer at harness boot (spec/dummy/config/
# application.rb mirrors only the registry's module methods), so the specs
# also validate the manifest against Decidim's own manifest validations and
# the real settings schema.
# ---------------------------------------------------------------------------

require "spec_helper"

# rubocop:disable RSpec/MultipleExpectations, RSpec/ExampleLength
# A cross-cutting contract (registry + engine + permissions), not one class.
RSpec.describe "Decidim component registration (civora-org/civora-platform#89)" do # rubocop:disable RSpec/DescribeClass
  let(:manifest) { Decidim.find_component_manifest(:contracts_sk) }
  let(:space_engine) { Decidim::ContractsSk::SpaceComponent::Engine }

  def route_table(engine)
    engine.routes.routes.map { |route| [route.verb, route.path.spec.to_s.sub("(.:format)", ""), route.name] }
  end

  describe "the manifest" do
    it "is registered exactly once, under the engine's name" do
      matching = Decidim.component_manifests.select { |candidate| candidate.name == :contracts_sk }

      expect(matching.size).to eq(1)
      expect(manifest).to be_a(Decidim::ComponentManifest)
      expect(manifest.valid?).to be(true)
    end

    it "mounts the in-space engine, never the standalone one" do
      expect(manifest.engine).to eq(space_engine)
      expect(manifest.engine).not_to eq(Decidim::ContractsSk::Engine)
    end

    it "wires the existing table-driven permissions class" do
      expect(manifest.permissions_class_name).to eq("Decidim::ContractsSk::Permissions")
      expect(manifest.permissions_class).to eq(Decidim::ContractsSk::Permissions)
    end

    it "declares the announcement in BOTH settings scopes (the core announcement partial reads both)" do
      %i[global step].each do |scope|
        attributes = manifest.settings(scope).attributes
        expect(attributes.keys).to eq([:announcement]), scope.to_s
        expect(attributes[:announcement].translated?).to be(true)
      end
      global = manifest.settings(:global).schema.new(announcement: { "en" => "Hello" })
      expect(global.announcement).to include("en" => "Hello")
      expect { manifest.settings(:step).schema.new({}).announcement }.not_to raise_error
    end

    it "owns no admin engine, exports, imports, hooks or data-portability entries (the component holds no data)" do
      aggregate_failures do
        expect(manifest.admin_engine).to be_nil
        expect(manifest.export_manifests).to be_empty
        expect(manifest.import_manifests).to be_empty
        expect(manifest.hooks).to be_empty
        expect(manifest.data_portable_entities).to be_empty
        expect(manifest.newsletter_participant_entities).to be_empty
        expect(manifest.actions).to be_empty
        expect(manifest.serializes_specific_data?).to be(false)
      end
    end

    it "keeps Decidim's stock query type and component form" do
      expect(manifest.query_type).to eq("Decidim::Core::ComponentType")
      expect(manifest.component_form_class_name).to eq("Decidim::Admin::ComponentForm")
    end

    it "sets no icon file (a missing pack entry would raise in the host's admin list), only the icon key" do
      expect(manifest.icon).to be_blank
      expect(manifest.icon_key).to eq("file-text-line")
    end
  end

  describe "the in-space engine's route table" do
    it "is exactly the read-only list and detail page, and names a root (Decidim requires one)" do
      expect(route_table(space_engine)).to contain_exactly(
        ["GET", "/", "root"],
        ["GET", "/contracts/:id", "contract"]
      )
    end

    it "carries no admin, export, feed, sitemap, supplier or statistics route" do
      paths = route_table(space_engine).map { |_verb, path, _name| path }

      expect(paths.grep(/admin|export|feed|sitemap|suppliers|statistics/)).to be_empty
    end

    it "resolves its controllers inside the in-space namespace" do
      controllers = space_engine.routes.routes.map { |route| route.defaults[:controller] }.uniq

      expect(controllers).to eq(["decidim/contracts_sk/space_component/contracts"])
    end

    it "shares the gem root but does not repeat the standalone engine's migrations, tasks, seeds or routes file" do
      aggregate_failures do
        expect(space_engine.root).to eq(Decidim::ContractsSk::Engine.root)
        expect(space_engine.paths["db/migrate"].existent).to be_empty
        expect(space_engine.paths["lib/tasks"].existent).to be_empty
        expect(space_engine.paths["config/routes.rb"].existent).to be_empty
        expect(space_engine.instance.load_seed).to be_nil
      end
    end
  end

  describe "isolation from the standalone engine" do
    it "keeps the standalone route table free of duplicates (the shared config/routes.rb is drawn once)" do
      table = route_table(Decidim::ContractsSk::Engine)

      expect(table.size).to eq(table.uniq.size)
      expect(table.map(&:last)).to include("contracts", "contract", "admin_root")
    end

    it "registers the component additively: the standalone mount point's catalogue and detail routes are untouched" do
      table = route_table(Decidim::ContractsSk::Engine)

      expect(table).to include(["GET", "/", "contracts"], ["GET", "/:id", "contract"])
    end
  end

  describe "permissions fail closed for everything Decidim runs through the manifest's class" do
    def outcome(user, scope:, action:, subject:, **context)
      permission_action = Decidim::PermissionAction.new(scope: scope, action: action, subject: subject)
      Decidim::ContractsSk::Permissions.new(user, permission_action, context).permissions
    end

    def unset?(*args, **kwargs)
      outcome(*args, **kwargs).allowed?
      false
    rescue Decidim::PermissionAction::PermissionNotSetError
      true
    end

    let(:org_admin) { Struct.new(:admin?, :admin_terms_accepted?).new(true, true) }

    it "never answers Decidim's own component permissions (read/update/share of :component are the core's to decide)" do
      aggregate_failures do
        expect(unset?(nil, scope: :public, action: :read, subject: :component)).to be(true)
        expect(unset?(org_admin, scope: :public, action: :read, subject: :component)).to be(true)
        expect(unset?(org_admin, scope: :admin, action: :update, subject: :component)).to be(true)
        expect(unset?(org_admin, scope: :admin, action: :share, subject: :component)).to be(true)
      end
    end

    it "grants the public nothing but the published read: no write action on a contract in the public scope" do
      %i[create update destroy publish approve import_crz].each do |action|
        result = unset?(org_admin, scope: :public, action: action, subject: :contract, state: :published)

        expect(result).to be(true), action.to_s
      end
    end

    it "admits the public read only for the lifecycle's public states and denies every other state" do
      Decidim::ContractsSk::ContractLifecycle::STATES.each do |state|
        expected = Decidim::ContractsSk::ContractLifecycle::PUBLIC_STATES.include?(state)
        allowed = outcome(nil, scope: :public, action: :read, subject: :contract, state: state).allowed?

        expect(allowed).to be(expected), state.to_s
      end
    end

    it "denies the public read when the state is absent or unknown" do
      expect(outcome(nil, scope: :public, action: :read, subject: :contract).allowed?).to be(false)
      expect(outcome(nil, scope: :public, action: :read, subject: :contract, state: :bogus).allowed?).to be(false)
    end
  end
end
# rubocop:enable RSpec/MultipleExpectations, RSpec/ExampleLength
