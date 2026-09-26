# frozen_string_literal: true

module Decidim
  module ContractsSk
    module Admin
      # Adds a project/result link to a contract record (M01-87,
      # civora-org/civora-platform#87).
      #
      # Tenancy is derived through the parent contract — the link is saved
      # through the contract's links association, so it can never attach to
      # a record outside the acting organization's tenant scope. The
      # controller's tenant-scoped lookup is the permission boundary; this
      # is defense-in-depth, not a permission decision of its own.
      #
      # Editability is re-checked at execution time, fail-closed, INSIDE the
      # contract's row lock — the TOCTOU doctrine of TransitionContract (the
      # repo-wide lock discipline since #69, proven again in #65): the
      # permission layer is checked when the request is admitted, but a
      # stale permission decision or a stale in-memory copy can never write
      # into a record that has left the editable states in the meantime.
      # The lock is the parent contract's row — the same row the lifecycle
      # commands lock, so a concurrent state change serializes against this
      # write — and with_lock reloads it first, so the guard reads the
      # in-database state. The form is validated before the lock (pure, no
      # DB access), so a rejection populates the form's errors for the
      # controller.
      class CreateLink < Decidim::Command
        def initialize(form, contract)
          super()
          @form = form
          @contract = contract
        end

        def call
          return broadcast(:invalid) unless form.valid?

          link = nil
          contract.with_lock do
            return broadcast(:invalid) unless contract.editable?

            link = contract.links.create!(link_attributes)
          end

          broadcast(:ok, link)
        rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique
          # RecordNotUnique is the DB backstop (the unique composite index)
          # firing in a concurrent race the model validation's read missed;
          # it degrades to the same :invalid outcome, never a 500.
          broadcast(:invalid)
        end

        private

        attr_reader :form, :contract

        # Only the form's fields are written — the parent contract (and with
        # it the tenancy) comes from the constructor, never from the form.
        # The digits-only target id casts losslessly to the bigint column.
        def link_attributes
          {
            target_type: form.target_type,
            target_id: form.target_id
          }
        end
      end
    end
  end
end
