# frozen_string_literal: true

module Decidim
  module ContractsSk
    module Admin
      # Editor-facing form for a contract's amendments
      # (M02-05-B, civora-org/civora-platform#65).
      #
      # Deliberately narrow: only the summary is exposed. A draft amendment
      # holds nothing else content-wise — the version is sequenced by the
      # command, and the content snapshot is taken by PublishAmendment from
      # the contract's live fields at publish time (ADR-006), so there is
      # nothing else to submit. The parent contract is never form input —
      # the controller loads it from the tenant scope and the command layer
      # creates through its amendments association, so the tenancy cannot
      # be influenced by a form param (strong params in the controller
      # mirror this allow-list).
      #
      # Fields are declared through ActiveModel::Attributes so the raw
      # string params cast at the form boundary, mirroring the model's
      # column type. The validation mirrors the Amendment model's summary
      # validation exactly, so a rejection surfaces on the form before the
      # command boundary.
      class AmendmentForm
        include ActiveModel::Model
        include ActiveModel::Attributes

        attribute :summary, :string

        validates :summary, presence: true, length: { maximum: 255 }
      end
    end
  end
end
