require "test_helper"

class ManagerTest
  extend Circulator

  attr_accessor :status, :counter, :user_role, :notes, :approval_count

  circulator :status, model: "TestTask" do
    state nil do
      action :do, to: :done
      action :undo, to: nil
    end
  end
end

class TestTask
  attr_accessor :status
end

class CirculatorFlowTest < Minitest::Test
  describe "Flow state machine behavior" do
    let(:flow_class) do
      Class.new do
        extend Circulator

        attr_accessor :status, :counter, :user_role, :notes, :approval_count

        def initialize
          @approval_count = 0
        end

        circulator :status do
          state :pending do
            action :approve, to: :approved do
              @approval_count += 1
            end
            action :reject, to: :rejected do
              @notes = "Rejected: #{@notes}"
            end
            action :hold, to: :on_hold
            action_allowed(:approve) { @user_role == "admin" || @user_role == "manager" }
          end

          state :on_hold do
            action :approve, to: :approved do
              @approval_count += 1
            end
            action :reject, to: :rejected do
              @notes = "Rejected: #{@notes}"
            end
            action_allowed(:approve) { @user_role == "admin" || @user_role == "manager" }
          end

          state :approved do
            action :publish, to: :published do
              @notes = "Published: #{@notes}"
            end
            action :request_changes, to: :pending do
              @notes = "Changes requested: #{@notes}"
            end
          end

          state :rejected do
            action :resubmit, to: :pending do
              @notes = "Resubmitted: #{@notes}"
            end
          end

          state :published do
            action :archive, to: :archived
          end

          state :archived do
            action :restore, to: :published
          end

          state :override_archive do
            action :restore, to: :published
          end
        end
        # Test for overriding the flow method and calling super
        def status_archive
          super
          @status = "override_archive"
        end
      end
    end

    let(:flow_object) { flow_class.new }

    describe "basic state transitions" do
      before do
        flow_object.status = :pending
        flow_object.counter = 0
        flow_object.approval_count = 0
        flow_object.notes = "Initial submission"
      end

      it "transitions from pending to approved" do
        flow_object.user_role = "manager"
        flow_object.status_approve
        assert_equal :approved, flow_object.status
      end

      it "transitions from pending to rejected" do
        flow_object.status_reject
        assert_equal :rejected, flow_object.status
      end

      it "transitions from pending to on_hold" do
        flow_object.status_hold
        assert_equal :on_hold, flow_object.status
      end

      it "executes transition blocks" do
        flow_object.user_role = "admin"
        flow_object.status_approve
        assert_equal :approved, flow_object.status
        assert_equal 1, flow_object.approval_count
      end

      it "updates notes during rejection" do
        flow_object.status_reject
        assert_equal :rejected, flow_object.status
        assert_equal "Rejected: Initial submission", flow_object.notes
      end
    end

    describe "conditional transitions" do
      before do
        flow_object.status = :pending
        flow_object.approval_count = 0
      end

      it "allows approval for admin users" do
        flow_object.user_role = "admin"
        flow_object.status_approve
        assert_equal :approved, flow_object.status
        assert_equal 1, flow_object.approval_count
      end

      it "allows approval for manager users" do
        flow_object.user_role = "manager"
        flow_object.status_approve
        assert_equal :approved, flow_object.status
        assert_equal 1, flow_object.approval_count
      end

      it "prevents approval for regular users" do
        flow_object.user_role = "user"
        flow_object.status_approve
        assert_equal :pending, flow_object.status
        assert_equal 0, flow_object.approval_count
      end

      it "prevents approval for nil user role" do
        flow_object.user_role = nil
        flow_object.status_approve
        assert_equal :pending, flow_object.status
        assert_equal 0, flow_object.approval_count
      end
    end

    describe "complex workflow scenarios" do
      it "handles complete approval workflow" do
        flow_object.status = :pending
        flow_object.user_role = "admin"
        flow_object.approval_count = 0
        flow_object.notes = "Initial submission"

        # Approve
        flow_object.status_approve
        assert_equal :approved, flow_object.status
        assert_equal 1, flow_object.approval_count

        # Publish
        flow_object.status_publish
        assert_equal :published, flow_object.status
        assert_equal "Published: Initial submission", flow_object.notes

        # Archive
        flow_object.status_archive
        assert_equal "override_archive", flow_object.status

        # Restore
        flow_object.status_restore
        assert_equal :published, flow_object.status
      end

      it "handles rejection and resubmission workflow" do
        flow_object.status = :pending
        flow_object.notes = "Initial submission"

        # Reject
        flow_object.status_reject
        assert_equal :rejected, flow_object.status
        assert_equal "Rejected: Initial submission", flow_object.notes

        # Resubmit
        flow_object.status_resubmit
        assert_equal :pending, flow_object.status
        assert_equal "Resubmitted: Rejected: Initial submission", flow_object.notes
      end

      it "handles request changes workflow" do
        flow_object.status = :approved
        flow_object.notes = "Original notes"

        # Request changes
        flow_object.status_request_changes
        assert_equal :pending, flow_object.status
        assert_equal "Changes requested: Original notes", flow_object.notes
      end

      it "handles hold and approval workflow" do
        flow_object.status = :pending
        flow_object.user_role = "user"
        flow_object.approval_count = 0

        # Put on hold
        flow_object.status_hold
        assert_equal :on_hold, flow_object.status

        # Try to approve as user (should fail)
        flow_object.status_approve
        assert_equal :on_hold, flow_object.status
        assert_equal 0, flow_object.approval_count

        # Approve as admin
        flow_object.user_role = "admin"
        flow_object.status_approve
        assert_equal :approved, flow_object.status
        assert_equal 1, flow_object.approval_count
      end
    end

    describe "flow method with arguments" do
      it "passes arguments to transition blocks" do
        flow_class_with_args = Class.new do
          extend Circulator

          attr_accessor :status, :args_received

          circulator :status do
            state :pending do
              action :approve, to: :approved do |*args, **kwargs|
                @args_received = {args: args, kwargs: kwargs}
              end
            end
          end
        end

        instance_with_args = flow_class_with_args.new
        instance_with_args.status = :pending

        instance_with_args.flow(:approve, :status, "arg1", "arg2", key: "value")
        assert_equal({
          args: ["arg1", "arg2"],
          kwargs: {key: "value"}
        }, instance_with_args.args_received)
        assert_equal :approved, instance_with_args.status
      end
    end

    describe "error handling" do
      it "raises error for invalid action" do
        flow_object.status = :pending
        assert_raises(RuntimeError) do
          flow_object.flow(:invalid_action, :status)
        end
      end

      it "raises error with no starting state" do
        flow_object.status = nil
        assert_raises(RuntimeError) do
          flow_object.status_approve
        end
        assert_nil flow_object.status
      end

      it "handles string status values" do
        flow_object.status = "pending"
        flow_object.user_role = "admin"
        flow_object.status_approve
        assert_equal :approved, flow_object.status
      end
    end

    describe "multiple flows on same object" do
      let(:multi_flow_class) do
        Class.new do
          extend Circulator

          attr_accessor :status, :priority, :counter

          circulator :status do
            state :pending do
              action :approve, to: :approved do
                @counter += 1
              end
            end
          end

          circulator :priority do
            state :low do
              action :escalate, to: :high do
                @counter += 10
              end
            end
          end
        end
      end

      let(:multi_instance) { multi_flow_class.new }

      it "manages multiple flows independently" do
        multi_instance.status = :pending
        multi_instance.priority = :low
        multi_instance.counter = 0

        # Transition status
        multi_instance.status_approve
        assert_equal :approved, multi_instance.status
        assert_equal 1, multi_instance.counter

        # Transition priority
        multi_instance.priority_escalate
        assert_equal :high, multi_instance.priority
        assert_equal 11, multi_instance.counter
      end
    end

    describe "flow method generation" do
      it "creates methods for all defined actions" do
        assert_includes flow_object.methods, :status_approve
        assert_includes flow_object.methods, :status_reject
        assert_includes flow_object.methods, :status_hold
        assert_includes flow_object.methods, :status_publish
        assert_includes flow_object.methods, :status_request_changes
        assert_includes flow_object.methods, :status_resubmit
        assert_includes flow_object.methods, :status_archive
        assert_includes flow_object.methods, :status_restore
      end

      it "allows for method overrides" do
        flow_object.status = :published
        flow_object.status_archive
        assert_equal "override_archive", flow_object.status
      end
    end

    describe "no_action behavior" do
      let(:no_action_flow_class) do
        Class.new do
          extend Circulator

          attr_accessor :status, :no_action_called, :no_action_args

          def initialize
            @no_action_called = false
            @no_action_args = nil
          end

          circulator :status do
            state :pending do
              action :approve, to: :approved
              # Define reject action but only for approved state to test no_action
              action :reject, to: :rejected, from: :approved
            end

            # Custom no_action block that logs the call
            no_action do |attribute_name, action|
              @no_action_called = true
              @no_action_args = {attribute_name: attribute_name, action: action}
              # Don't raise, just log
            end
          end
        end
      end

      let(:no_action_flow_object) { no_action_flow_class.new }

      it "calls custom no_action block when no transition exists" do
        no_action_flow_object.status = :pending

        # Try an action that doesn't exist for pending state
        no_action_flow_object.status_reject

        assert no_action_flow_object.no_action_called
        assert_equal({
          attribute_name: :status,
          action: :reject
        }, no_action_flow_object.no_action_args)
        # Status should remain unchanged
        assert_equal :pending, no_action_flow_object.status
      end

      it "calls custom no_action block when state is nil" do
        no_action_flow_object.status = nil

        no_action_flow_object.status_approve

        assert no_action_flow_object.no_action_called
        assert_equal({
          attribute_name: :status,
          action: :approve
        }, no_action_flow_object.no_action_args)
        assert_nil no_action_flow_object.status
      end

      it "calls custom no_action block when state is unknown" do
        no_action_flow_object.status = :unknown_state

        no_action_flow_object.status_approve

        assert no_action_flow_object.no_action_called
        assert_equal({
          attribute_name: :status,
          action: :approve
        }, no_action_flow_object.no_action_args)
        assert_equal :unknown_state, no_action_flow_object.status
      end

      it "does not call no_action block when transition exists" do
        no_action_flow_object.status = :pending

        no_action_flow_object.status_approve

        refute no_action_flow_object.no_action_called
        assert_equal :approved, no_action_flow_object.status
      end

      it "allows no_action block to raise custom errors" do
        custom_error_class = Class.new do
          extend Circulator

          attr_accessor :status

          circulator :status do
            state :pending do
              action :approve, to: :approved
              action :reject, to: :rejected, from: :approved
            end

            no_action do |attribute_name, action|
              raise "Custom error: Cannot perform #{action} on #{attribute_name}"
            end
          end
        end

        custom_error_object = custom_error_class.new
        custom_error_object.status = :pending

        error = assert_raises(RuntimeError) do
          custom_error_object.status_reject
        end
        assert_equal "Custom error: Cannot perform reject on status", error.message
        assert_equal :pending, custom_error_object.status
      end

      it "allows no_action block to perform side effects" do
        side_effect_class = Class.new do
          extend Circulator

          attr_accessor :status, :side_effect_count, :last_action_attempted

          def initialize
            @side_effect_count = 0
            @last_action_attempted = nil
          end

          circulator :status do
            state :pending do
              action :approve, to: :approved
              action :reject, to: :rejected, from: :approved
              action :publish, to: :published, from: :approved
            end

            no_action do |attribute_name, action|
              @side_effect_count += 1
              @last_action_attempted = action
              # Could log, notify, etc.
            end
          end
        end

        side_effect_object = side_effect_class.new
        side_effect_object.status = :pending

        side_effect_object.status_reject
        assert_equal 1, side_effect_object.side_effect_count
        assert_equal :reject, side_effect_object.last_action_attempted

        side_effect_object.status_publish
        assert_equal 2, side_effect_object.side_effect_count
        assert_equal :publish, side_effect_object.last_action_attempted
      end

      it "handles string status values in no_action blocks" do
        string_status_class = Class.new do
          extend Circulator

          attr_accessor :status, :no_action_called

          def initialize
            @no_action_called = false
          end

          circulator :status do
            state :pending do
              action :approve, to: :approved
              action :reject, to: :rejected, from: :approved
            end

            no_action do |attribute_name, action|
              @no_action_called = true
            end
          end
        end

        string_status_object = string_status_class.new
        string_status_object.status = "pending"

        string_status_object.status_reject

        assert string_status_object.no_action_called
        assert_equal "pending", string_status_object.status
      end

      it "defaults to raising error when no no_action block is specified" do
        default_class = Class.new do
          extend Circulator

          attr_accessor :status

          circulator :status do
            state :pending do
              action :approve, to: :approved
              action :reject, to: :rejected, from: :approved
            end
            # No no_action block specified
          end
        end

        default_object = default_class.new
        default_object.status = :pending

        assert_raises(RuntimeError) do
          default_object.status_reject
        end
      end

      it "allows no_action block to be set and retrieved" do
        # Create a flow instance directly
        flow_instance = Circulator::Flow.new(flow_class, :status) {}

        # Set custom no_action block
        custom_block = ->(attr, action) { "custom behavior" }
        flow_instance.no_action(&custom_block)

        # Retrieve the block
        retrieved_block = flow_instance.no_action

        assert_equal custom_block, retrieved_block
      end

      it "handles multiple no_action calls correctly" do
        multiple_calls_class = Class.new do
          extend Circulator

          attr_accessor :status, :call_count

          def initialize
            @call_count = 0
          end

          circulator :status do
            state :pending do
              action :approve, to: :approved
              action :reject, to: :rejected, from: :approved
            end

            # First no_action block
            no_action do |attribute_name, action|
              @call_count += 1
            end

            # Second no_action block (should override the first)
            no_action do |attribute_name, action|
              @call_count += 10
            end
          end
        end

        multiple_calls_object = multiple_calls_class.new
        multiple_calls_object.status = :pending

        multiple_calls_object.status_reject

        # Should only call the last no_action block
        assert_equal 10, multiple_calls_object.call_count
      end
    end

    describe "callable to: behavior" do
      let(:callable_to_class) do
        Class.new do
          extend Circulator

          attr_accessor :status, :counter, :transition_args, :transition_kwargs

          def initialize
            @counter = 0
            @transition_args = nil
            @transition_kwargs = nil
          end

          circulator :status do
            state :pending do
              # Simple callable that returns a static value
              action :approve, to: -> { :approved }

              # Callable that uses instance variables
              action :increment, to: -> {
                @counter += 1
                :incremented
              }

              # Callable that receives arguments
              action :custom, to: ->(*args, **kwargs) do
                @transition_args = args
                @transition_kwargs = kwargs
                :custom_state
              end
            end

            state :approved do
              # Callable that returns different states based on conditions
              action :process, to: ->(priority) do
                case priority
                when "high"
                  :urgent
                when "low"
                  :normal
                else
                  :pending
                end
              end
            end

            state :urgent do
              # Callable that uses multiple arguments
              action :resolve, to: ->(resolver, reason = "default") do
                @resolver = resolver
                @reason = reason
                :resolved
              end
            end

            # Actions with from: option and callable to:
            action :reset, to: -> { :pending }, from: [:approved, :urgent, :normal, :resolved]
            action :escalate, to: ->(level) { :"level_#{level}" }, from: [:normal, :pending]
          end
        end
      end

      let(:callable_to_object) { callable_to_class.new }

      it "uses callable to: for simple state transitions" do
        callable_to_object.status = :pending

        callable_to_object.status_approve

        assert_equal :approved, callable_to_object.status
      end

      it "executes callable to: with side effects" do
        callable_to_object.status = :pending
        callable_to_object.counter = 0

        callable_to_object.status_increment

        assert_equal :incremented, callable_to_object.status
        assert_equal 1, callable_to_object.counter
      end

      it "passes arguments to callable to:" do
        callable_to_object.status = :pending

        callable_to_object.status_custom("arg1", "arg2", key1: "value1", key2: "value2")

        assert_equal :custom_state, callable_to_object.status
        assert_equal ["arg1", "arg2"], callable_to_object.transition_args
        assert_equal({key1: "value1", key2: "value2"}, callable_to_object.transition_kwargs)
      end

      it "uses callable to: for conditional state transitions" do
        callable_to_object.status = :approved

        # High priority
        callable_to_object.status_process("high")
        assert_equal :urgent, callable_to_object.status

        # Low priority
        callable_to_object.status = :approved
        callable_to_object.status_process("low")
        assert_equal :normal, callable_to_object.status

        # Unknown priority
        callable_to_object.status = :approved
        callable_to_object.status_process("unknown")
        assert_equal :pending, callable_to_object.status
      end

      it "handles callable to: with default arguments" do
        callable_to_object.status = :urgent

        # With arguments
        callable_to_object.status_resolve("admin", "bug fix")
        assert_equal :resolved, callable_to_object.status
        assert_equal "admin", callable_to_object.instance_variable_get(:@resolver)
        assert_equal "bug fix", callable_to_object.instance_variable_get(:@reason)

        # With default argument
        callable_to_object.status = :urgent
        callable_to_object.status_resolve("user")
        assert_equal :resolved, callable_to_object.status
        assert_equal "user", callable_to_object.instance_variable_get(:@resolver)
        assert_equal "default", callable_to_object.instance_variable_get(:@reason)
      end

      it "works with from: option and callable to:" do
        # Test reset from different states
        [:approved, :urgent, :normal, :resolved].each do |state|
          callable_to_object.status = state
          callable_to_object.status_reset
          assert_equal :pending, callable_to_object.status
        end
      end

      it "handles callable to: with from: option and arguments" do
        # From normal state
        callable_to_object.status = :normal
        callable_to_object.status_escalate(3)
        assert_equal :level_3, callable_to_object.status

        # From pending state
        callable_to_object.status = :pending
        callable_to_object.status_escalate(1)
        assert_equal :level_1, callable_to_object.status
      end

      it "executes transition blocks before callable to:" do
        transition_block_class = Class.new do
          extend Circulator

          attr_accessor :status, :block_executed, :final_state

          def initialize
            @block_executed = false
            @final_state = nil
          end

          circulator :status do
            state :pending do
              action :process, to: -> {
                @final_state = :processed
                :approved
              } do
                @block_executed = true
              end
            end
          end
        end

        transition_block_object = transition_block_class.new
        transition_block_object.status = :pending

        transition_block_object.status_process

        assert transition_block_object.block_executed
        assert_equal :approved, transition_block_object.status
        assert_equal :processed, transition_block_object.final_state
      end

      it "respects allow_if conditions with callable to:" do
        conditional_class = Class.new do
          extend Circulator

          attr_accessor :status, :user_role, :transition_count

          def initialize
            @transition_count = 0
          end

          circulator :status do
            state :pending do
              action :approve, to: -> {
                @transition_count += 1
                :approved
              }, allow_if: -> { @user_role == "admin" }
            end
          end
        end

        conditional_object = conditional_class.new
        conditional_object.status = :pending

        # Should not transition when condition is false
        conditional_object.user_role = "user"
        conditional_object.status_approve
        assert_equal :pending, conditional_object.status
        assert_equal 0, conditional_object.transition_count

        # Should transition when condition is true
        conditional_object.user_role = "admin"
        conditional_object.status_approve
        assert_equal :approved, conditional_object.status
        assert_equal 1, conditional_object.transition_count
      end

      it "handles complex callable to: with multiple operations" do
        complex_class = Class.new do
          extend Circulator

          attr_accessor :status, :log, :timestamp

          def initialize
            @log = []
            @timestamp = nil
          end

          circulator :status do
            state :pending do
              action :complete, to: ->(user, note = nil) do
                @timestamp = Time.now
                @log << "Completed by #{user}"
                @log << "Note: #{note}" if note
                @log << "Timestamp: #{@timestamp}"
                :completed
              end
            end
          end
        end

        complex_object = complex_class.new
        complex_object.status = :pending

        complex_object.status_complete("admin", "All tests passing")

        assert_equal :completed, complex_object.status
        assert_includes complex_object.log, "Completed by admin"
        assert_includes complex_object.log, "Note: All tests passing"
        assert_instance_of Time, complex_object.timestamp
      end

      it "handles callable to: that returns nil or invalid states" do
        nil_return_class = Class.new do
          extend Circulator

          attr_accessor :status

          circulator :status do
            state :pending do
              action :process, to: -> {}
              action :invalid, to: -> { "invalid_state" }
            end
          end
        end

        nil_return_object = nil_return_class.new
        nil_return_object.status = :pending

        # Should handle nil return
        nil_return_object.status_process
        assert_nil nil_return_object.status

        # Should handle string return
        nil_return_object.status = :pending
        nil_return_object.status_invalid
        assert_equal "invalid_state", nil_return_object.status
      end

      it "works with string status values and callable to:" do
        string_status_class = Class.new do
          extend Circulator

          attr_accessor :status

          circulator :status do
            state :pending do
              action :approve, to: -> { "approved" }
            end
          end
        end

        string_status_object = string_status_class.new
        string_status_object.status = "pending"

        string_status_object.status_approve

        assert_equal "approved", string_status_object.status
      end
    end

    describe "nil to: and from: behavior" do
      let(:nil_behavior_class) do
        Class.new do
          extend Circulator

          attr_accessor :status, :transition_log

          def initialize
            @transition_log = []
          end

          circulator :status do
            state :pending do
              action :clear, to: nil do
                @transition_log << "cleared"
              end
              action :approve, to: :approved
            end

            state :approved do
              action :reset, to: nil do
                @transition_log << "reset"
              end
            end

            action :initialize, to: :pending, from: nil do
              @transition_log << "initialized"
            end

            action :restart, to: :pending, from: [:approved, :rejected, nil] do
              @transition_log << "restarted"
            end
          end
        end
      end

      let(:nil_behavior_object) { nil_behavior_class.new }

      it "handles nil transitions" do
        # Transition to nil
        nil_behavior_object.status = :pending
        nil_behavior_object.status_clear
        assert_nil nil_behavior_object.status
        assert_equal ["cleared"], nil_behavior_object.transition_log

        # Transition from nil
        nil_behavior_object.status_initialize
        assert_equal :pending, nil_behavior_object.status
        assert_equal ["cleared", "initialized"], nil_behavior_object.transition_log

        # Transition to nil from different state
        nil_behavior_object.status = :approved
        nil_behavior_object.status_reset
        assert_nil nil_behavior_object.status
        assert_equal ["cleared", "initialized", "reset"], nil_behavior_object.transition_log

        # Transition from multiple states including nil
        nil_behavior_object.status_restart
        assert_equal :pending, nil_behavior_object.status
        assert_equal ["cleared", "initialized", "reset", "restarted"], nil_behavior_object.transition_log
      end

      it "works with callable to: that returns nil" do
        callable_nil_class = Class.new do
          extend Circulator

          attr_accessor :status, :should_clear

          circulator :status do
            state :pending do
              action :conditional_clear, to: -> { @should_clear ? nil : :approved }
            end
          end
        end

        callable_nil_object = callable_nil_class.new
        callable_nil_object.status = :pending

        # When should_clear is true
        callable_nil_object.should_clear = true
        callable_nil_object.status_conditional_clear
        assert_nil callable_nil_object.status

        # When should_clear is false
        callable_nil_object.status = :pending
        callable_nil_object.should_clear = false
        callable_nil_object.status_conditional_clear
        assert_equal :approved, callable_nil_object.status
      end

      it "handles nil with allow_if conditions" do
        conditional_nil_class = Class.new do
          extend Circulator

          attr_accessor :status, :user_role, :transition_count

          def initialize
            @transition_count = 0
          end

          circulator :status do
            state :pending do
              action :clear, to: nil, allow_if: -> { @user_role == "admin" } do
                @transition_count += 1
              end
            end

            action :initialize, to: :pending, from: nil, allow_if: -> { @user_role == "admin" } do
              @transition_count += 1
            end
          end
        end

        conditional_nil_object = conditional_nil_class.new

        # Test to: nil with condition
        conditional_nil_object.status = :pending
        conditional_nil_object.user_role = "user"
        conditional_nil_object.status_clear
        assert_equal :pending, conditional_nil_object.status
        assert_equal 0, conditional_nil_object.transition_count

        conditional_nil_object.user_role = "admin"
        conditional_nil_object.status_clear
        assert_nil conditional_nil_object.status
        assert_equal 1, conditional_nil_object.transition_count

        # Test from: nil with condition
        conditional_nil_object.user_role = "user"
        conditional_nil_object.status_initialize
        assert_nil conditional_nil_object.status
        assert_equal 1, conditional_nil_object.transition_count

        conditional_nil_object.user_role = "admin"
        conditional_nil_object.status_initialize
        assert_equal :pending, conditional_nil_object.status
        assert_equal 2, conditional_nil_object.transition_count
      end

      it "works with blocks and nil transitions" do
        block_nil_class = Class.new do
          extend Circulator

          attr_accessor :status, :execution_order

          def initialize
            @execution_order = []
          end

          circulator :status do
            state :pending do
              action :clear, to: nil do
                @execution_order << "transition_block"
              end
            end

            action :initialize, to: :pending, from: nil do
              @execution_order << "transition_block"
            end
          end
        end

        block_nil_object = block_nil_class.new

        # Test to: nil with block
        block_nil_object.status = :pending
        block_nil_object.status_clear do
          @execution_order << "method_block"
        end
        assert_nil block_nil_object.status
        assert_equal ["transition_block", "method_block"], block_nil_object.execution_order

        # Test from: nil with block
        block_nil_object.execution_order = []
        block_nil_object.status_initialize do
          @execution_order << "method_block"
        end
        assert_equal :pending, block_nil_object.status
        assert_equal ["transition_block", "method_block"], block_nil_object.execution_order
      end

      it "handles string status values with nil transitions" do
        string_nil_class = Class.new do
          extend Circulator

          attr_accessor :status

          circulator :status do
            state :pending do
              action :clear, to: nil
            end

            action :initialize, to: :pending, from: nil
          end
        end

        string_nil_object = string_nil_class.new

        # Test to: nil with symbol status (converted from string)
        string_nil_object.status = "pending"
        string_nil_object.status_clear
        assert_nil string_nil_object.status

        # Test from: nil to symbol status
        string_nil_object.status_initialize
        assert_equal :pending, string_nil_object.status
      end

      it "works with no_action when transitioning to/from nil" do
        no_action_nil_class = Class.new do
          extend Circulator

          attr_accessor :status, :no_action_called

          def initialize
            @no_action_called = false
          end

          circulator :status do
            state :pending do
              action :clear, to: nil
              action :approve, to: :approved
            end

            action :clear, to: nil, from: nil

            no_action do |attribute_name, action|
              @no_action_called = true
            end
          end
        end

        no_action_nil_object = no_action_nil_class.new

        # Test that no_action is called for invalid actions when status is nil
        no_action_nil_object.status = nil
        no_action_nil_object.status_approve
        assert no_action_nil_object.no_action_called
        assert_nil no_action_nil_object.status

        # Test that no_action is NOT called for valid actions when status is nil
        no_action_nil_object.no_action_called = false
        no_action_nil_object.status_clear
        refute no_action_nil_object.no_action_called
        assert_nil no_action_nil_object.status
      end

      it "uses action_allowed with nil as from state" do
        # Test action_allowed with from: nil parameter
        flow = Circulator::Flow.new("TestClass", :status) do
          # Define action from nil state
          action :initialize, to: :pending, from: nil
          # Set action_allowed condition for nil state
          action_allowed(:initialize, from: nil) { true }
        end

        # Verify the transition map was set up correctly
        assert flow.transition_map[:initialize]
        assert flow.transition_map[:initialize][nil]
        assert flow.transition_map[:initialize][nil][:allow_if]
      end

      it "uses action_allowed within nil state block" do
        # Test action_allowed within a nil state block
        flow = Circulator::Flow.new("TestClass", :status) do
          state nil do
            action :start, to: :pending
            # This processes nil as the current state
            action_allowed(:start) { true }
          end
        end

        # Verify the transition map
        assert flow.transition_map[:start]
        assert flow.transition_map[:start][nil]
        assert flow.transition_map[:start][nil][:allow_if]
      end
    end

    describe "block passing behavior" do
      let(:block_flow_class) do
        Class.new do
          extend Circulator

          attr_accessor :status, :block_executed, :block_args, :block_kwargs, :execution_order

          def initialize
            @block_executed = false
            @block_args = nil
            @block_kwargs = nil
            @execution_order = []
          end

          circulator :status do
            state :pending do
              action :approve, to: :approved do
                @execution_order << "transition_block"
              end
              action :reject, to: :rejected
              action :process, to: :processing do
                @execution_order << "transition_block"
              end
            end

            state :approved do
              action :publish, to: :published do
                @execution_order << "transition_block"
              end
            end
          end
        end
      end

      let(:block_flow_object) { block_flow_class.new }

      it "executes blocks passed to dynamically defined methods" do
        block_flow_object.status = :pending
        block_executed = false

        block_flow_object.status_approve do
          block_executed = true
          @execution_order << "method_block"
        end

        assert block_executed
        assert_equal :approved, block_flow_object.status
        assert_equal ["transition_block", "method_block"], block_flow_object.execution_order
      end

      it "passes arguments to blocks passed to methods" do
        block_flow_object.status = :pending

        block_flow_object.status_approve("arg1", "arg2", key1: "value1") do |*args, **kwargs|
          @block_args = args
          @block_kwargs = kwargs
          @execution_order << "method_block"
        end

        assert_equal ["arg1", "arg2"], block_flow_object.block_args
        assert_equal({key1: "value1"}, block_flow_object.block_kwargs)
        assert_equal :approved, block_flow_object.status
      end

      it "executes blocks passed to flow method" do
        block_flow_object.status = :pending
        block_executed = false

        block_flow_object.flow(:approve, :status) do
          block_executed = true
          @execution_order << "flow_block"
        end

        assert block_executed
        assert_equal :approved, block_flow_object.status
        assert_equal ["transition_block", "flow_block"], block_flow_object.execution_order
      end

      it "passes arguments through flow method to blocks" do
        block_flow_object.status = :pending

        block_flow_object.flow(:approve, :status, "arg1", "arg2", key1: "value1") do |*args, **kwargs|
          @block_args = args
          @block_kwargs = kwargs
          @execution_order << "flow_block"
        end

        assert_equal ["arg1", "arg2"], block_flow_object.block_args
        assert_equal({key1: "value1"}, block_flow_object.block_kwargs)
        assert_equal :approved, block_flow_object.status
      end

      it "executes blocks even when no transition block is defined" do
        block_flow_object.status = :pending
        block_executed = false

        block_flow_object.status_reject do
          block_executed = true
          @execution_order << "method_block"
        end

        assert block_executed
        assert_equal :rejected, block_flow_object.status
        assert_equal ["method_block"], block_flow_object.execution_order
      end

      it "executes blocks with callable to: transitions" do
        callable_block_class = Class.new do
          extend Circulator

          attr_accessor :status, :execution_order

          def initialize
            @execution_order = []
          end

          circulator :status do
            state :pending do
              action :process, to: -> {
                @execution_order << "callable_to"
                :processed
              } do
                @execution_order << "transition_block"
              end
            end
          end
        end

        callable_block_object = callable_block_class.new
        callable_block_object.status = :pending

        callable_block_object.status_process do
          @execution_order << "method_block"
        end

        assert_equal :processed, callable_block_object.status
        assert_equal ["transition_block", "callable_to", "method_block"], callable_block_object.execution_order
      end

      it "executes blocks when allow_if condition is true" do
        conditional_block_class = Class.new do
          extend Circulator

          attr_accessor :status, :user_role, :block_executed

          def initialize
            @block_executed = false
          end

          circulator :status do
            state :pending do
              action :approve, to: :approved, allow_if: -> { @user_role == "admin" } do
                @execution_order ||= []
                @execution_order << "transition_block"
              end
            end
          end
        end

        conditional_block_object = conditional_block_class.new
        conditional_block_object.status = :pending
        conditional_block_object.user_role = "admin"

        conditional_block_object.status_approve do
          @block_executed = true
        end

        assert conditional_block_object.block_executed
        assert_equal :approved, conditional_block_object.status
      end

      it "does not execute blocks when allow_if condition is false" do
        conditional_block_class = Class.new do
          extend Circulator

          attr_accessor :status, :user_role, :block_executed

          def initialize
            @block_executed = false
          end

          circulator :status do
            state :pending do
              action :approve, to: :approved, allow_if: -> { @user_role == "admin" }
            end
          end
        end

        conditional_block_object = conditional_block_class.new
        conditional_block_object.status = :pending
        conditional_block_object.user_role = "user"

        conditional_block_object.status_approve do
          @block_executed = true
        end

        refute conditional_block_object.block_executed
        assert_equal :pending, conditional_block_object.status
      end

      it "does not execute blocks with no_action when no transition exists" do
        no_action_block_class = Class.new do
          extend Circulator

          attr_accessor :status, :block_executed

          def initialize
            @block_executed = false
          end

          circulator :status do
            state :pending do
              action :approve, to: :approved
              action :reject, to: :rejected, from: :approved
            end

            no_action do |attribute_name, action|
              @no_action_called = true
            end
          end
        end

        no_action_block_object = no_action_block_class.new
        no_action_block_object.status = :pending

        no_action_block_object.status_reject do
          @block_executed = true
        end

        refute no_action_block_object.block_executed # block should NOT be called
        assert_equal :pending, no_action_block_object.status
        assert no_action_block_object.instance_variable_get(:@no_action_called)
      end

      it "handles multiple blocks in complex scenarios" do
        complex_block_class = Class.new do
          extend Circulator

          attr_accessor :status, :execution_order, :counter

          def initialize
            @execution_order = []
            @counter = 0
          end

          circulator :status do
            state :pending do
              action :process, to: -> {
                @counter += 1
                :processing
              } do
                @execution_order << "transition_block"
              end
            end

            state :processing do
              action :complete, to: :completed do
                @execution_order << "transition_block"
              end
            end
          end
        end

        complex_block_object = complex_block_class.new
        complex_block_object.status = :pending

        # First transition with block
        complex_block_object.status_process do
          @execution_order << "method_block_1"
        end

        # Second transition with block
        complex_block_object.status_complete do
          @execution_order << "method_block_2"
        end

        assert_equal :completed, complex_block_object.status
        assert_equal 1, complex_block_object.counter
        assert_equal [
          "transition_block", "method_block_1",
          "transition_block", "method_block_2"
        ], complex_block_object.execution_order
      end

      it "works with string status values and blocks" do
        string_block_class = Class.new do
          extend Circulator

          attr_accessor :status, :block_executed

          def initialize
            @block_executed = false
          end

          circulator :status do
            state :pending do
              action :approve, to: "approved"
            end
          end
        end

        string_block_object = string_block_class.new
        string_block_object.status = "pending"

        string_block_object.status_approve do
          @block_executed = true
        end

        assert string_block_object.block_executed
        assert_equal "approved", string_block_object.status
      end

      it "handles blocks with from: option" do
        from_block_class = Class.new do
          extend Circulator

          attr_accessor :status, :block_executed

          def initialize
            @block_executed = false
          end

          circulator :status do
            state :pending do
              action :approve, to: :approved
            end

            action :reset, to: :pending, from: [:approved, :rejected] do
              @execution_order ||= []
              @execution_order << "transition_block"
            end
          end
        end

        from_block_object = from_block_class.new
        from_block_object.status = :approved

        from_block_object.status_reset do
          @block_executed = true
        end

        assert from_block_object.block_executed
        assert_equal :pending, from_block_object.status
      end

      it "executes blocks in correct order with all flow features" do
        order_flow_class = Class.new do
          extend Circulator

          attr_accessor :status, :execution_order

          def initialize
            @execution_order = []
          end

          circulator :status do
            state :pending do
              action :process, to: ->(*, **) {
                @execution_order << "callable_to"
                :processing
              }, allow_if: ->(*args, **kwargs) { true } do |*args, **kwargs|
                @execution_order << "transition_block"
              end
            end
          end
        end

        order_flow_object = order_flow_class.new
        order_flow_object.status = :pending

        order_flow_object.status_process("arg1", key1: "value1") do |*args, **kwargs|
          @execution_order << "method_block"
        end

        assert_equal :processing, order_flow_object.status
        assert_equal [
          "transition_block", "callable_to", "method_block"
        ], order_flow_object.execution_order
      end
    end
  end

  describe "Flow state machine behavior with model" do
    let(:manager) { ManagerTest.new }
    let(:task) { TestTask.new }

    it "controls the flow of a model" do
      assert_nil task.status

      manager.test_task_status_do(flow_target: task)

      assert_equal :done, task.status
    end

    it "can pass the flow target to the flow method" do
      assert_nil task.status

      manager.flow(:do, :status, flow_target: task)

      assert_equal :done, task.status
    end
  end

  describe "hash-based allow_if validation" do
    it "raises error when allow_if is not a Proc or Hash" do
      error = assert_raises(ArgumentError) do
        Class.new do
          extend Circulator

          attr_accessor :status, :priority

          circulator :status do
            state :pending do
              action :approve, to: :approved, allow_if: "invalid"
            end
          end
        end
      end

      assert_match(/allow_if must be a Proc or Hash/, error.message)
    end

    it "raises error when hash-based allow_if references undefined attribute" do
      error = assert_raises(ArgumentError) do
        Class.new do
          extend Circulator

          attr_accessor :status

          circulator :status do
            state :pending do
              action :approve, to: :approved, allow_if: {priority: [:high]}
            end
          end
        end
      end

      assert_match(/allow_if references undefined flow attribute/, error.message)
      assert_match(/:priority/, error.message)
    end

    it "raises error when hash-based allow_if references invalid states" do
      error = assert_raises(ArgumentError) do
        Class.new do
          extend Circulator

          attr_accessor :status, :priority

          circulator :priority do
            state :low do
              action :escalate, to: :high
            end

            state :high do
              action :critical, to: :critical
            end
          end

          circulator :status do
            state :pending do
              action :approve, to: :approved, allow_if: {priority: [:urgent, :critical]}
            end
          end
        end
      end

      assert_match(/allow_if references invalid states/, error.message)
      assert_match(/:urgent/, error.message)
      assert_match(/Valid states:/, error.message)
    end

    it "accepts hash with valid attribute and states" do
      klass = Class.new do
        extend Circulator

        attr_accessor :status, :priority

        circulator :priority do
          state :low do
            action :escalate, to: :high
          end

          state :high do
            action :escalate, to: :critical
          end
        end

        circulator :status do
          state :pending do
            action :approve, to: :approved, allow_if: {priority: [:high, :critical]}
          end
        end
      end

      # Should not raise an error
      instance = klass.new
      assert_respond_to instance, :status_approve
    end

    it "raises error when hash has more than one key" do
      error = assert_raises(ArgumentError) do
        Class.new do
          extend Circulator

          attr_accessor :status, :priority, :approval

          circulator :priority do
            state :high do
            end
          end

          circulator :approval do
            state :yes do
            end
          end

          circulator :status do
            state :pending do
              action :approve, to: :approved, allow_if: {priority: [:high], approval: [:yes]}
            end
          end
        end
      end

      assert_match(/allow_if hash must contain exactly one attribute/, error.message)
    end
  end

  describe "hash-based allow_if runtime evaluation" do
    it "allows transition when dependency state matches" do
      klass = Class.new do
        extend Circulator

        attr_accessor :status, :priority

        circulator :priority do
          state :low do
            action :escalate, to: :high
          end

          state :high do
            action :escalate, to: :critical
          end
        end

        circulator :status do
          state :pending do
            action :approve, to: :approved, allow_if: {priority: [:high, :critical]}
          end
        end
      end

      instance = klass.new
      instance.status = :pending
      instance.priority = :high

      instance.status_approve
      assert_equal :approved, instance.status
    end

    it "blocks transition when dependency state doesn't match" do
      klass = Class.new do
        extend Circulator

        attr_accessor :status, :priority

        circulator :priority do
          state :low do
            action :escalate, to: :high
          end

          state :high do
            action :escalate, to: :critical
          end
        end

        circulator :status do
          state :pending do
            action :approve, to: :approved, allow_if: {priority: [:high, :critical]}
          end
        end
      end

      instance = klass.new
      instance.status = :pending
      instance.priority = :low

      instance.status_approve
      assert_equal :pending, instance.status
    end

    it "handles string states in runtime evaluation" do
      klass = Class.new do
        extend Circulator

        attr_accessor :status, :priority

        circulator :priority do
          state :low do
            action :escalate, to: :high
          end

          state :high do
          end
        end

        circulator :status do
          state :pending do
            action :approve, to: :approved, allow_if: {priority: [:high]}
          end
        end
      end

      instance = klass.new
      instance.status = :pending
      instance.priority = "high"  # String instead of symbol

      instance.status_approve
      assert_equal :approved, instance.status
    end

    it "works with from: option and hash-based allow_if" do
      klass = Class.new do
        extend Circulator

        attr_accessor :status, :priority

        circulator :priority do
          state :low do
          end

          state :high do
          end
        end

        circulator :status do
          action :approve, to: :approved, from: :pending, allow_if: {priority: [:high]}
        end
      end

      instance = klass.new
      instance.status = :pending
      instance.priority = :high

      instance.status_approve
      assert_equal :approved, instance.status
    end
  end
end
