# frozen_string_literal: true

module Decidim
  module ContractsSk
    module Admin
      # The admin landing page for role holders: "What needs doing today"
      # (the rework of civora-org/civora-platform#126). A short, prioritised
      # list of ACTIONS for the signed-in person only, each with one plain
      # sentence and ONE primary button (see Admin::TodayTasks for the
      # groups and the rules). Below it, collapsed and one click away: the
      # state counts of all contracts and the last audit events.
      #
      # Gate: the same :read :contract permission as the contracts index
      # (any engine role); a roleless user gets the usual NeedsPermission
      # redirect + alert, an anonymous visitor the auth floor. The tasks are
      # NOT gated by role logic of their own: each one asks the permission
      # layer whether the user may perform the action it is about, so the
      # page can never drift from the permission table (four-eyes included)
      # and, being a read surface, shows nothing the index would not.
      #
      # Everything is tenant-scoped from the current organization. The query
      # count is independent of the number of rows: one COUNT per task kind,
      # one capped list for the CRZ deadlines, one grouped state count and
      # one audit list with bounded preloads (actors, targets, amendment
      # parent contracts).
      class DashboardController < Admin::ApplicationController
        include AuditEventPresentation

        # Preview cap of the audit list.
        LIST_LIMIT = 10

        helper_method :today_tasks, :today_task_path, :state_counts, :total_count, :recent_events,
                      :dashboard_today, :audit_trail_visible?, :can_create_contract?

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

        def audit_trail_visible?
          allowed_to?(:read, :audit_event)
        end

        def can_create_contract?
          allowed_to?(:create, :contract)
        end

        def today_tasks
          permission = ->(action, subject, context = {}) { allowed_to?(action, subject, context) }
          @today_tasks ||= TodayTasks.new(organization: current_organization, user: current_user,
                                          can: permission, today: dashboard_today)
        end

        # The button's target: the record itself when the task is about one,
        # otherwise the contracts index narrowed to exactly what the task
        # counted (the counts and the lists use the same Contract scopes).
        def today_task_path(task)
          contract = task.contract
          return admin_contracts_path(task.list) unless contract

          case task.action
          when :edit_returned, :fill_in then edit_admin_contract_path(contract)
          when :prepare_crz then edit_admin_contract_path(contract, anchor: "crz-handoff")
          when :confirm_filing then crz_filing_admin_contract_path(contract)
          else admin_contract_path(contract)
          end
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
