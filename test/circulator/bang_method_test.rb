require "test_helper"
require_relative "../sampler"

class BangMethodSampler
  extend Circulator

  attr_accessor :status, :user_role

  def initialize(status: nil)
    @status = status
    @user_role = nil
  end

  def admin?
    @user_role == "admin"
  end

  flow :status do
    state :pending do
      action :approve, to: :approved
      action :guarded_approve, to: :approved, allow_if: :admin?
    end

    state :approved do
      action :publish, to: :published
    end

    no_action do |attribute_name, action|
      # silent no-op for non-bang
    end
  end
end

class BangSelfTransitionSampler
  extend Circulator

  attr_accessor :status, :refreshed

  def initialize(status: nil)
    @status = status
    @refreshed = false
  end

  flow :status do
    state :active do
      action :refresh, to: :active do
        @refreshed = true
      end
    end
  end
end

class BangAroundSkipSampler
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

class BangCallableToSampler
  extend Circulator

  attr_accessor :status, :level

  def initialize(status: nil, level: 0)
    @status = status
    @level = level
  end

  flow :status do
    state :pending do
      action :escalate, to: -> { (@level > 5) ? :critical : :high }
    end
  end
end

class BangWithArgsSampler
  extend Circulator

  attr_accessor :status, :notes

  def initialize(status: nil)
    @status = status
    @notes = nil
  end

  flow :status do
    state :pending do
      action :approve, to: :approved do |reason|
        @notes = "Approved: #{reason}"
      end
    end
  end
end

class BangTargetModel
  attr_accessor :status

  def initialize
    @status = :pending
  end
end

class BangTargetManagerSampler
  extend Circulator

  flow :status, model: "BangTargetModel" do
    state :pending do
      action :approve, to: :approved
    end
  end
end

class BangAroundSampler
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

    no_action do |attribute_name, action|
      # silent no-op
    end
  end
end

class BangMethodTest < Minitest::Test
  describe "bang method variants" do
    describe "successful transitions" do
      it "transitions normally with bang method" do
        obj = BangMethodSampler.new(status: :pending)
        obj.status_approve!
        assert_equal :approved, obj.status
      end

      it "returns the new state value" do
        obj = BangMethodSampler.new(status: :pending)
        result = obj.status_approve!
        assert_equal :approved, result
      end
    end

    describe "no transition for current state" do
      it "raises InvalidTransition when no transition exists" do
        obj = BangMethodSampler.new(status: :approved)

        error = assert_raises(BangMethodSampler::InvalidTransition) do
          obj.status_approve!
        end
        assert_match(/approve/, error.message)
        assert_match(/approved/, error.message)
      end
    end

    describe "guard rejection" do
      it "raises InvalidTransition when guard rejects" do
        obj = BangMethodSampler.new(status: :pending)
        obj.user_role = "user"

        error = assert_raises(BangMethodSampler::InvalidTransition) do
          obj.status_guarded_approve!
        end
        assert_match(/guarded_approve/, error.message)
      end
    end

    describe "exception hierarchy" do
      it "defines InvalidTransition on the host class" do
        assert BangMethodSampler.const_defined?(:InvalidTransition)
      end

      it "host exception inherits from Circulator::InvalidTransition" do
        assert BangMethodSampler::InvalidTransition < Circulator::InvalidTransition
      end

      it "can be rescued as Circulator::InvalidTransition" do
        obj = BangMethodSampler.new(status: :approved)

        assert_raises(Circulator::InvalidTransition) do
          obj.status_approve!
        end
      end

      it "can be rescued as the host class exception" do
        obj = BangMethodSampler.new(status: :approved)

        assert_raises(BangMethodSampler::InvalidTransition) do
          obj.status_approve!
        end
      end
    end

    describe "with around block" do
      it "raises after around wraps the transition" do
        obj = BangAroundSampler.new(status: :approved)

        assert_raises(BangAroundSampler::InvalidTransition) do
          obj.status_approve!
        end
      end

      it "succeeds through around block" do
        obj = BangAroundSampler.new(status: :pending)
        obj.status_approve!

        assert_equal :approved, obj.status
        assert_equal ["around_before", "transition_block", "around_after"], obj.execution_order
      end
    end

    describe "self-transitions" do
      it "does not raise on self-transition" do
        obj = BangSelfTransitionSampler.new(status: :active)
        obj.status_refresh!
        assert_equal :active, obj.status
        assert obj.refreshed
      end
    end

    describe "around block that skips transition.call" do
      it "does not raise when around intentionally skips transition" do
        obj = BangAroundSkipSampler.new(status: :pending)
        obj.status_approve!
        assert_equal :pending, obj.status
      end
    end

    describe "callable to:" do
      it "works with callable to: destination" do
        obj = BangCallableToSampler.new(status: :pending, level: 10)
        obj.status_escalate!
        assert_equal :critical, obj.status
      end

      it "works with callable to: other branch" do
        obj = BangCallableToSampler.new(status: :pending, level: 1)
        obj.status_escalate!
        assert_equal :high, obj.status
      end
    end

    describe "with arguments" do
      it "passes arguments through to transition block" do
        obj = BangWithArgsSampler.new(status: :pending)
        obj.status_approve!("looks good")
        assert_equal :approved, obj.status
        assert_equal "Approved: looks good", obj.notes
      end
    end

    describe "with flow_target (model-based flows)" do
      it "transitions the target object" do
        manager = BangTargetManagerSampler.new
        target = BangTargetModel.new

        manager.bang_target_model_status_approve!(flow_target: target)
        assert_equal :approved, target.status
      end

      it "raises exception from the manager class, not the target" do
        manager = BangTargetManagerSampler.new
        target = BangTargetModel.new
        target.status = :approved

        assert_raises(BangTargetManagerSampler::InvalidTransition) do
          manager.bang_target_model_status_approve!(flow_target: target)
        end
      end
    end

    describe "non-bang methods remain unchanged" do
      it "returns nil on no transition without raising" do
        obj = BangMethodSampler.new(status: :approved)
        result = obj.status_approve
        assert_nil result
        assert_equal :approved, obj.status
      end

      it "returns nil on guard rejection without raising" do
        obj = BangMethodSampler.new(status: :pending)
        obj.user_role = "user"
        result = obj.status_guarded_approve
        assert_nil result
        assert_equal :pending, obj.status
      end
    end

    describe "flow instance method bang variant" do
      it "succeeds with flow!" do
        obj = BangMethodSampler.new(status: :pending)
        obj.flow!(:approve, :status)
        assert_equal :approved, obj.status
      end

      it "raises on invalid transition with flow!" do
        obj = BangMethodSampler.new(status: :approved)

        assert_raises(BangMethodSampler::InvalidTransition) do
          obj.flow!(:approve, :status)
        end
      end

      it "succeeds with flow variant: :bang" do
        obj = BangMethodSampler.new(status: :pending)
        obj.flow(:approve, :status, variant: :bang)
        assert_equal :approved, obj.status
      end

      it "raises on invalid transition with variant: :bang" do
        obj = BangMethodSampler.new(status: :approved)

        assert_raises(BangMethodSampler::InvalidTransition) do
          obj.flow(:approve, :status, variant: :bang)
        end
      end
    end

    describe "invalid variant raises ArgumentError" do
      it "raises on unknown variant" do
        obj = BangMethodSampler.new(status: :pending)

        error = assert_raises(ArgumentError) do
          obj.flow(:approve, :status, variant: :nonexistent)
        end
        assert_match(/nonexistent/, error.message)
      end
    end

    describe "error messages" do
      it "indicates missing transition in message" do
        obj = BangMethodSampler.new(status: :approved)

        error = assert_raises(BangMethodSampler::InvalidTransition) do
          obj.status_approve!
        end
        assert_match(/no transition/i, error.message)
      end

      it "indicates guard rejection in message" do
        obj = BangMethodSampler.new(status: :pending)
        obj.user_role = "user"

        error = assert_raises(BangMethodSampler::InvalidTransition) do
          obj.status_guarded_approve!
        end
        assert_match(/guard prevented/i, error.message)
      end
    end

    describe "exception only defined once" do
      it "reuses existing InvalidTransition across multiple flows" do
        klass = Class.new do
          extend Circulator

          attr_accessor :status, :priority

          flow :status do
            state :pending do
              action :approve, to: :approved
            end
          end

          flow :priority do
            state :low do
              action :escalate, to: :high
            end
          end
        end

        assert klass.const_defined?(:InvalidTransition)
        assert klass::InvalidTransition < Circulator::InvalidTransition
      end
    end
  end
end
