require "test_helper"
require_relative "../sampler"

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

class FlowWithArgsSampler
  extend Circulator

  attr_accessor :status, :args_received

  def initialize(status: nil)
    @status = status
  end

  circulator :status do
    state :pending do
      action :approve, to: :approved do |*args, **kwargs|
        @args_received = {args: args, kwargs: kwargs}
      end
    end
  end
end

class NilStateSampler
  extend Circulator

  attr_accessor :status

  def initialize(status: nil)
    @status = status
  end

  circulator :status do
    state nil do
      action :initialize, to: :pending
    end
    state :pending do
      action :clear, to: nil
    end
  end
end

class SkipMethodSampler
  extend Circulator

  attr_accessor :status

  def initialize(status: nil)
    @status = status
  end

  # First flow defines state
  circulator :status do
    state :pending do
      action :approve, to: :approved
    end
  end

  # Second flow with same attribute and same state
  # Should skip creating status_pending? since it already exists
  circulator :status do
    state :pending do
      action :complete, to: :done
    end
    state :approved do
      action :finalize, to: :finalized
    end
  end
end

class NoActionBehaviorSampler
  extend Circulator

  attr_accessor :error_status, :side_effect_status, :track_status,
    :default_status, :multi_status,
    :side_effect_count, :last_action_attempted,
    :no_action_called, :call_count

  def initialize(error_status: nil, side_effect_status: nil, track_status: nil,
    default_status: nil, multi_status: nil)
    @error_status = error_status
    @side_effect_status = side_effect_status
    @track_status = track_status
    @default_status = default_status
    @multi_status = multi_status
    @side_effect_count = 0
    @last_action_attempted = nil
    @no_action_called = false
    @call_count = 0
  end

  circulator :error_status do
    state :pending do
      action :approve, to: :approved
      action :reject, to: :rejected, from: :approved
    end

    no_action do |attribute_name, action|
      raise "Custom error: Cannot perform #{action} on #{attribute_name}"
    end
  end

  circulator :side_effect_status do
    state :pending do
      action :approve, to: :approved
      action :reject, to: :rejected, from: :approved
      action :publish, to: :published, from: :approved
    end

    no_action do |attribute_name, action|
      @side_effect_count += 1
      @last_action_attempted = action
    end
  end

  circulator :track_status do
    state :pending do
      action :approve, to: :approved
      action :reject, to: :rejected, from: :approved
    end

    no_action do |attribute_name, action|
      @no_action_called = true
    end
  end

  circulator :default_status do
    state :pending do
      action :approve, to: :approved
      action :reject, to: :rejected, from: :approved
    end
  end

  circulator :multi_status do
    state :pending do
      action :approve, to: :approved
      action :reject, to: :rejected, from: :approved
    end

    no_action do |attribute_name, action|
      @call_count += 1
    end

    no_action do |attribute_name, action|
      @call_count += 10
    end
  end
end

class CallableToConditionalSampler
  extend Circulator

  attr_accessor :status, :user_role, :transition_count

  def initialize(status: nil)
    @status = status
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

class CallableToComplexSampler
  extend Circulator

  attr_accessor :status, :log, :timestamp

  def initialize(status: nil)
    @status = status
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

class CallableToEdgeCasesSampler
  extend Circulator

  attr_accessor :nil_return, :string_return, :conditional_return, :should_clear

  def initialize(nil_return: nil, string_return: nil, conditional_return: nil)
    @nil_return = nil_return
    @string_return = string_return
    @conditional_return = conditional_return
  end

  circulator :nil_return do
    state :pending do
      action :process, to: -> {}
      action :invalid, to: -> { "invalid_state" }
    end
  end

  circulator :string_return do
    state :pending do
      action :approve, to: -> { "approved" }
    end
  end

  circulator :conditional_return do
    state :pending do
      action :conditional_clear, to: -> { @should_clear ? nil : :approved }
    end
  end
end

class NilTransitionsSampler
  extend Circulator

  attr_accessor :conditional_status, :block_status, :string_status, :no_action_status,
    :user_role, :transition_count, :execution_order, :no_action_called

  def initialize(conditional_status: nil, block_status: nil, string_status: nil,
    no_action_status: nil)
    @conditional_status = conditional_status
    @block_status = block_status
    @string_status = string_status
    @no_action_status = no_action_status
    @transition_count = 0
    @execution_order = []
    @no_action_called = false
  end

  circulator :conditional_status do
    state :pending do
      action :clear, to: nil, allow_if: -> { @user_role == "admin" } do
        @transition_count += 1
      end
    end

    action :initialize, to: :pending, from: nil, allow_if: -> { @user_role == "admin" } do
      @transition_count += 1
    end
  end

  circulator :block_status do
    state :pending do
      action :clear, to: nil do
        @execution_order << "transition_block"
      end
    end

    action :initialize, to: :pending, from: nil do
      @execution_order << "transition_block"
    end
  end

  circulator :string_status do
    state :pending do
      action :clear, to: nil
    end

    action :initialize, to: :pending, from: nil
  end

  circulator :no_action_status do
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

class CallableToBlockInteractionSampler
  extend Circulator

  attr_accessor :order_status, :exec_status, :execution_order, :block_executed, :final_state

  def initialize(order_status: nil, exec_status: nil)
    @order_status = order_status
    @exec_status = exec_status
    @execution_order = []
    @block_executed = false
    @final_state = nil
  end

  circulator :order_status do
    state :pending do
      action :process, to: -> {
        @execution_order << "callable_to"
        :processed
      } do
        @execution_order << "transition_block"
      end
    end
  end

  circulator :exec_status do
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

class StringBlockSampler
  extend Circulator

  attr_accessor :status, :block_executed

  def initialize(status: nil)
    @status = status
    @block_executed = false
  end

  circulator :status do
    state :pending do
      action :approve, to: "approved"
    end
  end
end

class FromBlockSampler
  extend Circulator

  attr_accessor :status, :block_executed

  def initialize(status: nil)
    @status = status
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

class BlockExecutionOrderSampler
  extend Circulator

  attr_accessor :multi_step, :full_order, :execution_order, :counter

  def initialize(multi_step: nil, full_order: nil)
    @multi_step = multi_step
    @full_order = full_order
    @execution_order = []
    @counter = 0
  end

  circulator :multi_step do
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

  circulator :full_order do
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

class HashAllowIfValidSampler
  extend Circulator

  attr_accessor :status, :priority

  def initialize(status: nil, priority: nil)
    @status = status
    @priority = priority
  end

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

class HashAllowIfFromSampler
  extend Circulator

  attr_accessor :status, :priority

  def initialize(status: nil, priority: nil)
    @status = status
    @priority = priority
  end

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

class HashAllowIfNonSymbolValidStatesSampler
  extend Circulator

  attr_accessor :status, :level

  def initialize(status: nil, level: nil)
    @status = status
    @level = level
  end

  circulator :level do
    state :basic do
    end

    state :advanced do
    end

    state "premium" do
    end

    state 99 do
    end
  end

  circulator :status do
    state :pending do
      # Use symbols, strings, and integers in the valid_states array
      action :process, to: :processed, allow_if: {level: [:advanced, "premium", 99]}
    end
  end
end

class AvailableFlowsSampler
  extend Circulator

  attr_accessor :basic, :terminal, :simple

  def initialize(basic: nil, terminal: nil, simple: nil)
    @basic = basic
    @terminal = terminal
    @simple = simple
  end

  circulator :basic do
    state :pending do
      action :approve, to: :approved
      action :reject, to: :rejected
    end

    state :approved do
      action :archive, to: :archived
    end

    state :rejected
    state :archived
  end

  circulator :terminal do
    state :pending do
      action :approve, to: :approved
    end

    state :approved
  end

  circulator :simple do
    state :pending do
      action :approve, to: :approved
    end
  end
end

class AvailableFlowsGuardedSampler
  extend Circulator

  attr_accessor :conditional, :symbolic, :ready

  def initialize(conditional: nil, symbolic: nil)
    @conditional = conditional
    @symbolic = symbolic
  end

  def ready?
    ready
  end

  circulator :conditional do
    state :pending do
      action :approve, to: :approved, allow_if: -> { ready }
      action :reject, to: :rejected
    end
  end

  circulator :symbolic do
    state :pending do
      action :approve, to: :approved, allow_if: :ready?
      action :reject, to: :rejected
    end
  end
end

class AvailableFlowsHashSampler
  extend Circulator

  attr_accessor :status, :review_status

  def initialize(status: nil, review_status: nil)
    @status = status
    @review_status = review_status
  end

  circulator :review_status do
    state :pending do
      action :approve_review, to: :approved
    end

    state :approved
  end

  circulator :status do
    state :draft do
      action :publish, to: :published, allow_if: {review_status: :approved}
      action :submit, to: :submitted
    end
  end
end

class AvailableFlowsArgsSampler
  extend Circulator

  attr_accessor :proc_arg, :symbol_arg, :kwargs_arg

  def initialize(proc_arg: nil, symbol_arg: nil, kwargs_arg: nil)
    @proc_arg = proc_arg
    @symbol_arg = symbol_arg
    @kwargs_arg = kwargs_arg
  end

  def can_approve?(min_level)
    min_level >= 5
  end

  def can_approve_kwargs?(level:, priority:)
    level >= 5 && priority == :high
  end

  circulator :proc_arg do
    state :pending do
      action :approve, to: :approved, allow_if: ->(min_level) { min_level >= 5 }
      action :reject, to: :rejected
    end
  end

  circulator :symbol_arg do
    state :pending do
      action :approve, to: :approved, allow_if: :can_approve?
      action :reject, to: :rejected
    end
  end

  circulator :kwargs_arg do
    state :pending do
      action :approve, to: :approved, allow_if: :can_approve_kwargs?
      action :reject, to: :rejected
    end
  end
end

class ArrayAllowIfSampler
  extend Circulator

  attr_accessor :status, :approved, :in_budget

  def initialize(status: nil)
    @status = status
    @approved = false
    @in_budget = false
  end

  def approved?
    @approved
  end

  def in_budget?
    @in_budget
  end

  circulator :status do
    state :pending do
      action :approve, to: :approved, allow_if: [:approved?, :in_budget?]
    end
  end
end

class MixedAllowIfCheckSampler
  extend Circulator

  attr_accessor :status, :admin

  def initialize(status: nil)
    @status = status
  end

  def check?
    true
  end

  circulator :status do
    state :pending do
      action :approve, to: :approved, allow_if: [:check?, -> { @admin }]
    end
  end
end

class FlowMergeSampler
  extend Circulator

  attr_accessor :status, :counter

  def initialize
    @counter = 0
  end

  def admin?
    true
  end
end

class CirculatorFlowTest < Minitest::Test
  describe "Flow state machine behavior" do
    describe "basic state transitions" do
      it "transitions from pending to approved" do
        obj = FlowClassSampler.new(status: :pending, counter: 0, approval_count: 0, notes: "Initial submission")
        obj.user_role = "manager"
        obj.status_approve
        assert_equal :approved, obj.status
      end

      it "transitions from pending to rejected" do
        obj = FlowClassSampler.new(status: :pending, counter: 0, approval_count: 0, notes: "Initial submission")
        obj.status_reject
        assert_equal :rejected, obj.status
      end

      it "transitions from pending to on_hold" do
        obj = FlowClassSampler.new(status: :pending, counter: 0, approval_count: 0, notes: "Initial submission")
        obj.status_hold
        assert_equal :on_hold, obj.status
      end

      it "executes transition blocks" do
        obj = FlowClassSampler.new(status: :pending, counter: 0, approval_count: 0, notes: "Initial submission")
        obj.user_role = "admin"
        obj.status_approve
        assert_equal :approved, obj.status
        assert_equal 1, obj.approval_count
      end

      it "updates notes during rejection" do
        obj = FlowClassSampler.new(status: :pending, counter: 0, approval_count: 0, notes: "Initial submission")
        obj.status_reject
        assert_equal :rejected, obj.status
        assert_equal "Rejected: Initial submission", obj.notes
      end
    end

    describe "conditional transitions" do
      it "allows approval for admin users" do
        obj = FlowClassSampler.new(status: :pending, approval_count: 0)
        obj.user_role = "admin"
        obj.status_approve
        assert_equal :approved, obj.status
        assert_equal 1, obj.approval_count
      end

      it "allows approval for manager users" do
        obj = FlowClassSampler.new(status: :pending, approval_count: 0)
        obj.user_role = "manager"
        obj.status_approve
        assert_equal :approved, obj.status
        assert_equal 1, obj.approval_count
      end

      it "prevents approval for regular users" do
        obj = FlowClassSampler.new(status: :pending, approval_count: 0)
        obj.user_role = "user"
        obj.status_approve
        assert_equal :pending, obj.status
        assert_equal 0, obj.approval_count
      end

      it "prevents approval for nil user role" do
        obj = FlowClassSampler.new(status: :pending, approval_count: 0)
        obj.user_role = nil
        obj.status_approve
        assert_equal :pending, obj.status
        assert_equal 0, obj.approval_count
      end
    end

    describe "symbol-based allow_if" do
      it "allows transition when symbol method returns true" do
        obj = SymbolAllowIfSampler.new(status: :pending)
        obj.active = true

        obj.status_activate
        assert_equal :active, obj.status
      end

      it "prevents transition when symbol method returns false" do
        obj = SymbolAllowIfSampler.new(status: :pending)
        obj.active = false

        obj.status_activate
        assert_equal :pending, obj.status
      end

      it "prevents transition when symbol method returns nil" do
        obj = SymbolAllowIfSampler.new(status: :pending)
        obj.active = nil

        obj.status_activate
        assert_equal :pending, obj.status
      end

      it "works with multiple symbol-based allow_if conditions" do
        obj = SymbolAllowIfSampler.new(status: :pending)

        # First action requires active? to be true
        obj.active = false
        obj.status_activate
        assert_equal :pending, obj.status

        # Second action requires premium? to be true
        obj.premium_user = true
        obj.status_upgrade
        assert_equal :premium, obj.status
      end

      it "raises ArgumentError when method doesn't exist" do
        error = assert_raises(ArgumentError) do
          Class.new do
            extend Circulator

            attr_accessor :status

            circulator :status do
              state :pending do
                action :process, to: :processed, allow_if: :nonexistent_method?
              end
            end
          end
        end
        assert_match(/allow_if references undefined method :nonexistent_method\?/, error.message)
      end

      it "works with transition blocks" do
        block_object = SymbolAllowIfSampler.new(block_status: :pending, active: true)

        block_object.block_status_activate
        assert_equal :active, block_object.block_status
        assert_equal 1, block_object.activated_count
      end

      it "is equivalent to proc-based allow_if" do
        obj = SymbolAllowIfSampler.new(status: :pending, proc_status: :pending, active: true)

        # Test symbol-based
        obj.status_activate
        symbol_result = obj.status

        # Test proc-based
        obj.proc_status_activate
        proc_result = obj.proc_status

        # Both should have same result
        assert_equal :active, symbol_result
        assert_equal :active, proc_result
      end
    end

    describe "complex workflow scenarios" do
      it "handles complete approval workflow" do
        obj = FlowClassSampler.new(status: :pending, approval_count: 0, notes: "Initial submission")
        obj.user_role = "admin"

        # Approve
        obj.status_approve
        assert_equal :approved, obj.status
        assert_equal 1, obj.approval_count

        # Publish
        obj.status_publish
        assert_equal :published, obj.status
        assert_equal "Published: Initial submission", obj.notes

        # Archive
        obj.status_archive
        assert_equal "override_archive", obj.status

        # Restore
        obj.status_restore
        assert_equal :published, obj.status
      end

      it "handles rejection and resubmission workflow" do
        obj = FlowClassSampler.new(status: :pending, notes: "Initial submission")

        # Reject
        obj.status_reject
        assert_equal :rejected, obj.status
        assert_equal "Rejected: Initial submission", obj.notes

        # Resubmit
        obj.status_resubmit
        assert_equal :pending, obj.status
        assert_equal "Resubmitted: Rejected: Initial submission", obj.notes
      end

      it "handles request changes workflow" do
        obj = FlowClassSampler.new(status: :approved, notes: "Original notes")

        # Request changes
        obj.status_request_changes
        assert_equal :pending, obj.status
        assert_equal "Changes requested: Original notes", obj.notes
      end

      it "handles hold and approval workflow" do
        obj = FlowClassSampler.new(status: :pending, approval_count: 0)
        obj.user_role = "user"

        # Put on hold
        obj.status_hold
        assert_equal :on_hold, obj.status

        # Try to approve as user (should fail)
        obj.status_approve
        assert_equal :on_hold, obj.status
        assert_equal 0, obj.approval_count

        # Approve as admin
        obj.user_role = "admin"
        obj.status_approve
        assert_equal :approved, obj.status
        assert_equal 1, obj.approval_count
      end
    end

    describe "flow method with arguments" do
      it "passes arguments to transition blocks" do
        instance_with_args = FlowWithArgsSampler.new(status: :pending)

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
        obj = FlowClassSampler.new(status: :pending)
        assert_raises(RuntimeError) do
          obj.flow(:invalid_action, :status)
        end
      end

      it "raises error with no starting state" do
        obj = FlowClassSampler.new
        assert_raises(RuntimeError) do
          obj.status_approve
        end
        assert_nil obj.status
      end

      it "handles string status values" do
        obj = FlowClassSampler.new(status: "pending")
        obj.user_role = "admin"
        obj.status_approve
        assert_equal :approved, obj.status
      end
    end

    describe "multiple flows on same object" do
      it "manages multiple flows independently" do
        multi_instance = MultiFlowSampler.new(status: :pending, priority: :low, counter: 0)

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
        obj = FlowClassSampler.new
        assert_includes obj.methods, :status_approve
        assert_includes obj.methods, :status_reject
        assert_includes obj.methods, :status_hold
        assert_includes obj.methods, :status_publish
        assert_includes obj.methods, :status_request_changes
        assert_includes obj.methods, :status_resubmit
        assert_includes obj.methods, :status_archive
        assert_includes obj.methods, :status_restore
      end

      it "allows for method overrides" do
        obj = FlowClassSampler.new(status: :published)
        obj.status_archive
        assert_equal "override_archive", obj.status
      end
    end

    describe "state predicate methods" do
      it "creates predicate methods for all defined states" do
        obj = FlowClassSampler.new
        assert_includes obj.methods, :status_pending?
        assert_includes obj.methods, :status_approved?
        assert_includes obj.methods, :status_rejected?
        assert_includes obj.methods, :status_published?
        assert_includes obj.methods, :status_archived?
        assert_includes obj.methods, :status_on_hold?
        assert_includes obj.methods, :status_override_archive?
      end

      it "returns true when state matches current value" do
        obj = FlowClassSampler.new(status: :pending)
        assert obj.status_pending?
        refute obj.status_approved?
        refute obj.status_rejected?
      end

      it "returns false when state does not match current value" do
        obj = FlowClassSampler.new(status: :approved)
        refute obj.status_pending?
        assert obj.status_approved?
        refute obj.status_rejected?
      end

      it "works with string values" do
        obj = FlowClassSampler.new(status: "pending")
        assert obj.status_pending?
        refute obj.status_approved?
      end

      it "does not create predicate method for nil state" do
        nil_state_object = NilStateSampler.new

        # Should not create a method for nil state
        refute_includes nil_state_object.methods, :status_?
        # But should create method for pending state
        assert_includes nil_state_object.methods, :status_pending?
        refute nil_state_object.status_pending?
      end

      it "skips creating predicate method if it already exists" do
        skip_method_object = SkipMethodSampler.new(status: :pending)

        # Should use the predicate method (doesn't matter which flow created it)
        assert skip_method_object.status_pending?

        # Should also have predicate for approved state
        skip_method_object = SkipMethodSampler.new(status: :approved)
        assert skip_method_object.status_approved?
      end
    end

    describe "no_action behavior" do
      it "calls custom no_action block when no transition exists" do
        obj = NoActionFlowSampler.new(status: :pending)

        # Try an action that doesn't exist for pending state
        obj.status_reject

        assert obj.no_action_called
        assert_equal({
          attribute_name: :status,
          action: :reject
        }, obj.no_action_args)
        # Status should remain unchanged
        assert_equal :pending, obj.status
      end

      it "calls custom no_action block when state is nil" do
        obj = NoActionFlowSampler.new

        obj.status_approve

        assert obj.no_action_called
        assert_equal({
          attribute_name: :status,
          action: :approve
        }, obj.no_action_args)
        assert_nil obj.status
      end

      it "calls custom no_action block when state is unknown" do
        obj = NoActionFlowSampler.new(status: :unknown_state)

        obj.status_approve

        assert obj.no_action_called
        assert_equal({
          attribute_name: :status,
          action: :approve
        }, obj.no_action_args)
        assert_equal :unknown_state, obj.status
      end

      it "does not call no_action block when transition exists" do
        obj = NoActionFlowSampler.new(status: :pending)

        obj.status_approve

        refute obj.no_action_called
        assert_equal :approved, obj.status
      end

      it "allows no_action block to raise custom errors" do
        obj = NoActionBehaviorSampler.new(error_status: :pending)

        error = assert_raises(RuntimeError) do
          obj.error_status_reject
        end
        assert_equal "Custom error: Cannot perform reject on error_status", error.message
        assert_equal :pending, obj.error_status
      end

      it "allows no_action block to perform side effects" do
        obj = NoActionBehaviorSampler.new(side_effect_status: :pending)

        obj.side_effect_status_reject
        assert_equal 1, obj.side_effect_count
        assert_equal :reject, obj.last_action_attempted

        obj.side_effect_status_publish
        assert_equal 2, obj.side_effect_count
        assert_equal :publish, obj.last_action_attempted
      end

      it "handles string status values in no_action blocks" do
        obj = NoActionBehaviorSampler.new(track_status: "pending")

        obj.track_status_reject

        assert obj.no_action_called
        assert_equal "pending", obj.track_status
      end

      it "defaults to raising error when no no_action block is specified" do
        obj = NoActionBehaviorSampler.new(default_status: :pending)

        assert_raises(RuntimeError) do
          obj.default_status_reject
        end
      end

      it "allows no_action block to be set and retrieved" do
        # Create a flow instance directly
        flow_instance = Circulator::Flow.new(FlowClassSampler, :status) {}

        # Set custom no_action block
        custom_block = ->(attr, action) { "custom behavior" }
        flow_instance.no_action(&custom_block)

        # Retrieve the block
        retrieved_block = flow_instance.no_action

        assert_equal custom_block, retrieved_block
      end

      it "handles multiple no_action calls correctly" do
        obj = NoActionBehaviorSampler.new(multi_status: :pending)

        obj.multi_status_reject

        # Should only call the last no_action block
        assert_equal 10, obj.call_count
      end
    end

    describe "callable to: behavior" do
      it "uses callable to: for simple state transitions" do
        obj = CallableToSampler.new(status: :pending)

        obj.status_approve

        assert_equal :approved, obj.status
      end

      it "executes callable to: with side effects" do
        obj = CallableToSampler.new(status: :pending, counter: 0)

        obj.status_increment

        assert_equal :incremented, obj.status
        assert_equal 1, obj.counter
      end

      it "passes arguments to callable to:" do
        obj = CallableToSampler.new(status: :pending)

        obj.status_custom("arg1", "arg2", key1: "value1", key2: "value2")

        assert_equal :custom_state, obj.status
        assert_equal ["arg1", "arg2"], obj.transition_args
        assert_equal({key1: "value1", key2: "value2"}, obj.transition_kwargs)
      end

      it "uses callable to: for conditional state transitions" do
        obj = CallableToSampler.new(status: :approved)

        # High priority
        obj.status_process("high")
        assert_equal :urgent, obj.status

        # Low priority
        obj = CallableToSampler.new(status: :approved)
        obj.status_process("low")
        assert_equal :normal, obj.status

        # Unknown priority
        obj = CallableToSampler.new(status: :approved)
        obj.status_process("unknown")
        assert_equal :pending, obj.status
      end

      it "handles callable to: with default arguments" do
        obj = CallableToSampler.new(status: :urgent)

        # With arguments
        obj.status_resolve("admin", "bug fix")
        assert_equal :resolved, obj.status
        assert_equal "admin", obj.instance_variable_get(:@resolver)
        assert_equal "bug fix", obj.instance_variable_get(:@reason)

        # With default argument
        obj = CallableToSampler.new(status: :urgent)
        obj.status_resolve("user")
        assert_equal :resolved, obj.status
        assert_equal "user", obj.instance_variable_get(:@resolver)
        assert_equal "default", obj.instance_variable_get(:@reason)
      end

      it "works with from: option and callable to:" do
        # Test reset from different states
        [:approved, :urgent, :normal, :resolved].each do |state|
          obj = CallableToSampler.new(status: state)
          obj.status_reset
          assert_equal :pending, obj.status
        end
      end

      it "handles callable to: with from: option and arguments" do
        # From normal state
        obj = CallableToSampler.new(status: :normal)
        obj.status_escalate(3)
        assert_equal :level_3, obj.status

        # From pending state
        obj = CallableToSampler.new(status: :pending)
        obj.status_escalate(1)
        assert_equal :level_1, obj.status
      end

      it "executes transition blocks before callable to:" do
        transition_block_object = CallableToBlockInteractionSampler.new(exec_status: :pending)

        transition_block_object.exec_status_process

        assert transition_block_object.block_executed
        assert_equal :approved, transition_block_object.exec_status
        assert_equal :processed, transition_block_object.final_state
      end

      it "respects allow_if conditions with callable to:" do
        conditional_object = CallableToConditionalSampler.new(status: :pending)

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
        complex_object = CallableToComplexSampler.new(status: :pending)

        complex_object.status_complete("admin", "All tests passing")

        assert_equal :completed, complex_object.status
        assert_includes complex_object.log, "Completed by admin"
        assert_includes complex_object.log, "Note: All tests passing"
        assert_instance_of Time, complex_object.timestamp
      end

      it "handles callable to: that returns nil or invalid states" do
        nil_return_object = CallableToEdgeCasesSampler.new(nil_return: :pending)

        # Should handle nil return
        nil_return_object.nil_return_process
        assert_nil nil_return_object.nil_return

        # Should handle string return
        nil_return_object = CallableToEdgeCasesSampler.new(nil_return: :pending)
        nil_return_object.nil_return_invalid
        assert_equal "invalid_state", nil_return_object.nil_return
      end

      it "works with string status values and callable to:" do
        string_status_object = CallableToEdgeCasesSampler.new(string_return: "pending")

        string_status_object.string_return_approve

        assert_equal "approved", string_status_object.string_return
      end
    end

    describe "nil to: and from: behavior" do
      it "handles nil transitions" do
        # Transition to nil
        obj = NilBehaviorSampler.new(status: :pending)
        obj.status_clear
        assert_nil obj.status
        assert_equal ["cleared"], obj.transition_log

        # Transition from nil
        obj.status_initialize
        assert_equal :pending, obj.status
        assert_equal ["cleared", "initialized"], obj.transition_log

        # Transition to :approved then reset to nil
        obj.status_approve
        assert_equal :approved, obj.status
        obj.status_reset
        assert_nil obj.status
        assert_equal ["cleared", "initialized", "reset"], obj.transition_log

        # Transition from multiple states including nil
        obj.status_restart
        assert_equal :pending, obj.status
        assert_equal ["cleared", "initialized", "reset", "restarted"], obj.transition_log
      end

      it "works with callable to: that returns nil" do
        callable_nil_object = CallableToEdgeCasesSampler.new(conditional_return: :pending)

        # When should_clear is true
        callable_nil_object.should_clear = true
        callable_nil_object.conditional_return_conditional_clear
        assert_nil callable_nil_object.conditional_return

        # When should_clear is false
        callable_nil_object = CallableToEdgeCasesSampler.new(conditional_return: :pending)
        callable_nil_object.should_clear = false
        callable_nil_object.conditional_return_conditional_clear
        assert_equal :approved, callable_nil_object.conditional_return
      end

      it "handles nil with allow_if conditions" do
        obj = NilTransitionsSampler.new(conditional_status: :pending)

        # Test to: nil with condition
        obj.user_role = "user"
        obj.conditional_status_clear
        assert_equal :pending, obj.conditional_status
        assert_equal 0, obj.transition_count

        obj.user_role = "admin"
        obj.conditional_status_clear
        assert_nil obj.conditional_status
        assert_equal 1, obj.transition_count

        # Test from: nil with condition
        obj.user_role = "user"
        obj.conditional_status_initialize
        assert_nil obj.conditional_status
        assert_equal 1, obj.transition_count

        obj.user_role = "admin"
        obj.conditional_status_initialize
        assert_equal :pending, obj.conditional_status
        assert_equal 2, obj.transition_count
      end

      it "works with blocks and nil transitions" do
        obj = NilTransitionsSampler.new(block_status: :pending)

        # Test to: nil with block
        obj.block_status_clear do
          @execution_order << "method_block"
        end
        assert_nil obj.block_status
        assert_equal ["transition_block", "method_block"], obj.execution_order

        # Test from: nil with block
        obj.execution_order = []
        obj.block_status_initialize do
          @execution_order << "method_block"
        end
        assert_equal :pending, obj.block_status
        assert_equal ["transition_block", "method_block"], obj.execution_order
      end

      it "handles string status values with nil transitions" do
        obj = NilTransitionsSampler.new(string_status: "pending")

        # Test to: nil with symbol status (converted from string)
        obj.string_status_clear
        assert_nil obj.string_status

        # Test from: nil to symbol status
        obj.string_status_initialize
        assert_equal :pending, obj.string_status
      end

      it "works with no_action when transitioning to/from nil" do
        obj = NilTransitionsSampler.new

        # Test that no_action is called for invalid actions when status is nil
        obj.no_action_status_approve
        assert obj.no_action_called
        assert_nil obj.no_action_status

        # Test that no_action is NOT called for valid actions when status is nil
        obj.no_action_called = false
        obj.no_action_status_clear
        refute obj.no_action_called
        assert_nil obj.no_action_status
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
      it "executes blocks passed to dynamically defined methods" do
        obj = BlockFlowSampler.new(status: :pending)
        block_executed = false

        obj.status_approve do
          block_executed = true
          @execution_order << "method_block"
        end

        assert block_executed
        assert_equal :approved, obj.status
        assert_equal ["transition_block", "method_block"], obj.execution_order
      end

      it "passes arguments to blocks passed to methods" do
        obj = BlockFlowSampler.new(status: :pending)

        obj.status_approve("arg1", "arg2", key1: "value1") do |*args, **kwargs|
          @block_args = args
          @block_kwargs = kwargs
          @execution_order << "method_block"
        end

        assert_equal ["arg1", "arg2"], obj.block_args
        assert_equal({key1: "value1"}, obj.block_kwargs)
        assert_equal :approved, obj.status
      end

      it "executes blocks passed to flow method" do
        obj = BlockFlowSampler.new(status: :pending)
        block_executed = false

        obj.flow(:approve, :status) do
          block_executed = true
          @execution_order << "flow_block"
        end

        assert block_executed
        assert_equal :approved, obj.status
        assert_equal ["transition_block", "flow_block"], obj.execution_order
      end

      it "passes arguments through flow method to blocks" do
        obj = BlockFlowSampler.new(status: :pending)

        obj.flow(:approve, :status, "arg1", "arg2", key1: "value1") do |*args, **kwargs|
          @block_args = args
          @block_kwargs = kwargs
          @execution_order << "flow_block"
        end

        assert_equal ["arg1", "arg2"], obj.block_args
        assert_equal({key1: "value1"}, obj.block_kwargs)
        assert_equal :approved, obj.status
      end

      it "executes blocks even when no transition block is defined" do
        obj = BlockFlowSampler.new(status: :pending)
        block_executed = false

        obj.status_reject do
          block_executed = true
          @execution_order << "method_block"
        end

        assert block_executed
        assert_equal :rejected, obj.status
        assert_equal ["method_block"], obj.execution_order
      end

      it "executes blocks with callable to: transitions" do
        callable_block_object = CallableToBlockInteractionSampler.new(order_status: :pending)

        callable_block_object.order_status_process do
          @execution_order << "method_block"
        end

        assert_equal :processed, callable_block_object.order_status
        assert_equal ["transition_block", "callable_to", "method_block"], callable_block_object.execution_order
      end

      it "executes blocks when allow_if condition is true" do
        obj = Sampler.new(status: :rejected)
        obj.user_role = "admin"

        obj.status_reconsider do
          @block_executed = true
        end

        assert obj.block_executed
        assert_equal :pending, obj.status
      end

      it "does not execute blocks when allow_if condition is false" do
        obj = Sampler.new(status: :rejected)
        obj.user_role = "user"

        obj.status_reconsider do
          @block_executed = true
        end

        refute obj.block_executed
        assert_equal :rejected, obj.status
      end

      it "does not execute blocks with no_action when no transition exists" do
        obj = Sampler.new(status: :pending)

        obj.status_publish do
          @block_executed = true
        end

        refute obj.block_executed # block should NOT be called
        assert_equal :pending, obj.status
        assert_includes obj.transition_log, "No action: status.publish"
      end

      it "handles multiple blocks in complex scenarios" do
        obj = BlockExecutionOrderSampler.new(multi_step: :pending)

        # First transition with block
        obj.multi_step_process do
          @execution_order << "method_block_1"
        end

        # Second transition with block
        obj.multi_step_complete do
          @execution_order << "method_block_2"
        end

        assert_equal :completed, obj.multi_step
        assert_equal 1, obj.counter
        assert_equal [
          "transition_block", "method_block_1",
          "transition_block", "method_block_2"
        ], obj.execution_order
      end

      it "works with string status values and blocks" do
        string_block_object = StringBlockSampler.new(status: "pending")

        string_block_object.status_approve do
          @block_executed = true
        end

        assert string_block_object.block_executed
        assert_equal "approved", string_block_object.status
      end

      it "handles blocks with from: option" do
        from_block_object = FromBlockSampler.new(status: :approved)

        from_block_object.status_reset do
          @block_executed = true
        end

        assert from_block_object.block_executed
        assert_equal :pending, from_block_object.status
      end

      it "executes blocks in correct order with all flow features" do
        obj = BlockExecutionOrderSampler.new(full_order: :pending)

        obj.full_order_process("arg1", key1: "value1") do |*args, **kwargs|
          @execution_order << "method_block"
        end

        assert_equal :processing, obj.full_order
        assert_equal [
          "transition_block", "callable_to", "method_block"
        ], obj.execution_order
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

      assert_match(/allow_if must be a Proc, Hash, Symbol, or Array/, error.message)
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
      instance = HashAllowIfValidSampler.new
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
      instance = HashAllowIfValidSampler.new(status: :pending, priority: :high)

      instance.status_approve
      assert_equal :approved, instance.status
    end

    it "blocks transition when dependency state doesn't match" do
      instance = HashAllowIfValidSampler.new(status: :pending, priority: :low)

      instance.status_approve
      assert_equal :pending, instance.status
    end

    it "handles string states in runtime evaluation" do
      instance = HashAllowIfValidSampler.new(status: :pending, priority: "high")

      instance.status_approve
      assert_equal :approved, instance.status
    end

    it "works with from: option and hash-based allow_if" do
      instance = HashAllowIfFromSampler.new(status: :pending, priority: :high)

      instance.status_approve
      assert_equal :approved, instance.status
    end

    it "handles hash-based allow_if with non-symbol state values" do
      # Test with integer priority (doesn't respond to :to_sym)
      instance = HashAllowIfValidSampler.new(status: :pending, priority: 1)
      instance.status_approve
      assert_equal :pending, instance.status

      # Test with string priority
      instance = HashAllowIfValidSampler.new(status: :pending, priority: "high")
      instance.status_approve
      assert_equal :approved, instance.status
    end

    it "handles hash-based allow_if with non-symbol valid states" do
      # Test with symbol level
      instance = HashAllowIfNonSymbolValidStatesSampler.new(status: :pending, level: :advanced)
      instance.status_process
      assert_equal :processed, instance.status

      # Test with string level that's in valid_states
      instance = HashAllowIfNonSymbolValidStatesSampler.new(status: :pending, level: "premium")
      instance.status_process
      assert_equal :processed, instance.status

      # Test with integer level that's in valid_states (doesn't respond to to_sym)
      instance = HashAllowIfNonSymbolValidStatesSampler.new(status: :pending, level: 99)
      instance.status_process
      assert_equal :processed, instance.status

      # Test with level not in valid_states
      instance = HashAllowIfNonSymbolValidStatesSampler.new(status: :pending, level: :basic)
      instance.status_process
      assert_equal :pending, instance.status
    end

    describe "available_flows" do
      it "returns actions available from current state" do
        object = AvailableFlowsSampler.new(basic: :pending)

        actions = object.available_flows(:basic)
        assert_equal [:approve, :reject].sort, actions.sort
      end

      it "returns empty array when no actions available" do
        object = AvailableFlowsSampler.new(terminal: :approved)

        actions = object.available_flows(:terminal)
        assert_equal [], actions
      end

      it "returns empty array for undefined attribute" do
        object = AvailableFlowsSampler.new(simple: :pending)

        actions = object.available_flows(:nonexistent)
        assert_equal [], actions
      end

      it "respects proc-based allow_if conditions" do
        object = AvailableFlowsGuardedSampler.new(conditional: :pending)
        object.ready = false

        actions = object.available_flows(:conditional)
        assert_equal [:reject], actions

        object.ready = true
        actions = object.available_flows(:conditional)
        assert_equal [:approve, :reject].sort, actions.sort
      end

      it "respects symbol-based allow_if conditions" do
        object = AvailableFlowsGuardedSampler.new(symbolic: :pending)
        object.ready = false

        actions = object.available_flows(:symbolic)
        assert_equal [:reject], actions

        object.ready = true
        actions = object.available_flows(:symbolic)
        assert_equal [:approve, :reject].sort, actions.sort
      end

      it "respects hash-based allow_if conditions" do
        object = AvailableFlowsHashSampler.new(status: :draft, review_status: :pending)

        actions = object.available_flows(:status)
        assert_equal [:submit], actions

        object = AvailableFlowsHashSampler.new(status: :draft, review_status: :approved)
        actions = object.available_flows(:status)
        assert_equal [:publish, :submit].sort, actions.sort
      end

      it "works with string attribute values" do
        object = AvailableFlowsSampler.new(simple: "pending")

        actions = object.available_flows(:simple)
        assert_equal [:approve], actions
      end

      it "passes arguments to proc-based allow_if" do
        object = AvailableFlowsArgsSampler.new(proc_arg: :pending)

        actions = object.available_flows(:proc_arg, 3)
        assert_equal [:reject], actions

        actions = object.available_flows(:proc_arg, 10)
        assert_equal [:approve, :reject].sort, actions.sort
      end

      it "passes arguments to symbol-based allow_if" do
        object = AvailableFlowsArgsSampler.new(symbol_arg: :pending)

        actions = object.available_flows(:symbol_arg, 3)
        assert_equal [:reject], actions

        actions = object.available_flows(:symbol_arg, 10)
        assert_equal [:approve, :reject].sort, actions.sort
      end

      it "passes keyword arguments to allow_if" do
        object = AvailableFlowsArgsSampler.new(kwargs_arg: :pending)

        actions = object.available_flows(:kwargs_arg, level: 10, priority: :low)
        assert_equal [:reject], actions

        actions = object.available_flows(:kwargs_arg, level: 10, priority: :high)
        assert_equal [:approve, :reject].sort, actions.sort
      end
    end

    describe "available_flow?" do
      it "returns true when action is available" do
        object = AvailableFlowsSampler.new(simple: :pending)

        assert object.available_flow?(:simple, :approve)
      end

      it "returns false when action is not available" do
        object = AvailableFlowsSampler.new(basic: :pending)

        assert object.available_flow?(:basic, :approve)
        refute object.available_flow?(:basic, :archive)
      end

      it "returns false for undefined attribute" do
        object = AvailableFlowsSampler.new(simple: :pending)

        refute object.available_flow?(:nonexistent, :approve)
      end

      it "respects allow_if conditions" do
        object = AvailableFlowsGuardedSampler.new(conditional: :pending)
        object.ready = false

        refute object.available_flow?(:conditional, :approve)
        assert object.available_flow?(:conditional, :reject)

        object.ready = true
        assert object.available_flow?(:conditional, :approve)
        assert object.available_flow?(:conditional, :reject)
      end

      it "passes arguments to allow_if" do
        object = AvailableFlowsArgsSampler.new(proc_arg: :pending)

        refute object.available_flow?(:proc_arg, :approve, 3)
        assert object.available_flow?(:proc_arg, :approve, 10)
      end

      it "validates array allow_if with symbols" do
        object = ArrayAllowIfSampler.new(status: :pending)

        # Both conditions false
        refute object.available_flow?(:status, :approve)

        # One condition true
        object.approved = true
        refute object.available_flow?(:status, :approve)

        # Both conditions true
        object.in_budget = true
        assert object.available_flow?(:status, :approve)

        # Can actually transition
        object.status_approve
        assert object.status_approved?
      end

      it "validates empty array raises error" do
        error = assert_raises(ArgumentError) do
          Class.new do
            extend Circulator

            attr_accessor :status

            circulator :status do
              state :pending do
                action :approve, to: :approved, allow_if: []
              end
            end
          end
        end

        assert_match(/allow_if array must not be empty/, error.message)
      end

      it "validates array elements must be symbols or procs" do
        error = assert_raises(ArgumentError) do
          Class.new do
            extend Circulator

            attr_accessor :status

            circulator :status do
              state :pending do
                action :approve, to: :approved, allow_if: [:valid?, "invalid_string"]
              end
            end
          end
        end

        assert_match(/allow_if array elements must be Symbols or Procs/, error.message)
      end

      it "validates undefined method in array raises error" do
        error = assert_raises(ArgumentError) do
          Class.new do
            extend Circulator

            attr_accessor :status

            circulator :status do
              state :pending do
                action :approve, to: :approved, allow_if: [:undefined_method?]
              end
            end
          end
        end

        assert_match(/allow_if references undefined method/, error.message)
        assert_match(/:undefined_method\?/, error.message)
      end

      it "guards_for returns symbol guards from array allow_if" do
        object = ArrayAllowIfSampler.new(status: :pending)
        object.approved = true
        object.in_budget = true

        guards = object.guards_for(:status, :approve)
        assert_equal [:approved?, :in_budget?], guards
      end

      it "guards_for returns nil for non-array allow_if" do
        object = SymbolAllowIfSampler.new(status: :pending)

        # Symbol guards return nil
        assert_nil object.guards_for(:status, :activate)
      end

      it "supports mixing symbols and procs in array allow_if" do
        object = MixedAllowIfCheckSampler.new(status: :pending)
        object.admin = false

        refute object.available_flow?(:status, :approve)

        object.admin = true
        assert object.available_flow?(:status, :approve)
      end

      it "guards_for with mixed symbols and procs returns only symbols" do
        object = MixedAllowIfCheckSampler.new(status: :pending)

        guards = object.guards_for(:status, :approve)
        assert_equal [:check?], guards
      end

      it "executes transition when array allow_if with proc passes" do
        object = MixedAllowIfCheckSampler.new(status: :pending)
        object.admin = true

        object.status_approve
        assert_equal :approved, object.status
      end

      it "blocks transition when array allow_if with proc fails" do
        object = MixedAllowIfCheckSampler.new(status: :pending)
        object.admin = false

        object.status_approve
        assert_equal :pending, object.status
      end
    end
  end

  describe "Flow#merge" do
    it "merges new actions into existing flow" do
      flow = Circulator::Flow.new(FlowMergeSampler, :status) do
        state :pending do
          action :approve, to: :approved
        end
      end

      assert flow.transition_map[:approve]
      refute flow.transition_map[:reject]

      flow.merge do
        state :pending do
          action :reject, to: :rejected
        end
      end

      assert flow.transition_map[:approve]
      assert flow.transition_map[:reject]
      assert_equal :rejected, flow.transition_map[:reject][:pending][:to]
    end

    it "merges new transitions into existing actions" do
      flow = Circulator::Flow.new(FlowMergeSampler, :status) do
        state :pending do
          action :cancel, to: :cancelled
        end
      end

      # Only has transition from :pending
      assert flow.transition_map[:cancel][:pending]
      refute flow.transition_map[:cancel][:processing]

      flow.merge do
        state :processing do
          action :cancel, to: :cancelled
        end
      end

      # Now has transitions from both states
      assert flow.transition_map[:cancel][:pending]
      assert flow.transition_map[:cancel][:processing]
    end

    it "returns self for chaining" do
      flow = Circulator::Flow.new(FlowMergeSampler, :status) do
        state :pending do
          action :approve, to: :approved
        end
      end

      result = flow.merge do
        state :approved do
          action :publish, to: :published
        end
      end

      assert_same flow, result
    end

    it "merges states into the flow" do
      flow = Circulator::Flow.new(FlowMergeSampler, :status) do
        state :pending do
          action :approve, to: :approved
        end
      end

      states_before = flow.instance_variable_get(:@states).to_a

      flow.merge do
        state :approved do
          action :archive, to: :archived
        end
      end

      states_after = flow.instance_variable_get(:@states).to_a
      assert_includes states_after, :archived
      assert states_after.length > states_before.length
    end

    it "allows multiple merges" do
      flow = Circulator::Flow.new(FlowMergeSampler, :status) do
        state :draft do
          action :submit, to: :pending
        end
      end

      flow.merge do
        state :pending do
          action :approve, to: :approved
        end
      end

      flow.merge do
        state :approved do
          action :publish, to: :published
        end
      end

      assert flow.transition_map[:submit]
      assert flow.transition_map[:approve]
      assert flow.transition_map[:publish]
    end

    it "overwrites existing transitions when merging same action from same state" do
      flow = Circulator::Flow.new(FlowMergeSampler, :status) do
        state :pending do
          action :approve, to: :approved
        end
      end

      assert_equal :approved, flow.transition_map[:approve][:pending][:to]

      flow.merge do
        state :pending do
          action :approve, to: :fast_tracked
        end
      end

      # The merge should overwrite the existing transition
      assert_equal :fast_tracked, flow.transition_map[:approve][:pending][:to]
    end

    it "works with action blocks" do
      flow = Circulator::Flow.new(FlowMergeSampler, :status) do
        state :pending do
          action :approve, to: :approved
        end
      end

      flow.merge do
        state :approved do
          action :count, to: :counted do
            @counter += 1
          end
        end
      end

      assert flow.transition_map[:count][:approved][:block]
    end

    it "works with allow_if conditions" do
      flow = Circulator::Flow.new(FlowMergeSampler, :status) do
        state :pending do
          action :approve, to: :approved
        end
      end

      flow.merge do
        state :pending do
          action :force_approve, to: :approved, allow_if: :admin?
        end
      end

      assert flow.transition_map[:force_approve][:pending][:allow_if]
    end
  end
end
