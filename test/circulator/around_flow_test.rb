require "test_helper"
require_relative "../sampler"

class AroundSelfSampler < SamplerBase
  extend Circulator

  attr_accessor :status, :around_self

  def initialize(status: nil)
    @status = status
  end

  flow :status do
    around do |transition|
      @around_self = self
      transition.call
    end

    state :pending do
      action :approve, to: :approved
    end
  end
end

class AroundGuardBehaviorSampler < SamplerBase
  extend Circulator

  attr_accessor :pass_status, :fail_status, :execution_order

  def initialize(pass_status: nil, fail_status: nil)
    @pass_status = pass_status
    @fail_status = fail_status
    @execution_order = []
  end

  flow :pass_status do
    around do |transition|
      @execution_order << "around_before"
      transition.call
      @execution_order << "around_after"
    end

    state :pending do
      action :approve, to: :approved, allow_if: -> {
        @execution_order << "guard_check"
        true
      }
    end
  end

  flow :fail_status do
    around do |transition|
      @execution_order << "around_before"
      transition.call
      @execution_order << "around_after"
    end

    state :pending do
      action :approve, to: :approved, allow_if: -> { false } do
        @execution_order << "transition_block"
      end
    end
  end
end

class AroundGuardedSampler < SamplerBase
  extend Circulator

  attr_accessor :status, :check_b_result, :hash_status, :review,
    :symbol_status, :proc_status

  def check_a = true

  def check_b
    @check_b_result.nil? || @check_b_result
  end

  def allowed? = true

  def initialize(status: nil, hash_status: nil, review: nil,
    symbol_status: nil, proc_status: nil)
    @status = status
    @hash_status = hash_status
    @review = review
    @symbol_status = symbol_status
    @proc_status = proc_status
  end

  flow :status do
    around do |transition|
      transition.call
    end

    state :pending do
      action :approve, to: :approved, allow_if: [:check_a, :check_b]
    end
  end

  flow :review do
    state :approved do
      action :done, to: :done
    end
  end

  flow :hash_status do
    around do |transition|
      transition.call
    end

    state :pending do
      action :approve, to: :approved, allow_if: {review: :approved}
    end
  end

  flow :symbol_status do
    around do |transition|
      transition.call
    end

    state :pending do
      action :approve, to: :approved, allow_if: :allowed?
    end
  end

  flow :proc_status do
    around do |transition|
      transition.call
    end

    state :pending do
      action :approve, to: :approved, allow_if: -> { true }
    end
  end
end

class AroundNoActionSampler < SamplerBase
  extend Circulator

  attr_accessor :status, :execution_order

  def initialize(status: nil)
    @status = status
    @execution_order = []
  end

  flow :status do
    around do |transition|
      @execution_order << "around_before"
      transition.call
      @execution_order << "around_after"
    end

    no_action { |attr, act| @execution_order << "no_action" }

    state :pending do
      action :approve, to: :approved
    end
  end
end

class AroundTransitionBlockSampler < SamplerBase
  extend Circulator

  attr_accessor :status, :execution_order

  def initialize(status: nil)
    @status = status
    @execution_order = []
  end

  flow :status do
    around do |transition|
      @execution_order << "around_before"
      transition.call
      @execution_order << "around_after"
    end

    state :pending do
      action :approve, to: :approved do
        @execution_order << "transition_block"
      end
    end
  end
end

class AroundTarget
  attr_accessor :status, :execution_order

  def initialize
    @execution_order = []
  end
end

class AroundTargetManagerSampler
  extend Circulator

  flow :status, model: "AroundTarget" do
    around do |transition|
      @execution_order << "around"
      transition.call
    end

    state :pending do
      action :approve, to: :approved
    end
  end
end

class AroundCallableToSampler < SamplerBase
  extend Circulator

  attr_accessor :status, :level

  def initialize(status: nil)
    @status = status
  end

  flow :status do
    around do |transition|
      transition.call
    end

    state :pending do
      action :approve, to: -> { (@level > 5) ? :premium : :approved }
    end
  end
end

class AroundMultiFlowSampler < SamplerBase
  extend Circulator

  attr_accessor :status, :priority, :category, :execution_order

  def initialize(status: nil, priority: nil, category: nil)
    @status = status
    @priority = priority
    @category = category
    @execution_order = []
  end

  flow :status do
    around do |transition|
      @execution_order << "status_around"
      transition.call
    end

    state :pending do
      action :approve, to: :approved
    end
  end

  flow :priority do
    around do |transition|
      @execution_order << "priority_around"
      transition.call
    end

    state :low do
      action :escalate, to: :high
    end
  end

  flow :category do
    state :low do
      action :escalate, to: :high
    end
  end
end

class AroundSkipTransitionSampler < SamplerBase
  extend Circulator

  attr_accessor :status

  def initialize(status: nil)
    @status = status
  end

  flow :status do
    around do |transition|
      # intentionally not calling transition.call
    end

    state :pending do
      action :approve, to: :approved
    end
  end
end

class AroundReturnValueSampler < SamplerBase
  extend Circulator

  attr_accessor :status

  def initialize(status: nil)
    @status = status
  end

  flow :status do
    state :pending do
      action :approve, to: :approved
    end
  end
end

class AroundNilGuardReturnSampler < SamplerBase
  extend Circulator

  attr_accessor :status

  def initialize(status: nil)
    @status = status
  end

  flow :status do
    around do |transition|
      transition.call
    end

    state :pending do
      action :approve, to: :approved, allow_if: -> { false }
    end
  end
end

class AroundFlowTest < Minitest::Test
  describe "around DSL" do
    it "wraps transitions and transition.call executes the flow logic" do
      obj = AroundFlowSampler.new(status: :pending)

      obj.status_approve
      assert_equal :approved, obj.status
      assert_equal ["around_before", "transition_block", "around_after"], obj.execution_order
    end

    it "instance_exec's the around block on the flow_target" do
      obj = AroundSelfSampler.new(status: :pending)
      obj.status_approve

      assert_same obj, obj.around_self
    end

    it "guard check happens inside the around wrapper" do
      obj = AroundGuardBehaviorSampler.new(pass_status: :pending)
      obj.pass_status_approve

      assert_equal ["around_before", "guard_check", "around_after"], obj.execution_order
    end

    it "guard failure: around completes normally, transition does not execute" do
      obj = AroundGuardBehaviorSampler.new(fail_status: :pending)
      obj.fail_status_approve

      assert_equal :pending, obj.fail_status
      assert_equal ["around_before", "around_after"], obj.execution_order
    end

    describe "all guard types work inside the wrapper" do
      it "Array guard" do
        obj = AroundGuardedSampler.new(status: :pending)
        obj.status_approve
        assert_equal :approved, obj.status
      end

      it "Array guard blocks when one fails" do
        obj = AroundGuardedSampler.new(status: :pending)
        obj.check_b_result = false
        obj.status_approve
        assert_equal :pending, obj.status
      end

      it "Hash guard" do
        obj = AroundGuardedSampler.new(hash_status: :pending, review: :approved)
        obj.hash_status_approve
        assert_equal :approved, obj.hash_status
      end

      it "Symbol guard" do
        obj = AroundGuardedSampler.new(symbol_status: :pending)
        obj.symbol_status_approve
        assert_equal :approved, obj.symbol_status
      end

      it "Proc guard" do
        obj = AroundGuardedSampler.new(proc_status: :pending)
        obj.proc_status_approve
        assert_equal :approved, obj.proc_status
      end
    end

    it "no_action runs inside the wrapper" do
      obj = AroundNoActionSampler.new(status: :approved) # no transition for :approve from :approved

      obj.status_approve
      assert_equal :approved, obj.status
      assert_equal ["around_before", "no_action", "around_after"], obj.execution_order
    end

    it "transition blocks and caller blocks execute inside the wrapper" do
      obj = AroundTransitionBlockSampler.new(status: :pending)

      obj.status_approve do
        @execution_order << "caller_block"
      end

      assert_equal ["around_before", "transition_block", "caller_block", "around_after"], obj.execution_order
    end

    it "works with flow_target: parameter" do
      target = AroundTarget.new
      target.status = :pending

      manager = AroundTargetManagerSampler.new

      manager.around_target_status_approve(flow_target: target)

      assert_equal :approved, target.status
      assert_equal ["around"], target.execution_order
    end

    it "works with callable to:" do
      obj = AroundCallableToSampler.new(status: :pending)
      obj.level = 10

      obj.status_approve
      assert_equal :premium, obj.status
    end

    it "default behavior unchanged when no around defined" do
      obj = AroundReturnValueSampler.new(status: :pending)
      obj.status_approve
      assert_equal :approved, obj.status
    end

    it "multiple flows on same class can have different around blocks" do
      obj = AroundMultiFlowSampler.new(status: :pending, priority: :low)

      obj.status_approve
      assert_equal ["status_around"], obj.execution_order

      obj.execution_order.clear
      obj.priority_escalate
      assert_equal ["priority_around"], obj.execution_order
    end

    it "one flow with around and another without" do
      obj = AroundMultiFlowSampler.new(status: :pending, category: :low)

      obj.status_approve
      assert_equal :approved, obj.status
      assert_equal ["status_around"], obj.execution_order

      obj.execution_order.clear
      obj.category_escalate
      assert_equal :high, obj.category
      assert_empty obj.execution_order
    end

    it "transition does not execute if transition.call is not called" do
      obj = AroundSkipTransitionSampler.new(status: :pending)
      obj.status_approve
      assert_equal :pending, obj.status
    end

    it "return value preserved on success" do
      obj = AroundReturnValueSampler.new(status: :pending)
      result = obj.status_approve
      assert_equal :approved, result
    end

    it "returns nil on guard failure" do
      obj = AroundNilGuardReturnSampler.new(status: :pending)
      result = obj.status_approve
      assert_nil result
    end
  end
end
