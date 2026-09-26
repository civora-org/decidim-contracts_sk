# frozen_string_literal: true

module Decidim
  module ContractsSk
    module Admin
      # Performs one lifecycle transition on a contract record
      # (civora-org/civora-platform#59).
      #
      # Authorization is re-derived here at execution time, fail-closed, from
      # the same config-time seams the permission layer used: the engine role
      # resolver and the lifecycle transition table. Each transition edge
      # carries exactly one role, so the first intersection is deterministic;
      # a request whose roles intersect no edge (wrong role or no edge at
      # all) broadcasts :invalid without touching the record. The permission
      # layer remains the request-admission authority — this re-check covers
      # stale permission decisions and keeps the command safe to call from
      # other contexts.
      #
      # The state change and the audit row commit atomically: both happen
      # inside contract.with_lock (row lock + single transaction), so a
      # failure at either step rolls the record back — a transition either
      # fully happened (with its audit row) or did not happen at all. The
      # publication stamp (published_at, #75) rides the same transaction: it
      # is assigned inside the lock BEFORE the state write, so the state's
      # update! persists it in the same UPDATE, and an audit failure rolls
      # the stamp back together with the state. It is a system field — the
      # admin form never writes it; the archive event leaves the original
      # stamp untouched, and there is no un-publish edge, so a stamp is
      # never cleared. The audit payload shape is fixed by the #57 migration
      # (D4): action "contract.<event>", polymorphic target, explicit
      # organization/actor, timestamps — no JSON payload, no from/to.
      #
      # The publish edge additionally carries the ADR-007 privacy-redaction
      # gate (civora-org/civora-platform#91): a record whose
      # redaction_confirmed_at is blank cannot publish. The guard runs
      # INSIDE the lock against the reloaded row — the same in-lock re-check
      # doctrine as the state guard — so a request admitted before the stamp
      # existed (or racing it) refuses fail-closed, and the check reads the
      # in-database stamp, never the request-start copy. ConfirmRedaction is
      # the only writer of the stamp.
      #
      # The reviewer decision reason (civora-org/civora-platform#90,
      # Gate-1 Option A): the return and reject edges REQUIRE a non-blank
      # reason, capped at MAX_REASON_LENGTH characters — the reviewer's
      # judgment text, stored on the record with its reviewed_at timestamp.
      # The write happens INSIDE the with_lock transaction (reason +
      # timestamp assigned before the state write, so one UPDATE persists
      # all three), keeping the decision, its stamps and the audit row
      # atomic. The reason is request-shaped input that depends on no row
      # state, so its blank/over-cap guard runs BEFORE the lock (the same
      # pre-lock fail-closed tier as the role check) — a malformed request
      # never takes the row lock; everything that reads or writes row state
      # stays inside it. The judgment vocabulary stays reviewer-only: any
      # OTHER event (approve, publish, archive, submit) must arrive without
      # a reason and FAILS CLOSED when one is passed — the internal clearing
      # below is the command's own act, never an input. On the resubmit
      # edge (submit from returned) the command itself clears the stale
      # review_reason and reviewed_at inside the same lock, so a fresh
      # in_review record never carries the previous round's judgment (from
      # draft the columns are already nil, making the clearing a no-op).
      #
      # Refusal reason channel (#91 review round): the :invalid broadcasts
      # stay :invalid — the caller contract is unchanged — but a refusal
      # may ride a payload that the existing on(:invalid) handler may read
      # (Wisper passes broadcast args through). This lets the UI flash a
      # dedicated, actionable message for a refusal without a new outcome
      # symbol and without exposing anything beyond the already-public
      # gates: the redaction-gate refusal carries :redaction_gate (#91),
      # the missing-decision-reason refusal carries REASON_REQUIRED and the
      # refused-reason refusal (over-cap, or a reason on an event that
      # takes none) carries REASON_REJECTED (#90).
      class TransitionContract < Decidim::Command
        # The payload the redaction-gate refusal adds to its :invalid
        # broadcast (see the class comment).
        REDACTION_GATE_REASON = :redaction_gate

        # The payloads the reviewer-decision-reason refusals add to their
        # :invalid broadcasts (civora-org/civora-platform#90): a return/
        # reject without a usable reason carries REASON_REQUIRED; a refused
        # reason (over-cap on a judgment edge, or any reason on an event
        # that takes none) carries REASON_REJECTED.
        REASON_REQUIRED = :reason_required
        REASON_REJECTED = :reason_rejected

        # The judgment edges that demand a decision reason, and the cap the
        # reason must fit. Hand-pinned to the lifecycle's reviewer edges on
        # purpose: the lifecycle table owns states and roles, the decision
        # text is this command's input contract. Both frozen so a captured
        # reference cannot mutate the vocabulary.
        REASON_EVENTS = %i[return reject].freeze
        MAX_REASON_LENGTH = 1000

        def initialize(contract, event:, user:, reason: nil)
          super()
          @contract = contract
          @event = event
          @user = user
          @reason = reason
        end

        def call
          return broadcast(:invalid) unless role

          reason_failure = review_reason_failure
          return broadcast(:invalid, reason_failure) if reason_failure

          perform_transition
        end

        private

        attr_reader :contract, :event, :user, :reason

        # The locked transition: the in-lock guards and writes of the #69
        # doctrine. with_lock reloads the row first, so the redaction gate
        # and the state guard read the in-database state, never the
        # request-start copy; the event's attribute writes ride the same
        # transaction, so a failure at any step rolls the record back — a
        # transition either fully happened (with its audit row and stamps)
        # or did not happen at all.
        def perform_transition
          contract.with_lock do
            return broadcast(:invalid, REDACTION_GATE_REASON) unless redaction_gate_open?

            apply_event_writes!
            contract.transition_state!(event: event, role: role)
            record_audit!
          end

          broadcast(:ok, contract)
        rescue ContractLifecycle::InvalidTransitionError, ActiveRecord::RecordInvalid
          broadcast(:invalid)
        end

        # The event's attribute writes, inside the caller's lock (each
        # helper documents its own act): the resubmit clears the stale
        # reviewer decision, the judgment edges stamp the decision, and the
        # publish edge stamps its publication date — all assigned BEFORE
        # the state write, so the state's update! persists every attribute
        # in one UPDATE.
        def apply_event_writes!
          clear_review_decision! if submit_event?
          stamp_review_decision! if reason_event?
          stamp_published_at!
        end

        # The refusal payload for the request's reason shape, or nil when
        # the shape is acceptable: a judgment edge (return/reject) demands
        # a non-blank reason (REASON_REQUIRED) that fits the cap
        # (REASON_REJECTED beyond it), and every other edge demands NO
        # reason at all (REASON_REJECTED when one arrives) — the judgment
        # vocabulary stays reviewer-only. Evaluated before the lock: the
        # shape depends only on the request, never on row state.
        def review_reason_failure
          if reason_event?
            return REASON_REQUIRED if normalized_reason.blank?
            return REASON_REJECTED if normalized_reason.length > MAX_REASON_LENGTH
          elsif normalized_reason.present?
            return REASON_REJECTED
          end

          nil
        end

        # The reason as it is stored: stripped of surrounding whitespace, so
        # a whitespace-only payload counts as blank and a padded reason is
        # trimmed at the single boundary where input meets the record.
        def normalized_reason
          @normalized_reason ||= reason.to_s.strip
        end

        # True on the judgment edges that carry a decision reason. The event
        # is normalized with #to_sym at this boundary — this file's doctrine
        # wherever input meets the lifecycle (cf. #role, #stamp_published_at!).
        def reason_event?
          REASON_EVENTS.include?(event&.to_sym)
        end

        def submit_event?
          event.to_s == "submit"
        end

        # The resubmit's clearing act (civora-org/civora-platform#90): the
        # stale reviewer decision must not survive the record's re-entry
        # into review. Assigned inside the lock BEFORE the state write, so
        # the state's update! persists the cleared columns with the state —
        # a resubmit either fully happened (state + cleared decision + audit
        # row) or did not happen at all. From draft the columns are already
        # nil, so the assignment is a no-op there.
        def clear_review_decision!
          contract.review_reason = nil
          contract.reviewed_at = nil
        end

        # The reviewer's decision text and timestamp on the judgment edges:
        # assigned inside the lock BEFORE transition_state! so the state's
        # update! persists reason, timestamp and state in one UPDATE (the
        # stamp_published_at! doctrine) — an audit failure rolls all of it
        # back together.
        def stamp_review_decision!
          contract.review_reason = normalized_reason
          contract.reviewed_at = Time.current
        end

        # The publish edge's ADR-007 precondition (civora-org/civora-platform
        # #91), evaluated INSIDE the lock on the reloaded row: publishing is
        # refused while the privacy-redaction confirmation stamp is missing.
        # Every other event passes unchecked (the event is normalized with
        # #to_s at this boundary — same doctrine as stamp_published_at!).
        def redaction_gate_open?
          event.to_s != "publish" || contract.redaction_confirmed_at.present?
        end

        # The publish stamp: assigned before transition_state! so the
        # state's update! persists both attributes atomically (this runs
        # inside the caller's with_lock transaction, so an audit failure
        # rolls the stamp back with the state). The event is normalized
        # with #to_s at this boundary — this file's doctrine wherever input
        # meets the lifecycle (cf. the #to_sym normalization in
        # transition_state! and #role): a caller passing "publish" as a
        # String must stamp exactly like the symbol, otherwise the edge
        # would resolve and only the stamp would silently be skipped.
        def stamp_published_at!
          contract.published_at = Time.current if event.to_s == "publish"
        end

        # The D4-payload audit row: written inside the caller's transaction,
        # so its failure rolls the state change back with it.
        def record_audit!
          AuditEvent.create!(action: "contract.#{event}", target: contract,
                             organization: contract.organization, actor: user)
        end

        # The single engine role that may fire this event from the record's
        # current state, or nil when the user's roles intersect no edge.
        # Rails enum getters return Strings while ContractLifecycle is keyed
        # on Symbols — normalize both the state and the event at this
        # boundary (same as the Permissions class), so a String event
        # resolves its edge instead of silently missing it and leaving the
        # stamp behind.
        def role
          state = contract.state&.to_sym
          roles = Array(Decidim::ContractsSk.role_resolver.call(user, {})) & ContractLifecycle::ROLES

          (ContractLifecycle.allowed_roles(from: state, event: event&.to_sym) & roles).first
        end
      end
    end
  end
end
