# frozen_string_literal: true

module Decidim
  module ContractsSk
    # An append-only audit record of something that happened to a target
    # (today: contracts). Written by the admin lifecycle transitions
    # (M02-03-B, civora-org/civora-platform#59): exactly one row per
    # successful transition, atomically with the state change, action
    # "contract.<event>".
    #
    # Tenancy and the actor are stored explicitly (decidim_organization_id /
    # decidim_user_id), not derived through the target: the polymorphic
    # target deliberately carries no FK and may dangle after its record is
    # deleted — the Decidim ActionLog precedent — while the trail itself
    # must remain attributable to its organization and author.
    class AuditEvent < ApplicationRecord
      belongs_to :organization,
                 foreign_key: "decidim_organization_id",
                 class_name: "Decidim::Organization"

      belongs_to :actor,
                 foreign_key: "decidim_user_id",
                 class_name: "Decidim::User"

      belongs_to :target, polymorphic: true

      validates :action, presence: true, length: { maximum: 255 }

      # Append-only enforcement: once persisted, every write path that goes
      # through the model raises ActiveRecord::ReadOnlyRecord — save, update,
      # update!, touch, update_columns and destroy all check #readonly?
      # (see ActiveRecord::Persistence). Accepted gaps: #delete,
      # .delete_all/.update_all and raw SQL bypass the model surface (DB
      # triggers were rejected — they break migration reversibility and the
      # SQLite :db spec harness). A dangling target after the target's own
      # destroy is by design, matching the Decidim ActionLog precedent.
      def readonly?
        persisted?
      end
    end
  end
end
