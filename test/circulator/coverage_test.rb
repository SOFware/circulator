require "test_helper"
require_relative "../sampler"

class CirculatorCoverageTest < Minitest::Test
  describe "Additional coverage tests" do
    describe "Method already defined error" do
      it "raises ArgumentError when method is already defined" do
        assert_raises(ArgumentError) do
          test_class = Class.new do
            extend Circulator

            attr_accessor :status
          end

          # First define the flow to create the method
          test_class.circulator :status do
            state :pending do
              action :approve, to: :approved
            end
          end

          # Now try to define it again - this should raise
          test_class.circulator :status do
            state :pending do
              action :approve, to: :approved
            end
          end
        end
      end
    end

    describe "Anonymous class handling" do
      it "handles anonymous classes in model_key" do
        anonymous_class = Class.new do
          extend Circulator

          attr_accessor :status
        end

        anonymous_object = anonymous_class.new

        # The model_key method should handle anonymous classes
        key = Circulator.model_key(anonymous_object)
        assert_match(/^anonymous_/, key)
      end

      it "handles anonymous class string directly" do
        # Test the "#<Class:" branch directly
        anonymous_string = "#<Class:0x00007f8b8c0a5b30>"
        puts "Testing anonymous string: #{anonymous_string}" if ENV["DEBUG"]
        key = Circulator.model_key(anonymous_string)
        puts "Result: #{key}" if ENV["DEBUG"]
        assert_equal "anonymous_00007f8b8c0a5b30", key
      end

      it "handles regular class objects" do
        # Test passing an actual object (not a string)
        regular_object = Sampler.new
        key = Circulator.model_key(regular_object)
        assert_equal "Sampler", key
      end

      it "handles namespaced class objects" do
        # Test with a namespaced class
        manager = SamplerManager.new
        key = Circulator.model_key(manager)
        assert_equal "SamplerManager", key
      end
    end

    describe "InstanceMethods flow method coverage" do
      it "handles flow_target != self scenario" do
        # This tests lines 221-222 where flow_target is different from self
        manager = SamplerManager.new
        task = SamplerTask.new
        task.status = :pending

        # Call flow with different flow_target
        manager.flow(:start, :status, flow_target: task)
        assert_equal :in_progress, task.status
      end

      it "calls method on self when respond_to? is true" do
        # This tests line 227 where self responds to the method
        sampler = Sampler.new
        sampler.status = :pending

        # Use flow method when object has the method
        sampler.flow(:approve, :status)
        assert_equal :approved, sampler.status
      end

      it "raises error when no method exists" do
        # This tests line 231 - the error case
        sampler = Sampler.new
        sampler.status = :pending

        assert_raises(RuntimeError, /Invalid action/) do
          sampler.flow(:nonexistent_action, :status)
        end
      end

      it "accesses private flows method" do
        # This indirectly tests line 238 - the private flows method
        sampler = Sampler.new
        sampler.status = :pending

        # The flow method internally uses the private flows method
        sampler.flow(:approve, :status)
        assert_equal :approved, sampler.status
      end
    end

    describe "Invalid action error in flow method" do
      it "raises error for invalid action in flow method" do
        flow_class = Class.new do
          extend Circulator

          attr_accessor :status

          circulator :status do
            state :pending do
              action :approve, to: :approved
            end
          end
        end

        flow_object = flow_class.new
        flow_object.status = :pending

        # This action doesn't exist for pending state
        assert_raises(RuntimeError, /Invalid action/) do
          flow_object.flow(:nonexistent, :status)
        end
      end
    end

    describe "action_allowed without state block" do
      it "raises error when action_allowed is called outside state block without from option" do
        assert_raises(RuntimeError) do
          Class.new do
            extend Circulator

            attr_accessor :status

            circulator :status do
              # This should raise because we're not in a state block and no from: option
              action_allowed(:approve) { true }
            end
          end
        end
      end

      it "works with from option outside state block" do
        allowed_class = Class.new do
          extend Circulator

          attr_accessor :status, :user_role

          circulator :status do
            state :pending do
              action :approve, to: :approved
            end

            # This should work because we have from: option
            action_allowed(:approve, from: :pending) { @user_role == "admin" }
          end
        end

        allowed_object = allowed_class.new
        allowed_object.status = :pending
        allowed_object.user_role = "user"

        # Should not transition because allow_if returns false
        allowed_object.status_approve
        assert_equal :pending, allowed_object.status

        allowed_object.user_role = "admin"
        allowed_object.status_approve
        assert_equal :approved, allowed_object.status
      end
    end

    describe "action_allowed with nil from state" do
      it "handles action_allowed with nil from state" do
        nil_allowed_class = Class.new do
          extend Circulator

          attr_accessor :status, :can_initialize

          def initialize
            @can_initialize = false
          end

          circulator :status do
            action :initialize, to: :pending, from: nil
            action_allowed(:initialize, from: nil) { @can_initialize }
          end
        end

        nil_allowed_object = nil_allowed_class.new
        nil_allowed_object.status = nil

        # Should not transition when can_initialize is false
        nil_allowed_object.status_initialize
        assert_nil nil_allowed_object.status

        # Should transition when can_initialize is true
        nil_allowed_object.can_initialize = true
        nil_allowed_object.status_initialize
        assert_equal :pending, nil_allowed_object.status
      end

      it "handles action_allowed with nil state in state block" do
        nil_state_allowed_class = Class.new do
          extend Circulator

          attr_accessor :status, :can_proceed

          def initialize
            @can_proceed = false
          end

          circulator :status do
            state nil do
              action :start, to: :pending
              action_allowed(:start) { @can_proceed }
            end

            state :pending do
              action :reset, to: nil
            end
          end
        end

        nil_state_object = nil_state_allowed_class.new
        nil_state_object.status = nil

        # Should not transition when can_proceed is false
        nil_state_object.status_start
        assert_nil nil_state_object.status

        # Should transition when can_proceed is true
        nil_state_object.can_proceed = true
        nil_state_object.status_start
        assert_equal :pending, nil_state_object.status

        # Can transition back to nil
        nil_state_object.status_reset
        assert_nil nil_state_object.status
      end
    end

    describe "no_action getter" do
      it "returns the no_action proc when called without block" do
        getter_class = Class.new do
          extend Circulator

          attr_accessor :status

          circulator :status do
            state :pending do
              action :approve, to: :approved
            end

            no_action { |attr, action| "Custom no action" }
          end
        end

        # Access the flow instance
        flow = getter_class.instance_variable_get(:@flows).values.first.values.first

        # Test the getter
        no_action_proc = flow.no_action
        assert_kind_of Proc, no_action_proc
        assert_equal "Custom no action", no_action_proc.call(:status, :invalid)
      end

      it "returns the default no_action proc when not set" do
        default_getter_class = Class.new do
          extend Circulator

          attr_accessor :status

          circulator :status do
            state :pending do
              action :approve, to: :approved
            end
            # Don't set a custom no_action
          end
        end

        # Access the flow instance
        flow = default_getter_class.instance_variable_get(:@flows).values.first.values.first

        # Test the getter returns the default proc
        no_action_proc = flow.no_action
        assert_kind_of Proc, no_action_proc

        # The default proc references self, so we can't call it directly on the flow
        # But we can verify it's the default proc by checking it's not nil
        refute_nil no_action_proc
      end
    end

    describe "allow_if returning false" do
      it "does not transition when allow_if returns false" do
        allow_if_class = Class.new do
          extend Circulator

          attr_accessor :status, :transition_count

          def initialize
            @transition_count = 0
          end

          circulator :status do
            state :pending do
              action :approve, to: :approved, allow_if: -> { false } do
                @transition_count += 1
              end
            end
          end
        end

        allow_if_object = allow_if_class.new
        allow_if_object.status = :pending

        # Should not transition or execute block
        allow_if_object.status_approve
        assert_equal :pending, allow_if_object.status
        assert_equal 0, allow_if_object.transition_count
      end
    end

    describe "transition with block execution" do
      it "executes transition block when present" do
        block_class = Class.new do
          extend Circulator

          attr_accessor :status, :block_executed

          def initialize
            @block_executed = false
          end

          circulator :status do
            state :pending do
              action :approve, to: :approved do
                @block_executed = true
              end
            end
          end
        end

        block_object = block_class.new
        block_object.status = :pending

        block_object.status_approve
        assert_equal :approved, block_object.status
        assert block_object.block_executed
      end
    end

    describe "callable to option" do
      it "uses callable to option to determine next state" do
        callable_class = Class.new do
          extend Circulator

          attr_accessor :status, :next_state

          def initialize
            @next_state = :approved
          end

          circulator :status do
            state :pending do
              action :process, to: -> { @next_state }
            end
          end
        end

        callable_object = callable_class.new
        callable_object.status = :pending
        callable_object.next_state = :completed

        callable_object.status_process
        assert_equal :completed, callable_object.status
      end
    end

    describe "no transition found" do
      it "calls no_action when no transition found" do
        no_transition_class = Class.new do
          extend Circulator

          attr_accessor :status, :no_action_called

          def initialize
            @no_action_called = false
          end

          circulator :status do
            state :pending do
              action :approve, to: :approved
            end

            state :approved do
              # No actions defined for approved state
            end

            no_action do |attribute_name, action|
              @no_action_called = true
              # Don't raise an error, just track that it was called
            end
          end
        end

        no_transition_object = no_transition_class.new
        no_transition_object.status = :approved

        # Try to approve from approved state (no transition defined)
        no_transition_object.status_approve
        assert no_transition_object.no_action_called
        assert_equal :approved, no_transition_object.status  # State unchanged
      end
    end

    describe "flow with additional block" do
      it "executes additional block passed to flow method" do
        additional_block_class = Class.new do
          extend Circulator

          attr_accessor :status, :additional_block_executed

          def initialize
            @additional_block_executed = false
          end

          circulator :status do
            state :pending do
              action :approve, to: :approved
            end
          end
        end

        additional_block_object = additional_block_class.new
        additional_block_object.status = :pending

        additional_block_object.status_approve do
          @additional_block_executed = true
        end

        assert_equal :approved, additional_block_object.status
        assert additional_block_object.additional_block_executed
      end
    end

    describe "flow target responds but self does not" do
      it "delegates to flow_target when self doesn't respond to method" do
        # Create a Task class
        task_class = Class.new do
          extend Circulator

          attr_accessor :status, :completed

          def self.name
            "SpecialTask"
          end

          def initialize
            @status = :pending
            @completed = false
          end

          circulator :status do
            state :pending do
              action :complete, to: :done do
                @completed = true
              end
            end
          end

          # Manually define the prefixed method that would be called from manager
          # This simulates the method that would exist if manager had defined flows for task
          define_method :special_task_status_complete do |*args, **kwargs, &block|
            # Delegate to the regular method
            status_complete(*args, **kwargs, &block)
          end
        end

        # Create a Manager class that doesn't have the method
        manager_class = Class.new do
          extend Circulator

          def self.name
            "TaskManager"
          end

          # Manager doesn't define any flows or methods for special_task_status
        end

        # Create instances
        task = task_class.new
        manager = manager_class.new

        # Verify initial state
        assert_equal :pending, task.status
        refute task.completed

        # Verify the prefixed method exists on task but not on manager
        method_name = "special_task_status_complete"
        assert task.respond_to?(method_name), "Task should respond to #{method_name}"
        refute manager.respond_to?(method_name), "Manager should not respond to #{method_name}"

        # Manager calls flow with task as flow_target
        # This will trigger line 229 because:
        # - manager doesn't respond to special_task_status_complete (line 226 returns false)
        # - task does respond to special_task_status_complete (line 228 returns true)
        # - so line 229 executes: flow_target.send(method_name, *args, **kwargs, &block)
        manager.flow(:complete, :status, flow_target: task)

        # Verify the method was called on task and state changed
        assert_equal :done, task.status
        assert task.completed
      end
    end

    describe "non-symbol status values" do
      it "handles integer status values" do
        integer_status_class = Class.new do
          extend Circulator

          attr_accessor :status

          circulator :status do
            state 0 do
              action :increment, to: 1
            end
            state 1 do
              action :increment, to: 2
            end
          end
        end

        integer_object = integer_status_class.new
        integer_object.status = 0

        integer_object.status_increment
        assert_equal 1, integer_object.status

        integer_object.status_increment
        assert_equal 2, integer_object.status
      end
    end
  end
end
