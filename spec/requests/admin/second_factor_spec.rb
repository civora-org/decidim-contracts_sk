# frozen_string_literal: true

# ---------------------------------------------------------------------------
# Request specs for the optional second-factor guard on the engine admin
# (civora-org/civora-platform#165, ADR-010), run against the dummy harness
# (engine mounted at "/", so the admin root is /admin).
#
# The seams are config-time host settings: second_factor_satisfied
# (user, session) -> boolean, default true; second_factor_redirect_path
# (controller) -> path, default the Decidim root. The guard lives in the
# engine ADMIN base controller only; the public catalogue and the in-space
# component do not inherit it.
#
# Synthetic data only, no real PII.
# ---------------------------------------------------------------------------

require "spec_helper"

SecondFactorViewer = Struct.new(:id, :engine_roles, keyword_init: true)

# rubocop:disable RSpec/AnyInstance, RSpec/MultipleExpectations, RSpec/ExampleLength
RSpec.describe "admin second-factor guard", :db, type: :request do
  let(:message) { I18n.t("decidim.contracts_sk.admin.second_factor.required") }
  let(:admin_paths) { %w[/admin /admin/contracts/new] }
  let(:viewer) { SecondFactorViewer.new(id: 1, engine_roles: %i[editor reviewer]) }

  around do |example|
    originals = [Decidim::ContractsSk.role_resolver, Decidim::ContractsSk.second_factor_satisfied,
                 Decidim::ContractsSk.second_factor_redirect_path]
    Decidim::ContractsSk.role_resolver = ->(user, _context) { Array(user&.engine_roles) }
    example.run
    Decidim::ContractsSk.role_resolver, Decidim::ContractsSk.second_factor_satisfied,
      Decidim::ContractsSk.second_factor_redirect_path = originals
  end

  before do
    migrate_engine_schema!
    admin = Decidim::ContractsSk::Admin
    [admin::ContractsController, admin::DashboardController].each do |controller|
      allow_any_instance_of(controller).to receive_messages(current_user: viewer, user_signed_in?: true,
                                                            current_organization: organization)
    end
  end

  it "ships a default that is satisfied and redirects to the Decidim root" do
    expect(Decidim::ContractsSk.second_factor_satisfied.call(nil, {})).to be(true)
    expect(Decidim::ContractsSk.second_factor_redirect_path.call(Object.new)).to eq("/")
  end

  it "lets admin requests through with the default seam" do
    admin_paths.each do |path|
      get path
      expect(response).to have_http_status(:ok), path
    end
  end

  it "redirects admin requests with the flash alert when the callable returns false" do
    Decidim::ContractsSk.second_factor_satisfied = ->(_user, _session) { false }

    admin_paths.each do |path|
      get path
      expect(response).to redirect_to("/"), path
      expect(flash[:alert]).to eq(message)
    end
  end

  it "sends an unsatisfied request to the host-configured path" do
    Decidim::ContractsSk.second_factor_satisfied = ->(_user, _session) { false }
    Decidim::ContractsSk.second_factor_redirect_path = ->(_controller) { "/two-factor" }

    get "/admin/contracts/new"

    expect(response).to redirect_to("/two-factor")
  end

  it "passes the user and a session to the callable" do
    seen = nil
    Decidim::ContractsSk.second_factor_satisfied = lambda { |user, session|
      seen = [user, session.respond_to?(:[])]
      true
    }

    get "/admin/contracts/new"

    expect(seen).to eq([viewer, true])
  end

  it "lets admin requests through when the callable returns true" do
    Decidim::ContractsSk.second_factor_satisfied = ->(_user, _session) { true }

    admin_paths.each do |path|
      get path
      expect(response).to have_http_status(:ok), path
    end
  end

  context "with a false callable and the public surfaces" do
    before do
      Decidim::ContractsSk.second_factor_satisfied = ->(_user, _session) { false }
      allow_any_instance_of(Decidim::ContractsSk::ContractsController)
        .to receive(:current_organization).and_return(organization)
      allow_any_instance_of(Decidim::ContractsSk::SpaceComponent::ContractsController)
        .to receive(:current_organization).and_return(organization)
    end

    it "leaves the public catalogue unaffected" do
      get "/"

      expect(response).to have_http_status(:ok)
    end

    it "leaves the in-space component unaffected" do
      get "/spaces/town/f/7"

      expect(response).to have_http_status(:ok)
    end
  end
end
# rubocop:enable RSpec/AnyInstance, RSpec/MultipleExpectations, RSpec/ExampleLength
