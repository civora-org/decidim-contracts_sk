# frozen_string_literal: true

module Decidim
  module ContractsSk
    module Admin
      # "New contract from a template" and "generate again"
      # (civora-org/civora-platform#211).
      #
      # - index: the chooser of the organization's ACTIVE contract templates;
      # - new / create: the form built from the picked template, then the
      #   generation of a draft contract with its Word and PDF files;
      # - edit / update (nested under a contract): the saved values, to correct
      #   them and generate again;
      # - amount_in_words: a read-only JSON answer for the form's live preview.
      #
      # Tenancy: the template and the contract are always loaded from the
      # organization's own scope (another tenant's id is a 404), and the
      # template is handed to the form by the controller, never taken from
      # params. Permissions: a new contract needs :create, :contract;
      # regenerating needs :update, :contract on the loaded record (editor
      # role and an editable state). The command re-checks editability inside
      # the row lock.
      #
      # The pages hold personal data the person typed, so every response is
      # `Cache-Control: no-store`. No value is ever written to a log, a flash
      # or the audit trail.
      # Cop note: the new/create and edit/update pairs share one set of loaders,
      # handlers and messages; splitting them would duplicate that, not simplify.
      # rubocop:disable Metrics/ClassLength
      class TemplateEntriesController < Admin::ApplicationController
        MAX_AMOUNT_CHARS = 32

        before_action :forbid_caching

        def index
          enforce_permission_to :create, :contract

          @templates = chooser_templates
        end

        def new
          enforce_permission_to :create, :contract

          @template = active_template
          @form = TemplateEntryForm.new(template: @template, title: @template.name)
          @profile = organization_profile
        end

        def create
          enforce_permission_to :create, :contract

          @template = active_template
          @form = TemplateEntryForm.new(template: @template, title: entry_params(@template)[:title],
                                        values: entry_params(@template)[:values] || {})
          @profile = organization_profile

          generate(:new)
        end

        def edit
          load_entry
          enforce_permission_to :update, :contract, contract: @contract

          @form = TemplateEntryForm.for_entry(@entry, title: @contract.title)
          @profile = organization_profile
        rescue ActiveRecord::Encryption::Errors::Configuration
          # Reading the saved personal values needs the host's encryption keys.
          flash[:alert] = t("decidim.contracts_sk.admin.template_entries.failure.encryption_unavailable")
          redirect_to admin_contract_path(@contract)
        end

        def update
          load_entry
          enforce_permission_to :update, :contract, contract: @contract

          @template = @entry.contract_template
          @form = TemplateEntryForm.new(template: @template, title: entry_params(@template)[:title],
                                        values: entry_params(@template)[:values] || {})
          @profile = organization_profile

          generate(:edit, contract: @contract)
        end

        # The spelled-out amount for the form's live preview. Always 200: an
        # amount that does not parse answers an empty text, never an error.
        def amount_in_words
          enforce_permission_to :create, :contract

          parsed = Templates::FieldValues.parse("money", params[:amount].to_s.first(MAX_AMOUNT_CHARS))
          words = parsed.ok? && parsed.value.present? ? Templates::Words.for_amount(parsed.value) : ""
          render json: { words: words }
        end

        private

        def generate(failure_view, contract: nil)
          GenerateFromTemplate.call(@form, template: @template, user: current_user,
                                           organization: current_organization, contract: contract,
                                    &generation_handlers(failure_view))
        end

        def generation_handlers(view)
          proc do
            on(:ok) { |record| succeeded(record) }
            on(:not_editable) { not_editable }
            on(:invalid) { failed(view, :invalid) }
            on(:header_incomplete) { |keys| failed(view, :header_incomplete, keys: Array(keys)) }
            on(:redaction_failed) { failed(view, :redaction_failed) }
            on(:conversion_failed) { failed(view, :conversion_failed) }
            on(:encryption_unavailable) { failed(view, :encryption_unavailable) }
          end
        end

        def succeeded(contract)
          flash[:notice] = t("decidim.contracts_sk.admin.template_entries.generated")
          redirect_to admin_contract_path(contract)
        end

        def not_editable
          flash[:alert] = t("decidim.contracts_sk.admin.template_entries.failure.not_editable")
          redirect_to admin_contract_path(@contract)
        end

        # Re-renders the form with the reason. flash.now keeps it to this
        # render; the typed values stay in the form object.
        def failed(view, reason, keys: [])
          flash.now[:alert] = failure_message(reason, keys)
          render view, status: :unprocessable_entity
        end

        def failure_message(reason, keys)
          scope = "decidim.contracts_sk.admin.template_entries.failure"
          return t("#{scope}.#{reason}") unless reason == :header_incomplete

          names = keys.map { |key| t("decidim.contracts_sk.admin.template_entries.header.#{key}", default: key.to_s) }
          t("#{scope}.header_incomplete", fields: names.join(", "))
        end

        def chooser_templates
          ContractTemplate.where(organization: current_organization, status: "active")
                          .includes(:fields).order(version: :desc).to_a.uniq(&:lineage_key).sort_by(&:name)
        end

        def active_template
          ContractTemplate.where(organization: current_organization, status: "active")
                          .includes(:fields).find(params[:contract_template_id])
        end

        def load_entry
          @contract = Contract.where(organization: current_organization).find(params[:contract_id])
          @entry = ContractTemplateEntry.find_by!(contract: @contract)
        end

        def organization_profile
          ContractOrganizationProfile.find_by(organization: current_organization)
        end

        # Only the title and the template's own input keys are admitted; the
        # template and the tenant never come from params.
        def entry_params(template)
          @entry_params ||= begin
            keys = TemplateEntryForm.new(template: template).input_fields.map { |field| field.key.to_sym }
            # `entry=x` (not a hash) is read as no input at all: the form then
            # fails validation instead of raising.
            raw = params[:entry]
            raw = ActionController::Parameters.new unless raw.is_a?(ActionController::Parameters)
            raw.permit(:title, values: keys)
          end
        end

        def forbid_caching
          response.headers["Cache-Control"] = "no-store"
        end
      end
      # rubocop:enable Metrics/ClassLength
    end
  end
end
