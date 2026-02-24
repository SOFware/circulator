require "test_helper"

class CirculatorInheritanceTest < Minitest::Test
  # Reset extensions before each test
  def setup
    Circulator.instance_variable_set(:@extensions, Hash.new { |h, k| h[k] = [] })
  end

  describe "Flow#dup_for" do
    it "creates a copy with a different owning class" do
      parent = Class.new do
        extend Circulator

        attr_accessor :status
        def initialize(status: nil) = @status = status
        def self.name = "DupParent"

        flow :status do
          state :pending do
            action :approve, to: :approved
          end
          state :approved
        end
      end

      child = Class.new(parent) do
        def self.name = "DupChild"
      end

      flows = parent.instance_variable_get(:@flows)
      model_key = flows.keys.first
      parent_flow = flows.dig(model_key, :status)
      child_flow = parent_flow.dup_for(child)

      # Different object
      refute_same parent_flow, child_flow

      # Same transitions
      assert_equal parent_flow.transition_map.keys, child_flow.transition_map.keys

      # Deep copy — mutating child doesn't affect parent
      child_flow.transition_map[:approve][:pending][:to] = :rejected
      assert_equal :approved, parent_flow.transition_map[:approve][:pending][:to]
    end
  end
end
