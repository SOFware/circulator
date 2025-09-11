require "test_helper"

class FlowCoverageTest < Minitest::Test
  describe "Flow class uncovered lines" do
    it "covers no_action getter branch" do
      # Create a flow directly to test the getter
      flow = Circulator::Flow.new("TestClass", :status) do
        state :pending do
          action :approve, to: :approved
        end
        # Don't set a custom no_action
      end
      
      # Call no_action without a block to trigger the getter branch (line 69)
      no_action_proc = flow.no_action
      assert_kind_of Proc, no_action_proc
      refute_nil no_action_proc
    end
    
    it "covers action_allowed with nil selected_state" do
      # Create a flow that uses action_allowed with nil state
      flow = Circulator::Flow.new("TestClass", :status) do
        # First define the action from nil
        action :initialize, to: :pending, from: nil
        # Then use action_allowed with from: nil to hit line 53
        action_allowed(:initialize, from: nil) { true }
      end
      
      # Verify the transition map was set up correctly
      assert flow.transition_map[:initialize]
      assert flow.transition_map[:initialize][nil]
      assert flow.transition_map[:initialize][nil][:allow_if]
    end
    
    it "covers action_allowed within nil state block" do
      # Another way to hit the nil state case
      flow = Circulator::Flow.new("TestClass", :status) do
        state nil do
          action :start, to: :pending
          # This should process nil as the current state
          action_allowed(:start) { true }
        end
      end
      
      # Verify the transition map
      assert flow.transition_map[:start]
      assert flow.transition_map[:start][nil]
      assert flow.transition_map[:start][nil][:allow_if]
    end
  end
end