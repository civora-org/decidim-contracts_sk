# frozen_string_literal: true

module Decidim
  module ContractsSk
    # A numbered version of a contract record: (contract, version) is unique
    # and version is a positive integer.
    #
    # ADR-006 (M02-05-B, civora-org/civora-platform#65, Option A): an
    # amendment is an immutable content-snapshot row on the SAME contract —
    # the contract's live fields stay the current version, and publishing an
    # amendment freezes the contract's content fields as they were at
    # publish time into content_snapshot, so the public catalogue can
    # present "current vs historical" side by side without ever overwriting
    # history.
    #
    # Lifecycle: state is draft -> published only. Draft amendments may be
    # updated and destroyed through the admin commands; published ones are
    # immutable forever. Immutability is enforced at the model layer by
    # #readonly? (mirroring AuditEvent's append-only idiom) with the
    # COMMAND layer as the primary guard (fail-closed state re-checks
    # before any write). The readonly? check deliberately reads the
    # PERSISTED in-database state, not the (possibly dirty) attribute:
    # the publish write itself must be able to flip a draft row to
    # published.
    #
    # Accepted gaps (the AuditEvent precedent): #delete, .delete_all/
    # .update_all and raw SQL bypass the model surface, and a hand-crafted
    # create with state "published" is not blocked either (a new record is
    # never readonly). Every engine write path flows through the admin
    # commands, which never do either.
    #
    # Tenancy and attribution are explicit (decidim_organization_id /
    # decidim_author_id, mirroring the contracts table) so they survive
    # independent of lookup context; the columns are nullable in the schema
    # (a NOT NULL add_column cannot serve pre-migration rows without
    # fabricating FK values) but required at the model layer through
    # belongs_to. Like Party, everyday scoping is derived through the
    # contract's organization.
    class Amendment < ApplicationRecord
      belongs_to :contract

      # Explicit optional: false on purpose: the presence requirement must
      # not depend on the host app's belongs_to_required_by_default setting
      # — the explicit tenancy/attribution columns are the amendment's
      # provenance contract (see the class comment).
      belongs_to :organization,
                 foreign_key: "decidim_organization_id",
                 class_name: "Decidim::Organization",
                 optional: false

      belongs_to :author,
                 foreign_key: "decidim_author_id",
                 class_name: "Decidim::User",
                 optional: false

      # Stored-string state vocabulary for the inclusion validator — frozen
      # so a captured validator reference cannot mutate the vocabulary.
      STATES = %w[draft published].freeze

      # Symbol => stored String mapping for the Rails enum, mirroring
      # Contract's STATE_VALUES style.
      STATE_VALUES = STATES.to_h { |state| [state, state] }.freeze

      # The contract content fields frozen into content_snapshot at publish
      # time (civora-org/civora-platform#65): the data-dictionary content
      # set from the add_content_fields migration (#75), minus published_at
      # (a system stamp, not content). Frozen so a captured reference
      # cannot mutate the snapshot vocabulary.
      SNAPSHOT_FIELDS = %w[subject_matter amount currency signed_on effective_from crz_url].freeze

      validates :version, presence: true,
                          numericality: { only_integer: true, greater_than: 0 },
                          uniqueness: { scope: :contract_id }
      validates :summary, presence: true, length: { maximum: 255 }
      validates :state, presence: true,
                        inclusion: { in: STATES }

      # Positional arguments: the Rails 7.2 enum API (the keyword form is
      # deprecated and removed in Rails 8). Column and enum agree on the
      # "draft" default.
      enum :state, STATE_VALUES, default: "draft"

      # The public version history reads published amendments only; drafts
      # are never publicly visible (ADR-006).
      scope :published, -> { where(state: "published") }

      # Published amendments are immutable: every model write path checks
      # #readonly? (see ActiveRecord::Persistence), so once the in-database
      # state is "published", update/update!/touch/destroy all raise
      # ActiveRecord::ReadOnlyRecord. Reads the PERSISTED state (not the
      # dirty attribute) on purpose: the publish command's own write must
      # pass this check while the row is still a draft in the database.
      def readonly?
        persisted? && state_in_database == "published"
      end
    end
  end
end
