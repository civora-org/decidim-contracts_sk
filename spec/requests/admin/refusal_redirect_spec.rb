# frozen_string_literal: true

# ---------------------------------------------------------------------------
# Request specs for the engine admin's refusal landing (civora-org/
# civora-platform#161, D1 of the #108 spike), run against the dummy harness
# (engine mounted at "/", so the admin root is /admin and the public
# catalogue root is /).
#
# Decidim's admin base redirects every refusal to /admin, which is a 404 for
# a non-admin engine-role holder on a real host. The engine overrides the
# landing: role holders go to the engine admin root, everyone else to the
# public catalogue. The harness stand-in's own landing is "/", so the
# role-holder case (/admin) is distinguishable from the stand-in's default.
# ---------------------------------------------------------------------------

require "spec_helper"

RefusalViewer = Struct.new(:engine_roles, keyword_init: true)

# rubocop:disable RSpec/AnyInstance, RSpec/MultipleExpectations
RSpec.describe "admin refusal redirect", type: :request do
  let(:unauthorized) { "You are not authorized to perform this action." }

  around do |example|
    original = Decidim::ContractsSk.role_resolver
    Decidim::ContractsSk.role_resolver = ->(user, _context) { Array(user&.engine_roles) }
    example.run
    Decidim::ContractsSk.role_resolver = original
  end

  def sign_in(roles:)
    controller = Decidim::ContractsSk::Admin::ContractsController
    allow_any_instance_of(controller).to receive(:current_user).and_return(RefusalViewer.new(engine_roles: roles))
    allow_any_instance_of(controller).to receive(:user_signed_in?).and_return(true)
    allow_any_instance_of(controller).to receive(:current_organization).and_return(nil)
  end

  it "sends a reviewer refused on the new-contract form to the engine admin root, with the flash" do
    sign_in(roles: %i[reviewer])
    get "/admin/contracts/new"

    expect(response).to redirect_to("/admin")
    expect(flash[:alert]).to eq(unauthorized)
  end

  it "sends a roleless user refused on the index to the public catalogue, with the flash" do
    sign_in(roles: [])
    get "/admin/contracts"

    expect(response).to redirect_to("/")
    expect(flash[:alert]).to eq(unauthorized)
  end

  it "lets a referer win over the landing path (NeedsPermission behaviour is kept)" do
    sign_in(roles: %i[reviewer])
    get "/admin/contracts/new", headers: { "HTTP_REFERER" => "http://www.example.com/admin/contracts" }

    expect(response).to redirect_to("http://www.example.com/admin/contracts")
  end
end
# rubocop:enable RSpec/AnyInstance, RSpec/MultipleExpectations
