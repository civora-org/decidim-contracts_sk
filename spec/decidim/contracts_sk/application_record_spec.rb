# frozen_string_literal: true

# ---------------------------------------------------------------------------
# Deterministic, offline, class-level specs for the engine's abstract base
# model.
#
# The dummy Rails app (spec/dummy) boots the engine, so the model is provided
# by the application autoloader; the Decidim::ApplicationRecord stand-in
# these specs run against lives in spec/support/contracts_sk_db_helpers.rb.
# Assertions cover pure class-level metadata (inheritance, abstract_class,
# table name prefix, default scopes, association reflections) - none of them
# touch a DB connection.
# ---------------------------------------------------------------------------

require "spec_helper"

RSpec.describe Decidim::ContractsSk::ApplicationRecord do
  # AC: model uses the Decidim multi-tenancy base - it loads properly as a
  # class (the require above would raise on any class-definition error).
  it "is defined as a class" do
    expect(described_class).to be_a(Class)
  end

  # AC: model uses the Decidim multi-tenancy base - direct subclass of
  # Decidim::ApplicationRecord.
  it "inherits directly from Decidim::ApplicationRecord" do
    expect(described_class.superclass).to eq(Decidim::ApplicationRecord)
  end

  # AC: model uses the Decidim multi-tenancy base - the base class must not
  # map to a table of its own, so it is declared abstract.
  it "is abstract" do
    expect(described_class.abstract_class?).to be(true)
  end

  # AC: tables have prefix - the declared prefix applies to the base class.
  it "declares the decidim_contracts_sk_ table name prefix" do
    expect(described_class.table_name_prefix).to eq("decidim_contracts_sk_")
  end

  # AC: tables have prefix - future real models will subclass this abstract
  # base, so the prefix must be inherited by concrete subclasses.
  it "propagates the table name prefix to concrete subclasses" do
    concrete = Class.new(described_class)

    expect(concrete.table_name_prefix).to eq("decidim_contracts_sk_")
  end

  # D1-A regression guard (civora-org/civora-platform#37): NO default_scope
  # for tenant isolation - tenant scoping happens on concrete models via
  # their organization association plus query object scoping, matching
  # Decidim core conventions.
  it "declares no default scopes" do
    expect(described_class.default_scopes).to be_empty
  end

  # D2-B regression guard (civora-org/civora-platform#37): NO associations on
  # the base class - belongs_to :organization and other associations belong
  # on concrete models.
  it "declares no :organization association" do
    expect(described_class.reflect_on_association(:organization)).to be_nil
  end
end
