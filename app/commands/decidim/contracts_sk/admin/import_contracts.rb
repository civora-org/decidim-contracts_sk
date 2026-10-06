# frozen_string_literal: true

module Decidim
  module ContractsSk
    module Admin
      # Imports a validated spreadsheet preview as DRAFT contract records
      # (civora-org/civora-platform#129).
      #
      # Product rules: the rows are the municipality's own editorial
      # records. They land in the model's draft default, authored by the
      # importing user, with no submitter stamp, no redaction confirmation
      # and no publication stamp, so every one of them still goes through
      # the normal workflow (submit, four-eyes review, redaction
      # confirmation, publish). The import never publishes anything.
      #
      # All-or-nothing: the command refuses unless the preview is
      # importable (every row valid), and the whole batch runs in ONE
      # transaction, so a failure (a concurrent import taking a reference
      # between the preview and the write, caught by the validation or the
      # unique (organization, reference) index) rolls everything back.
      # Each created record gets one "contract.imported_from_file" audit
      # row in the same transaction. Tenancy is a fail-closed check, like
      # CreateContract's; the command takes the Preview, never raw rows, so
      # nothing unvalidated can reach the writer.
      #
      # Broadcasts :ok with the created contracts, or :invalid.
      class ImportContracts < Decidim::Command
        AUDIT_ACTION = "contract.imported_from_file"

        def initialize(preview, user:, organization:)
          super()
          @preview = preview
          @user = user
          @organization = organization
        end

        def call
          return broadcast(:invalid) unless tenancy_ok? && preview.importable?

          contracts = Contract.transaction { preview.rows.map { |row| create_row!(row) } }

          broadcast(:ok, contracts)
        rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique
          broadcast(:invalid)
        end

        private

        attr_reader :preview, :user, :organization

        def create_row!(row)
          contract = Contract.create!(contract_attributes(row.contract_form))
          row.party_forms.each do |party|
            contract.parties.create!(role: party.role, name: party.name, ico: party.ico)
          end
          AuditEvent.create!(action: AUDIT_ACTION, target: contract, organization: organization, actor: user)
          contract
        end

        # Same field set as CreateContract; state stays on the draft default.
        def contract_attributes(form)
          {
            organization: organization, author: user,
            title: form.title, reference: form.reference,
            subject_matter: form.subject_matter, amount: form.amount,
            currency: form.currency, signed_on: form.signed_on,
            effective_from: form.effective_from, crz_url: form.crz_url
          }
        end

        def tenancy_ok?
          return true unless user.respond_to?(:organization)

          user.organization == organization
        end
      end
    end
  end
end
