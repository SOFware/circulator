require "test_helper"
require_relative "../sampler"

class CirculatorDotTest < Minitest::Test
  describe "Circulator::Dot" do
    describe "#initialize" do
      it "accepts a model class that extends Circulator" do
        dot = Circulator::Dot.new(Sampler)
        assert_instance_of Circulator::Dot, dot
      end

      it "raises ArgumentError if class doesn't extend Circulator" do
        invalid_class = Class.new

        error = assert_raises(ArgumentError) do
          Circulator::Dot.new(invalid_class)
        end

        assert_match(/must extend Circulator/, error.message)
      end

      it "raises ArgumentError if class has no flows defined" do
        empty_class = Class.new do
          extend Circulator
        end

        error = assert_raises(ArgumentError) do
          Circulator::Dot.new(empty_class)
        end

        assert_match(/no flows defined/, error.message)
      end
    end

    describe "#generate" do
      it "returns a string" do
        dot = Circulator::Dot.new(Sampler)
        result = dot.generate

        assert_instance_of String, result
      end

      it "returns valid DOT format with digraph declaration" do
        dot = Circulator::Dot.new(Sampler)
        result = dot.generate

        assert_match(/digraph .+ \{/, result)
        assert_match(/\}/, result)
        assert_match(/rankdir=LR/, result)
      end

      it "includes all states as nodes" do
        dot = Circulator::Dot.new(Sampler)
        result = dot.generate

        assert_match(/pending/, result)
        assert_match(/approved/, result)
        assert_match(/rejected/, result)
      end

      it "includes all actions as edges with labels" do
        dot = Circulator::Dot.new(Sampler)
        result = dot.generate

        assert_match(/pending -> approved/, result)
        assert_match(/label="approve"/, result)
        assert_match(/approved -> published/, result)
        assert_match(/label="publish"/, result)
      end

      it "handles nil state transitions" do
        dot = Circulator::Dot.new(Sampler)
        result = dot.generate

        # Sampler has workflow_state flow with from: nil transitions
        assert_match(/nil/, result)
        assert_match(/nil -> in_progress/, result)
        assert_match(/label="start"/, result)
      end

      it "handles multiple flows on same model" do
        dot = Circulator::Dot.new(Sampler)
        result = dot.generate

        # Should include states from multiple flows (status, priority, workflow_state, processing_state)
        assert_match(/pending/, result)
        assert_match(/normal/, result)
        assert_match(/in_progress/, result)
        assert_match(/idle/, result)
      end

      it "handles conditional transitions with allow_if" do
        dot = Circulator::Dot.new(Sampler)
        result = dot.generate

        # Sampler has rejected -> pending transition with allow_if
        assert_match(/rejected -> pending/, result)
        assert_match(/label="reconsider \(conditional\)"/, result)
      end

      it "handles dynamic state determination with callable to:" do
        dot = Circulator::Dot.new(Sampler)
        result = dot.generate

        # Sampler has priority flow with callable to: options
        assert_match(/normal -> \?/, result)
        assert_match(/label="escalate \(dynamic\)"/, result)
      end

      it "handles multiple from states for one action" do
        dot = Circulator::Dot.new(Sampler)
        result = dot.generate

        # Sampler workflow_state has fail action from: [:in_progress, :completed]
        assert_match(/in_progress -> failed/, result)
        assert_match(/completed -> failed/, result)
        assert_match(/label="fail"/, result)
      end

      it "handles model-based flows" do
        dot = Circulator::Dot.new(SamplerManager)
        result = dot.generate

        assert_match(/SamplerTask/, result)
        assert_match(/pending -> in_progress/, result)
      end

      it "generates complete valid DOT graph structure" do
        dot = Circulator::Dot.new(Sampler)
        result = dot.generate

        # Verify structure
        assert_match(/^digraph/, result)
        assert_match(/rankdir=LR;/, result)
        assert_match(/pending \[shape=\w+\];/, result)
        assert_match(/approved \[shape=\w+\];/, result)
        assert_match(/pending -> approved \[label="approve"\];/, result)
        assert result.end_with?("}\n")
      end
    end

    describe "branch coverage" do
      it "covers anonymous class name branch in graph_name" do
        # Create anonymous class (no name)
        model_class = Class.new do
          extend Circulator

          attr_accessor :status

          circulator :status do
            state :pending do
              action :approve, to: :approved
            end
          end
        end

        dot = Circulator::Dot.new(model_class)
        result = dot.generate

        # Should use anonymous_XXX format when class has no name
        assert_match(/digraph anonymous_[0-9a-f]+_flows/, result)
      end

      it "covers model_key different from class_name branch in graph_name" do
        dot = Circulator::Dot.new(SamplerManager)
        result = dot.generate

        # Should use model key (SamplerTask) for the model-based flow
        assert_match(/SamplerTask_flows/, result)
      end

      it "covers nil state in state node output" do
        dot = Circulator::Dot.new(Sampler)
        result = dot.generate

        # Should output "nil" for nil state
        assert_match(/nil \[shape=circle\];/, result)
      end

      it "covers nil from_state in transition output" do
        dot = Circulator::Dot.new(Sampler)
        result = dot.generate

        # Should output "nil" as from state in transition
        assert_match(/nil -> in_progress/, result)
      end

      it "covers nil to_state in transition output" do
        dot = Circulator::Dot.new(Sampler)
        result = dot.generate

        # Should output "nil" as to state in transition (reset action)
        assert_match(/completed -> nil/, result)
      end

      it "covers non-callable to state without allow_if" do
        dot = Circulator::Dot.new(Sampler)
        result = dot.generate

        # Label should be just the action name without "(conditional)" for most transitions
        assert_match(/pending -> approved \[label="approve"\];/, result)
        assert_match(/approved -> published \[label="publish"\];/, result)
      end

      it "covers flows.empty? branch in initialize" do
        error = assert_raises(ArgumentError) do
          Circulator::Dot.new(EmptyFlowsSampler)
        end

        assert_match(/no flows defined/, error.message)
      end
    end
  end
end
