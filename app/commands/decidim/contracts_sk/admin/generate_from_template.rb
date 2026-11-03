# frozen_string_literal: true

require "digest"
require "stringio"

module Decidim
  module ContractsSk
    module Admin
      # Fills a contract template from a TemplateEntryForm and stores the result
      # on a draft contract (civora-org/civora-platform#211): the entry (what was
      # typed), the internal number, and four generated documents (internal and
      # publication copy, each as Word and PDF).
      #
      #   GenerateFromTemplate.call(form, template: t, user: u, organization: o)                  # a new draft
      #   GenerateFromTemplate.call(form, template: t, user: u, organization: o, contract: c)     # regenerate / extend
      #
      # Without a contract the draft is created through CreateContract (same
      # form, same attributes, lifecycle state on the model's draft default).
      # With one, the contract must still be editable: the check runs INSIDE
      # the row lock (the TOCTOU doctrine of UpdateContract and
      # TransitionContract), on the post-lock instance, so a stale copy loaded
      # by the request can never write to a record that has left the editable
      # states. Regeneration reuses the internal number, marks the previous
      # documents superseded and clears the redaction confirmation: the
      # documents changed, so a human has to confirm them again.
      #
      # Everything (counter, contract, entry, documents, audit row) commits in
      # one transaction; any failure rolls it ALL back, including the number
      # taken from the counter. Generation itself (LibreOffice) runs inside it,
      # a second or so; redaction verification (DocumentGenerator) happens
      # before anything is written, and a RedactionFailed stores nothing.
      #
      # Broadcasts :ok(contract), or one of :invalid (form, tenancy, template no
      # longer usable), :not_editable, :header_incomplete(missing header keys),
      # :redaction_failed, :conversion_failed, :encryption_unavailable. The audit event
      # "contract.generated_from_template" carries only ids and timestamps.
      # Cop note: one command owns the whole generation transaction (counter,
      # contract, entry, documents, audit) so that it reads top to bottom and
      # commits or rolls back as one; splitting it would scatter that single
      # transaction rather than simplify it.
      # rubocop:disable Metrics/ClassLength, Metrics/MethodLength, Metrics/AbcSize, Metrics/ParameterLists
      class GenerateFromTemplate < Decidim::Command
        # Internal control flow: carries the event to broadcast after a
        # rollback.
        class Halt < StandardError
          attr_reader :event, :args

          def initialize(event, *args)
            super(event.to_s)
            @event = event
            @args = args
          end
        end

        SEQUENCE = "zmluvy"
        DEFAULT_PATTERN = "{N}/{YYYY}"
        # DocumentGenerator refuses an empty list; a key no template uses means
        # "nothing is personal", so the publication copy equals the internal one.
        NO_PERSONAL_KEY = "_none"
        CONTENT_TYPES = {
          "docx" => "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
          "pdf" => "application/pdf"
        }.freeze
        # [variant, format, DocumentGenerator result key]
        OUTPUTS = [
          %w[internal docx internal_docx], %w[internal pdf internal_pdf],
          %w[publication docx publication_docx], %w[publication pdf publication_pdf]
        ].freeze

        def initialize(form, template:, user:, organization:, contract: nil)
          super()
          @form = form
          @template = template
          @user = user
          @organization = organization
          @contract = contract
        end

        def call
          return broadcast(:invalid) unless tenancy_ok? && form.valid?

          broadcast(:ok, contract ? regenerate : create_new)
        rescue Halt => e
          broadcast(e.event, *e.args)
        rescue Templates::DocumentGenerator::RedactionFailed
          broadcast(:redaction_failed)
        rescue Templates::PdfConverter::Error
          broadcast(:conversion_failed)
        rescue ActiveRecord::Encryption::Errors::Configuration
          # The host has not set the encryption keys; nothing was stored.
          broadcast(:encryption_unavailable)
        rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotFound, ActiveRecord::RecordNotUnique,
               ActiveStorage::FileNotFoundError
          broadcast(:invalid)
        end

        private

        attr_reader :form, :template, :user, :organization, :contract

        # Fail-closed defense in depth behind the permission layer and the
        # controller's tenant-scoped lookups.
        def tenancy_ok?
          return false unless form.template == template && template.decidim_organization_id == organization.id
          return false if contract && contract.decidim_organization_id != organization.id

          !user.respond_to?(:organization) || user.organization == organization
        end

        def create_new
          ActiveRecord::Base.transaction do
            current = usable_template!
            profile = header_profile!
            number = next_number(current)
            documents = generate(current, profile, number)
            created = create_contract!(number)
            entry = create_entry!(created, current, number)
            store!(entry, current, documents)
            audit!(created)
            created
          end
        end

        def regenerate
          contract.with_lock do
            raise Halt, :not_editable unless contract.editable?

            entry = contract.template_entry
            current = entry ? pinned_template!(entry) : usable_template!
            profile = header_profile!
            number = entry&.internal_number.presence || next_number(current)
            documents = generate(current, profile, number)
            update_contract!
            entry = save_entry!(entry, current, number)
            store!(entry, current, documents)
            audit!(contract)
            contract
          end
        end

        # The template as it is NOW: active and the organization's. A stale
        # request copy of an archived template must not start new contracts.
        def usable_template!
          current = ContractTemplate.where(organization: organization, status: "active").find_by(id: template.id)
          raise Halt, :invalid unless current

          current
        end

        # An existing entry stays on the exact version it was written with
        # (archived or not), and only that one.
        def pinned_template!(entry)
          raise Halt, :invalid unless entry.contract_template_id == template.id

          entry.contract_template
        end

        def header_profile!
          profile = ContractOrganizationProfile.find_by(organization: organization)
          missing = form.missing_header_keys(profile)
          raise Halt.new(:header_incomplete, missing) if missing.any?

          profile
        end

        def generate(current, profile, number)
          raise Halt, :invalid unless current.file.attached?

          values = form.document_values(profile: profile, internal_number: number)
          Templates::DocumentGenerator.call(
            template_bytes: current.file.download, values: values,
            personal_keys: form.personal_keys.presence || [NO_PERSONAL_KEY]
          )
        end

        # {N}/{YYYY} by default; the template's own pattern may use {N} and
        # {YYYY}. Allocated from the per-organization yearly counter. A number
        # whose reference already exists in the organization (a hand-entered
        # contract, say) is skipped and the counter moves past it, so a clash
        # never blocks generation for the rest of the year. The counter row
        # stays locked until the transaction ends.
        MAX_NUMBER_SKIPS = 100

        def next_number(current)
          year = Time.zone.today.year
          scope = ReferenceCounter.scope_key_for(SEQUENCE, year)
          pattern = current.reference_pattern.presence || DEFAULT_PATTERN
          MAX_NUMBER_SKIPS.times do
            candidate = pattern.gsub("{N}", ReferenceCounter.next!(organization, scope).to_s).gsub("{YYYY}", year.to_s)
            return candidate unless Contract.exists?(organization: organization, reference: candidate)
          end
          raise Halt, :invalid
        end

        def create_contract!(number)
          created = nil
          CreateContract.call(contract_form(number), user: user, organization: organization) do
            on(:ok) { |record| created = record }
          end
          raise Halt, :invalid unless created

          created
        end

        def contract_form(number)
          ContractForm.new(title: form.title, reference: number, amount: form.amount,
                           currency: "EUR", signed_on: form.signed_on)
        end

        def update_contract!
          contract.update!(title: form.title, amount: form.amount, signed_on: form.signed_on,
                           redaction_confirmed_at: nil)
        end

        def create_entry!(created, current, number)
          ContractTemplateEntry.create!(
            contract: created, contract_template: current, created_by: user, internal_number: number,
            values: form.stored_values, personal_values: form.stored_personal_values,
            last_generated_at: Time.current
          )
        end

        def save_entry!(entry, current, number)
          return create_entry!(contract, current, number) unless entry

          entry.update!(values: form.stored_values, personal_values: form.stored_personal_values,
                        last_generated_at: Time.current)
          entry
        end

        # Marks the entry's current documents superseded and stores the new set.
        def store!(entry, current, documents)
          now = Time.current
          GeneratedDocument.where(entry: entry, status: "current").update_all(status: "superseded", updated_at: now)
          OUTPUTS.each do |variant, format, key|
            attach!(entry, current, now, variant, format, documents.fetch(key.to_sym))
          end
        end

        def attach!(entry, current, now, variant, format, bytes)
          document = GeneratedDocument.new(
            contract: entry.contract, entry: entry, variant: variant, file_format: format, generated_by: user,
            generated_at: now, template_version: current.version, checksum: Digest::SHA256.hexdigest(bytes)
          )
          document.file.attach(io: StringIO.new(bytes), filename: filename(entry, variant, format),
                               content_type: CONTENT_TYPES.fetch(format), identify: false)
          document.save!
        end

        def filename(entry, variant, format)
          slug = entry.internal_number.to_s.parameterize.presence || "zmluva"
          "zmluva-#{slug}-#{variant == "internal" ? "interna" : "zverejnenie"}.#{format}"
        end

        # Ids and timestamps only (the row's own created_at); never a value.
        def audit!(target)
          AuditEvent.create!(action: "contract.generated_from_template", target: target,
                             organization: organization, actor: user)
        end
      end
      # rubocop:enable Metrics/ClassLength, Metrics/MethodLength, Metrics/AbcSize, Metrics/ParameterLists
    end
  end
end
