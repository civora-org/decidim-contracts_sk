# frozen_string_literal: true

require "spec_helper"

# Offline spec for the notification vocabulary (civora-org/civora-platform#94,
# M03-05-A / #104). The event class itself cannot load in the AR-free dummy
# (Decidim::Events::SimpleEvent needs decidim-core), so everything decidable
# lives in the plain module under test and the class is host-verified (#107).
# The raw I18n template tokens (%{reason}, ...) are the subject of the locale
# examples below, not format strings.
# rubocop:disable Style/FormatStringToken
RSpec.describe Decidim::ContractsSk::TransitionNotification do
  let(:names) { described_class::NAMES.values }
  let(:text_keys) { %i[email_subject email_intro email_outro notification_title] }

  describe ".event_name" do
    it "namespaces a lifecycle event under decidim.events.contracts_sk" do
      expect(described_class.event_name(:submit)).to eq("decidim.events.contracts_sk.contract_submitted")
    end

    it "accepts String input" do
      expect(described_class.event_name("submit")).to eq("decidim.events.contracts_sk.contract_submitted")
    end

    it "maps every notified lifecycle event" do
      expect(described_class::NAMES.keys.map { |e| described_class.event_name(e).split(".").last })
        .to eq(%w[contract_submitted contract_returned contract_approved contract_rejected contract_published])
    end

    it "returns nil for archive, which is deliberately not notified" do
      expect(described_class.event_name(:archive)).to be_nil
    end

    it "returns nil for unknown events and nil" do
      expect([described_class.event_name(:bogus), described_class.event_name(nil)]).to eq([nil, nil])
    end
  end

  describe ".i18n_scope" do
    it "moves the scope under decidim.contracts_sk.events" do
      expect(described_class.i18n_scope("decidim.events.contracts_sk.contract_returned"))
        .to eq("decidim.contracts_sk.events.contract_returned")
    end

    it "round-trips every event_name" do
      scopes = described_class::NAMES.keys.map { |e| described_class.i18n_scope(described_class.event_name(e)) }
      expect(scopes).to eq(names.map { |n| "decidim.contracts_sk.events.#{n}" })
    end
  end

  describe "REASON_EVENTS" do
    it "is exactly return and reject" do
      expect(described_class::REASON_EVENTS).to eq(%i[return reject])
    end
  end

  describe "locale texts" do
    it "exists for every name, key and locale" do
      missing = names.product(text_keys, %i[en sk]).reject do |name, key, locale|
        I18n.exists?("decidim.contracts_sk.events.#{name}.#{key}", locale)
      end
      expect(missing).to eq([])
    end

    %i[en sk].each do |locale|
      it "uses %{reason} in the notification_title of returned and rejected only (#{locale})" do
        with_reason = names.select do |name|
          I18n.t("decidim.contracts_sk.events.#{name}.notification_title", locale: locale).include?("%{reason}")
        end
        expect(with_reason.sort).to eq(%w[contract_rejected contract_returned])
      end
    end

    it "keeps %{reason} out of every text of the events that carry no reason" do
      reasonless = names - %w[contract_returned contract_rejected]
      leaking = reasonless.product(text_keys, %i[en sk]).select do |name, key, locale|
        I18n.t("decidim.contracts_sk.events.#{name}.#{key}", locale: locale).include?("%{reason}")
      end
      expect(leaking).to eq([])
    end

    # Privacy rule of #94: only title, reference, link and the reviewer's
    # reason; never amounts, parties or document names.
    it "interpolates only the allowed placeholders" do
      allowed = %w[resource_title reference resource_path resource_url reason]
      used = names.product(text_keys, %i[en sk]).flat_map do |name, key, locale|
        I18n.t("decidim.contracts_sk.events.#{name}.#{key}", locale: locale).scan(/%\{(\w+)\}/).flatten
      end
      expect(used.uniq - allowed).to eq([])
    end
  end
end
# rubocop:enable Style/FormatStringToken
