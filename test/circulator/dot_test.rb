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

        # With multi-flow grouping, states are prefixed
        assert_match(/status_pending/, result)
        assert_match(/status_approved/, result)
        assert_match(/status_rejected/, result)
      end

      it "includes all actions as edges with labels" do
        dot = Circulator::Dot.new(Sampler)
        result = dot.generate

        # With multi-flow grouping, transitions use prefixed names
        assert_match(/status_pending -> status_approved/, result)
        assert_match(/label="approve"/, result)
        assert_match(/status_approved -> status_published/, result)
        assert_match(/label="publish"/, result)
      end

      it "handles nil state transitions" do
        dot = Circulator::Dot.new(Sampler)
        result = dot.generate

        # Sampler has workflow_state flow with from: nil transitions
        assert_match(/workflow_state_nil/, result)
        assert_match(/workflow_state_nil -> workflow_state_in_progress/, result)
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

      it "groups multiple flows into subgraph clusters with labels" do
        dot = Circulator::Dot.new(Sampler)
        result = dot.generate

        # Should have subgraph clusters for each flow attribute
        assert_match(/subgraph cluster_0 \{/, result)
        assert_match(/label=":status"/, result)
        assert_match(/subgraph cluster_1 \{/, result)
        assert_match(/label=":priority"/, result)
        assert_match(/subgraph cluster_2 \{/, result)
        assert_match(/label=":workflow_state"/, result)
        assert_match(/subgraph cluster_3 \{/, result)
        assert_match(/label=":processing_state"/, result)
      end

      it "prefixes state names with attribute in multi-flow diagrams" do
        dot = Circulator::Dot.new(Sampler)
        result = dot.generate

        # States should be prefixed with their attribute name
        assert_match(/status_pending/, result)
        assert_match(/priority_normal/, result)
        assert_match(/workflow_state_in_progress/, result)
        assert_match(/processing_state_idle/, result)
      end

      it "uses prefixed state names in transitions for multi-flow diagrams" do
        dot = Circulator::Dot.new(Sampler)
        result = dot.generate

        # Transitions should use prefixed state names
        assert_match(/status_pending -> status_approved/, result)
        assert_match(/priority_normal -> "priority_\?"/, result)
        assert_match(/workflow_state_nil -> workflow_state_in_progress/, result)
      end

      it "handles conditional transitions with allow_if Proc" do
        dot = Circulator::Dot.new(Sampler)
        result = dot.generate

        # Sampler has rejected -> pending transition with allow_if Proc
        assert_match(/status_rejected -> status_pending/, result)
        assert_match(/label="reconsider \(conditional\)"/, result)
      end

      it "handles conditional transitions with allow_if Hash" do
        dot = Circulator::Dot.new(NestedDependencySampler)
        result = dot.generate

        # NestedDependencySampler has publish with allow_if: {review_status: [:approved, :final]}
        assert_match(/document_status_submitted -> document_status_published/, result)
        assert_match(/label="publish \(review_status: approved, final\)"/, result)
      end

      it "handles conditional transitions with allow_if Symbol" do
        dot = Circulator::Dot.new(ConditionalSampler)
        result = dot.generate

        # ConditionalSampler has approve with allow_if: :can_approve?
        assert_match(/pending -> approved/, result)
        assert_match(/label="approve \(can_approve\?\)"/, result)
      end

      it "handles conditional transitions with allow_if Array of Symbols" do
        dot = Circulator::Dot.new(ConditionalSampler)
        result = dot.generate

        # ConditionalSampler has force_approve with allow_if: [:can_approve?, :is_admin?]
        assert_match(/label="force_approve \(can_approve\?, is_admin\?\)"/, result)
      end

      it "handles conditional transitions with allow_if Array with Proc" do
        dot = Circulator::Dot.new(ConditionalSampler)
        result = dot.generate

        # ConditionalSampler has custom_approve with allow_if: [:can_approve?, -> { true }]
        assert_match(/label="custom_approve \(can_approve\?, conditional\)"/, result)
      end

      it "handles dynamic state determination with callable to:" do
        dot = Circulator::Dot.new(Sampler)
        result = dot.generate

        # Sampler has priority flow with callable to: options
        assert_match(/priority_normal -> "priority_\?"/, result)
        assert_match(/label="  escalate \(dynamic\)"/, result)
      end

      it "handles multiple from states for one action" do
        dot = Circulator::Dot.new(Sampler)
        result = dot.generate

        # Sampler workflow_state has fail action from: [:in_progress, :completed]
        assert_match(/workflow_state_in_progress -> workflow_state_failed/, result)
        assert_match(/workflow_state_completed -> workflow_state_failed/, result)
        assert_match(/label="fail"/, result)
      end

      it "handles model-based flows" do
        dot = Circulator::Dot.new(SamplerManager)
        result = dot.generate

        assert_match(/SamplerTask/, result)
        # SamplerManager has 2 flows, so transitions use prefixed names
        assert_match(/status_pending -> status_in_progress/, result)
      end

      it "generates complete valid DOT graph structure" do
        dot = Circulator::Dot.new(Sampler)
        result = dot.generate

        # Verify structure with multi-flow prefixes
        assert_match(/^digraph/, result)
        assert_match(/rankdir=LR;/, result)
        assert_match(/status_pending \[label="pending", shape=circle\];/, result)
        assert_match(/status_approved \[label="approved", shape=circle\];/, result)
        assert_match(/status_pending -> status_approved \[label="approve"\];/, result)
        assert result.end_with?("}\n")
      end
    end

    describe "#generate_separate" do
      it "returns a hash with one entry per flow attribute" do
        dot = Circulator::Dot.new(Sampler)
        result = dot.generate_separate

        assert_instance_of Hash, result
        assert_equal 4, result.size
        assert result.key?(:status)
        assert result.key?(:priority)
        assert result.key?(:workflow_state)
        assert result.key?(:processing_state)
      end

      it "generates valid DOT diagram for each flow" do
        dot = Circulator::Dot.new(Sampler)
        result = dot.generate_separate

        result.each do |attribute_name, content|
          assert_match(/^digraph/, content)
          assert_match(/rankdir=LR;/, content)
          assert content.end_with?("}\n")
          assert_match(/#{attribute_name} flow/, content)
        end
      end

      it "includes only states from that specific flow in each diagram" do
        dot = Circulator::Dot.new(Sampler)
        result = dot.generate_separate

        # Status flow should have status states but not priority states
        assert_match(/pending/, result[:status])
        assert_match(/approved/, result[:status])
        refute_match(/normal/, result[:status])
        refute_match(/critical/, result[:status])

        # Priority flow should have priority states but not status states
        assert_match(/normal/, result[:priority])
        assert_match(/critical/, result[:priority])
        refute_match(/pending/, result[:priority])
        refute_match(/approved/, result[:priority])
      end

      it "does not use prefixed state names in separate diagrams" do
        dot = Circulator::Dot.new(Sampler)
        result = dot.generate_separate

        # Separate diagrams should use clean state names without prefixes
        assert_match(/pending \[shape=circle\];/, result[:status])
        refute_match(/status_pending/, result[:status])
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
        assert_match(/digraph "anonymous_[0-9a-f]+ flows"/, result)
      end

      it "covers model_key different from class_name branch in graph_name" do
        dot = Circulator::Dot.new(SamplerManager)
        result = dot.generate

        # Should use model key (SamplerTask) for the model-based flow
        assert_match(/SamplerTask flows/, result)
      end

      it "covers nil state in state node output" do
        dot = Circulator::Dot.new(Sampler)
        result = dot.generate

        # Should output "nil" for nil state (with prefix)
        assert_match(/workflow_state_nil \[label="nil", shape=circle\];/, result)
      end

      it "covers nil from_state in transition output" do
        dot = Circulator::Dot.new(Sampler)
        result = dot.generate

        # Should output "nil" as from state in transition (with prefix)
        assert_match(/workflow_state_nil -> workflow_state_in_progress/, result)
      end

      it "covers nil to_state in transition output" do
        dot = Circulator::Dot.new(Sampler)
        result = dot.generate

        # Should output "nil" as to state in transition (reset action, with prefix)
        assert_match(/workflow_state_completed -> workflow_state_nil/, result)
      end

      it "covers non-callable to state without allow_if" do
        dot = Circulator::Dot.new(Sampler)
        result = dot.generate

        # Label should be just the action name without "(conditional)" for most transitions
        assert_match(/status_pending -> status_approved \[label="approve"\];/, result)
        assert_match(/status_approved -> status_published \[label="publish"\];/, result)
      end

      it "covers flows.empty? branch in initialize" do
        error = assert_raises(ArgumentError) do
          Circulator::Dot.new(EmptyFlowsSampler)
        end

        assert_match(/no flows defined/, error.message)
      end

      it "quotes node names with special characters" do
        dot = Circulator::Dot.new(Sampler)
        result = dot.generate

        # The ? state should be quoted in both node declarations and transitions
        assert_match(/"priority_\?" \[label="\?", shape=circle\];/, result)
        assert_match(/priority_normal -> "priority_\?"/, result)
        assert_match(/priority_critical -> "priority_\?"/, result)
      end

      it "does not quote node names with only alphanumeric and underscore characters" do
        dot = Circulator::Dot.new(Sampler)
        result = dot.generate

        # Regular node names should not be quoted
        assert_match(/status_pending \[label="pending", shape=circle\];/, result)
        assert_match(/priority_normal \[label="normal", shape=circle\];/, result)
        assert_match(/status_pending -> status_approved/, result)
      end
    end
  end
end
