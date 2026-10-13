# frozen_string_literal: true

module Decidim
  module ContractsSk
    # Where a contract is in the editorial process, as the five steps a
    # municipal clerk thinks in: Draft, Check, Approved, Published, Filed in
    # the CRZ. A read-only view over the lifecycle state and the CRZ filing
    # stamp; it decides nothing (permissions and transitions stay with the
    # lifecycle and the permission layer).
    #
    #   draft, returned -> step 1 (a returned draft is flagged, not a new step)
    #   in_review       -> step 2
    #   approved        -> step 3
    #   published       -> step 4, or all done once the CRZ filing is confirmed
    #   archived        -> as published (the record is closed)
    #   rejected        -> stopped at step 2
    #
    # CRZ mirrors (imported records) never ran through the process, so they
    # have no progress (+applicable?+ is false).
    class ContractProgress
      STEPS = %i[draft review approved published filed].freeze

      Step = Struct.new(:key, :status, keyword_init: true)

      def initialize(contract)
        @contract = contract
      end

      def applicable?
        @contract.source.to_s != CrzImport::Mapper::SOURCE
      end

      def steps
        STEPS.each_with_index.map { |key, index| Step.new(key: key, status: status_at(index)) }
      end

      # Locale key of the "what happens next" sentence.
      def next_key
        return :filed if filed? && %i[published archived].include?(state)
        return :published if state == :published

        state
      end

      def returned?
        state == :returned
      end

      def rejected?
        state == :rejected
      end

      private

      def state
        @contract.state.to_sym
      end

      def filed?
        @contract.crz_filed_at.present?
      end

      # The step a record in each state is on (published and archived depend
      # on the CRZ filing, see #current_index).
      STEP_OF_STATE = { draft: 0, returned: 0, in_review: 1, rejected: 1, approved: 2 }.freeze

      # Index of the step the record is on; STEPS.size when everything is done.
      def current_index
        return STEP_OF_STATE.fetch(state) if STEP_OF_STATE.key?(state)
        return STEPS.size if filed?

        state == :published ? 3 : 4
      end

      def status_at(index)
        return :stopped if rejected? && index == 1
        return :done if index < current_index
        return :current if index == current_index && !closed?

        :upcoming
      end

      # An archived record is closed: nothing is "current" any more.
      def closed?
        state == :archived || rejected?
      end
    end
  end
end
