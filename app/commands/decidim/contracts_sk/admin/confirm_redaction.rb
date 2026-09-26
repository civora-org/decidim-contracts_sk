# frozen_string_literal: true

module Decidim
  module ContractsSk
    module Admin
      # Stamps the ADR-007 privacy-redaction confirmation on a contract
      # record (civora-org/civora-platform#91): the editor's affirmation,
      # made on the contract's edit page after checking the redaction
      # checklist, that personal data was removed from the record and its
      # attached documents. The stamp (`redaction_confirmed_at`) is the hard
      # precondition of the publish transition (TransitionContract refuses
      # the publish edge without it) — the confirmation gate itself, not the
      # redaction, is this command's job.
      #
      # Confirmability is re-checked at execution time, fail-closed, INSIDE
      # the contract's row lock — the TOCTOU doctrine of TransitionContract
      # (the #69 doctrine): the permission layer is checked when the request
      # is admitted, but a stale permission decision or a stale in-memory
      # copy can never stamp a record that has left the confirmable states
      # in the meantime. The confirmable window is
      # ContractLifecycle::CONFIRMABLE_STATES (editable states + :approved
      # — the #91 review round widened ONLY this window, never
      # `editable?` itself), and with_lock reloads the row first, so the
      # guard reads the in-database state, never the request-start copy.
      #
      # The stamp and its audit row commit atomically: both happen inside
      # the same with_lock transaction, so a failure at either step rolls
      # the other back — a confirmation either fully happened (with its
      # audit row) or did not happen at all. The audit payload shape follows
      # the TransitionContract pattern (#57/#59): action
      # "contract.redaction_confirmed", polymorphic target = the contract,
      # explicit organization/actor, timestamps only. The stamp is a system
      # field — never form-writable — and is never cleared by this command.
      #
      # Idempotency decision (#91 Gate-1): a record that already carries the
      # stamp refuses (:invalid). The UI hides the control once the stamp is
      # present, so a repeat POST is a stale page or a hand-crafted request;
      # re-stamping would silently move the confirmation date without a
      # fresh editorial affirmation behind it.
      class ConfirmRedaction < Decidim::Command
        def initialize(contract, user:)
          super()
          @contract = contract
          @user = user
        end

        def call
          contract.with_lock do
            return broadcast(:invalid) unless contract.confirmable? && contract.redaction_confirmed_at.blank?

            contract.update!(redaction_confirmed_at: Time.current)
            record_audit!
          end

          broadcast(:ok, contract)
        rescue ActiveRecord::RecordInvalid
          broadcast(:invalid)
        end

        private

        attr_reader :contract, :user

        # The audit row is written inside the caller's locked transaction,
        # so its failure rolls the stamp back with it.
        def record_audit!
          AuditEvent.create!(action: "contract.redaction_confirmed", target: contract,
                             organization: contract.organization, actor: user)
        end
      end
    end
  end
end
