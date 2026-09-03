# frozen_string_literal: true

# ---------------------------------------------------------------------------
# Deterministic, offline behavioural specs for the ContractState concern
# (M02-02-A, civora-org/civora-platform#55).
#
# The concern's contract is deliberately narrow — it relies only on a #state
# reader and #update! — so it is exercised here on a plain double: a minimal
# stand-in class (no ActiveRecord, no database) that applies attributes and
# records every update! call, letting the specs assert that illegal
# transitions mutate nothing at all.
#
# The expected edges below are derived from ContractLifecycle::TRANSITIONS,
# keeping this spec aligned with the single source of truth by construction.
# ---------------------------------------------------------------------------

require "spec_helper"

require "active_support/concern"

# Several examples deliberately walk the full edge x role matrix and hold
# several related expectations, exceeding the default budgets.
# rubocop:disable RSpec/MultipleExpectations, RSpec/ExampleLength

RSpec.describe Decidim::ContractsSk::ContractState do
  let(:lifecycle) { Decidim::ContractsSk::ContractLifecycle }
  let(:error) { Decidim::ContractsSk::ContractLifecycle::InvalidTransitionError }

  # Plain double standing in for a state-bearing record: a #state reader,
  # a recording #update!, nothing else the concern could lean on.
  let(:model_class) do
    Class.new do
      include Decidim::ContractsSk::ContractState

      attr_reader :state, :updates

      def initialize(state: nil)
        @state = state
        @updates = []
      end

      # Stand-in for ActiveRecord's #update!: records the call, then applies
      # the attributes so specs can assert exactly what mutated.
      def update!(**attributes)
        @updates << attributes
        attributes.each { |name, value| instance_variable_set(:"@#{name}", value) }
        true
      end
    end
  end

  let(:edges) do
    lifecycle::TRANSITIONS.flat_map do |from, table_edges|
      table_edges.map { |event, edge| { from: from, event: event, to: edge[:to], roles: edge[:roles] } }
    end
  end

  describe "TRANSITION_EVENTS" do
    it "is derived from the lifecycle transition table, never hand-enumerated" do
      expect(described_class::TRANSITION_EVENTS)
        .to eq(lifecycle::TRANSITIONS.values.flat_map(&:keys).uniq.sort)
    end

    it "pins the exact event vocabulary" do
      expect(described_class::TRANSITION_EVENTS).to eq(%i[approve archive publish reject return submit])
    end

    it "is frozen" do
      expect(described_class::TRANSITION_EVENTS).to be_frozen
    end

    it "generates one convenience method per event" do
      described_class::TRANSITION_EVENTS.each do |event|
        expect(model_class.new).to respond_to(:"#{event}!")
      end
    end

    it "stays disjoint from state names, so enum bang setters can never shadow the conveniences" do
      # On the Contract model the Rails enum also defines a `<state>!` setter
      # per state. A state/event name collision would make the two method
      # families fight over one name (whichever is defined last wins).
      state_bangs = lifecycle::STATES.map { |state| :"#{state}!" }

      expect(described_class::TRANSITION_EVENTS & state_bangs).to be_empty
    end
  end

  describe "#transition_state!" do
    it "calls update! once with the table target and returns self on every edge x allowed role" do
      edges.each do |edge|
        edge[:roles].each do |role|
          record = model_class.new(state: edge[:from].to_s)

          expect(record.transition_state!(event: edge[:event], role: role)).to equal(record)
          expect(record.updates).to eq([{ state: edge[:to] }]),
                                    "#{edge[:from]} --#{edge[:event]}(#{role})--> must update! #{edge[:to]}"
          expect(record.state).to eq(edge[:to])
        end
      end
    end

    it "raises InvalidTransitionError and mutates nothing on illegal input" do
      # Every (edge, disallowed-role) pair, plus terminal, missing and
      # unknown states — each attempt stays tied to its own edge.
      illegal = edges.flat_map do |edge|
        (lifecycle::ROLES - edge[:roles]).map do |role|
          { state: edge[:from], event: edge[:event], role: role }
        end
      end

      illegal += [
        { state: :rejected, event: :submit, role: :editor },   # terminal
        { state: :archived, event: :publish, role: :editor },  # terminal
        { state: nil, event: :submit, role: :editor },         # missing state
        { state: :bogus, event: :submit, role: :editor }       # unknown state
      ]

      illegal.each do |attempt|
        record = model_class.new(state: attempt[:state])

        expect { record.transition_state!(event: attempt[:event], role: attempt[:role]) }
          .to raise_error(error), attempt.inspect
        expect(record.updates).to eq([]), "illegal transition must not call update!: #{attempt.inspect}"
        expect(record.state).to eq(attempt[:state]), "illegal transition must not mutate state: #{attempt.inspect}"
      end
    end

    it "coerces String state, event and role input to the table's symbols" do
      record = model_class.new(state: "draft")

      record.transition_state!(event: "submit", role: "editor")

      expect(record.updates).to eq([{ state: :in_review }])
    end
  end

  describe "per-event conveniences" do
    it "delegate to transition_state! on their allowed edges" do
      edges.each do |edge|
        edge[:roles].each do |role|
          record = model_class.new(state: edge[:from].to_s)

          record.public_send(:"#{edge[:event]}!", by_role: role)

          expect(record.updates).to eq([{ state: edge[:to] }]),
                                    "##{edge[:event]}! must behave like transition_state! on #{edge[:from]} as #{role}"
        end
      end
    end
  end

  describe "#can_transition?" do
    it "is true exactly where the lifecycle table allows the edge" do
      lifecycle::STATES.product(lifecycle::TRANSITIONS.values.flat_map(&:keys).uniq, lifecycle::ROLES)
                       .each do |state, event, role|
        expected = lifecycle.transition_allowed?(from: state, event: event, role: role)

        expect(model_class.new(state: state).can_transition?(event: event, role: role))
          .to eq(expected), "#{state} --#{event}(#{role})-->"
      end
    end

    it "is false — without raising — for illegal roles, events, terminal and nil states" do
      [
        { state: :draft, event: :submit, role: :reviewer },
        { state: :draft, event: :archive, role: :editor },
        { state: :rejected, event: :submit, role: :editor },
        { state: nil, event: :submit, role: :editor },
        { state: :bogus, event: :submit, role: :editor }
      ].each do |attempt|
        expect(model_class.new(state: attempt[:state]).can_transition?(event: attempt[:event], role: attempt[:role]))
          .to be(false), attempt.inspect
      end
    end
  end

  describe "#allowed_events_for" do
    {
      draft: { editor: [:submit], reviewer: [] },
      in_review: { editor: [], reviewer: %i[approve reject return] },
      returned: { editor: [:submit], reviewer: [] },
      approved: { editor: [:publish], reviewer: [] },
      published: { editor: [:archive], reviewer: [] },
      rejected: { editor: [], reviewer: [] },
      archived: { editor: [], reviewer: [] }
    }.each do |state, expectations_per_role|
      expectations_per_role.each do |role, expected|
        it "lists #{expected.inspect} for #{state} x #{role}" do
          expect(model_class.new(state: state).allowed_events_for(role: role)).to eq(expected)
        end
      end
    end

    it "fails closed for a missing state and foreign roles" do
      expect(model_class.new.allowed_events_for(role: :editor)).to eq([])
      expect(model_class.new(state: :draft).allowed_events_for(role: :visitor)).to eq([])
    end

    it "returns frozen results" do
      expect(model_class.new(state: :draft).allowed_events_for(role: :editor)).to be_frozen
      expect(model_class.new.allowed_events_for(role: :editor)).to be_frozen
    end
  end

  describe "predicates" do
    Decidim::ContractsSk::ContractLifecycle::STATES.each do |state|
      it "reports #{state} exactly as the lifecycle does" do
        record = model_class.new(state: state)

        expect(record.terminal?).to eq(lifecycle::TERMINAL_STATES.include?(state))
        expect(record.editable?).to eq(lifecycle::EDITABLE_STATES.include?(state))
        expect(record.publicly_visible?).to eq(lifecycle::PUBLIC_STATES.include?(state))
      end
    end

    it "fail closed for nil and unknown states" do
      [nil, :bogus].each do |state|
        record = model_class.new(state: state)

        expect(record.terminal?).to be(false)
        expect(record.editable?).to be(false)
        expect(record.publicly_visible?).to be(false)
      end
    end

    it "accept String states via to_sym coercion" do
      expect(model_class.new(state: "draft").editable?).to be(true)
      expect(model_class.new(state: "published").publicly_visible?).to be(true)
    end
  end
end

# rubocop:enable RSpec/MultipleExpectations, RSpec/ExampleLength
