# frozen_string_literal: true

# ---------------------------------------------------------------------------
# Deterministic, offline locale-contract specs for civora-org/civora-platform#39
# (M01-01-G: Add locales).
#
# Loading pattern (no dummy Rails app, no engine boot):
#
#   1. both locale files are parsed with YAML.safe_load for structural
#      assertions (shipped file surface, key parity, leaf-value sanity);
#   2. the files are additionally loaded into a FRESH I18n::Backend::Simple
#      instance, so acceptance criterion 1 ("I18n.t('decidim.contracts_sk.
#      contract.title') works") is verified through the real i18n translation
#      path without mutating global I18n state. The backend-translate form is
#      equivalent to I18n.t: I18n.t delegates to I18n.backend.translate.
# ---------------------------------------------------------------------------

require "spec_helper"

require "i18n"
require "yaml"

# Shared vocabulary and introspection for the example groups below. Kept in a
# plain module (not inside a describe block) so that its constants stay
# lint-clean and its helpers can be included where needed. Cop note: the
# module IS the pinned key/label vocabulary — its length grows with the
# engine's locale surface, not with logic, so the module budget is disabled
# rather than splitting the contract tables apart.
# rubocop:disable Metrics/ModuleLength
module LocaleContract
  # Repo-root-relative locale dir: this spec lives at spec/decidim/, so two
  # levels up is the engine root (config/locales sits beneath it).
  LOCALES_DIR = File.expand_path("../../config/locales", __dir__)
  LOCALES = %w[en sk].freeze

  # The acceptance-criterion key of civora-org/civora-platform#39.
  ACCEPTANCE_KEY = "decidim.contracts_sk.contract.title"

  # The admin content-field form labels per locale, per the data dictionary
  # (civora-org/civora-platform#75).
  CONTENT_FIELD_LABELS = {
    en: { subject_matter: "Subject matter", amount: "Amount", currency: "Currency",
          signed_on: "Signed on", effective_from: "Effective from", crz_url: "CRZ URL" },
    sk: { subject_matter: "Predmet zmluvy", amount: "Hodnota", currency: "Mena",
          signed_on: "Dátum podpisu", effective_from: "Dátum účinnosti", crz_url: "Odkaz na CRZ" }
  }.freeze

  # The admin party labels per locale, per the approved Slovak translations
  # (civora-org/civora-platform#76): object party = Objednávateľ,
  # contractor = Dodávateľ.
  PARTY_ROLE_LABELS = {
    en: { object: "Object party", contractor: "Contractor" },
    sk: { object: "Objednávateľ", contractor: "Dodávateľ" }
  }.freeze

  # The document kind labels per locale, per the approved translations
  # (civora-org/civora-platform#73). The admin (admin.documents.kinds.*)
  # and public (contract.document.*) vocabularies deliberately share the
  # same terminology.
  DOCUMENT_KIND_LABELS = {
    en: { contract: "Contract document", crz_export: "CRZ export", annex: "Annex", other: "Other document" },
    sk: { contract: "Zmluvný dokument", crz_export: "Export z CRZ", annex: "Príloha", other: "Iný dokument" }
  }.freeze

  # The public detail page's document section labels per locale
  # (civora-org/civora-platform#73).
  DOCUMENT_VIEW_LABELS = {
    en: {
      "contracts.show.documents" => "Documents",
      "contracts.show.documents_empty" => "No documents have been attached to this contract."
    },
    sk: {
      "contracts.show.documents" => "Dokumenty",
      "contracts.show.documents_empty" => "K tejto zmluve nie sú pripojené žiadne dokumenty."
    }
  }.freeze

  # The exact expected leaf-key surface under decidim.contracts_sk, including
  # the public catalogue keys (plan Option B of #39), the admin CRUD keys
  # (civora-org/civora-platform#58), the admin content-field form keys
  # (civora-org/civora-platform#75), the admin party keys
  # (civora-org/civora-platform#76), the public catalogue view keys
  # (civora-org/civora-platform#62, #63) and the admin/public document keys
  # (civora-org/civora-platform#73). Sorted alphabetically.
  EXPECTED_KEYS = [
    "admin.contracts.create.error",
    "admin.contracts.create.success",
    "admin.contracts.edit.title",
    "admin.contracts.form.amount",
    "admin.contracts.form.crz_url",
    "admin.contracts.form.currency",
    "admin.contracts.form.effective_from",
    "admin.contracts.form.reference",
    "admin.contracts.form.signed_on",
    "admin.contracts.form.subject_matter",
    "admin.contracts.form.title",
    "admin.contracts.index.title",
    "admin.contracts.new.title",
    "admin.contracts.transition.invalid",
    "admin.contracts.transition.success",
    "admin.contracts.update.error",
    "admin.contracts.update.success",
    "admin.documents.back_to_contract",
    "admin.documents.create.error",
    "admin.documents.create.success",
    "admin.documents.destroy.confirm",
    "admin.documents.destroy.error",
    "admin.documents.destroy.link",
    "admin.documents.destroy.success",
    "admin.documents.edit.title",
    "admin.documents.form.current_file",
    "admin.documents.form.file",
    "admin.documents.form.kind",
    "admin.documents.form.title",
    "admin.documents.index.title",
    "admin.documents.kinds.annex",
    "admin.documents.kinds.contract",
    "admin.documents.kinds.crz_export",
    "admin.documents.kinds.other",
    "admin.documents.new.title",
    "admin.documents.update.error",
    "admin.documents.update.success",
    "admin.parties.back_to_contract",
    "admin.parties.create.error",
    "admin.parties.create.success",
    "admin.parties.destroy.confirm",
    "admin.parties.destroy.error",
    "admin.parties.destroy.link",
    "admin.parties.destroy.success",
    "admin.parties.edit.title",
    "admin.parties.form.address",
    "admin.parties.form.ico",
    "admin.parties.form.name",
    "admin.parties.form.role",
    "admin.parties.index.title",
    "admin.parties.new.title",
    "admin.parties.roles.contractor",
    "admin.parties.roles.object",
    "admin.parties.update.error",
    "admin.parties.update.success",
    "contract.amount",
    "contract.crz_url",
    "contract.currency",
    "contract.document.annex",
    "contract.document.contract",
    "contract.document.crz_export",
    "contract.document.other",
    "contract.effective_from",
    "contract.party.contractor",
    "contract.party.object",
    "contract.published_on",
    "contract.reference_number",
    "contract.signed_on",
    "contract.status",
    "contract.subject_matter",
    "contract.title",
    "contracts.index.empty",
    "contracts.index.title",
    "contracts.show.documents",
    "contracts.show.documents_empty",
    "contracts.show.parties",
    "contracts.show.parties_empty",
    "contracts.show.title"
  ].freeze

  def locale_file(locale)
    File.join(LOCALES_DIR, "#{locale}.yml")
  end

  # Parsed YAML tree for a locale: { "en" => { "decidim" => { ... } } }.
  def translations(locale)
    YAML.safe_load(File.read(locale_file(locale)))
  end

  # The subtree under decidim.contracts_sk for a locale: the parsed tree is
  # { "<locale>" => { "decidim" => { "contracts_sk" => { ... } } } }.
  def module_tree(locale)
    translations(locale).fetch(locale).fetch("decidim").fetch("contracts_sk")
  end

  # Recursively collects sorted "a.b.c"-style leaf key paths of a subtree.
  def leaf_paths(subtree, prefix = [])
    subtree.each_with_object([]) do |(key, value), paths|
      path = prefix + [key]
      if value.is_a?(Hash)
        paths.concat(leaf_paths(value, path))
      else
        paths << path.join(".")
      end
    end.sort
  end

  # "locale: a.b.c" => leaf value, for every leaf of every shipped locale.
  def leaf_values
    LOCALES.each_with_object({}) do |locale, map|
      tree = module_tree(locale)
      leaf_paths(tree).each do |path|
        map["#{locale}: #{path}"] = path.split(".").reduce(tree, :fetch)
      end
    end
  end

  # Fresh backend per call - deterministic, no global I18n mutation.
  def fresh_backend
    backend = I18n::Backend::Simple.new
    backend.load_translations(*LOCALES.map { |locale| locale_file(locale) })
    backend
  end
end
# rubocop:enable Metrics/ModuleLength

# The public catalogue's own vocabulary (civora-org/civora-platform#62, #63),
# kept in its own module so that LocaleContract stays within its length
# budget and the public surface stays visually separate from the admin one.
module PublicCatalogueLabels
  # View labels per locale, keyed by their path under decidim.contracts_sk.
  VIEW_LABELS = {
    en: {
      "contract.published_on" => "Published on",
      "contracts.index.empty" => "No published contracts yet.",
      "contracts.show.parties" => "Parties",
      "contracts.show.parties_empty" => "No parties have been recorded for this contract."
    },
    sk: {
      "contract.published_on" => "Dátum zverejnenia",
      "contracts.index.empty" => "Zatiaľ nie je zverejnená žiadna zmluva.",
      "contracts.show.parties" => "Zmluvné strany",
      "contracts.show.parties_empty" => "K tejto zmluve nie sú zaznamenané žiadne zmluvné strany."
    }
  }.freeze

  # The public detail page's party role labels: they reuse the terminology
  # fixed for the admin party management (#76) — object party =
  # Objednávateľ, contractor = Dodávateľ — never a second vocabulary.
  PARTY_ROLE_LABELS = {
    en: { object: "Object party", contractor: "Contractor" },
    sk: { object: "Objednávateľ", contractor: "Dodávateľ" }
  }.freeze
end

RSpec.describe Decidim::ContractsSk do
  include LocaleContract

  describe "shipped file surface" do
    it "ships exactly the en and sk locale files" do
      expect(Dir.children(LocaleContract::LOCALES_DIR).sort).to eq(%w[en.yml sk.yml])
    end
  end

  describe "key surface (civora-org/civora-platform#39)" do
    it "declares exactly the expected decidim.contracts_sk keys in every locale" do
      LocaleContract::LOCALES.each do |locale|
        expect(leaf_paths(module_tree(locale))).to eq(LocaleContract::EXPECTED_KEYS), "locale: #{locale}"
      end
    end

    it "keeps en and sk in full key parity" do
      expect(leaf_paths(module_tree("sk"))).to eq(leaf_paths(module_tree("en")))
    end
  end

  describe "leaf values" do
    it "maps every decidim.contracts_sk leaf to a String" do
      leaf_values.each_value { |value| expect(value).to be_a(String) }
    end

    it "maps no decidim.contracts_sk leaf to a blank string" do
      leaf_values.each_value { |value| expect(value).to match(/\S/) }
    end
  end

  describe "I18n resolution (acceptance criterion 1)" do
    let(:backend) { fresh_backend }

    it "translates decidim.contracts_sk.contract.title in en" do
      expect(backend.translate(:en, LocaleContract::ACCEPTANCE_KEY)).to eq("Contract")
    end

    it "translates decidim.contracts_sk.contract.title in sk" do
      expect(backend.translate(:sk, LocaleContract::ACCEPTANCE_KEY)).to eq("Zmluva")
    end

    it "translates the public catalogue titles in both locales" do
      aggregate_failures do
        expect(backend.translate(:en, "decidim.contracts_sk.contracts.index.title")).to eq("Contracts")
        expect(backend.translate(:sk, "decidim.contracts_sk.contracts.show.title")).to eq("Detail zmluvy")
      end
    end

    it "translates the admin content-field labels in both locales (civora-org/civora-platform#75)" do
      LocaleContract::CONTENT_FIELD_LABELS.each do |locale, labels|
        labels.each do |key, value|
          expect(backend.translate(locale, "decidim.contracts_sk.admin.contracts.form.#{key}")).to eq(value)
        end
      end
    end

    it "translates the admin party role labels in both locales (civora-org/civora-platform#76)" do
      LocaleContract::PARTY_ROLE_LABELS.each do |locale, labels|
        labels.each do |role, value|
          expect(backend.translate(locale, "decidim.contracts_sk.admin.parties.roles.#{role}")).to eq(value)
        end
      end
    end

    it "translates the admin document kind labels in both locales (civora-org/civora-platform#73)" do
      LocaleContract::DOCUMENT_KIND_LABELS.each do |locale, labels|
        labels.each do |kind, value|
          expect(backend.translate(locale, "decidim.contracts_sk.admin.documents.kinds.#{kind}")).to eq(value)
        end
      end
    end

    it "keeps the public document kind vocabulary identical to the admin one (civora-org/civora-platform#73)" do
      LocaleContract::DOCUMENT_KIND_LABELS.each do |locale, labels|
        labels.each do |kind, value|
          expect(backend.translate(locale, "decidim.contracts_sk.contract.document.#{kind}")).to eq(value)
        end
      end
    end

    it "translates the public detail page's document section labels in both locales (civora-org/civora-platform#73)" do
      LocaleContract::DOCUMENT_VIEW_LABELS.each do |locale, labels|
        labels.each do |key, value|
          expect(backend.translate(locale, "decidim.contracts_sk.#{key}")).to eq(value)
        end
      end
    end

    it "translates the public catalogue view labels in both locales (civora-org/civora-platform#62, #63)" do
      PublicCatalogueLabels::VIEW_LABELS.each do |locale, labels|
        labels.each do |key, value|
          expect(backend.translate(locale, "decidim.contracts_sk.#{key}")).to eq(value)
        end
      end
    end

    it "keeps the established Slovak party terminology on the public detail page (civora-org/civora-platform#63)" do
      PublicCatalogueLabels::PARTY_ROLE_LABELS.each do |locale, labels|
        labels.each do |role, value|
          expect(backend.translate(locale, "decidim.contracts_sk.contract.party.#{role}")).to eq(value)
        end
      end
    end
  end
end
