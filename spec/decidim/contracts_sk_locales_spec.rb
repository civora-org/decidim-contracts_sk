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
# lint-clean, mirroring the engine_routing_spec pattern.
module LocaleContract
  # Repo-root-relative locale dir: this spec lives at spec/decidim/, so two
  # levels up is the engine root (config/locales sits beneath it).
  LOCALES_DIR = File.expand_path("../../config/locales", __dir__)
  LOCALES = %w[en sk].freeze

  # The acceptance-criterion key of civora-org/civora-platform#39.
  ACCEPTANCE_KEY = "decidim.contracts_sk.contract.title"

  # The exact expected leaf-key surface under decidim.contracts_sk, including
  # the public catalogue keys (plan Option B of #39) and the admin CRUD keys
  # (civora-org/civora-platform#58). Sorted alphabetically.
  EXPECTED_KEYS = [
    "admin.contracts.create.error",
    "admin.contracts.create.success",
    "admin.contracts.edit.title",
    "admin.contracts.form.reference",
    "admin.contracts.form.title",
    "admin.contracts.index.title",
    "admin.contracts.new.title",
    "admin.contracts.transition.invalid",
    "admin.contracts.transition.success",
    "admin.contracts.update.error",
    "admin.contracts.update.success",
    "contract.amount",
    "contract.reference_number",
    "contract.status",
    "contract.title",
    "contracts.index.title",
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
  end
end
