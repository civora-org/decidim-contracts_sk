# frozen_string_literal: true

module Decidim
  module ContractsSk
    module Admin
      # Editor-facing form for a contract's project/result links
      # (civora-org/civora-platform#87).
      #
      # Deliberately narrow: only the polymorphic target's type and id are
      # exposed, as plain form fields (no JS picker). The parent contract is
      # never form input — the controller loads it from the tenant scope and
      # the command layer creates through its links association, so the
      # tenancy cannot be influenced by a form param.
      #
      # The target type must come from the config-time whitelist
      # (Decidim::ContractsSk.supported_link_target_types — read through the
      # callable form at validation time, never captured, so a config-time
      # whitelist change is honored without redeploying the validator and a
      # mutable host assignment can never corrupt the vocabulary). The
      # target id must be an all-digits string within the bigint range —
      # the form keeps it a String and rejects non-numeric input at the
      # boundary, so the command's write can never trip an adapter cast
      # error.
      #
      # There is deliberately no target-existence check: the polymorphic
      # target carries no FK (the AuditEvent precedent), a dangling link is
      # a legal state (the admin surface flags it for cleanup), and probing
      # arbitrary host classes at form-validation time would couple the
      # form to the host's object graph.
      class LinkForm
        include ActiveModel::Model
        include ActiveModel::Attributes

        attribute :target_type, :string
        attribute :target_id, :string

        # A digit string of at most 18 digits always fits the bigint
        # target_id column (int64 tops out at 19 digits), so a validated
        # write can never raise ActiveRecord::RangeError on PostgreSQL.
        MAX_TARGET_ID_LENGTH = 18

        validates :target_type, presence: true,
                                inclusion: {
                                  in: ->(_) { Decidim::ContractsSk.supported_link_target_types }
                                }
        validates :target_id, presence: true,
                              length: { maximum: MAX_TARGET_ID_LENGTH },
                              format: { with: /\A\d+\z/ }
      end
    end
  end
end
