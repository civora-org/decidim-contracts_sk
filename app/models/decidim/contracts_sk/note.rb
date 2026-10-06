# frozen_string_literal: true

module Decidim
  module ContractsSk
    # An internal review note on a contract (civora-org/civora-platform#128):
    # one message in the private thread role holders keep on a record (the
    # editor asks the lawyer, the reviewer explains a change request).
    #
    # Internal by design: notes are rendered only by the admin notes surface
    # and the edit page's notes panel. No public view, serializer, feed,
    # sitemap, meta tag, PDF or CRZ handoff reads them; the public specs pin
    # that absence.
    #
    # Append-only like the audit trail: once persisted, every write path
    # through the model raises ActiveRecord::ReadOnlyRecord (see
    # #readonly?). There is no edit or delete surface. The same accepted gaps
    # as AuditEvent apply (#delete, .delete_all and raw SQL bypass the
    # model); the contract's `dependent: :delete_all` relies on that on
    # purpose, so a note thread leaves with its record.
    #
    # Tenancy derives through the contract's organization (no organization
    # column — the parties/documents/links precedent). The author is stored
    # as a plain id with no FK (the contract author precedent) and may
    # dangle after the user's deletion; readers nil-guard it.
    class Note < ApplicationRecord
      # The body cap of the issue's scope ("body <= 2000 chars"); the form
      # and the model both enforce it, the text column has no DB limit.
      MAX_BODY_LENGTH = 2000

      belongs_to :contract

      belongs_to :author,
                 foreign_key: "decidim_author_id",
                 class_name: "Decidim::User"

      # Explicit presence: the host's belongs_to-required default is not an
      # engine guarantee (the DB NOT NULL columns are the last backstop).
      validates :contract, :author, presence: true
      validates :body, presence: true, length: { maximum: MAX_BODY_LENGTH }

      # Append-only enforcement: see the class comment.
      def readonly?
        persisted?
      end
    end
  end
end
