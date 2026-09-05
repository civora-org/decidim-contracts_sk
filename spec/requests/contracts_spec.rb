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
#   seam — see spec/requests/admin/contracts_spec.rb). Documents are part
#   of the show render since M02-05-A0 (#73): the offline doubles carry
#   plain arrays of document doubles — a blob-backed link needs a real
#   blob row, so the offline group covers only the not-attached/empty
#   shapes, while the real download links run in the :db group.
#
# * The :db group (CONTRACTS_SK_DB=1) pins the published-only scoping, the
#   organization tenancy, the document links against the real ActiveStorage
#   tables (built from the pinned activestorage gem's own migration; the
#   engine ships none — the host app owns that schema) and the end-to-end
#   rendering on an in-memory SQLite adapter.
#
# Not-found semantics: both actions read exclusively through the published
# scope, so an unpublished record, another organization's record and a
# nonexistent id take the SAME code path and raise the SAME exception
# (ActiveRecord::RecordNotFound). The harness re-raises exceptions out of
# the request (show_exceptions :none — see spec/dummy/config/application.rb),
# so the raise itself is the asserted behavior, exactly as in the admin
# specs.
#
# Synthetic data only, no real PII (the uploaded fixtures are synthetic
# PDF-shaped/text bytes, no real content).
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
    let(:documents) { [] }
    # The controller loads the public version history through the
    # amendment association (published scope + newest-version-first
    # order); the offline double mirrors that chain (#65).
    let(:amendments) { [] }
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
        parties: parties,
        documents: documents,
        amendments: double(published: double(order: amendments))
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

    it "renders the empty-document state gracefully (civora-org/civora-platform#73)" do
      stub_published_contracts(double(find: contract))

      get "/7"

      expect(response).to have_http_status(:ok)
      aggregate_failures do
        expect(response.body).to include("Documents")
        expect(response.body).to include("No documents have been attached to this contract.")
      end
    end

    it "renders the published amendments as a labelled version history (M02-05-B, civora-org/civora-platform#65)" do
      amendments << double(version: 2,
                           summary: "Extended delivery deadline",
                           published_at: Time.new(2026, 9, 2, 12, 0, 0),
                           content_snapshot: {
                             "subject_matter" => "Supply and installation of road signage",
                             "amount" => "1000.0",
                             "currency" => "EUR"
                           })
      stub_published_contracts(double(find: contract))

      get "/7"

      expect(response).to have_http_status(:ok)
      aggregate_failures do
        expect(response.body).to include("Version history")
        # The current/historical distinction is labelled (ADR-006).
        expect(response.body).to include("Current version")
        expect(response.body).to include("Version 2")
        expect(response.body).to include("Extended delivery deadline")
        expect(response.body).to include("2026-09-02")
        # The frozen snapshot fields render under the record's own
        # content-field vocabulary.
        expect(response.body).to include("Subject matter")
        expect(response.body).to include("1000.0")
      end
    end

    it "skips metadata-only documents that carry no attached file (civora-org/civora-platform#73)" do
      documents << double(file: double(attached?: false))
      stub_published_contracts(double(find: contract))

      get "/7"

      expect(response).to have_http_status(:ok)
      # A document without a file has neither a link nor a size to show —
      # it is skipped, and the section falls back to the empty state.
      expect(response.body).to include("No documents have been attached to this contract.")
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
  # the shared :db support). Document examples additionally build the
  # ActiveStorage tables (host-app-owned schema, test-built from the pinned
  # gem's migration) and wipe the Disk service root for hermeticity.
  describe "published-only scoping and real rendering (civora-org/civora-platform#62, #63)", :db do
    before do
      migrate_engine_schema!
      FileUtils.rm_rf(active_storage_root)

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

    # Path to a synthetic fixture (PDF-shaped/text bytes, no real content).
    def sample_fixture(name)
      File.join(engine_root, "spec", "fixtures", "files", name)
    end

    # Creates a document on the contract and attaches a real fixture file.
    def attach!(contract, title:, kind:, fixture:, type:)
      document = contract.documents.create!(title: title, kind: kind)
      document.attach_file!(Rack::Test::UploadedFile.new(sample_fixture(fixture), type))
      document
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

    it "lists a published record's documents as download links with kind and size (civora-org/civora-platform#73)" do
      contract = create_contract!
      attach!(contract, title: "Signed contract scan", kind: "contract",
                        fixture: "sample.pdf", type: "application/pdf")
      attach!(contract, title: "Annex notes", kind: "annex",
                        fixture: "sample-notes.txt", type: "text/plain")

      get "/#{contract.id}"

      expect(response).to have_http_status(:ok)
      scan = contract.documents.reload.first
      expected_link = "/rails/active_storage/blobs/redirect/#{scan.file.blob.signed_id}/sample.pdf"
      # A sub-1024-byte fixture humanizes as "<n> Bytes" under the en locale.
      annex_size = "#{File.size(sample_fixture("sample-notes.txt"))} Bytes"
      aggregate_failures do
        # Download links through the host's ActiveStorage route, forced
        # attachment disposition, one per document.
        expect(response.body).to include("Signed contract scan")
        expect(response.body).to include(%(href="#{expected_link}?disposition=attachment))
        expect(response.body).to include("Annex notes")
        expect(response.body).to include("Contract document")
        expect(response.body).to include("(Annex, #{annex_size})")
      end
    end

    it "renders the empty-document state for a published record without attachments (#73)" do
      contract = create_contract!
      # A metadata-only row without an attachment is legal (the #56 shape):
      # it renders nothing rather than a dead entry.
      contract.documents.create!(title: "Placeholder", kind: "other")

      get "/#{contract.id}"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("No documents have been attached to this contract.")
    end

    it "renders the published amendments newest-first as a labelled version history (#65)" do
      # M02-05-B (civora-org/civora-platform#65): published amendments are
      # the frozen historical versions; created directly here with a
      # pinned snapshot shape (the publish command's own spec pins how the
      # snapshot is taken).
      contract = create_contract!
      contract.amendments.create!(
        version: 1, summary: "Original scope",
        state: "published", published_at: Time.utc(2026, 9, 1, 12, 0, 0),
        content_snapshot: { "subject_matter" => "Original signage scope", "amount" => "1000.0", "currency" => "EUR" },
        organization: organization, author: author
      )
      contract.amendments.create!(
        version: 2, summary: "Extended delivery deadline",
        state: "published", published_at: Time.utc(2026, 9, 2, 12, 0, 0),
        content_snapshot: { "subject_matter" => "Extended signage scope", "amount" => "1500.0",
                            "currency" => "EUR" },
        organization: organization, author: author
      )

      get "/#{contract.id}"

      expect(response).to have_http_status(:ok)
      aggregate_failures do
        expect(response.body).to include("Version history")
        expect(response.body).to include("Current version")
        expect(response.body).to include("Version 1")
        expect(response.body).to include("Original scope")
        expect(response.body).to include("Original signage scope")
        expect(response.body).to include("Version 2")
        expect(response.body).to include("Extended delivery deadline")
        expect(response.body).to include("2026-09-02")
        # Newest version first (ADR-006 presentation order).
        expect(response.body.index("Version 2")).to be < response.body.index("Version 1")
        # The live fields above stay the current version — the record's own
        # amount is unchanged by the published versions.
        expect(response.body).to include("1250.5")
      end
    end

    it "never renders draft amendments publicly (#65, ADR-006)" do
      contract = create_contract!
      contract.amendments.create!(
        version: 1, summary: "Secret upcoming change",
        organization: organization, author: author
      )
      contract.amendments.create!(
        version: 2, summary: "Public change",
        state: "published", published_at: Time.utc(2026, 9, 2, 12, 0, 0),
        content_snapshot: { "subject_matter" => "Public scope", "currency" => "EUR" },
        organization: organization, author: author
      )

      get "/#{contract.id}"

      expect(response).to have_http_status(:ok)
      aggregate_failures do
        # The published version renders; the draft is indistinguishable
        # from an absent one.
        expect(response.body).to include("Public change")
        expect(response.body).not_to include("Secret upcoming change")
        expect(response.body).not_to include("Version 1")
      end
    end

    it "renders the empty-versions state for a record without amendments (#65)" do
      contract = create_contract!

      get "/#{contract.id}"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("No amendments have been published for this contract.")
    end

    it "hides an unpublished record's documents behind the same not-found path (civora-org/civora-platform#73)" do
      draft = create_contract!(
        title: "Draft road with documents", reference: "ZP-2026-008",
        state: "draft", published_at: nil
      )
      draft.documents.create!(title: "Hidden scan", kind: "contract")
           .attach_file!(Rack::Test::UploadedFile.new(sample_fixture("sample.pdf"), "application/pdf"))

      # The published-only scope is the entire public gate: a draft record's
      # documents cannot leak through the detail page.
      expect { get "/#{draft.id}" }.to raise_error(ActiveRecord::RecordNotFound)
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
