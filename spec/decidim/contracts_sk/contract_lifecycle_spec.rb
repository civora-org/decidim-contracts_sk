# frozen_string_literal: true

require "spec_helper"

# This suite is an exhaustive contract test: several examples deliberately
# walk the full state x event x role matrix, so they intentionally hold many
# expectations and exceed the default example-length budget.
# rubocop:disable RSpec/MultipleExpectations, RSpec/ExampleLength

# The documented transition table (docs/contract-lifecycle.md, rows 2-8).
# Row 1 (`create`) is realized as INITIAL_STATE, not a machine event, so it
# deliberately has no edge here.
EXPECTED_EDGES = [
  { from: :draft, event: :submit, to: :in_review, roles: %i[editor].freeze },
  { from: :in_review, event: :return, to: :returned, roles: %i[reviewer].freeze },
  { from: :in_review, event: :approve, to: :approved, roles: %i[reviewer].freeze },
  { from: :in_review, event: :reject, to: :rejected, roles: %i[reviewer].freeze },
  { from: :returned, event: :submit, to: :in_review, roles: %i[editor].freeze },
  { from: :approved, event: :publish, to: :published, roles: %i[editor].freeze },
  { from: :published, event: :archive, to: :archived, roles: %i[editor].freeze }
].map(&:freeze).freeze

RSpec.describe Decidim::ContractsSk::ContractLifecycle do
  subject(:lifecycle) { described_class }

  let(:roles) { described_class::ROLES }
  let(:foreign_roles) { %i[visitor] }

  def all_events
    lifecycle::TRANSITIONS.values.flat_map(&:keys).uniq.sort
  end

  def valid_edges
    lifecycle::TRANSITIONS.flat_map do |from, edges|
      edges.map { |event, edge| { from: from, event: event, to: edge[:to], roles: edge[:roles] } }
    end
  end

  describe "constants" do
    it "defines the exact state list" do
      expect(lifecycle::STATES).to eq(%i[draft in_review returned approved rejected published archived])
    end

    it "defines draft as the initial state" do
      expect(lifecycle::INITIAL_STATE).to eq(:draft)
    end

    it "pins terminal states exactly" do
      expect(lifecycle::TERMINAL_STATES).to eq(%i[rejected archived])
    end

    it "does not make the initial state terminal" do
      expect(lifecycle::TERMINAL_STATES).not_to include(lifecycle::INITIAL_STATE)
    end

    it "defines editable states as draft and returned" do
      expect(lifecycle::EDITABLE_STATES).to eq(%i[draft returned])
    end

    it "defines public states as published and archived" do
      expect(lifecycle::PUBLIC_STATES).to eq(%i[published archived])
    end

    it "defines exactly the editor and reviewer roles" do
      expect(lifecycle::ROLES).to eq(%i[editor reviewer])
    end
  end

  describe "freezing" do
    %i[STATES TERMINAL_STATES EDITABLE_STATES PUBLIC_STATES ROLES].each do |const|
      it "deep-freezes #{const}" do
        expect(lifecycle.const_get(const)).to be_frozen
      end
    end

    it "deep-freezes TRANSITIONS including nested hashes, edge hashes and role arrays" do
      expect(lifecycle::TRANSITIONS).to be_frozen
      lifecycle::TRANSITIONS.each_value do |edges|
        expect(edges).to be_frozen
        edges.each_value do |edge|
          expect(edge).to be_frozen
          expect(edge[:roles]).to be_frozen
        end
      end
    end
  end

  describe "documented table pin" do
    it "matches the documented transition table exactly (docs/contract-lifecycle.md rows 2-8)" do
      expect(valid_edges).to eq(EXPECTED_EDGES)
    end

    it "keeps every reviewer-granted edge a judgment gate out of :in_review" do
      reviewer_edges = EXPECTED_EDGES.select { |edge| edge[:roles].include?(:reviewer) }

      expect(reviewer_edges.map { |edge| edge[:from] }).to all(eq(:in_review))
      expect(reviewer_edges.map { |edge| edge[:to] }).to match_array(%i[returned approved rejected])
    end

    it "grants no editor edge out of :in_review" do
      editor_edges = EXPECTED_EDGES.select { |edge| edge[:roles].include?(:editor) }

      expect(editor_edges.map { |edge| edge[:from] }).not_to include(:in_review)
    end
  end

  describe "table referential integrity" do
    it "has an entry for every state" do
      expect(lifecycle::TRANSITIONS.keys).to match_array(lifecycle::STATES)
    end

    it "only targets known states" do
      valid_edges.each { |edge| expect(lifecycle::STATES).to include(edge[:to]) }
    end

    it "only grants known roles" do
      valid_edges.each do |edge|
        expect(edge[:roles]).not_to be_empty
        expect(lifecycle::ROLES).to include(*edge[:roles])
      end
    end
  end

  describe "exhaustive transition matrix" do
    it "allows exactly the table edges, with exactly the table roles" do
      lifecycle::STATES.product(all_events).each do |from, event|
        edge = valid_edges.find { |e| e[:from] == from && e[:event] == event }

        roles.each do |role|
          if edge
            expect(lifecycle.transition_allowed?(from: from, event: event, role: role))
              .to eq(edge[:roles].include?(role)),
                  "expected #{from} --#{event}(#{role})--> to be #{edge[:roles].include?(role)}"
          else
            expect(lifecycle.transition_allowed?(from: from, event: event, role: role))
              .to be(false), "unexpected edge #{from} --#{event}(#{role})-->"
          end
        end

        foreign_roles.each do |role|
          next unless edge

          expect(lifecycle.transition_allowed?(from: from, event: event, role: role))
            .to be(false), "foreign role #{role} must never be allowed on #{from} --#{event}-->"
        end
      end
    end
  end

  describe "terminality" do
    described_class::TERMINAL_STATES.each do |state|
      it "offers no events from #{state}" do
        expect(lifecycle.events_from(state)).to eq([])
      end

      it "rejects every event from #{state}" do
        all_events.each do |event|
          roles.each do |role|
            expect(lifecycle.transition_allowed?(from: state, event: event, role: role)).to be(false)
          end
        end
      end
    end
  end

  describe ".terminal?" do
    it "is true for rejected and archived" do
      expect(lifecycle.terminal?(:rejected)).to be(true)
      expect(lifecycle.terminal?(:archived)).to be(true)
    end

    it "is false for draft" do
      expect(lifecycle.terminal?(:draft)).to be(false)
    end

    it "is false for unknown states" do
      expect(lifecycle.terminal?(:bogus)).to be(false)
    end
  end

  describe "fail-closed predicates" do
    %i[terminal? editable? publicly_visible?].each do |predicate|
      [nil, :bogus].each do |input|
        it "#{predicate} returns false without raising for #{input.inspect}" do
          expect(lifecycle.public_send(predicate, input)).to be(false)
        end
      end
    end
  end

  describe ".state?" do
    it "is true for known states" do
      lifecycle::STATES.each { |state| expect(lifecycle.state?(state)).to be(true) }
    end

    it "fails closed for unknown input" do
      expect(lifecycle.state?(:bogus)).to be(false)
      expect(lifecycle.state?(nil)).to be(false)
    end
  end

  describe ".editable?" do
    it "is true exactly for draft and returned" do
      lifecycle::STATES.each do |state|
        expect(lifecycle.editable?(state)).to eq(%i[draft returned].include?(state))
      end
    end

    it "locks in_review" do
      expect(lifecycle.editable?(:in_review)).to be(false)
    end
  end

  describe ".publicly_visible?" do
    it "is true exactly for published and archived" do
      lifecycle::STATES.each do |state|
        expect(lifecycle.publicly_visible?(state)).to eq(%i[published archived].include?(state))
      end
    end
  end

  describe ".events_from" do
    it "lists sorted events per state" do
      expect(lifecycle.events_from(:in_review)).to eq(%i[approve reject return])
      expect(lifecycle.events_from(:draft)).to eq([:submit])
    end

    it "fails closed for unknown states" do
      expect(lifecycle.events_from(:bogus)).to eq([])
    end

    it "returns frozen arrays" do
      expect(lifecycle.events_from(:draft)).to be_frozen
      expect(lifecycle.events_from(:bogus)).to be_frozen
    end
  end

  describe ".allowed_roles" do
    it "returns the roles of the edge" do
      expect(lifecycle.allowed_roles(from: :draft, event: :submit)).to eq(%i[editor])
      expect(lifecycle.allowed_roles(from: :in_review, event: :approve)).to eq(%i[reviewer])
    end

    it "returns empty for non-existent edges" do
      expect(lifecycle.allowed_roles(from: :draft, event: :archive)).to eq([])
    end
  end

  describe ".next_state" do
    it "returns the target state" do
      expect(lifecycle.next_state(from: :approved, event: :publish)).to eq(:published)
    end

    it "returns nil for non-existent edges" do
      expect(lifecycle.next_state(from: :rejected, event: :submit)).to be_nil
      expect(lifecycle.next_state(from: :bogus, event: :submit)).to be_nil
    end
  end

  describe "error class" do
    it "specializes the engine base error" do
      expect(described_class::InvalidTransitionError).to be < Decidim::ContractsSk::Error
    end
  end

  describe ".transition!" do
    it "returns the target state on every valid edge" do
      valid_edges.each do |edge|
        edge[:roles].each do |role|
          expect(lifecycle.transition!(from: edge[:from], event: edge[:event], role: role))
            .to eq(edge[:to])
        end
      end
    end

    it "raises InvalidTransitionError with context on unknown event" do
      expect { lifecycle.transition!(from: :draft, event: :bogus, role: :editor) }
        .to raise_error(described_class::InvalidTransitionError,
                        /Invalid transition: :bogus from :draft by :editor/)
    end

    it "raises InvalidTransitionError on wrong role" do
      expect { lifecycle.transition!(from: :in_review, event: :approve, role: :editor) }
        .to raise_error(described_class::InvalidTransitionError)
    end

    it "raises InvalidTransitionError on unknown state" do
      expect { lifecycle.transition!(from: :bogus, event: :submit, role: :editor) }
        .to raise_error(described_class::InvalidTransitionError)
    end
  end

  describe "non-mutation" do
    it "leaves the table untouched after queries" do
      snapshot = Marshal.load(Marshal.dump(lifecycle::TRANSITIONS))

      lifecycle::STATES.product(all_events) do |from, event|
        lifecycle.events_from(from)
        lifecycle.allowed_roles(from: from, event: event)
        lifecycle.next_state(from: from, event: event)
        roles.each { |role| lifecycle.transition_allowed?(from: from, event: event, role: role) }
      end

      expect(lifecycle::TRANSITIONS).to eq(snapshot)
    end

    it "returns frozen results that cannot be mutated" do
      expect { lifecycle.allowed_roles(from: :draft, event: :submit) << :reviewer }
        .to raise_error(FrozenError)
    end
  end
end

# rubocop:enable RSpec/MultipleExpectations, RSpec/ExampleLength
