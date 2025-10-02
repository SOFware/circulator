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

        assert_match(/state pending/, result)
        assert_match(/state approved/, result)
        assert_match(/state rejected/, result)
      end

      it "includes all transitions with action labels" do
        plantuml = Circulator::PlantUml.new(Sampler)
        result = plantuml.generate

        assert_match(/pending --> approved : approve/, result)
        assert_match(/approved --> archived : archive/, result)
      end

      it "handles nil state transitions" do
        plantuml = Circulator::PlantUml.new(Sampler)
        result = plantuml.generate

        assert_match(/\[\*\]/, result)
        assert_match(/\[\*\] --> in_progress : start/, result)
      end

      it "handles multiple flows on same model" do
        plantuml = Circulator::PlantUml.new(Sampler)
        result = plantuml.generate

        # Should include states from both flows
        assert_match(/pending/, result)
        assert_match(/normal/, result)
        assert_match(/approved/, result)
      end

      it "handles conditional transitions with allow_if" do
        plantuml = Circulator::PlantUml.new(Sampler)
        result = plantuml.generate

        assert_match(/rejected --> pending : reconsider/, result)
        assert_match(/note on link/, result)
        assert_match(/conditional/, result)
      end

      it "handles dynamic state determination with callable to:" do
        plantuml = Circulator::PlantUml.new(Sampler)
        result = plantuml.generate

        assert_match(/normal --> \[\*\] : escalate/, result)
        assert_match(/note on link/, result)
        assert_match(/dynamic/, result)
      end

      it "handles multiple from states for one action" do
        plantuml = Circulator::PlantUml.new(Sampler)
        result = plantuml.generate

        assert_match(/in_progress --> failed : fail/, result)
        assert_match(/completed --> failed : fail/, result)
      end

      it "handles model-based flows" do
        plantuml = Circulator::PlantUml.new(SamplerManager)
        result = plantuml.generate

        assert_match(/pending --> in_progress/, result)
      end

      it "generates complete valid PlantUML structure" do
        plantuml = Circulator::PlantUml.new(Sampler)
        result = plantuml.generate

        # Verify structure
        assert_match(/@startuml/, result)
        assert_match(/state pending/, result)
        assert_match(/state approved/, result)
        assert_match(/pending --> approved : approve/, result)
        assert_match(/@enduml/, result)
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
        assert_match(/completed --> \[\*\]/, result)
      end

      it "covers non-callable to state without allow_if" do
        plantuml = Circulator::PlantUml.new(Sampler)
        result = plantuml.generate

        # Should not have notes for simple transitions
        assert_match(/pending --> approved : approve/, result)
        lines = result.split("\n")
        transition_line_index = lines.index { |l| l.include?("pending --> approved") }
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
