# frozen_string_literal: true

module Decidim
  module ContractsSk
    # Notification vocabulary for contract lifecycle transitions
    # (civora-org/civora-platform#94, M03-05-A / #104). A plain module on
    # purpose: the offline spec dummy cannot load Decidim::Events::SimpleEvent,
    # so every decision lives here (testable offline) and
    # ContractTransitionEvent stays a thin shell verified on the host.
    #
    # Vocabulary only: nothing publishes these events yet (M03-05-C).
    module TransitionNotification
      # Lifecycle event => notification name. `archive` is deliberately
      # absent: archiving is not notified (#94).
      NAMES = {
        submit: "contract_submitted",
        return: "contract_returned",
        approve: "contract_approved",
        reject: "contract_rejected",
        publish: "contract_published"
      }.freeze

      # Events whose notification carries the reviewer's stored reason.
      REASON_EVENTS = %i[return reject].freeze

      module_function

      # The Decidim event name for a lifecycle event, or nil when the event
      # is not notified (e.g. `archive`, unknown values, nil).
      def event_name(event)
        name = NAMES[event&.to_sym]
        name && "decidim.events.contracts_sk.#{name}"
      end

      # Who is notified about +event+ on +contract+ (#94, M03-05-B / #105):
      # submit -> candidates whose resolved roles include :reviewer;
      # return/approve/reject/publish -> the contract's author; anything
      # else (e.g. archive) -> nobody. The actor is never notified about
      # their own action (consistent with four-eyes review), nils are
      # dropped and users are unique by id. Nothing is memoized: both seams
      # are config-time and may be swapped in specs.
      def recipients(event:, contract:, actor:)
        users =
          case event&.to_sym
          when :submit then reviewers(contract)
          when :return, :approve, :reject, :publish then [contract.author]
          else []
          end

        users.compact.reject { |user| user.id == actor&.id }.uniq(&:id)
      end

      # Candidates narrowed through the role resolver. The result is always
      # intersected with ContractLifecycle::ROLES (the same intersection
      # TransitionContract#role uses): resolver output is never trusted raw.
      def reviewers(contract)
        candidates = Decidim::ContractsSk.notification_candidates.call(contract.organization)
        candidates.to_a.compact.select do |user|
          roles = Array(Decidim::ContractsSk.role_resolver.call(user, {})) & ContractLifecycle::ROLES
          roles.include?(:reviewer)
        end
      end

      # Decidim defaults the i18n scope to the event name; the engine pins
      # every key under decidim.contracts_sk (key-surface spec), so the scope
      # is rewritten from the last event-name segment.
      def i18n_scope(event_name)
        "decidim.contracts_sk.events.#{event_name.to_s.split(".").last}"
      end
    end
  end
end
