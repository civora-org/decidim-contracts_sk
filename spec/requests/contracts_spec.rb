# frozen_string_literal: true

# ---------------------------------------------------------------------------
# Request specs for the public contracts catalogue (civora-org/civora-platform
# #62, #63), run against the Stage-1 dummy harness (spec/dummy mounts the
# engine at "/"). Two layers, one file — mirroring the admin request specs:
#
# * The default (offline, DB-free) group pins the rendering and the
#   not-found path. The controller's #published_contracts is the record
#   seam: an AR scope execution would need a connection, so request specs
#   stub it per-example with allow_any_instance_of (the approved harness
#   seam — see spec/requests/admin/contracts_spec.rb).
#
# * The :db group (CONTRACTS_SK_DB=1) pins the published-only scoping, the
#   organization tenancy and the end-to-end rendering against the real
#   migrations on an in-memory SQLite adapter.
#
# Not-found semantics: both actions read exclusively through the published
# scope, so an unpublished record, another organization's record and a
# nonexistent id take the SAME code path and raise the SAME exception
# (ActiveRecord::RecordNotFound — a real deployment renders it as 404; the
# dummy is deliberately AR-railtie-free and does not rescue it, so the raise
# itself is the asserted behavior, exactly as in the admin specs).
#
# Synthetic data only, no real PII.
#
# Cop note: allow_any_instance_of is the approved seam for this harness (the
# record scope lives on the controller; request specs cannot inject records
# into the framework's instantiation path), so the cop is disabled file-wide
# along with the dense-assertion cops.
# ---------------------------------------------------------------------------

require "spec_helper"

# Attributes of the published fixture contract shared by the :db examples
# (a fresh database per example; the overrides keep identities unique). Kept
# in a plain module (not inside a describe block) so that its constant stays
# lint-clean, mirroring the locales/routing spec pattern.
module PublishedContractFixture
  DEFAULTS = {
    state: "published",
    published_at: Time.utc(2026, 9, 1, 12, 0, 0),
    subject_matter: "Supply and installation of road signage",
    amount: BigDecimal("1250.50"),
    currency: "EUR",
    signed_on: Date.new(2026, 9, 1),
    effective_from: Date.new(2026, 8, 15),
    crz_url: "https://crz.gov.sk/record/123"
  }.freeze
end

# Status and body are asserted per example by design: every example must
# prove what rendered and why.
# rubocop:disable RSpec/MultipleExpectations, RSpec/ExampleLength, RSpec/AnyInstance
RSpec.describe "public contracts catalogue", type: :request do
  # The controller's published scope is the single offline seam (see the
  # header): both actions read every record through it.
  def stub_published_contracts(scope)
    allow_any_instance_of(Decidim::ContractsSk::ContractsController)
      .to receive(:published_contracts).and_return(scope)
  end

  def published_contract_double(overrides = {})
    double(
      title: "Road reconstruction",
      reference: "ZP-2026-001",
      published_at: Time.new(2026, 9, 1, 12, 0, 0),
      to_param: "7",
      **overrides
    )
  end

  describe "catalogue index (civora-org/civora-platform#62)" do
    it "lists a published contract with title, reference, publication date and a detail link" do
      stub_published_contracts([published_contract_double])

      get "/"

      expect(response).to have_http_status(:ok)
      aggregate_failures do
        expect(response.body).to include("Road reconstruction")
        expect(response.body).to include("ZP-2026-001")
        expect(response.body).to include("2026-09-01")
        expect(response.body).to include(%(href="/7"))
      end
    end

    it "renders the localized empty state when nothing is published" do
      stub_published_contracts([])

      get "/"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("No published contracts yet.")
    end
  end

  describe "contract detail (civora-org/civora-platform#63)" do
    let(:parties) { [] }
    let(:contract) do
      double(
        title: "Road reconstruction",
        reference: "ZP-2026-001",
        published_at: Time.new(2026, 9, 1, 12, 0, 0),
        subject_matter: "Supply and installation of road signage",
        amount: BigDecimal("1250.50"),
        currency: "EUR",
        signed_on: Date.new(2026, 9, 1),
        effective_from: Date.new(2026, 8, 15),
        crz_url: "https://crz.gov.sk/record/123",
        parties: parties
      )
    end

    it "renders the published-safe content fields and the associated parties" do
      parties << double(role: "object", name: "Obec Zelen", ico: "12345678", address: nil)
      stub_published_contracts(double(find: contract))

      get "/7"

      expect(response).to have_http_status(:ok)
      aggregate_failures do
        expect(response.body).to include("Road reconstruction")
        expect(response.body).to include("ZP-2026-001")
        expect(response.body).to include("2026-09-01")
        expect(response.body).to include("Supply and installation of road signage")
        expect(response.body).to include("1250.5")
        expect(response.body).to include("EUR")
        expect(response.body).to include("2026-08-15")
        expect(response.body).to include(%(href="https://crz.gov.sk/record/123"))
        expect(response.body).to include("Object party")
        expect(response.body).to include("Obec Zelen")
      end
    end

    it "renders the empty-party state gracefully" do
      stub_published_contracts(double(find: contract))

      get "/7"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("No parties have been recorded for this contract.")
    end

    it "raises the not-found exception for a nonexistent id through the published scope" do
      # Offline the raise is all that can be asserted (see the header); the
      # :db group proves below that an unpublished record takes exactly the
      # same path.
      scope = double
      allow(scope).to receive(:find).and_raise(ActiveRecord::RecordNotFound)
      stub_published_contracts(scope)

      expect { get "/nonexistent" }.to raise_error(ActiveRecord::RecordNotFound)
    end
  end

  # Real end-to-end group: the published-only scope, the organization
  # tenancy, the rendering and the not-found indistinguishability against
  # the REAL migrations (in-memory SQLite; fresh database per example via
  # the shared :db support).
  describe "published-only scoping and real rendering (civora-org/civora-platform#62, #63)", :db do
    before do
      migrate_engine_schema!

      # Tenancy seam (Gate-1 fold-in): the catalogue reads
      # current_organization, exactly like the admin side; the :db group
      # carries the shared-context organization on it.
      allow_any_instance_of(Decidim::ContractsSk::ContractsController)
        .to receive(:current_organization).and_return(organization)
    end

    # Creates a contract with the published fixture defaults; the overrides
    # adjust identity fields, the lifecycle state and anything else per
    # example.
    def create_contract!(overrides = {})
      Decidim::ContractsSk::Contract.create!(
        contract_attributes(PublishedContractFixture::DEFAULTS.merge(overrides))
      )
    end

    it "lists only published contracts, newest publication first, linked to their detail pages" do
      newer = create_contract!(
        title: "First published road", reference: "ZP-2026-001"
      )
      older = create_contract!(
        title: "Second published road", reference: "ZP-2026-002",
        published_at: Time.utc(2026, 6, 1, 12, 0, 0)
      )
      create_contract!(
        title: "Draft road", reference: "ZP-2026-003",
        state: "draft", published_at: nil
      )
      create_contract!(
        title: "Archived road", reference: "ZP-2026-004",
        state: "archived", published_at: Time.utc(2026, 7, 1, 12, 0, 0)
      )

      get "/"

      expect(response).to have_http_status(:ok)
      aggregate_failures do
        expect(response.body).to include("First published road")
        expect(response.body).to include("Second published road")
        # The published-only scope is the Gate-1 decision: drafts AND
        # archived records stay out of the catalogue.
        expect(response.body).not_to include("Draft road")
        expect(response.body).not_to include("Archived road")
        # Newest publication first.
        expect(response.body.index("First published road")).to be < response.body.index("Second published road")
        expect(response.body).to include(%(href="/#{newer.id}"))
        expect(response.body).to include(%(href="/#{older.id}"))
      end
    end

    it "shows a published contract with its content fields and both party roles" do
      contract = create_contract!
      contract.parties.create!(role: "object", name: "Obec Zelen", ico: "12345678")
      contract.parties.create!(role: "contractor", name: "Zeleň a.s.", ico: "87654321")

      get "/#{contract.id}"

      expect(response).to have_http_status(:ok)
      aggregate_failures do
        expect(response.body).to include("Road reconstruction")
        expect(response.body).to include("ZP-2026-001")
        expect(response.body).to include("2026-09-01")
        expect(response.body).to include("Supply and installation of road signage")
        expect(response.body).to include("1250.5")
        expect(response.body).to include("EUR")
        expect(response.body).to include("2026-08-15")
        expect(response.body).to include(%(href="https://crz.gov.sk/record/123"))
        expect(response.body).to include("Object party")
        expect(response.body).to include("Obec Zelen")
        expect(response.body).to include("Contractor")
        expect(response.body).to include("Zeleň a.s.")
      end
    end

    it "omits the CRZ link section entirely when the record carries no crz_url" do
      contract = create_contract!(crz_url: nil)

      get "/#{contract.id}"

      expect(response).to have_http_status(:ok)
      # Neither the localized label nor any link residue may render — the
      # section is guarded, not rendered with an empty href.
      aggregate_failures do
        expect(response.body).not_to include("CRZ URL")
        expect(response.body).not_to include("crz.gov.sk")
      end
    end

    it "renders the empty-party state gracefully for a published record without parties" do
      contract = create_contract!

      get "/#{contract.id}"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("No parties have been recorded for this contract.")
    end

    it "hides an unpublished record and a nonexistent id behind the same not-found path" do
      draft = create_contract!(
        title: "Draft road", reference: "ZP-2026-005",
        state: "draft", published_at: nil
      )

      # Same exception through the same scoped find: the response cannot
      # distinguish "hidden" from "absent" (see the header for the
      # raise-vs-404 harness note).
      aggregate_failures do
        expect { get "/#{draft.id}" }.to raise_error(ActiveRecord::RecordNotFound)
        expect { get "/#{draft.id + 100_000}" }.to raise_error(ActiveRecord::RecordNotFound)
      end
    end

    it "hides an archived record from the detail page too (the scope is published-only, Gate 1)" do
      archived = create_contract!(
        title: "Archived road", reference: "ZP-2026-006",
        state: "archived", published_at: Time.utc(2026, 7, 1, 12, 0, 0)
      )

      expect { get "/#{archived.id}" }.to raise_error(ActiveRecord::RecordNotFound)
    end

    it "hides another organization's published contract from the index and 404s its id like a nonexistent one" do
      # Tenant isolation (Gate-1 fold-in): the catalogue is org-scoped, so
      # a PUBLISHED record of another organization is as invisible as a
      # hidden one — absent from the index, and its id takes the same
      # tenant-scoped find as a nonexistent id (indistinguishable raise;
      # see the header for the raise-vs-404 harness note).
      foreign_org = Decidim::Organization.create!
      foreign = create_contract!(
        organization: foreign_org,
        title: "Foreign road", reference: "ZP-2026-007"
      )

      get "/"

      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include("Foreign road")
      expect(response.body).not_to include("ZP-2026-007")

      aggregate_failures do
        expect { get "/#{foreign.id}" }.to raise_error(ActiveRecord::RecordNotFound)
        expect { get "/#{foreign.id + 100_000}" }.to raise_error(ActiveRecord::RecordNotFound)
      end

      # The foreign record itself is untouched — scoping hides, never harms.
      foreign.reload
      expect(foreign.state).to eq("published")
    end
  end

  # Cross-cutting guard carried over from the scaffold era: an
  # unauthenticated admin visit must never render the public catalogue body.
  it "does not render the public catalogue body for an unauthenticated admin visit" do
    get "/admin/contracts"

    expect(response).to have_http_status(:redirect)
    # Both markers: the catalogue page itself (its h1) and any record data
    # that only a real catalogue render could have carried.
    expect(response.body).not_to include("Contracts")
    expect(response.body).not_to include("Road reconstruction")
  end
end
# rubocop:enable RSpec/MultipleExpectations, RSpec/ExampleLength, RSpec/AnyInstance
