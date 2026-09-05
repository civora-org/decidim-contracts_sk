# frozen_string_literal: true

module Decidim
  module ContractsSk
    module Admin
      # Creates a draft amendment on a published contract record
      # (M02-05-B, civora-org/civora-platform#65).
      #
      # Amendments exist only from publication onwards (ADR-006): the
      # parent contract must be in the published state — a version history
      # makes sense only once there is a published version to supersede.
      # The contract's state is re-checked at execution time, fail-closed,
      # INSIDE the contract's row lock — the TOCTOU doctrine of
      # TransitionContract: the permission layer is checked when the
      # request is admitted, but a stale permission decision or a stale
      # in-memory copy must never write a draft onto a record that is not
      # published anymore. with_lock reloads the row first, so the check
      # reads the in-database state. The form is validated at this
      # boundary before the lock (pure, no DB access), so a rejection
      # populates the form's errors for the controller's re-render.
      #
      # The version is sequenced inside the same locked transaction: the
      # next number is the contract's current maximum + 1, read under the
      # lock so a concurrent creation cannot be double-counted, and the
      # (contract, version) unique index stays the belt-and-braces backstop
      # against a concurrent creation (its RecordNotUnique also lands on
      # :invalid).
      #
      # Tenancy and attribution are explicit but never form-writable: the
      # organization comes from the parent contract, the author is the
      # acting user. The draft carries only the summary — the content
      # snapshot is taken at publish time, from the contract's live fields.
      class CreateAmendment < Decidim::Command
        def initialize(form, contract, user:)
          super()
          @form = form
          @contract = contract
          @user = user
        end

        def call
          return broadcast(:invalid) unless form.valid?

          amendment = nil
          contract.with_lock do
            return broadcast(:invalid) unless contract.published?

            amendment = contract.amendments.create!(amendment_attributes)
          end

          broadcast(:ok, amendment)
        rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique
          broadcast(:invalid)
        end

        private

        attr_reader :form, :contract, :user

        # The version sequence is read inside the caller's locked
        # transaction (contract.with_lock) so a concurrent creation cannot
        # be double-counted; the unique index remains the hard backstop
        # (its failure lands on :invalid). Only the form's field is
        # written — the parent contract (and with it the tenancy) comes
        # from the constructor, never from the form.
        def amendment_attributes
          {
            version: contract.amendments.maximum(:version).to_i + 1,
            summary: form.summary,
            organization: contract.organization,
            author: user
          }
        end
      end
    end
  end
end
