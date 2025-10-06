require "test_helper"
require_relative "../sampler"

class CirculatorPlantUmlTest < Minitest::Test
  describe "Circulator::PlantUml" do
    describe "#initialize" do
      it "accepts a model class that extends Circulator" do
        plantuml = Circulator::PlantUml.new(Sampler)
        assert_instance_of Circulator::PlantUml, plantuml
      end

      it "raises ArgumentError if class doesn't extend Circulator" do
        invalid_class = Class.new

        error = assert_raises(ArgumentError) do
          Circulator::PlantUml.new(invalid_class)
        end

        assert_match(/must extend Circulator/, error.message)
      end

      it "raises ArgumentError if class has no flows defined" do
        empty_class = Class.new do
          extend Circulator
        end

        error = assert_raises(ArgumentError) do
          Circulator::PlantUml.new(empty_class)
        end

        assert_match(/no flows defined/, error.message)
      end
    end

    describe "#generate" do
      it "returns a string" do
        plantuml = Circulator::PlantUml.new(Sampler)
        result = plantuml.generate

        assert_instance_of String, result
      end

      it "returns valid PlantUML format with @startuml and @enduml" do
        plantuml = Circulator::PlantUml.new(Sampler)
        result = plantuml.generate

        assert_match(/@startuml/, result)
        assert_match(/@enduml/, result)
      end

      it "includes all states" do
        plantuml = Circulator::PlantUml.new(Sampler)
        result = plantuml.generate

        # With multi-flow grouping, states are prefixed
        assert_match(/state "pending" as status_pending/, result)
        assert_match(/state "approved" as status_approved/, result)
        assert_match(/state "rejected" as status_rejected/, result)
      end

      it "includes all transitions with action labels" do
        plantuml = Circulator::PlantUml.new(Sampler)
        result = plantuml.generate

        # With multi-flow grouping, transitions use prefixed names
        assert_match(/status_pending --> status_approved : approve/, result)
        assert_match(/status_approved --> status_archived : archive/, result)
      end

      it "handles nil state transitions" do
        plantuml = Circulator::PlantUml.new(Sampler)
        result = plantuml.generate

        assert_match(/\[\*\]/, result)
        assert_match(/\[\*\] --> workflow_state_in_progress : start/, result)
      end

      it "handles multiple flows on same model" do
        plantuml = Circulator::PlantUml.new(Sampler)
        result = plantuml.generate

        # Should include states from both flows
        assert_match(/pending/, result)
        assert_match(/normal/, result)
        assert_match(/approved/, result)
      end

      it "groups multiple flows into composite states with labels" do
        plantuml = Circulator::PlantUml.new(Sampler)
        result = plantuml.generate

        # Should have composite states for each flow attribute
        assert_match(/state ":status" as status_group \{/, result)
        assert_match(/state ":priority" as priority_group \{/, result)
        assert_match(/state ":workflow_state" as workflow_state_group \{/, result)
        assert_match(/state ":processing_state" as processing_state_group \{/, result)
      end

      it "prefixes state names with attribute in multi-flow diagrams" do
        plantuml = Circulator::PlantUml.new(Sampler)
        result = plantuml.generate

        # States should be defined with attribute prefixes
        assert_match(/state "pending" as status_pending/, result)
        assert_match(/state "normal" as priority_normal/, result)
        assert_match(/state "in_progress" as workflow_state_in_progress/, result)
        assert_match(/state "idle" as processing_state_idle/, result)
        # Special characters like ? are replaced with safe identifiers
        assert_match(/state "\?" as priority_unknown/, result)
      end

      it "uses prefixed state names in transitions for multi-flow diagrams" do
        plantuml = Circulator::PlantUml.new(Sampler)
        result = plantuml.generate

        # Transitions should use prefixed state names
        assert_match(/status_pending --> status_approved/, result)
        # Special characters like ? are replaced with safe identifiers
        assert_match(/priority_normal --> priority_unknown/, result)
        assert_match(/workflow_state_in_progress --> workflow_state_completed/, result)
      end

      it "handles conditional transitions with allow_if" do
        plantuml = Circulator::PlantUml.new(Sampler)
        result = plantuml.generate

        assert_match(/status_rejected --> status_pending : reconsider/, result)
        assert_match(/note on link/, result)
        assert_match(/conditional/, result)
      end

      it "handles dynamic state determination with callable to:" do
        plantuml = Circulator::PlantUml.new(Sampler)
        result = plantuml.generate

        # Special characters like ? are replaced with safe identifiers
        assert_match(/priority_normal --> priority_unknown : escalate/, result)
        assert_match(/note on link/, result)
        assert_match(/dynamic/, result)
      end

      it "handles multiple from states for one action" do
        plantuml = Circulator::PlantUml.new(Sampler)
        result = plantuml.generate

        assert_match(/workflow_state_in_progress --> workflow_state_failed : fail/, result)
        assert_match(/workflow_state_completed --> workflow_state_failed : fail/, result)
      end

      it "handles model-based flows" do
        plantuml = Circulator::PlantUml.new(SamplerManager)
        result = plantuml.generate

        # SamplerManager has 2 flows, so they should be prefixed
        assert_match(/status_pending --> status_in_progress/, result)
      end

      it "generates complete valid PlantUML structure" do
        plantuml = Circulator::PlantUml.new(Sampler)
        result = plantuml.generate

        # Verify structure
        assert_match(/@startuml/, result)
        assert_match(/state "pending" as status_pending/, result)
        assert_match(/state "approved" as status_approved/, result)
        assert_match(/status_pending --> status_approved : approve/, result)
        assert_match(/@enduml/, result)
      end
    end

    describe "#generate_separate" do
      it "returns a hash with one entry per flow attribute" do
        plantuml = Circulator::PlantUml.new(Sampler)
        result = plantuml.generate_separate

        assert_instance_of Hash, result
        assert_equal 4, result.size
        assert result.key?(:status)
        assert result.key?(:priority)
        assert result.key?(:workflow_state)
        assert result.key?(:processing_state)
      end

      it "generates valid PlantUML diagram for each flow" do
        plantuml = Circulator::PlantUml.new(Sampler)
        result = plantuml.generate_separate

        result.each do |attribute_name, content|
          assert_match(/@startuml/, content)
          assert_match(/@enduml/, content)
          assert_match(/#{attribute_name} flow/, content)
        end
      end

      it "includes only states from that specific flow in each diagram" do
        plantuml = Circulator::PlantUml.new(Sampler)
        result = plantuml.generate_separate

        # Status flow should have status states but not priority states
        assert_match(/state pending/, result[:status])
        assert_match(/state approved/, result[:status])
        refute_match(/state normal/, result[:status])
        refute_match(/state critical/, result[:status])

        # Priority flow should have priority states but not status states
        assert_match(/state normal/, result[:priority])
        assert_match(/state critical/, result[:priority])
        refute_match(/state pending/, result[:priority])
        refute_match(/state approved/, result[:priority])
      end

      it "does not use prefixed state names in separate diagrams" do
        plantuml = Circulator::PlantUml.new(Sampler)
        result = plantuml.generate_separate

        # Separate diagrams should use clean state names without prefixes
        assert_match(/state pending/, result[:status])
        assert_match(/pending --> approved : approve/, result[:status])
        refute_match(/status_pending/, result[:status])
      end
    end

    describe "branch coverage" do
      it "covers nil state in state declaration" do
        plantuml = Circulator::PlantUml.new(Sampler)
        result = plantuml.generate

        # nil state should be represented as [*]
        assert_match(/\[\*\]/, result)
      end

      it "covers nil to_state in transition" do
        plantuml = Circulator::PlantUml.new(Sampler)
        result = plantuml.generate

        # Transition to nil should show [*]
        assert_match(/workflow_state_completed --> \[\*\]/, result)
      end

      it "covers non-callable to state without allow_if" do
        plantuml = Circulator::PlantUml.new(Sampler)
        result = plantuml.generate

        # Should not have notes for simple transitions
        assert_match(/status_pending --> status_approved : approve/, result)
        lines = result.split("\n")
        transition_line_index = lines.index { |l| l.include?("status_pending --> status_approved") }
        next_line = lines[transition_line_index + 1]
        refute_match(/note on link/, next_line) if next_line
      end

      it "covers flows.empty? branch in initialize" do
        error = assert_raises(ArgumentError) do
          Circulator::PlantUml.new(EmptyFlowsSampler)
        end

        assert_match(/no flows defined/, error.message)
      end
    end
  end
end
