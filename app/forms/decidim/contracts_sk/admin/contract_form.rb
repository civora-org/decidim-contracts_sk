# frozen_string_literal: true

module Decidim
  module ContractsSk
    module Admin
      # Editor-facing form for creating and updating contract records
      # (civora-org/civora-platform#58; content fields per #75).
      #
      # Deliberately narrow: only the editorial identity fields (title,
      # reference) and the contract content fields (subject matter, amount,
      # currency, signature/effectivity dates, CRZ link) are exposed. The
      # lifecycle state, provenance metadata, organization, author and the
      # publication timestamp are set by the command layer / persistence —
      # a form param can never influence them (strong params in the
      # controller mirror this allow-list). `published_at` in particular is
      # a system field stamped by TransitionContract on the publish event
      # and has no accessor here at all.
      #
      # Fields are declared through ActiveModel::Attributes so the raw
      # string params cast at the form boundary, mirroring the model's
      # column types: `amount` arrives as BigDecimal, the dates as Date.
      # Currency defaults to "EUR" (the D1 allowlist's only entry) when the
      # form is built without one.
      #
      # The amount carries two guards the model cannot provide on its own:
      # a strict format check on raw String input (the :decimal cast never
      # fails a String — it delegates to String#to_d, which silently zeroes
      # garbage; see the validator comment below) and the decimal(12,2)
      # range cap, so an oversized value dies as a validation error here
      # instead of as an ActiveRecord::RangeError (500) on PostgreSQL hosts
      # at write time.
      class ContractForm
        include ActiveModel::Model
        include ActiveModel::Attributes

        # Dot-decimal amount strings only (review round of #75). The leading
        # minus is legal SYNTAX here — the sign policy (non-negative) stays
        # owned by the numericality validator. Deliberately rejected: comma
        # decimals ("12,50" — the Slovak decimal-comma habit is caught at
        # the boundary so the stored value can never silently differ from
        # what the editor meant), scientific notation ("1e5"), surrounding
        # whitespace and a leading plus — the editorial form keeps one
        # unambiguous input shape.
        STRICT_AMOUNT_FORMAT = /\A-?\d+(\.\d+)?\z/

        attribute :title, :string
        attribute :reference, :string
        attribute :subject_matter, :string
        attribute :amount, :decimal
        attribute :currency, :string, default: "EUR"
        attribute :signed_on, :date
        attribute :effective_from, :date
        attribute :crz_url, :string

        # Raw amount capture, BEFORE the :decimal cast (ActiveModel::Attributes
        # exposes no *_before_type_cast reader, so the form keeps its own). The
        # strict format guard below reads it at validation time; numeric inputs
        # (specs, API callers) skip that guard, staying cast-compatible.
        def amount=(value)
          @raw_amount = value
          super
        end

        validates :title, presence: true, length: { maximum: 255 }
        validates :reference, presence: true, length: { maximum: 255 }

        # Mirrors the model's content-field validations so a rejection
        # surfaces on the form before the command boundary (#75): non-
        # negative amounts capped at the decimal(12,2) ceiling (MAX_AMOUNT,
        # a BigDecimal — a Float literal of the same value is inexact and
        # would make the boundary itself unreliable), the EUR-only currency
        # allowlist and http(s)-only CRZ links. The dates carry no cross-
        # constraint — retroactive effectivity is legal (D2).
        validates :amount,
                  numericality: {
                    greater_than_or_equal_to: 0,
                    less_than_or_equal_to: Decidim::ContractsSk::Contract::MAX_AMOUNT
                  },
                  allow_nil: true
        validates :currency,
                  inclusion: { in: Decidim::ContractsSk::Contract::SUPPORTED_CURRENCIES }
        validates :crz_url,
                  format: { with: Decidim::ContractsSk::Contract::CRZ_URL_FORMAT },
                  allow_blank: true

        # Strict amount format for raw STRING input (#75 review round). The
        # ActiveModel :decimal cast never fails on a String — String#to_d
        # returns 0 for garbage ("abc".to_d == 0, no exception) — so a
        # non-numeric amount would reach the numericality validator as a
        # legitimate-looking 0 and persist silently as 0.00. The guard
        # inspects the pre-cast raw value and rejects Strings outside
        # STRICT_AMOUNT_FORMAT; numeric inputs never enter this path.
        validate :strict_amount_format

        private

        def strict_amount_format
          raw = @raw_amount
          return unless raw.is_a?(String) && raw.present?
          return if raw.match?(STRICT_AMOUNT_FORMAT)

          errors.add(:amount, :not_a_number)
        end
      end
    end
  end
end
