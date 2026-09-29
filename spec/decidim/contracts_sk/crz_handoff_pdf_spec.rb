# frozen_string_literal: true

# ---------------------------------------------------------------------------
# Offline (DB-free) specs for the CRZ-handoff PDF renderer
# (M02-05-C, civora-org/civora-platform#74).
#
# CrzHandoffPdf duck-types its contract, so these examples run against a
# plain Struct — no ActiveRecord, no ActiveStorage, no network. Prawn is
# pure Ruby and the DejaVu font ships inside the gem (data/fonts), so the
# renderer itself is exercised FOR REAL: every assertion below inspects the
# actual generated PDF bytes.
#
# The PDF's text streams are font-subset-encoded (glyph codes, not ASCII),
# so byte-level content assertions are impossible by design; the renderer's
# content discipline is pinned instead through the locale contract
# (contracts_sk_locales_spec.rb) and the integration request specs.
# ---------------------------------------------------------------------------

require "spec_helper"

# Duck-typed contract + party stand-ins: exactly the surface the renderer
# reads (title, reference, state, subject_matter, amount, currency,
# signed_on, effective_from, crz_url, parties[role, name]).
FakeHandoffContract = Struct.new(:title, :reference, :state, :subject_matter, :amount,
                                 :currency, :signed_on, :effective_from, :crz_url,
                                 :parties, keyword_init: true)
FakeHandoffParty = Struct.new(:role, :name)

RSpec.describe Decidim::ContractsSk::CrzHandoffPdf do
  subject(:pdf_bytes) { described_class.new(contract).render }

  let(:contract) do
    FakeHandoffContract.new(
      title: "Rekonštrukcia cesty",
      reference: "ZP-2026-001",
      state: "in_review",
      subject_matter: "Stavebné práce",
      amount: BigDecimal("12345.67"),
      currency: "EUR",
      signed_on: Date.new(2026, 1, 31),
      effective_from: Date.new(2026, 2, 1),
      crz_url: "https://crz.gov.sk/0/12345",
      parties: [FakeHandoffParty.new(:object, "Mesto Test"),
                FakeHandoffParty.new(:contractor, "Dodávateľ s.r.o.")]
    )
  end

  # A contract carrying only its identity: every optional content field and
  # the parties are blank, the shape the renderer must never choke on.
  def blank_optional_fields(**identity)
    FakeHandoffContract.new(state: "draft", subject_matter: nil, amount: nil, currency: nil,
                            signed_on: nil, effective_from: nil, crz_url: nil, parties: [], **identity)
  end

  it "renders a real PDF document" do
    aggregate_failures do
      expect(pdf_bytes).to be_a(String)
      expect(pdf_bytes).to start_with("%PDF-")
      expect(pdf_bytes.rstrip).to end_with("%%EOF")
    end
  end

  it "renders Slovak diacritics without an encoding error" do
    # The regression this renderer exists to avoid: prawn's WinAnsi core
    # fonts raise Prawn::Errors::IncompatibleStringEncoding on Slovak text;
    # the vendored Unicode font must absorb it.
    expect { pdf_bytes }.not_to raise_error
  end

  it "leaves the ambient I18n locale untouched (content is forced to :sk internally)" do
    expect do
      pdf_bytes
    end.not_to change(I18n, :locale)
  end

  it "renders a record with every optional field blank and no parties" do
    bare = blank_optional_fields(title: "Rekonštrukcia cesty", reference: "ZP-2026-001")

    expect { described_class.new(bare).render }.not_to raise_error
  end

  it "renders an unknown state token without inventing a label" do
    contract.state = "mystery"

    expect { pdf_bytes }.not_to raise_error
  end

  it "renders the amount in fixed-point notation, never scientific" do
    contract.amount = BigDecimal("0.125e4")

    expect { pdf_bytes }.not_to raise_error
  end

  it "labels the footer generation stamp with an explicit UTC zone (civora-org/civora-platform#81)" do
    # Byte-level content assertions are impossible (font-subset encoding —
    # see the header), so the stamp is asserted through the method the
    # footer draws: UTC-converted digits plus the zone label.
    stamp = described_class.new(contract).send(:generated_stamp)

    expect(stamp).to match(/\A\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2} UTC\z/)
  end
end
