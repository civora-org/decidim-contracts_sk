# frozen_string_literal: true

# ---------------------------------------------------------------------------
# Request specs for the public contracts catalogue, run against the Stage-1
# dummy harness (spec/dummy mounts the engine at "/"; see
# civora-org/civora-platform#61).
#
# The scaffold renders localized plain-text placeholders (see
# ContractsController), so the bodies are asserted against those exact
# strings (en locale, the dummy's default).
#
# Admin paths pin the current admin/public separation: the admin routes exist
# in the engine's route table, but no admin controller class does yet (the
# admin CRUD milestone is civora-org/civora-platform#45). Rails raises
# ActionController::RoutingError when it cannot resolve the controller, and
# with config.action_dispatch.show_exceptions = :rescuable that maps to
# 404 — the expected fail-closed answer for an unauthenticated admin surface.
# ---------------------------------------------------------------------------

require "spec_helper"

# Status + body are asserted per example by design: for a scaffold that
# renders plain-text placeholders, the status alone proves nothing.
# rubocop:disable RSpec/MultipleExpectations
RSpec.describe "public contracts catalogue", type: :request do
  it "renders the catalogue index at the mount root" do
    get "/"

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Contracts")
  end

  it "renders the contract detail for an /:id path" do
    get "/42"

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Contract details")
  end

  it "serves any /:id segment through the show catch-all" do
    # Pins the mount-root catch-all: a single /:id segment always reaches
    # show, even when it cannot name a real contract yet.
    get "/nonexistent"

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Contract details")
  end

  it "answers 404 for the admin contracts index (admin controllers absent)" do
    get "/admin/contracts"

    expect(response).to have_http_status(:not_found)
  end

  it "answers 404 for the admin new-contract form" do
    get "/admin/contracts/new"

    expect(response).to have_http_status(:not_found)
  end
end
# rubocop:enable RSpec/MultipleExpectations
