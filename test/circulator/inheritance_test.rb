require "test_helper"

class CirculatorInheritanceTest < Minitest::Test
  # Reset extensions before each test
  def setup
    Circulator.instance_variable_set(:@extensions, Hash.new { |h, k| h[k] = [] })
  end

  describe "subclass inherits parent flows" do
    it "returns parent flows when subclass has none" do
      parent = Class.new do
        extend Circulator

        attr_accessor :status
        def initialize(status: nil) = @status = status
        def self.name = "InheritParent"

        flow :status do
          state :pending do
            action :approve, to: :approved
          end
          state :approved
        end
      end

      child = Class.new(parent) do
        def self.name = "InheritChild"
      end

      assert_nil child.instance_variable_get(:@flows)
      refute_nil child.flows
      assert_equal parent.instance_variable_get(:@flows), child.flows
    end

    it "child instances can use inherited flow action methods" do
      parent = Class.new do
        extend Circulator

        attr_accessor :status
        def initialize(status: nil) = @status = status
        def self.name = "ActionParent"

        flow :status do
          state :pending do
            action :approve, to: :approved
          end
          state :approved
        end
      end

      child = Class.new(parent) do
        def self.name = "ActionChild"
      end

      obj = child.new(status: :pending)
      assert obj.respond_to?(:status_approve)
      obj.status_approve
      assert_equal :approved, obj.status
    end

    it "child instances can use available_flows" do
      parent = Class.new do
        extend Circulator

        attr_accessor :status
        def initialize(status: nil) = @status = status
        def self.name = "AvailParent"

        flow :status do
          state :pending do
            action :approve, to: :approved
          end
          state :approved
        end
      end

      child = Class.new(parent) do
        def self.name = "AvailChild"
      end

      obj = child.new(status: :pending)
      assert_includes obj.available_flows(:status), :approve
    end

    it "child instances can use state predicate methods" do
      parent = Class.new do
        extend Circulator

        attr_accessor :status
        def initialize(status: nil) = @status = status
        def self.name = "PredParent"

        flow :status do
          state :pending do
            action :approve, to: :approved
          end
          state :approved
        end
      end

      child = Class.new(parent) do
        def self.name = "PredChild"
      end

      obj = child.new(status: :pending)
      assert obj.status_pending?
      refute obj.status_approved?
    end
  end

  describe "error on redeclaration" do
    it "raises when subclass declares flow for same attribute as parent" do
      parent = Class.new do
        extend Circulator

        attr_accessor :status
        def initialize(status: nil) = @status = status
        def self.name = "RedeclareParent"

        flow :status do
          state :pending do
            action :approve, to: :approved
          end
          state :approved
        end
      end

      error = assert_raises(ArgumentError) do
        Class.new(parent) do
          def self.name = "RedeclareChild"

          flow :status do
            state :draft do
              action :submit, to: :pending
            end
          end
        end
      end

      assert_match(/inherits.*:status.*flow/, error.message)
      assert_match(/Circulator\.extension/, error.message)
    end

    it "allows subclass to declare flow for a different attribute" do
      parent = Class.new do
        extend Circulator

        attr_accessor :status, :priority
        def initialize(status: nil, priority: nil)
          @status = status
          @priority = priority
        end

        def self.name = "DiffAttrParent"

        flow :status do
          state :pending do
            action :approve, to: :approved
          end
          state :approved
        end
      end

      # Should NOT raise
      child = Class.new(parent) do
        def self.name = "DiffAttrChild"

        flow :priority do
          state :low do
            action :escalate, to: :high
          end
          state :high
        end
      end

      obj = child.new(status: :pending, priority: :low)
      obj.status_approve
      assert_equal :approved, obj.status
      obj.priority_escalate
      assert_equal :high, obj.priority
    end
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

  describe "inheritance edge cases" do
    it "grandchild inherits from parent through child" do
      grandparent = Class.new do
        extend Circulator

        attr_accessor :status
        def initialize(status: nil) = @status = status
        def self.name = "GrandParent"

        flow :status do
          state :pending do
            action :approve, to: :approved
          end
          state :approved
        end
      end

      child = Class.new(grandparent) { def self.name = "GChild" }
      grandchild = Class.new(child) { def self.name = "GGChild" }

      obj = grandchild.new(status: :pending)
      obj.status_approve
      assert_equal :approved, obj.status
    end

    it "class with no parent flow is unaffected" do
      klass = Class.new do
        extend Circulator

        attr_accessor :status
        def initialize(status: nil) = @status = status
        def self.name = "Standalone"

        flow :status do
          state :draft do
            action :publish, to: :published
          end
          state :published
        end
      end

      obj = klass.new(status: :draft)
      obj.status_publish
      assert_equal :published, obj.status
    end
  end

  describe "inherited flow features" do
    it "child instances use inherited around block" do
      parent = Class.new do
        extend Circulator

        attr_accessor :status, :log
        def initialize(status: nil)
          @status = status
          @log = []
        end

        def self.name = "AroundParent"

        flow :status do
          around do |transition|
            @log << :before
            transition.call
            @log << :after
          end

          state :pending do
            action :approve, to: :approved
          end
          state :approved
        end
      end

      child = Class.new(parent) { def self.name = "AroundChild" }

      obj = child.new(status: :pending)
      obj.status_approve
      assert_equal :approved, obj.status
      assert_equal [:before, :after], obj.log
    end

    it "child instances use inherited action_missing handler" do
      parent = Class.new do
        extend Circulator

        attr_accessor :status, :missing_action_called
        def initialize(status: nil)
          @status = status
          @missing_action_called = false
        end

        def self.name = "MissingParent"

        flow :status do
          action_missing do |attr, act|
            @missing_action_called = true
          end

          state :pending do
            action :approve, to: :approved
          end
          state :approved
        end
      end

      child = Class.new(parent) { def self.name = "MissingChild" }

      obj = child.new(status: :approved)
      obj.status_approve # no transition from :approved, triggers action_missing
      assert obj.missing_action_called
    end

    it "child instances respect inherited allow_if guards" do
      parent = Class.new do
        extend Circulator

        attr_accessor :status, :admin
        def initialize(status: nil, admin: false)
          @status = status
          @admin = admin
        end

        def admin? = @admin
        def self.name = "GuardParent"

        flow :status do
          state :pending do
            action :approve, to: :approved, allow_if: :admin?
          end
          state :approved
        end
      end

      child = Class.new(parent) { def self.name = "GuardChild" }

      blocked = child.new(status: :pending, admin: false)
      blocked.status_approve
      assert_equal :pending, blocked.status # guard blocked it

      allowed = child.new(status: :pending, admin: true)
      allowed.status_approve
      assert_equal :approved, allowed.status
    end

    it "bang methods work on inherited flows" do
      parent = Class.new do
        extend Circulator

        attr_accessor :status
        def initialize(status: nil) = @status = status
        def self.name = "BangParent"

        flow :status do
          state :pending do
            action :approve, to: :approved
          end
          state :approved
        end
      end

      child = Class.new(parent) { def self.name = "BangChild" }

      # Successful bang
      obj = child.new(status: :pending)
      obj.status_approve!
      assert_equal :approved, obj.status

      # Failed bang raises InvalidTransition
      obj2 = child.new(status: :approved)
      assert_raises(parent.const_get(:InvalidTransition)) do
        obj2.status_approve!
      end
    end
  end
end
