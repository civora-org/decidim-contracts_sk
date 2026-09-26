# frozen_string_literal: true

module Decidim
  module ContractsSk
    module Admin
      # Admin CRUD and lifecycle transitions for contract records
      # (civora-org/civora-platform#58, #59), the manual CRZ-handoff
      # download/generate pair (M02-05-C, civora-org/civora-platform#74)
      # and the single-record CRZ import (ADR-008,
      # civora-org/civora-platform#86).
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
      # The index additionally paginates (CONTRACTS_PER_PAGE, Kaminari —
      # shipped with decidim-core) over a filtered scope: state, source and
      # free-text q are GET params validated against the real vocabularies,
      # and an unknown value falls back to the default instead of erroring.
      #
      # Cop note: the class stays deliberately cohesive — the six transition
      # shells exist so the derived routes map onto readable actions, and
      # splitting them off would obscure the one-transition-per-action rule
      # rather than simplify it.
      # rubocop:disable Metrics/ClassLength
      class ContractsController < Admin::ApplicationController
        # Exposes the per-record allowed events to the index view; derived
        # from the lifecycle table and the user's engine roles, never
        # hand-enumerated. The index filter option lists and the normalized
        # filter state back the filter form the same way.
        helper_method :transition_events_for, :index_filters,
                      :index_state_options, :index_source_options

        # Case-insensitive free-text match for the index :q filter over the
        # two editorial identity fields; :pattern is always pre-escaped with
        # sanitize_sql_like, so user-supplied % and _ stay literal.
        SEARCH_CONDITION = "LOWER(title) LIKE :pattern OR LOWER(reference) LIKE :pattern"

        # Deterministic index ordering: newest records first, with the id as
        # the tiebreaker — a total order, so a page can never repeat or drop
        # a row across page boundaries on PostgreSQL (where an unordered
        # query's row order is undefined).
        INDEX_ORDER = { created_at: :desc, id: :desc }.freeze

        # Normalized index filter state (civora-org/civora-platform#86b):
        # state is a lifecycle state symbol or nil ("any state"), source is
        # :crz / :editorial or nil ("all sources"), q is the stripped search
        # term. Carries request-derived values only — never persisted.
        IndexFilters = Struct.new(:state, :source, :q, keyword_init: true)

        def index
          enforce_permission_to :read, :contract

          # The page param reaches Kaminari only as a string: an array
          # (page[]=2) would raise inside Kaminari's Integer coercion.
          @contracts = filtered_contracts.page(params[:page].to_s)
                                         .per(Decidim::ContractsSk::CONTRACTS_PER_PAGE)
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

          @form = edit_form

          load_crz_handoff_document
        end

        def update
          @contract = contracts_scope.find(params[:id])

          enforce_permission_to :update, :contract, contract: @contract

          @form = ContractForm.new(form_params)

          # The failed-update re-render needs the handoff ivar too, or the
          # section silently drops off the page until the next full visit
          # (civora-org/civora-platform#77).
          load_crz_handoff_document

          UpdateContract.call(@form, @contract) do
            on(:ok) { update_succeeded }
            on(:invalid) { update_failed }
          end
        end

        # Manual CRZ-handoff export (M02-05-C, civora-org/civora-platform#74).
        # Both verbs share the path /admin/contracts/:id/crz_handoff but the
        # gates are deliberately split: generating the handoff aid is
        # editorial work on an editable record (ADR-002), so it gates exactly
        # like :update; downloading the already-generated aid is role-gated
        # only (editor on ANY lifecycle state) through the dedicated
        # :download_crz_handoff permission action.
        def download_crz_handoff
          @contract = contracts_scope.find(params[:id])

          enforce_permission_to :download_crz_handoff, :contract, contract: @contract

          document = @contract.documents.find_by(kind: "crz_export")
          return download_missing unless document&.file&.attached?

          # Streams straight from the attached blob — no disk temp files.
          send_data document.file.download,
                    filename: document.file_name,
                    type: document.content_type,
                    disposition: :attachment
        end

        def generate_crz_handoff
          @contract = contracts_scope.find(params[:id])

          enforce_permission_to :update, :contract, contract: @contract

          GenerateCrzHandoff.call(@contract, user: current_user) do
            on(:ok) { generate_succeeded }
            on(:invalid) { generate_failed }
          end
        end

        # Single-record CRZ import (ADR-008, civora-org/civora-platform#86):
        # pulls ONE contract from ekosystem.slovensko.digital by its CRZ
        # numeric id and upserts it through the same command the scheduled
        # batch sync uses. Editor-gated (:import_crz, role-only); every
        # outcome is a PRG redirect to the index with a localized flash —
        # the ADR-008 outcome vocabulary (collision, lifecycle guard,
        # source unavailable, ...) maps 1:1 onto flash keys. Network and
        # record-locking concerns live in the CrzImport layers.
        def import_crz
          enforce_permission_to :import_crz, :contract

          source_id = params[:source_id].to_s.strip
          return import_blank_id unless source_id.match?(/\A\d+\z/)

          outcome = CrzImport::Sync.import_one(source_id: source_id,
                                               organization: current_organization,
                                               actor: current_user)

          add_import_flash(outcome, source_id)
          redirect_to admin_contracts_path
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

        # The import outcome vocabulary mirrors CrzImport outcomes 1:1;
        # the successful trio flashes :notice, everything else :alert.
        IMPORT_NOTICE_OUTCOMES = %i[created updated unchanged].freeze

        private

        def add_import_flash(outcome, source_id)
          key = "decidim.contracts_sk.admin.contracts.import_crz.#{outcome}"
          level = IMPORT_NOTICE_OUTCOMES.include?(outcome) ? :notice : :alert
          flash[level] = t(key, source_id: source_id)
        end

        # A blank or non-numeric id never reaches the network — the CRZ id
        # is numeric by definition (ADR-008 decision 1).
        def import_blank_id
          flash[:alert] = t("decidim.contracts_sk.admin.contracts.import_crz.blank_id")
          redirect_to admin_contracts_path
        end

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

        # The handoff section reads the record's single crz_export document
        # (civora-org/civora-platform#74): its presence decides between the
        # download link + regenerate button and the plain generate button.
        # Shared by :edit and :update so a failed-update re-render keeps the
        # section (civora-org/civora-platform#77).
        def load_crz_handoff_document
          @crz_handoff_document = @contract.documents.find_by(kind: "crz_export")
        end

        # The handoff is generated before it can be downloaded; a missing
        # artifact sends the admin back to the edit page with a localized
        # alert instead of a 404 (the button is hidden when absent, so this
        # only fires on stale pages or hand-crafted requests).
        def download_missing
          flash[:alert] = t("decidim.contracts_sk.admin.crz_handoff.download_missing")
          redirect_to edit_admin_contract_path(@contract)
        end

        # Both generate outcomes are PRG redirects to the edit page (the
        # handoff section's home): a failure means the record changed under
        # us, and there is no form to re-render — the edit page shows the
        # truth.
        def generate_succeeded
          flash[:notice] = t("decidim.contracts_sk.admin.crz_handoff.create.success")
          redirect_to edit_admin_contract_path(@contract)
        end

        def generate_failed
          flash[:alert] = t("decidim.contracts_sk.admin.crz_handoff.create.error")
          redirect_to edit_admin_contract_path(@contract)
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

        # The edit form is pre-filled from the persisted record (never from
        # the request) — only update carries request params.
        def edit_form
          ContractForm.new(title: @contract.title,
                           reference: @contract.reference,
                           subject_matter: @contract.subject_matter,
                           amount: @contract.amount,
                           currency: @contract.currency,
                           signed_on: @contract.signed_on,
                           effective_from: @contract.effective_from,
                           crz_url: @contract.crz_url)
        end

        # Tenant-scoped record access: a contract of another organization is
        # invisible here (find raises RecordNotFound → 404), not merely
        # permission-denied.
        def contracts_scope
          Contract.where(organization: current_organization)
        end

        # The index read surface: the tenant scope under its deterministic
        # order (INDEX_ORDER), with the normalized GET filters applied on top
        # (never around it, so organization scoping survives every filter
        # combination), then paginated by the caller. Each filter is
        # conditional — an absent or unknown value contributes no WHERE
        # clause, so a hand-crafted param degrades to the default view,
        # never to a 500.
        def filtered_contracts
          scope = contracts_scope.order(INDEX_ORDER)
          apply_q_filter(apply_source_filter(apply_state_filter(scope)))
        end

        def apply_state_filter(scope)
          index_filters.state ? scope.where(state: index_filters.state) : scope
        end

        def apply_source_filter(scope)
          case index_filters.source
          when :crz then scope.where(source: CrzImport::Mapper::SOURCE)
          when :editorial then scope.where.not(source: CrzImport::Mapper::SOURCE)
          else scope
          end
        end

        def apply_q_filter(scope)
          pattern = index_search_pattern
          pattern ? scope.where(SEARCH_CONDITION, pattern: pattern) : scope
        end

        # The normalized filter state, shared by the query builder and the
        # filter form (prefill). Vocabulary membership is validated against
        # the real sources of truth — ContractLifecycle::STATES via
        # ContractLifecycle.state? and the CrzImport source constant — so the
        # form and the scope can never drift apart.
        def index_filters
          IndexFilters.new(
            state: index_state_param,
            source: index_source_param,
            q: params[:q].to_s.strip
          )
        end

        def index_state_param
          candidate = params[:state].to_s.presence&.to_sym
          candidate if candidate && ContractLifecycle.state?(candidate)
        end

        def index_source_param
          candidate = params[:source].to_s.presence&.to_sym
          candidate if %i[crz editorial].include?(candidate)
        end

        # The escaped LIKE pattern for the :q filter; nil when the term is
        # blank, so an empty search box contributes no WHERE clause.
        def index_search_pattern
          term = index_filters.q
          "%#{ActiveRecord::Base.sanitize_sql_like(term)}%" if term.present?
        end

        # Filter-form option lists: the "any" default first, then the real
        # vocabulary with its established labels (contract_states.* for the
        # states — the table labels and the filter options are one
        # vocabulary, never a second one).
        def index_state_options
          [[t("decidim.contracts_sk.admin.contracts.index.filters.states.any"), ""]] +
            ContractLifecycle::STATES.map do |state|
              [t(state, scope: "decidim.contracts_sk.contract_states"), state]
            end
        end

        def index_source_options
          [[t("decidim.contracts_sk.admin.contracts.index.filters.sources.all"), ""]] +
            %i[crz editorial].map do |source|
              [t("decidim.contracts_sk.admin.contracts.index.filters.sources.#{source}"), source]
            end
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
