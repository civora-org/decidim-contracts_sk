# frozen_string_literal: true

module Decidim
  module ContractsSk
    module Admin
      # The admin home's "What needs doing today" list: a short, prioritised
      # set of ACTIONS for ONE signed-in person. Pure read model, no HTML and
      # no routes: the view turns a Task into a sentence and ONE button.
      #
      # Who may see what is never decided here. Every task asks the
      # permission layer (the +can+ callable, the controller's allowed_to?)
      # whether the person may perform the action the task is about, with the
      # same context the rest of the admin uses, so the home can never drift
      # from the permission table: four-eyes (a submitter never sees their
      # own record in the review task), the editor-only filing and publish
      # steps and the reviewer-only judgment all follow from it. A person
      # without a role simply gets an empty list.
      #
      # Three groups, in the order they are shown:
      # * :urgent  - CRZ deadlines (overdue or due within DUE_SOON_DAYS), one
      #              task per record, most overdue first, capped; the action
      #              is the record's own next step for this person;
      # * :waiting - what waits for this person: records to review, returned
      #              drafts, approved records to publish, published records
      #              whose filing in the CRZ is not yet confirmed; one task
      #              per kind with a count (the record itself when it is one);
      # * :tidy    - data-quality nudges on records this person may still
      #              edit: a missing amount, a missing signing date.
      #
      # Query shape: one COUNT per task kind plus one capped list for the
      # urgent group; independent of the number of records.
      class TodayTasks
        GROUPS = %i[urgent waiting tidy].freeze

        # At most this many urgent tasks are listed individually; the total
        # is carried in +urgent_total+ for the "and N more" line.
        URGENT_LIMIT = 5

        # Fetched before the per-record permission filter (the set is small:
        # tracked, unfiled and past or near its deadline).
        URGENT_FETCH_LIMIT = 200

        # key      - the task kind (locale key, DOM id)
        # group    - one of GROUPS
        # action   - the button's verb (locale key under today.actions)
        # total    - how many records the task stands for
        # contract - the record when the task is about exactly one
        # list     - the filtered contracts index params for a many-record task
        # days     - urgent tasks: days left (negative = overdue)
        # extra    - kind-specific number (approved: how many still lack the
        #            redaction confirmation)
        # state => [the permission that makes the record this person's task,
        # the task's action]. The permission layer decides; this is only the
        # pairing of a state with the step that moves it forward.
        URGENT_ACTIONS = {
          draft: %i[update prepare_crz], returned: %i[update prepare_crz],
          in_review: %i[approve review], approved: %i[publish publish],
          published: %i[confirm_crz_filing confirm_filing]
        }.freeze

        Task = Struct.new(:key, :group, :action, :total, :contract, :list, :days, :extra, keyword_init: true)

        def initialize(organization:, user:, can:, today: Date.current)
          @scope = Contract.where(organization: organization)
          @user = user
          @can = can
          @today = today
        end

        def tasks
          @tasks ||= (urgent_tasks + waiting_tasks + tidy_tasks).freeze
        end

        def by_group(group)
          tasks.select { |task| task.group == group }
        end

        # How many urgent records the person may act on in all (the listed
        # tasks are capped at URGENT_LIMIT).
        def urgent_total
          urgent_candidates.size
        end

        def empty?
          tasks.empty?
        end

        private

        def can?(action, subject, context = {})
          @can.call(action, subject, context)
        end

        # --- urgent: CRZ deadlines ---

        def urgent_tasks
          urgent_candidates.first(URGENT_LIMIT).map do |contract, action|
            Task.new(key: :"crz_#{contract.crz_days_left(today: @today).negative? ? :overdue : :due_soon}",
                     group: :urgent, action: action, total: 1, contract: contract,
                     days: contract.crz_days_left(today: @today))
          end
        end

        # [contract, action] pairs for the records this person can move
        # forward, most overdue first. Memoized: urgent_total reuses it.
        def urgent_candidates
          @urgent_candidates ||= begin
            records = @scope.crz_overdue(@today).or(@scope.crz_due_soon(@today))
                            .order(signed_on: :asc, id: :asc).limit(URGENT_FETCH_LIMIT).to_a
            records.filter_map do |contract|
              action = urgent_action(contract)
              [contract, action] if action
            end
          end
        end

        # The person's own next step on a record, or nil when they have none
        # (then the record is not their task).
        def urgent_action(contract)
          permission, action = URGENT_ACTIONS[contract.state.to_sym]
          action if permission && can?(permission, :contract, contract: contract)
        end

        # --- waiting ---

        def waiting_tasks
          [review_task, returned_task, publish_task, filing_task].compact
        end

        def review_task
          return unless can?(:approve, :contract, state: :in_review)

          link = { state: :in_review }
          link[:submitter] = :others unless Decidim::ContractsSk.allow_self_review
          counted_task(:review, :review, @scope.awaiting_review_by(@user), link, order: { updated_at: :asc, id: :asc })
        end

        def returned_task
          return unless can?(:submit, :contract, state: :returned)

          counted_task(:returned, :edit_returned, @scope.returned_to(@user), { state: :returned, submitter: :me },
                       order: { reviewed_at: :desc, id: :desc })
        end

        def publish_task
          return unless can?(:publish, :contract, state: :approved)

          scope = @scope.approved
          task = counted_task(:publish, :publish, scope, { state: :approved }, order: { updated_at: :asc, id: :asc })
          task&.extra = scope.where(redaction_confirmed_at: nil).count
          task
        end

        # Published editorial records the CRZ filing of which nobody has
        # confirmed yet. The scope is the deadline-tracked one narrowed to
        # published; the permission is checked per record for the single
        # one and by role for the count (the filing gate is the editor
        # role plus these very conditions).
        def filing_task
          return unless can?(:create, :contract)

          scope = @scope.crz_deadline_tracked.published
          counted_task(:confirm_filing, :confirm_filing, scope, { state: :published, deadline: :unfiled },
                       order: { published_at: :asc, id: :asc })
        end

        # One task for a scope: nil when empty, the record itself (so the
        # button can go straight to it) when exactly one.
        def counted_task(key, action, scope, list, order:)
          count = scope.count
          return if count.zero?

          contract = count == 1 ? scope.order(order).first : nil
          Task.new(key: key, group: :waiting, action: action, total: count, contract: contract, list: list)
        end

        # --- tidy ---

        def tidy_tasks
          return [] unless can?(:update, :contract, state: :draft)

          editable = @scope.where(state: ContractLifecycle::EDITABLE_STATES.map(&:to_s))
          [[:missing_amount, :amount, editable.where(amount: nil)],
           [:missing_signed_on, :signed_on, editable.where(signed_on: nil)]].filter_map do |key, field, scope|
            counted_task(key, :fill_in, scope, { missing: field }, order: { id: :asc }).tap { |t| t&.group = :tidy }
          end
        end
      end
    end
  end
end
