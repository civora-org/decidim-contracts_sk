# frozen_string_literal: true

module Decidim
  module ContractsSk
    module Admin
      # The admin landing page for role holders (civora-org/civora-platform
      # #126): what waits for ME, per role, plus the organization-wide
      # state counts, the CRZ deadline watch and the last audit events.
      # Read-only; every list is a capped preview that links to the
      # matching filtered contracts index (the "Show all (N)" counts are the
      # index's own, because both sides use the same Contract scopes).
      #
      # Gate: the same :read :contract permission as the contracts index
      # (any engine role); a roleless user gets the usual NeedsPermission
      # redirect + alert, an anonymous visitor the auth floor. The role-
      # specific blocks are NOT gated by new role logic: each one asks the
      # permission layer whether the user may perform the event the block
      # is about (:approve on in_review, :submit on returned, :publish on
      # approved, :read on the audit trail), so the dashboard can never
      # drift from the permission table — and, being a read surface, shows
      # nothing the index would not.
      #
      # Everything is tenant-scoped from the current organization. Query
      # count is independent of the number of rows: per block one capped
      # list query and one COUNT (the review queue adds one preload for the
      # submitters), one grouped state count, and one audit list with
      # bounded preloads (actors, targets, amendment parent contracts).
      class DashboardController < Admin::ApplicationController
        include AuditEventPresentation

        # Preview cap per list (the "Show all (N)" link covers the rest).
        LIST_LIMIT = 10

        # One block of the page: the capped rows, the full total and the
        # filtered-index target. Blocks the user may not see are simply never
        # built (the view gates them through the visibility predicates).
        Block = Struct.new(:records, :total, :path, keyword_init: true)

        helper_method :review_queue, :returned_list, :approved_list, :overdue_list,
                      :due_soon_list, :state_counts, :total_count, :recent_events,
                      :dashboard_today, :audit_trail_visible?,
                      :review_queue_visible?, :returned_visible?, :approved_visible?

        def show
          enforce_permission_to :read, :contract
        end

        private

        def contracts_scope
          Contract.where(organization: current_organization)
        end

        def dashboard_today
          @dashboard_today ||= Date.current
        end

        # --- visibility: the permission layer decides, no role logic here ---

        def review_queue_visible?
          allowed_to?(:approve, :contract, state: :in_review)
        end

        def returned_visible?
          allowed_to?(:submit, :contract, state: :returned)
        end

        def approved_visible?
          allowed_to?(:publish, :contract, state: :approved)
        end

        def audit_trail_visible?
          allowed_to?(:read, :audit_event)
        end

        # --- blocks ---

        # In-review records the user may judge (four-eyes: own submissions
        # excluded unless the allow_self_review seam is on, in which case the
        # index link carries no submitter narrowing either).
        def review_queue
          @review_queue ||= begin
            scope = contracts_scope.awaiting_review_by(current_user)
            link = { state: :in_review }
            link[:submitter] = :others unless Decidim::ContractsSk.allow_self_review
            build_block(scope.includes(:submitted_by).order(updated_at: :asc, id: :asc), scope, link)
          end
        end

        def returned_list
          @returned_list ||= begin
            scope = contracts_scope.returned_to(current_user)
            build_block(scope.order(Arel.sql("reviewed_at IS NULL"), reviewed_at: :desc, id: :desc), scope,
                        state: :returned, submitter: :me)
          end
        end

        def approved_list
          @approved_list ||= begin
            scope = contracts_scope.approved
            build_block(scope.order(updated_at: :asc, id: :asc), scope, state: :approved)
          end
        end

        def overdue_list
          @overdue_list ||= deadline_block(contracts_scope.crz_overdue(dashboard_today), :overdue)
        end

        def due_soon_list
          @due_soon_list ||= deadline_block(contracts_scope.crz_due_soon(dashboard_today), :due_soon)
        end

        def deadline_block(scope, deadline)
          build_block(scope.order(signed_on: :asc, id: :asc), scope, deadline: deadline)
        end

        def build_block(ordered, counted, link_params)
          Block.new(records: ordered.limit(LIST_LIMIT).to_a,
                    total: counted.count,
                    path: admin_contracts_path(link_params))
        end

        # One grouped COUNT over the tenant scope, zeros included, in the
        # lifecycle's own order (the vocabulary is never hand-enumerated).
        def state_counts
          @state_counts ||= begin
            grouped = contracts_scope.group(:state).count.transform_keys(&:to_sym)
            ContractLifecycle::STATES.to_h { |state| [state, grouped.fetch(state, 0)] }
          end
        end

        def total_count
          @total_count ||= state_counts.values.sum
        end

        # The last audit events of the organization (tenancy explicit on the
        # rows), newest first under the viewer's own total order. Actors and
        # targets are preloaded; an amendment target's parent contract (which
        # the target label links through) is preloaded in one more query, so
        # the page's query count never depends on the rows.
        def recent_events
          @recent_events ||= begin
            events = recent_events_scope.includes(:actor, :target).to_a
            amendments = events.map(&:target).grep(Amendment)
            ActiveRecord::Associations::Preloader.new(records: amendments, associations: :contract).call
            events
          rescue NameError => e
            raise if e.is_a?(NoMethodError)

            # A target_type whose class no longer loads cannot be preloaded;
            # fall back to the lazy per-row resolution, whose helper is
            # fail-closed (the viewer's dangling-target doctrine).
            recent_events_scope.includes(:actor).to_a
          end
        end

        def recent_events_scope
          AuditEvent.where(organization: current_organization)
                    .order(INDEX_ORDER)
                    .limit(LIST_LIMIT)
        end
      end
    end
  end
end
