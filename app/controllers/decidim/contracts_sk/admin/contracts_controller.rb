# frozen_string_literal: true

module Decidim
  module ContractsSk
    module Admin
      # Admin CRUD and lifecycle transitions for contract records
      # (civora-org/civora-platform#58, #59).
      #
      # index/new/create open with enforce_permission_to before anything
      # else; edit/update and the transition actions load the record first,
      # so the permission check can see the record's lifecycle state. Denial
      # is handled by the inherited Decidim::NeedsPermission machinery
      # (redirect + alert). The lifecycle state is never written through the
      # form: creation lands on the model's draft default, updates go through
      # UpdateContract, and transitions go through TransitionContract — one
      # explicit action per transition event, each a thin shell over the
      # private #transition (civora-org/civora-platform#59).
      #
      # Cop note: the class stays deliberately cohesive — the six transition
      # shells exist so the derived routes map onto readable actions, and
      # splitting them off would obscure the one-transition-per-action rule
      # rather than simplify it.
      # rubocop:disable Metrics/ClassLength
      class ContractsController < Admin::ApplicationController
        # Exposes the per-record allowed events to the index view; derived
        # from the lifecycle table and the user's engine roles, never
        # hand-enumerated.
        helper_method :transition_events_for

        def index
          enforce_permission_to :read, :contract

          @contracts = contracts_scope
        end

        def new
          enforce_permission_to :create, :contract

          @form = ContractForm.new
        end

        def create
          enforce_permission_to :create, :contract

          @form = ContractForm.new(form_params)

          CreateContract.call(@form, user: current_user, organization: current_organization) do
            on(:ok) { create_succeeded }
            on(:invalid) { create_failed }
          end
        end

        def edit
          @contract = contracts_scope.find(params[:id])

          enforce_permission_to :update, :contract, contract: @contract

          @form = ContractForm.new(title: @contract.title,
                                   reference: @contract.reference,
                                   subject_matter: @contract.subject_matter,
                                   amount: @contract.amount,
                                   currency: @contract.currency,
                                   signed_on: @contract.signed_on,
                                   effective_from: @contract.effective_from,
                                   crz_url: @contract.crz_url)
        end

        def update
          @contract = contracts_scope.find(params[:id])

          enforce_permission_to :update, :contract, contract: @contract

          @form = ContractForm.new(form_params)

          UpdateContract.call(@form, @contract) do
            on(:ok) { update_succeeded }
            on(:invalid) { update_failed }
          end
        end

        # One explicit action per lifecycle transition event. The route set
        # is derived from ContractLifecycle::TRANSITIONS in config/routes.rb;
        # these named shells exist so the derived routes map onto readable
        # controller actions.
        def submit
          transition(:submit)
        end

        def return
          transition(:return)
        end

        def approve
          transition(:approve)
        end

        def reject
          transition(:reject)
        end

        def publish
          transition(:publish)
        end

        def archive
          transition(:archive)
        end

        private

        # PRG on success: notice + back to the admin index.
        def create_succeeded
          flash[:notice] = t("decidim.contracts_sk.admin.contracts.create.success")
          redirect_to admin_contracts_path
        end

        def update_succeeded
          flash[:notice] = t("decidim.contracts_sk.admin.contracts.update.success")
          redirect_to admin_contracts_path
        end

        # Failure re-renders the form with the command layer's error message
        # (flash.now so it survives only this render).
        def create_failed
          flash.now[:alert] = t("decidim.contracts_sk.admin.contracts.create.error")
          render :new, status: :unprocessable_entity
        end

        def update_failed
          flash.now[:alert] = t("decidim.contracts_sk.admin.contracts.update.error")
          render :edit, status: :unprocessable_entity
        end

        # Shared transition pipeline: load the record from the tenant scope,
        # ask the permission layer (event-specific: the lifecycle edge's role
        # set decides), then run the command. Both outcomes are PRG redirects
        # — a failure never re-renders, because the record's state may have
        # changed under us; the index shows the truth.
        def transition(event)
          @contract = contracts_scope.find(params[:id])

          enforce_permission_to event, :contract, contract: @contract

          TransitionContract.call(@contract, event: event, user: current_user) do
            on(:ok) { transition_succeeded }
            on(:invalid) { transition_failed }
          end
        end

        def transition_succeeded
          flash[:notice] = t("decidim.contracts_sk.admin.contracts.transition.success")
          redirect_to admin_contracts_path
        end

        def transition_failed
          flash[:alert] = t("decidim.contracts_sk.admin.contracts.transition.invalid")
          redirect_to admin_contracts_path
        end

        # Events the acting user may trigger on this record right now: the
        # lifecycle's events from the record's state, filtered by the edges
        # whose roles intersect the user's engine roles. Uses the same
        # config-time resolution seam as the Permissions class. Empty for a
        # roleless user — no derivation hand-enumerated anywhere.
        def transition_events_for(contract)
          state = contract.state&.to_sym
          roles = Array(Decidim::ContractsSk.role_resolver.call(current_user, {})) & ContractLifecycle::ROLES

          ContractLifecycle.events_from(state).select do |event|
            (ContractLifecycle.allowed_roles(from: state, event: event) & roles).any?
          end
        end

        # Tenant-scoped record access: a contract of another organization is
        # invisible here (find raises RecordNotFound → 404), not merely
        # permission-denied.
        def contracts_scope
          Contract.where(organization: current_organization)
        end

        # Only the editorial identity and content fields are updatable
        # through the form (content fields per civora-org/civora-platform#75).
        # state, provenance, organization, author and the system-stamped
        # published_at are deliberately absent: adding them here would
        # bypass the command layer's ownership rules.
        def form_params
          params.require(:contract).permit(:title, :reference, :subject_matter, :amount,
                                           :currency, :signed_on, :effective_from, :crz_url)
        end
      end
      # rubocop:enable Metrics/ClassLength
    end
  end
end
