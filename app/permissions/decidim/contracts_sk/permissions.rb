# frozen_string_literal: true

module Decidim
  module ContractsSk
    # Permission checks for the engine's contract records, following Decidim's
    # DefaultPermissions contract: it may set the permission action's state
    # only for subject :contract and leaves every other action untouched, so
    # the rest of the host's permission_class_chain decides those.
    #
    # Admin scope, subject :contract:
    # - :create is allowed when the user's engine roles include :editor
    #   (the transition-table row 1 analog).
    # - Transition events (:submit, :return, :approve, :reject, :publish,
    #   :archive) are allowed when ContractLifecycle.allowed_roles for the
    #   record's state intersect the user's engine roles. The event list is
    #   derived from ContractLifecycle::TRANSITIONS, never hand-enumerated.
    # - :read is allowed when the user holds any engine role (admin index).
    #
    # Public scope, subject :contract:
    # - :read is allowed exactly when the record's state is publicly visible
    #   (ContractLifecycle::PUBLIC_STATES). No authentication required.
    #
    # Every other scope/subject/action combination is left unset, which
    # Decidim's permission machinery treats as denied (PermissionNotSetError
    # rescued to false — fail-closed).
    #
    # The record's state is read duck-typed from context[:contract]&.state
    # or context[:state]; callers pass at least one.
    # Load-time note: TRANSITION_EVENTS below evaluates ContractLifecycle
    # at class-body load; this file is only ever loaded through the gem's
    # lib require chain (which defines ContractLifecycle first), never
    # standalone.
    class Permissions < Decidim::DefaultPermissions
      TRANSITION_EVENTS = ContractLifecycle::TRANSITIONS.values
                                                        .flat_map(&:keys)
                                                        .uniq.sort.freeze

      def permissions
        return permission_action unless subject == :contract

        case permission_action.scope
        when :admin
          admin_action
        when :public
          public_action
        end

        permission_action
      end

      private

      def admin_action
        case action
        when :create
          toggle_allow(roles_for_user.include?(:editor))
        when :read
          toggle_allow(roles_for_user.any?)
        when *TRANSITION_EVENTS
          toggle_allow(transition_roles.any?)
        end
      end

      def public_action
        toggle_allow(ContractLifecycle.publicly_visible?(state)) if action == :read
      end

      def transition_roles
        ContractLifecycle.allowed_roles(from: state, event: action) & roles_for_user
      end

      # Rails enum getters return Strings while ContractLifecycle is keyed
      # on Symbols; normalize (nil-safely) at this single boundary so both
      # state sources behave identically.
      def state
        (context[:contract]&.state || context[:state])&.to_sym
      end

      def roles_for_user
        Array(Decidim::ContractsSk.role_resolver.call(user, context)) & ContractLifecycle::ROLES
      end
    end
  end
end
