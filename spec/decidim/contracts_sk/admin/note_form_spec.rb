# frozen_string_literal: true

require "spec_helper"

# Offline specs for the internal-note form (civora-org/civora-platform#128).
RSpec.describe Decidim::ContractsSk::Admin::NoteForm do
  def form(body)
    described_class.new(body: body)
  end

  it "is valid with a body" do
    expect(form("Ask the lawyer.")).to be_valid
  end

  [nil, "", "  \n\t "].each do |blank|
    it "rejects the blank body #{blank.inspect}" do
      expect(form(blank)).not_to be_valid
    end
  end

  it "strips surrounding whitespace on assignment" do
    expect(form("  hello \n").body).to eq("hello")
  end

  it "accepts exactly 2000 characters, padding not counted" do
    expect(form("  #{"a" * 2000}  ")).to be_valid
  end

  it "rejects 2001 characters" do
    expect(form("a" * 2001)).not_to be_valid
  end
end
