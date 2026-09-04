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
# Admin paths are covered by spec/requests/admin/contracts_spec.rb since the
# admin CRUD milestone (civora-org/civora-platform#58); one cross-cutting
# guard stays here: an unauthenticated admin visit must never render the
# public catalogue body.
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

  it "does not render the public catalogue body for an unauthenticated admin visit" do
    get "/admin/contracts"

    # The admin base bounces the visitor (redirect, not a render) — and the
    # bounce response must carry no catalogue content either.
    expect(response).to have_http_status(:redirect)
    expect(response.body).not_to include("Contracts")
  end
end
# rubocop:enable RSpec/MultipleExpectations
