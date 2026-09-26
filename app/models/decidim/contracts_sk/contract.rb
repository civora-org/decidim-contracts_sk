# frozen_string_literal: true

module Decidim
  module ContractsSk
    # A public contract record moving through the engine's lifecycle.
    #
    # Identity is per organization: (organization, reference) is unique.
    # The state column is validated against ContractLifecycle::STATES and
    # transitions run through ContractState, backed by ContractLifecycle —
    # the single source of truth for the lifecycle.
    #
    # The content fields (subject matter, amount, currency, signature and
    # effectivity dates, CRZ link) follow the data dictionary's "Contract
    # content" table, finalized in M02-02-D (civora-org/civora-platform#75).
    # `published_at` is a system field: TransitionContract stamps it on the
    # publish event — it is never form-writable.
    #
    # `redaction_confirmed_at` is likewise a system field (ADR-007,
    # civora-org/civora-platform#91): ConfirmRedaction stamps it when an
    # editor confirms the privacy-redaction checklist on the edit page, and
    # the publish transition refuses while it is blank. Never form-writable.
    #
    # The source/source_id/imported_at/import_status columns are
    # CRZ-mirror provenance metadata (docs/contracts-domain-notes.md);
    # checksum carries the source-payload digest and import_status is
    # validated against IMPORT_STATUSES — written by the CRZ import ETL
    # (ADR-008, docs/crz-import.md); editorial records keep them
    # untouched (source stays "editorial", import lifecycle fields nil).
    class Contract < ApplicationRecord
      include Decidim::ContractsSk::ContractState

      # Symbol => stored String mapping for the Rails enum, derived from the
      # lifecycle's single source of truth.
      STATE_VALUES = ContractLifecycle::STATES.to_h { |state| [state, state.to_s] }.freeze

      # Stored-string state vocabulary for the inclusion validator — frozen
      # so a captured validator reference cannot mutate the vocabulary.
      STATE_STRINGS = ContractLifecycle::STATES.map(&:to_s).freeze

      # Currency allowlist for the content fields (D1 of #75): EUR only for
      # V0.1 — Slovak public contracts under Act No. 211/2000 §5a report
      # values in EUR. Frozen so a captured validator reference cannot
      # mutate the vocabulary; the column default mirrors the single entry.
      SUPPORTED_CURRENCIES = %w[EUR].freeze

      # http(s)-only URL shape for the manual CRZ handoff link (the data
      # dictionary's "Odkaz na CRZ"). Anchored on purpose (\A...\z): Rails
      # `format:` matches unanchored by default, and the bare make_regexp
      # product would let an https:// smuggled inside another scheme
      # ("javascript:alert(https://evil)") or embedded in surrounding text
      # pass. The EXTENDED flag is required: make_regexp emits its source
      # already written in extended format (free-format whitespace and
      # (?# ...) comments), so it only composes correctly under that flag.
      # Blank stays legal: the handoff is a checklist item, not a hard
      # publication requirement (ADR-002).
      CRZ_URL_FORMAT = Regexp.new(
        "\\A(?:#{URI::DEFAULT_PARSER.make_regexp(%w[http https]).source})\\z",
        Regexp::EXTENDED
      ).freeze

      # Upper bound for the amount, mirroring the decimal(12,2) column: a
      # value beyond it would pass validation and blow up on PostgreSQL
      # hosts with ActiveRecord::RangeError at write time. A BigDecimal on
      # purpose — a Float literal of the same value is inexact and would
      # make the boundary comparison itself unreliable.
      MAX_AMOUNT = BigDecimal("9999999999.99").freeze

      # Approved import-status vocabulary for the manual CRZ-handoff
      # provenance column (#85): the import arc stamps it once it lands.
      # Frozen so a captured validator reference cannot mutate the
      # vocabulary; nil stays legal — editorial records carry no import
      # lifecycle.
      IMPORT_STATUSES = %w[pending succeeded failed stale].freeze

      belongs_to :organization,
                 foreign_key: "decidim_organization_id",
                 class_name: "Decidim::Organization"

      belongs_to :author,
                 foreign_key: "decidim_author_id",
                 class_name: "Decidim::User"

      # Contract-scoped child records: they follow the contract's tenancy
      # and are destroyed with it.
      has_many :parties, dependent: :destroy
      has_many :documents, dependent: :destroy
      has_many :amendments, dependent: :destroy

      # Platform-level project/result links (civora-org/civora-platform#87):
      # record content like the child records above, so they die with the
      # contract (unlike the audit trail). The association name deliberately
      # diverges from the class name, so the class_name is spelled out.
      has_many :links, class_name: "Decidim::ContractsSk::ContractLink",
                       dependent: :destroy

      # The audit trail must survive contract deletion — dangling targets
      # after the target's own destroy are the Decidim ActionLog precedent —
      # so no dependent option here.
      has_many :audit_events, as: :target

      validates :title, presence: true, length: { maximum: 255 }
      validates :reference, presence: true,
                            length: { maximum: 255 },
                            uniqueness: { scope: :decidim_organization_id }
      validates :state, presence: true,
                        inclusion: { in: STATE_STRINGS }

      # Content-field validations (#75). Amounts are non-negative and capped
      # at the decimal(12,2) column's ceiling (MAX_AMOUNT above) — the cap
      # mirrors the form's so no write path can reach a RangeError on
      # PostgreSQL. Nil stays legal (the value may be unknown while
      # drafting). The currency allowlist is the D1 constant above.
      validates :amount,
                numericality: {
                  greater_than_or_equal_to: 0,
                  less_than_or_equal_to: MAX_AMOUNT
                },
                allow_nil: true
      validates :currency, inclusion: { in: SUPPORTED_CURRENCIES }
      validates :crz_url, format: { with: CRZ_URL_FORMAT }, allow_blank: true

      # Import provenance (#85): hand-filled until the import arc lands;
      # nil stays legal (see IMPORT_STATUSES above).
      validates :import_status, inclusion: { in: IMPORT_STATUSES }, allow_nil: true

      # No signed_on/effective_from cross-validation on purpose (D2 of #75):
      # retroactive effectivity is legal — a contract may take effect before
      # its signing date — and neither the data dictionary nor ADR-002
      # imposes an ordering constraint, so inventing one would block lawful
      # records. subject_matter and the dates carry no other constraints.

      # Positional arguments: the Rails 7.2 enum API (the keyword form is
      # deprecated and removed in Rails 8). The getter returns Strings, which
      # ContractState and the permissions layer normalize via #to_sym.
      enum :state, STATE_VALUES, default: "draft"
    end
  end
end
