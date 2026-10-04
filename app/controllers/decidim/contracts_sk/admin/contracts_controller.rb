# frozen_string_literal: true

module Decidim
  module ContractsSk
    module Admin
      # Admin CRUD and lifecycle transitions for contract records
      # (civora-org/civora-platform#58, #59), the manual CRZ-handoff
      # download/generate pair (M02-05-C, civora-org/civora-platform#74),
      # the single-record CRZ import (ADR-008,
      # civora-org/civora-platform#86), the ADR-007 privacy-redaction
      # confirmation POST (civora-org/civora-platform#91) and the
      # reviewer-decision-reason pass-through on the transition actions
      # (civora-org/civora-platform#90), and the CRZ filing confirmation
      # pair (civora-org/civora-platform#125: a read-only side-by-side
      # preview and the verifying POST, both editor-gated on a published,
      # unfiled editorial record).
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
      # The deadline filter (civora-org/civora-platform#124) narrows to the
      # tracked records due within 14 days or overdue for filing in CRZ.
      # The submitter filter (civora-org/civora-platform#126) narrows to
      # records the signed-in user submitted (me) or everyone else's, NULL
      # stamps included (others) — the filter the admin dashboard's review
      # queue and returned-to-me links point at.
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
        # filter state back the filter form the same way, and
        # #reason_event? tells the row which transition controls take a
        # reviewer decision reason (civora-org/civora-platform#90). The
        # per-state counter helpers back the index header chips and the
        # filtered no-matches empty state (civora-org/civora-platform#93).
        helper_method :transition_events_for, :index_filters,
                      :index_state_options, :index_source_options, :reason_event?,
                      :index_state_counts, :index_total_count, :index_filters_active?,
                      :index_counter_label, :index_counter_path, :index_counter_classes,
                      :index_deadline_options, :index_deadline_counts,
                      :index_deadline_counter_label, :index_deadline_counter_path,
                      :index_deadline_counter_classes, :index_today,
                      :index_submitter_options

        # Case-insensitive free-text match for the index :q filter over the
        # two editorial identity fields — the engine's shared TextSearch
        # (down-cased term, explicit ESCAPE, so user-supplied % and _ stay
        # literal on every database; civora-org/civora-platform#116).
        SEARCH_CONDITION = TextSearch::CONTRACT_CONDITION

        # Deterministic index ordering: newest records first, with the id as
        # the tiebreaker — a total order, so a page can never repeat or drop
        # a row across page boundaries on PostgreSQL (where an unordered
        # query's row order is undefined).
        INDEX_ORDER = { created_at: :desc, id: :desc }.freeze

        # Normalized index filter state (civora-org/civora-platform#86b):
        # state is a lifecycle state symbol or nil ("any state"), source is
        # :crz / :editorial or nil ("all sources"), q is the stripped search
        # term. Carries request-derived values only — never persisted.
        # deadline (civora-org/civora-platform#124) is :due_soon / :overdue
        # or nil ("any deadline"). submitter (civora-org/civora-platform#126)
        # is :me / :others or nil ("any submitter").
        IndexFilters = Struct.new(:state, :source, :q, :deadline, :submitter, keyword_init: true)

        # The deadline filter vocabulary (civora-org/civora-platform#124).
        DEADLINE_FILTERS = %i[due_soon overdue].freeze

        # The submitter filter vocabulary (civora-org/civora-platform#126).
        SUBMITTER_FILTERS = %i[me others].freeze

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

        # ADR-007 privacy-redaction confirmation (civora-org/civora-platform
        # #91): the editor's checklist affirmation on the edit page that
        # personal data was redacted — the stamp TransitionContract's publish
        # edge requires. Gated through the dedicated :confirm_redaction
        # permission action (editor on a confirmable record — editable
        # states plus approved, mirroring :update's role rule on a wider
        # window); the command re-checks both conditions inside the row
        # lock. The affirmation itself is consumed SERVER-SIDE: the checkbox
        # value must arrive as a truthy boolean, so a stale or hand-crafted
        # POST without it is refused before the command runs (no stamp, no
        # audit row — the checkbox's `required` attribute is a UX aid, never
        # the gate). Both outcomes are PRG redirects to the edit page (the
        # control's home) with a localized flash — the checkbox form has no
        # state to re-render.
        def confirm_redaction
          @contract = contracts_scope.find(params[:id])

          enforce_permission_to :confirm_redaction, :contract, contract: @contract

          return confirm_redaction_failed unless redaction_affirmed?

          ConfirmRedaction.call(@contract, user: current_user) do
            on(:ok) { confirm_redaction_succeeded }
            on(:invalid) { confirm_redaction_failed }
          end
        end

        # CRZ filing confirmation (civora-org/civora-platform#125), GET: the
        # CRZ-id form and — with ?crz_id= — the read-only side-by-side
        # comparison of this record against the official one fetched
        # through the ekosystem feed. WRITES NOTHING: the confirm form it
        # renders carries the preview's checksum token, which the POST's
        # command re-verifies inside the row lock. The id is validated
        # (`\A\d+\z`) before any network call (the import_crz precedent).
        # A refusal re-renders the id form with a localized alert.
        def crz_filing
          @contract = contracts_scope.find(params[:id])

          enforce_permission_to :confirm_crz_filing, :contract, contract: @contract

          @crz_id = params[:crz_id].to_s.strip
          load_filing_preview if @crz_id.present?
        end

        # CRZ filing confirmation, POST: the verifying command. Every
        # outcome is a PRG redirect with a localized flash — success to the
        # index (a filed record is published and no longer editable); a
        # refusal the editor can act on (stale preview, reason problems)
        # back to the preview of the same id, the others to the id form or
        # the index (see FILING_PREVIEW_REASONS / #filing_failed).
        def confirm_crz_filing
          @contract = contracts_scope.find(params[:id])

          enforce_permission_to :confirm_crz_filing, :contract, contract: @contract

          crz_id = params[:crz_id].to_s.strip
          return filing_failed(:not_found, crz_id) unless crz_id.match?(CRZ_ID_FORMAT)

          run_filing_confirmation(crz_id)
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
        IMPORT_NOTICE_OUTCOMES = %i[created updated unchanged linked].freeze

        # Filing-confirmation refusals that redirect back to the PREVIEW of
        # the same id (the editor can correct the reason, or must re-read a
        # changed official record); every other refusal returns to the bare
        # id form, and :already_filed / :not_fileable to the index.
        CRZ_ID_FORMAT = /\A\d+\z/
        FILING_PREVIEW_REASONS = %i[stale reason_required reason_rejected].freeze
        FILING_INDEX_REASONS = %i[already_filed not_fileable].freeze

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

        # The preview fetch (read-only, FilingLookup): sets the comparison
        # and checksum token for the view, or re-renders the id form with a
        # localized refusal. A non-numeric id never reaches the network.
        def load_filing_preview
          return filing_invalid_id unless @crz_id.match?(CRZ_ID_FORMAT)

          lookup = CrzImport::FilingLookup.call(crz_id: @crz_id, organization: current_organization)
          return flash.now[:alert] = filing_message(lookup.refusal, @crz_id) unless lookup.ok?

          @crz_record = lookup.record
          @comparison = CrzImport::FilingComparison.new(contract: @contract, record: @crz_record)
        end

        def filing_invalid_id
          flash.now[:alert] = t("decidim.contracts_sk.admin.contracts.crz_filing.invalid_id")
        end

        def run_filing_confirmation(crz_id)
          ConfirmCrzFiling.call(@contract, crz_id: crz_id, checksum: params[:checksum],
                                           reason: params[:reason], user: current_user) do
            on(:ok) { |outcome| filing_succeeded(outcome, crz_id) }
            on(:invalid) { |reason| filing_failed(reason, crz_id) }
          end
        end

        def filing_message(reason, crz_id)
          t("decidim.contracts_sk.admin.contracts.crz_filing.refusals.#{reason}", crz_id: crz_id)
        end

        def filing_succeeded(outcome, crz_id)
          flash[:notice] = t("decidim.contracts_sk.admin.contracts.crz_filing.#{outcome}", crz_id: crz_id)
          redirect_to admin_contracts_path
        end

        def filing_failed(reason, crz_id)
          flash[:alert] = filing_message(reason, crz_id)

          if FILING_INDEX_REASONS.include?(reason)
            redirect_to admin_contracts_path
          elsif FILING_PREVIEW_REASONS.include?(reason)
            redirect_to crz_filing_admin_contract_path(@contract, crz_id: crz_id)
          else
            redirect_to crz_filing_admin_contract_path(@contract)
          end
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
          # A RecordInvalid leaves the submitted values assigned on the
          # in-memory record; the edit header's CRZ deadline line
          # (civora-org/civora-platform#124) must read the PERSISTED values,
          # so drop the unsaved changes (the form re-renders from @form).
          @contract.restore_attributes
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

        # Both confirm outcomes are PRG redirects to the edit page, same
        # doctrine as the generate pair: the :invalid path covers the
        # missing affirmation and the non-confirmable / already-stamped
        # refusals, and the edit page shows the truth (stamp line or
        # checkbox form) either way.
        def confirm_redaction_succeeded
          flash[:notice] = t("decidim.contracts_sk.admin.contracts.confirm_redaction.success")
          redirect_to edit_admin_contract_path(@contract)
        end

        def confirm_redaction_failed
          flash[:alert] = t("decidim.contracts_sk.admin.contracts.confirm_redaction.invalid")
          redirect_to edit_admin_contract_path(@contract)
        end

        # The affirmation consumed server-side (see #confirm_redaction):
        # ActiveModel::Type::Boolean's vocabulary is pinned here — "1",
        # "true", "t" and "on" count as the affirmation; a missing value,
        # "0", "false", "f", "off" or any other payload does not. The
        # comparison is against exactly `true`, so nil (missing/empty)
        # refuses too.
        def redaction_affirmed?
          ActiveModel::Type::Boolean.new.cast(params[:redaction_confirmed]) == true
        end

        # Shared transition pipeline: load the record from the tenant scope,
        # ask the permission layer (event-specific: the lifecycle edge's role
        # set decides), then run the command. The raw reason param rides
        # along on EVERY event (civora-org/civora-platform#90): the command
        # is the single authority on the judgment vocabulary — it requires a
        # reason on return/reject and fails ANY other event closed when one
        # arrives, so the controller applies no reason logic of its own and
        # nothing is ever written outside the command's lock. Both outcomes
        # are PRG redirects — a failure never re-renders, because the
        # record's state may have changed under us; the index shows the
        # truth. The command's refusal payloads (TransitionContract's
        # :redaction_gate, REASON_REQUIRED, REASON_REJECTED, SELF_REVIEW_REASON) select the
        # dedicated flashes (see #transition_failed).
        def transition(event)
          @contract = contracts_scope.find(params[:id])

          enforce_permission_to event, :contract, contract: @contract

          TransitionContract.call(@contract, event: event, user: current_user,
                                             reason: params[:reason]) do
            on(:ok) { transition_succeeded }
            on(:invalid) { |failure = nil| transition_failed(failure) }
          end
        end

        def transition_succeeded
          flash[:notice] = t("decidim.contracts_sk.admin.contracts.transition.success")
          redirect_to admin_contracts_path
        end

        # The refusal-payload → localized-alert mapping: dedicated,
        # actionable messages for the ADR-007 redaction gate (#91) and the
        # #90 decision-reason refusals, the generic transition alert for
        # every other refusal. Keyed off the command's broadcast payload —
        # deterministic, no state re-read, and nothing beyond the
        # already-public gates is revealed.
        TRANSITION_FAILURE_KEYS = {
          TransitionContract::REDACTION_GATE_REASON => "redaction_required",
          TransitionContract::REASON_REQUIRED => "review_reason_required",
          TransitionContract::REASON_REJECTED => "review_reason_rejected",
          TransitionContract::SELF_REVIEW_REASON => "self_review"
        }.freeze

        def transition_failed(failure = nil)
          key = "decidim.contracts_sk.admin.contracts.transition." \
                "#{TRANSITION_FAILURE_KEYS.fetch(failure, :invalid)}"

          flash[:alert] = t(key)
          redirect_to admin_contracts_path
        end

        # The events the acting user may trigger on this record right now: the
        # lifecycle's events from the record's state, filtered by the edges
        # whose roles intersect the user's engine roles. Uses the same
        # config-time resolution seam as the Permissions class. Empty for a
        # roleless user — no derivation hand-enumerated anywhere. The
        # four-eyes rule (civora-org/civora-platform#123) additionally
        # drops the judgment events the user may not perform on their own
        # submission, so their buttons never render.
        def transition_events_for(contract)
          state = contract.state&.to_sym
          roles = Array(Decidim::ContractsSk.role_resolver.call(current_user, {})) & ContractLifecycle::ROLES

          ContractLifecycle.events_from(state).select do |event|
            (ContractLifecycle.allowed_roles(from: state, event: event) & roles).any? &&
              !Decidim::ContractsSk.self_review_blocked?(contract, current_user, event)
          end
        end

        # Whether the transition event takes a reviewer decision reason
        # (civora-org/civora-platform#90) — the index view's switch between
        # the bare confirm button and the inline reason form. Single-sourced
        # from the command's REASON_EVENTS vocabulary: the command is the
        # authority on which events carry a reason, the view only mirrors it.
        def reason_event?(event)
          TransitionContract::REASON_EVENTS.include?(event.to_sym)
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
          apply_deadline_filter(apply_q_filter(apply_source_filter(apply_submitter_filter(apply_state_filter(scope)))))
        end

        # Submitter filter (civora-org/civora-platform#126): "me" is the
        # signed-in user's own submissions, "others" everyone else's AND
        # records with no submitter stamp (the shared Contract scopes, so the
        # dashboard's queue counts and this filter always agree).
        def apply_submitter_filter(scope)
          case index_filters.submitter
          when :me then scope.submitted_by_user(current_user)
          when :others then scope.not_submitted_by_user(current_user)
          else scope
          end
        end

        # CRZ deadline filter (civora-org/civora-platform#124): composes on
        # the tenant scope like the others; the model scopes compare
        # signed_on against Ruby-computed thresholds (D1), so the date
        # arithmetic is exact on every database.
        def apply_deadline_filter(scope)
          case index_filters.deadline
          when :due_soon then scope.crz_due_soon(index_today)
          when :overdue then scope.crz_overdue(index_today)
          else scope
          end
        end

        # "Today" for every deadline computation of one request, in the
        # application time zone (Decidim's admin applies the organization's).
        def index_today
          @index_today ||= Date.current
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
            q: TextSearch.clean(params[:q]).strip,
            deadline: index_deadline_param,
            submitter: index_submitter_param
          )
        end

        def index_submitter_param
          candidate = params[:submitter].to_s.presence&.to_sym
          candidate if SUBMITTER_FILTERS.include?(candidate)
        end

        def index_deadline_param
          candidate = params[:deadline].to_s.presence&.to_sym
          candidate if DEADLINE_FILTERS.include?(candidate)
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
          TextSearch.pattern(term) if term.present?
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

        def index_deadline_options
          [[t("decidim.contracts_sk.admin.contracts.index.filters.deadlines.any"), ""]] +
            DEADLINE_FILTERS.map do |deadline|
              [t("decidim.contracts_sk.admin.contracts.index.filters.deadlines.#{deadline}",
                 days: Decidim::ContractsSk::CrzDeadline::DUE_SOON_DAYS), deadline]
            end
        end

        def index_submitter_options
          [[t("decidim.contracts_sk.admin.contracts.index.filters.submitters.any"), ""]] +
            SUBMITTER_FILTERS.map do |submitter|
              [t("decidim.contracts_sk.admin.contracts.index.filters.submitters.#{submitter}"), submitter]
            end
        end

        def index_source_options
          [[t("decidim.contracts_sk.admin.contracts.index.filters.sources.all"), ""]] +
            %i[crz editorial].map do |source|
              [t("decidim.contracts_sk.admin.contracts.index.filters.sources.#{source}"), source]
            end
        end

        # Per-state lifecycle counters for the index header (civora-org/
        # civora-platform#93): ONE grouped query over the UNFILTERED tenant
        # scope — the chips are the honest "3 awaiting review" navigation,
        # so the counts deliberately ignore the active filter. Keys are
        # normalized to the lifecycle symbols the view iterates (the DB
        # hands raw string keys back from the grouped count).
        def index_state_counts
          @index_state_counts ||= contracts_scope.group(:state).count
                                                 .transform_keys(&:to_sym)
        end

        # The "All" chip total, derived from the same grouped result — no
        # second query. The state column is NOT NULL (schema default
        # "draft"), so the grouped counts cover every record.
        def index_total_count
          @index_total_count ||= index_state_counts.values.sum
        end

        # Whether the NORMALIZED index filters are non-default (civora-org/
        # civora-platform#93): gates the no-matches empty state, so a
        # garbage param — normalized away to the default view — never gets
        # the filtered wording over the true-empty one.
        def index_filters_active?
          index_filters.state.present? || index_filters.source.present? ||
            index_filters.q.present? || index_filters.deadline.present? ||
            index_filters.submitter.present?
        end

        # CRZ deadline counters (civora-org/civora-platform#124): due-soon
        # and overdue counts over the UNFILTERED tenant scope, like the state
        # chips — navigation, not a readout of the active view. Two COUNT
        # queries, memoized per request.
        def index_deadline_counts
          @index_deadline_counts ||= {
            due_soon: contracts_scope.crz_due_soon(index_today).count,
            overdue: contracts_scope.crz_overdue(index_today).count
          }
        end

        def index_deadline_counter_label(deadline)
          label = t("decidim.contracts_sk.admin.contracts.index.counters.crz_#{deadline}",
                    days: Decidim::ContractsSk::CrzDeadline::DUE_SOON_DAYS)
          "#{label} (#{index_deadline_counts.fetch(deadline)})"
        end

        # Chip target: deadline=<value> plus the other ACTIVE normalized
        # filters (state/source/q).
        def index_deadline_counter_path(deadline)
          admin_contracts_path(index_filter_params.merge(deadline: deadline))
        end

        def index_deadline_counter_classes(deadline)
          classes = %w[button button__sm button__secondary contracts-sk__counter]
          classes << "contracts-sk__counter--active" if index_filters.deadline == deadline
          classes.join(" ")
        end

        # The normalized, ACTIVE filters as link params (never raw params).
        def index_filter_params
          { state: index_filters.state, source: index_filters.source,
            q: index_filters.q.presence, deadline: index_filters.deadline,
            submitter: index_filters.submitter }.compact
        end

        # Chip label: the localized state label (the shared contract_states.*
        # vocabulary — never a second one) or the "All" label, plus the count
        # in parentheses — a state's grouped count, or the summed total for
        # the All chip (the grouped result has no nil key: state is NOT NULL).
        def index_counter_label(state)
          count = state ? index_state_counts.fetch(state, 0) : index_total_count
          label = if state
                    t(state, scope: "decidim.contracts_sk.contract_states")
                  else
                    t("decidim.contracts_sk.admin.contracts.index.counters.all")
                  end
          "#{label} (#{count})"
        end

        # Chip target: state=<value> (absent for the All chip) plus the other
        # ACTIVE filter values — the normalized ones, never raw params, so a
        # garbage value cannot ride along (the same allowlist discipline as
        # the pagination partial's filter_keys).
        def index_counter_path(state)
          counter_params = index_filter_params.except(:state)
          counter_params[:state] = state if state
          admin_contracts_path(counter_params)
        end

        # Chip classes: the view's established button styles plus a
        # namespaced active marker when the chip's state matches the
        # normalized filter state (nil marks the All chip).
        def index_counter_classes(state)
          classes = %w[button button__sm button__secondary contracts-sk__counter]
          classes << "contracts-sk__counter--active" if index_filters.state == state
          classes.join(" ")
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
