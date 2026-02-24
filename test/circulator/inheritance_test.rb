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

  describe "extension on subclass" do
    it "copies parent flow and applies extension" do
      parent = Class.new do
        extend Circulator

        attr_accessor :status
        def initialize(status: nil) = @status = status
        def self.name = "ExtParent"

        flow :status do
          state :pending do
            action :approve, to: :approved
          end
          state :approved
        end
      end

      child = Class.new(parent) do
        def self.name = "ExtChild"
      end
      Object.const_set(:ExtChild, child)

      Circulator.extension(:ExtChild, :status) do
        state :pending do
          action :reject, to: :rejected
        end
        state :rejected
      end

      obj = child.new(status: :pending)

      # Should have parent's action
      assert obj.respond_to?(:status_approve)

      # Should have extension's action
      assert obj.respond_to?(:status_reject)

      # Parent should NOT have the extension's action
      parent_obj = parent.new(status: :pending)
      refute parent_obj.respond_to?(:status_reject)

      # Extension action works
      obj.status_reject
      assert_equal :rejected, obj.status
    ensure
      Object.send(:remove_const, :ExtChild) if defined?(ExtChild)
    end

    it "extension can modify existing transitions from parent" do
      parent = Class.new do
        extend Circulator

        attr_accessor :status
        def initialize(status: nil) = @status = status
        def self.name = "ModParent"

        flow :status do
          state :pending do
            action :approve, to: :approved
          end
          state :approved
        end
      end

      child = Class.new(parent) do
        def self.name = "ModChild"
      end
      Object.const_set(:ModChild, child)

      # Override approve to go to a different state
      Circulator.extension(:ModChild, :status) do
        state :pending do
          action :approve, to: :reviewed
        end
        state :reviewed
      end

      child_obj = child.new(status: :pending)
      child_obj.status_approve
      assert_equal :reviewed, child_obj.status

      # Parent is unaffected
      parent_obj = parent.new(status: :pending)
      parent_obj.status_approve
      assert_equal :approved, parent_obj.status
    ensure
      Object.send(:remove_const, :ModChild) if defined?(ModChild)
    end
  end

  describe "early extension on subclass (registered before class exists)" do
    it "early extension modifying existing transition works on first call" do
      parent = Class.new do
        extend Circulator

        attr_accessor :status
        def initialize(status: nil) = @status = status
        def self.name = "EarlyModParent"

        flow :status do
          state :pending do
            action :approve, to: :approved
          end
          state :approved
        end
      end

      # Register extension that MODIFIES an existing transition
      Circulator.extension(:EarlyModChild, :status) do
        state :pending do
          action :approve, to: :reviewed
        end
        state :reviewed
      end

      child = Class.new(parent) do
        def self.name = "EarlyModChild"
      end
      Object.const_set(:EarlyModChild, child)

      # The very first call on the first instance must use the extended transition
      obj = child.new(status: :pending)
      obj.status_approve
      assert_equal :reviewed, obj.status

      # Parent unaffected
      parent_obj = parent.new(status: :pending)
      parent_obj.status_approve
      assert_equal :approved, parent_obj.status
    ensure
      Object.send(:remove_const, :EarlyModChild) if defined?(EarlyModChild)
    end

    it "applies pending extension when subclass is defined" do
      parent = Class.new do
        extend Circulator

        attr_accessor :status
        def initialize(status: nil) = @status = status
        def self.name = "EarlyParent"

        flow :status do
          state :pending do
            action :approve, to: :approved
          end
          state :approved
        end
      end

      # Register extension BEFORE child class exists
      Circulator.extension(:EarlyChild, :status) do
        state :approved do
          action :publish, to: :published
        end
        state :published
      end

      # Now define the child — the pending extension should be applied
      child = Class.new(parent) do
        def self.name = "EarlyChild"
      end
      Object.const_set(:EarlyChild, child)

      obj = child.new(status: :pending)
      assert obj.respond_to?(:status_approve)
      obj.status_approve
      assert_equal :approved, obj.status

      assert obj.respond_to?(:status_publish)
      obj.status_publish
      assert_equal :published, obj.status

      # Parent unaffected
      parent_obj = parent.new(status: :approved)
      refute parent_obj.respond_to?(:status_publish)
    ensure
      Object.send(:remove_const, :EarlyChild) if defined?(EarlyChild)
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

    it "sibling subclasses with different extensions don't interfere" do
      parent = Class.new do
        extend Circulator

        attr_accessor :status
        def initialize(status: nil) = @status = status
        def self.name = "SibParent"

        flow :status do
          state :pending do
            action :approve, to: :approved
          end
          state :approved
        end
      end

      child_a = Class.new(parent) { def self.name = "SibChildA" }
      Object.const_set(:SibChildA, child_a)

      child_b = Class.new(parent) { def self.name = "SibChildB" }
      Object.const_set(:SibChildB, child_b)

      Circulator.extension(:SibChildA, :status) do
        state :pending do
          action :fast_track, to: :approved
        end
      end

      Circulator.extension(:SibChildB, :status) do
        state :pending do
          action :reject, to: :rejected
        end
        state :rejected
      end

      a = child_a.new(status: :pending)
      b = child_b.new(status: :pending)

      assert a.respond_to?(:status_fast_track)
      refute a.respond_to?(:status_reject)

      assert b.respond_to?(:status_reject)
      refute b.respond_to?(:status_fast_track)
    ensure
      Object.send(:remove_const, :SibChildA) if defined?(SibChildA)
      Object.send(:remove_const, :SibChildB) if defined?(SibChildB)
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
