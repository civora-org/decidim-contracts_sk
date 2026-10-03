# frozen_string_literal: true

module Decidim
  # Engine for Slovak public contracts workflow and catalogue.
  module ContractsSk
    # The four-eyes rule's config seam and single-source predicate
    # (civora-org/civora-platform#123): the person who last submitted a
    # contract for review may not judge it — return, approve or reject it.
    # The default role resolver gives org admins BOTH engine roles, so the
    # role split alone never separated duties per person; the submitter
    # stamp (Contract#decidim_submitted_by_id, written by TransitionContract
    # on every submit) is what the rule compares against.
    #
    # Both enforcement points — Permissions (request admission, buttons
    # hidden) and TransitionContract (in-lock re-check) — and the admin
    # controller's button derivation call the predicates below, so the
    # event vocabulary and the comparison live in exactly one place.
    #
    # +allow_self_review+ is the escape hatch for one-person municipalities
    # that cannot field a second reviewer: assign +true+ in an initializer
    # and the submitter may judge their own record, with every such act
    # audited under a distinct "contract.<event>_self" action. The default
    # is +false+. Config-time only, like the role_resolver and stale_after
    # seams: never mutate this setting at request time.
    #
    # Pure Ruby on purpose (no Rails constants), duck-typed on the
    # record's +decidim_submitted_by_id+ and the user's +id+, so
    # Permissions specs may pass plain structs or doubles: an object that
    # does not respond to the reader, a nil record, a nil user and a nil
    # stamp are all "not a self review" (legacy records carry a nil stamp).

    # The events the four-eyes rule judges (the reviewer's decisions).
    JUDGMENT_EVENTS = %i[return approve reject].freeze

    class << self
      attr_accessor :allow_self_review

      # True when +user+ is the recorded submitter of +contract+ AND the
      # event is a judgment event. Independent of the config seam — it
      # answers "is this a self review", not "is it forbidden"; the audit
      # label (_self) is keyed off this one.
      def self_review?(contract, user, event)
        return false unless JUDGMENT_EVENTS.include?(event.to_s.to_sym)
        return false unless contract.respond_to?(:decidim_submitted_by_id)
        return false unless user.respond_to?(:id)

        submitter_id = contract.decidim_submitted_by_id
        submitter_id.present? && submitter_id == user.id
      end

      # True when the rule forbids the act: a self review while the seam
      # is off. The single question both enforcement points ask.
      def self_review_blocked?(contract, user, event)
        self_review?(contract, user, event) && !allow_self_review
      end
    end

    self.allow_self_review = false
  end
end
