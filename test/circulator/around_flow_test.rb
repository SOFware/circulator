require "test_helper"

class AroundFlowTest < Minitest::Test
  describe "around DSL" do
    let(:around_class) do
      Class.new do
        extend Circulator

        attr_accessor :status, :execution_order

        def initialize
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

          state :approved do
            action :publish, to: :published
          end
        end
      end
    end

    it "wraps transitions and transition.call executes the flow logic" do
      obj = around_class.new
      obj.status = :pending

      obj.status_approve
      assert_equal :approved, obj.status
      assert_equal ["around_before", "transition_block", "around_after"], obj.execution_order
    end

    it "instance_exec's the around block on the flow_target" do
      klass = Class.new do
        extend Circulator

        attr_accessor :status, :around_self

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

      obj = klass.new
      obj.status = :pending
      obj.status_approve

      assert_same obj, obj.around_self
    end

    it "guard check happens inside the around wrapper" do
      order = []

      klass = Class.new do
        extend Circulator

        attr_accessor :status

        define_method(:can_approve?) { true }

        flow :status do
          around do |transition|
            order << "around_before"
            transition.call
            order << "around_after"
          end

          state :pending do
            action :approve, to: :approved, allow_if: -> {
              order << "guard_check"
              true
            }
          end
        end
      end

      obj = klass.new
      obj.status = :pending
      obj.status_approve

      assert_equal ["around_before", "guard_check", "around_after"], order
    end

    it "guard failure: around completes normally, transition does not execute" do
      order = []

      klass = Class.new do
        extend Circulator

        attr_accessor :status

        flow :status do
          around do |transition|
            order << "around_before"
            transition.call
            order << "around_after"
          end

          state :pending do
            action :approve, to: :approved, allow_if: -> { false } do
              order << "transition_block"
            end
          end
        end
      end

      obj = klass.new
      obj.status = :pending
      obj.status_approve

      assert_equal :pending, obj.status
      assert_equal ["around_before", "around_after"], order
    end

    describe "all guard types work inside the wrapper" do
      it "Array guard" do
        klass = Class.new do
          extend Circulator

          attr_accessor :status
          define_method(:check_a) { true }
          define_method(:check_b) { true }

          flow :status do
            around do |transition|
              transition.call
            end

            state :pending do
              action :approve, to: :approved, allow_if: [:check_a, :check_b]
            end
          end
        end

        obj = klass.new
        obj.status = :pending
        obj.status_approve
        assert_equal :approved, obj.status
      end

      it "Array guard blocks when one fails" do
        klass = Class.new do
          extend Circulator

          attr_accessor :status
          define_method(:check_a) { true }
          define_method(:check_b) { false }

          flow :status do
            around do |transition|
              transition.call
            end

            state :pending do
              action :approve, to: :approved, allow_if: [:check_a, :check_b]
            end
          end
        end

        obj = klass.new
        obj.status = :pending
        obj.status_approve
        assert_equal :pending, obj.status
      end

      it "Hash guard" do
        klass = Class.new do
          extend Circulator

          attr_accessor :status, :review

          flow :review do
            state :approved do
              action :done, to: :done
            end
          end

          flow :status do
            around do |transition|
              transition.call
            end

            state :pending do
              action :approve, to: :approved, allow_if: {review: :approved}
            end
          end
        end

        obj = klass.new
        obj.status = :pending
        obj.review = :approved
        obj.status_approve
        assert_equal :approved, obj.status
      end

      it "Symbol guard" do
        klass = Class.new do
          extend Circulator

          attr_accessor :status
          define_method(:allowed?) { true }

          flow :status do
            around do |transition|
              transition.call
            end

            state :pending do
              action :approve, to: :approved, allow_if: :allowed?
            end
          end
        end

        obj = klass.new
        obj.status = :pending
        obj.status_approve
        assert_equal :approved, obj.status
      end

      it "Proc guard" do
        klass = Class.new do
          extend Circulator

          attr_accessor :status

          flow :status do
            around do |transition|
              transition.call
            end

            state :pending do
              action :approve, to: :approved, allow_if: -> { true }
            end
          end
        end

        obj = klass.new
        obj.status = :pending
        obj.status_approve
        assert_equal :approved, obj.status
      end
    end

    it "no_action runs inside the wrapper" do
      order = []

      klass = Class.new do
        extend Circulator

        attr_accessor :status

        flow :status do
          around do |transition|
            order << "around_before"
            transition.call
            order << "around_after"
          end

          no_action { |attr, act| order << "no_action" }

          state :pending do
            action :approve, to: :approved
          end
        end
      end

      obj = klass.new
      obj.status = :approved # no transition for :approve from :approved

      obj.status_approve
      assert_equal :approved, obj.status
      assert_equal ["around_before", "no_action", "around_after"], order
    end

    it "transition blocks and caller blocks execute inside the wrapper" do
      order = []

      klass = Class.new do
        extend Circulator

        attr_accessor :status

        flow :status do
          around do |transition|
            order << "around_before"
            transition.call
            order << "around_after"
          end

          state :pending do
            action :approve, to: :approved do
              order << "transition_block"
            end
          end
        end
      end

      obj = klass.new
      obj.status = :pending

      obj.status_approve do
        order << "caller_block"
      end

      assert_equal ["around_before", "transition_block", "caller_block", "around_after"], order
    end

    it "works with flow_target: parameter" do
      target_class = Class.new do
        attr_accessor :status
      end

      order = []

      manager_class = Class.new do
        extend Circulator

        flow :status, model: "AroundTarget" do
          around do |transition|
            order << "around"
            transition.call
          end

          state :pending do
            action :approve, to: :approved
          end
        end
      end

      # Register the target class name
      Object.const_set(:AroundTarget, target_class) unless Object.const_defined?(:AroundTarget)

      target = target_class.new
      target.status = :pending

      manager = manager_class.new
      manager.around_target_status_approve(flow_target: target)

      assert_equal :approved, target.status
      assert_equal ["around"], order
    ensure
      Object.send(:remove_const, :AroundTarget) if Object.const_defined?(:AroundTarget)
    end

    it "works with callable to:" do
      klass = Class.new do
        extend Circulator

        attr_accessor :status, :level

        flow :status do
          around do |transition|
            transition.call
          end

          state :pending do
            action :approve, to: -> { (@level > 5) ? :premium : :approved }
          end
        end
      end

      obj = klass.new
      obj.status = :pending
      obj.level = 10

      obj.status_approve
      assert_equal :premium, obj.status
    end

    it "default behavior unchanged when no around defined" do
      klass = Class.new do
        extend Circulator

        attr_accessor :status

        flow :status do
          state :pending do
            action :approve, to: :approved do
              @approved = true
            end
          end
        end
      end

      obj = klass.new
      obj.status = :pending
      obj.status_approve
      assert_equal :approved, obj.status
    end

    it "multiple flows on same class can have different around blocks" do
      order = []

      klass = Class.new do
        extend Circulator

        attr_accessor :status, :priority

        flow :status do
          around do |transition|
            order << "status_around"
            transition.call
          end

          state :pending do
            action :approve, to: :approved
          end
        end

        flow :priority do
          around do |transition|
            order << "priority_around"
            transition.call
          end

          state :low do
            action :escalate, to: :high
          end
        end
      end

      obj = klass.new
      obj.status = :pending
      obj.priority = :low

      obj.status_approve
      assert_equal ["status_around"], order

      order.clear
      obj.priority_escalate
      assert_equal ["priority_around"], order
    end

    it "one flow with around and another without" do
      order = []

      klass = Class.new do
        extend Circulator

        attr_accessor :status, :priority

        flow :status do
          around do |transition|
            order << "around"
            transition.call
          end

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

      obj = klass.new
      obj.status = :pending
      obj.priority = :low

      obj.status_approve
      assert_equal :approved, obj.status
      assert_equal ["around"], order

      order.clear
      obj.priority_escalate
      assert_equal :high, obj.priority
      assert_empty order
    end

    it "transition does not execute if transition.call is not called" do
      klass = Class.new do
        extend Circulator

        attr_accessor :status

        flow :status do
          around do |transition|
            # intentionally not calling transition.call
          end

          state :pending do
            action :approve, to: :approved
          end
        end
      end

      obj = klass.new
      obj.status = :pending
      obj.status_approve
      assert_equal :pending, obj.status
    end

    it "return value preserved on success" do
      klass = Class.new do
        extend Circulator

        attr_accessor :status

        flow :status do
          state :pending do
            action :approve, to: :approved
          end
        end
      end

      obj = klass.new
      obj.status = :pending
      result = obj.status_approve
      assert_equal :approved, result
    end

    it "returns nil on guard failure" do
      klass = Class.new do
        extend Circulator

        attr_accessor :status

        flow :status do
          around do |transition|
            transition.call
          end

          state :pending do
            action :approve, to: :approved, allow_if: -> { false }
          end
        end
      end

      obj = klass.new
      obj.status = :pending
      result = obj.status_approve
      assert_nil result
    end
  end
end
