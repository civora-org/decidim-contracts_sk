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
    # `review_reason`/`reviewed_at` are likewise system fields (#90): only
    # TransitionContract writes them — the reviewer's return/reject judgment
    # and its stamp, atomic with the state — and the resubmit edge clears
    # both. Never form-writable.
    #
    # `decidim_submitted_by_id` is likewise a system field (four-eyes rule,
    # civora-org/civora-platform#123): TransitionContract stamps the acting
    # user on every submit, the rule forbids that person to return, approve
    # or reject the record, and no form or the CRZ upsert ever writes it.
    # The column has no index and was introduced as read per record; since
    # the admin dashboard (civora-org/civora-platform#126) it IS also queried
    # as a set — the submitter scopes below back the review queue, the
    # returned-to-me list and the index submitter filter — always on the
    # small, tenant-scoped, state-narrowed relation, so the original
    # no-index decision stands.
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

      # The person who last submitted the record for review (four-eyes
      # rule, civora-org/civora-platform#123). Optional: legacy and
      # never-submitted records carry nil, which the rule treats as "not
      # blocked". Mirrors the author association, deliberately without a
      # database FK (see the migration).
      belongs_to :submitted_by,
                 foreign_key: "decidim_submitted_by_id",
                 class_name: "Decidim::User",
                 optional: true

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

      # Submitter scopes (civora-org/civora-platform#126), shared by the admin
      # dashboard and the contracts index submitter filter so both always
      # agree. The stamp is nullable (legacy/never-submitted records), so the
      # negative form is spelled out as "NULL OR <> id" — a bare where.not
      # would silently drop the NULL rows (SQL three-valued logic).
      # A nil user matches nothing (never the NULL stamps: "me" is nobody).
      scope :submitted_by_user, lambda { |user|
        user ? where(decidim_submitted_by_id: user.id) : none
      }
      scope :not_submitted_by_user, lambda { |user|
        where(decidim_submitted_by_id: nil).or(where.not(decidim_submitted_by_id: user&.id))
      }

      # The reviewer's queue: in_review records the user may judge. The set
      # twin of Decidim::ContractsSk.self_review_blocked?(contract, user,
      # :approve) (the four-eyes rule, #123): a record is in the queue
      # exactly when that predicate is false. With the allow_self_review
      # seam on the submitter clause drops, as the predicate then never
      # blocks. Note the predicate reads the CONFIG seam; +allow_self+
      # defaults to it and is a keyword only so specs can pin both modes.
      scope :awaiting_review_by, lambda { |user, allow_self: Decidim::ContractsSk.allow_self_review|
        queue = in_review
        allow_self ? queue : queue.merge(not_submitted_by_user(user))
      }

      # Records the user submitted that a reviewer sent back: the submitter's
      # "returned to me" list (the resubmit edge is theirs).
      scope :returned_to, ->(user) { returned.merge(submitted_by_user(user)) }

      # CRZ publication deadline tracking (§ 47a OZ, civora-org/civora-platform
      # #124). The deadline is computed from signed_on and the config seam
      # Decidim::ContractsSk.crz_deadline — never stored — and the arithmetic
      # lives in CrzDeadline; the scopes below only compare signed_on against
      # dates that module computes (SQL date arithmetic is not portable), so
      # the instance helpers and the scopes agree by construction.
      #
      # Tracked = an editorial record (source != the CRZ mirror's), in a
      # DEADLINE_TRACKED_STATES state, with crz_filed_at NULL — "not
      # confirmed as filed in CRZ" (the verified filing confirmation of
      # civora-org/civora-platform#125 replaced the #124 crz_url proxy;
      # a typed crz_url alone no longer counts). Records with an
      # unknown signed_on ARE tracked here (the edit page and the row badge
      # flag them) but belong to neither the overdue nor the due-soon scope.
      scope :crz_deadline_tracked, lambda {
        where.not(source: CrzImport::Mapper::SOURCE)
             .where(state: ContractLifecycle::DEADLINE_TRACKED_STATES.map(&:to_s))
             .where(crz_filed_at: nil)
      }

      # Tracked records whose deadline lies before +today+:
      # deadline < today <=> signed_on < threshold(today).
      scope :crz_overdue, lambda { |today = Date.current|
        crz_deadline_tracked.where(signed_on: ...CrzDeadline.threshold(today))
      }

      # Tracked records with 0..DUE_SOON_DAYS days left (inclusive):
      # deadline in [today, today + 14] <=> signed_on in
      # [threshold(today), threshold(today + 15)).
      scope :crz_due_soon, lambda { |today = Date.current|
        crz_deadline_tracked.where(
          signed_on: CrzDeadline.threshold(today)...CrzDeadline.threshold(today + (CrzDeadline::DUE_SOON_DAYS + 1))
        )
      }

      # The record's computed CRZ deadline; nil when signed_on is unknown.
      def crz_deadline
        CrzDeadline.deadline_for(signed_on)
      end

      # Whole days until the deadline (0 = today, negative = overdue); nil
      # when signed_on is unknown.
      def crz_days_left(today: Date.current)
        CrzDeadline.days_left(signed_on, today: today)
      end

      # Whether this record is subject to deadline tracking (the instance
      # twin of the crz_deadline_tracked scope).
      def crz_deadline_tracked?
        CrzDeadline.tracked?(source: source, state: state, crz_filed_at: crz_filed_at)
      end

      # :untracked (filed, mirror or terminal), :unknown (tracked, no
      # signing date), :overdue, :due_soon or :ok — consistent with scope
      # membership: :overdue/:due_soon exactly when the record is in the
      # crz_overdue/crz_due_soon scope for the same +today+.
      def crz_deadline_status(today: Date.current)
        return :untracked unless crz_deadline_tracked?

        CrzDeadline.status(signed_on, today: today)
      end
    end
  end
end
