require "test_helper"

# Test classes for late extension tests - defined outside describe block
class LateExtendedDoc
  extend Circulator

  attr_accessor :status

  def initialize(status: nil)
    @status = status
  end

  flow :status do
    state :pending do
      action :approve, to: :approved
    end

    state :approved
  end
end

class MultiLateExtensionDoc
  extend Circulator

  attr_accessor :status

  def initialize(status: nil)
    @status = status
  end

  flow :status do
    state :draft do
      action :submit, to: :submitted
    end

    state :submitted
  end
end

class NoDuplicatesDoc
  extend Circulator

  attr_accessor :status

  def initialize(status: nil)
    @status = status
  end

  flow :status do
    state :pending do
      action :cancel, to: :cancelled
    end

    state :cancelled
  end
end

class ExistingInstanceDoc
  extend Circulator

  attr_accessor :status

  def initialize(status: nil)
    @status = status
  end

  flow :status do
    state :active do
      action :deactivate, to: :inactive
    end

    state :inactive
  end
end

class CirculatorExtensionApplicationTest < Minitest::Test
  describe "Extension Application" do
    # Reset extensions before each test
    before do
      Circulator.instance_variable_set(:@extensions, Hash.new { |h, k| h[k] = [] })
    end

    it "applies extensions when flow is defined" do
      # Register an extension
      Circulator.extension(:TestDocument, :status) do
        state :pending do
          action :send_to_legal, to: :legal_review
        end

        state :legal_review do
          action :approve, to: :approved
        end
      end

      # Define the base flow
      klass = Class.new do
        extend Circulator

        attr_accessor :status

        def initialize(status: nil)
          @status = status
        end

        def self.name
          "TestDocument"
        end

        flow :status do
          state :pending do
            action :approve, to: :approved
            action :reject, to: :rejected
          end

          state :approved do
            action :publish, to: :published
          end
        end
      end

      # Create an instance and verify extension actions are available
      doc = klass.new(status: :pending)

      # Should have base actions
      assert doc.respond_to?(:status_approve)
      assert doc.respond_to?(:status_reject)

      # Should have extension action
      assert doc.respond_to?(:status_send_to_legal)

      # Execute extension action
      doc.status_send_to_legal
      assert_equal :legal_review, doc.status

      # Extension state should have its actions
      assert doc.respond_to?(:status_legal_review?)
      assert doc.status_legal_review?
    end

    it "applies multiple extensions in order" do
      # Register first extension
      Circulator.extension(:Task, :status) do
        state :todo do
          action :start, to: :in_progress
        end
      end

      # Register second extension
      Circulator.extension(:Task, :status) do
        state :in_progress do
          action :pause, to: :paused
        end

        state :paused do
          action :resume, to: :in_progress
        end
      end

      # Define the base flow
      klass = Class.new do
        extend Circulator

        attr_accessor :status

        def initialize(status: nil)
          @status = status
        end

        def self.name
          "Task"
        end

        flow :status do
          state :todo do
            action :complete, to: :done
          end

          state :done
        end
      end

      task = klass.new(status: :todo)

      # Should have actions from base and both extensions
      assert task.respond_to?(:status_complete)
      assert task.respond_to?(:status_start)
      assert task.respond_to?(:status_pause)
      assert task.respond_to?(:status_resume)
    end

    it "works without extensions" do
      # No extensions registered

      klass = Class.new do
        extend Circulator

        attr_accessor :status

        def initialize(status: nil)
          @status = status
        end

        def self.name
          "SimpleDoc"
        end

        flow :status do
          state :pending do
            action :approve, to: :approved
          end
        end
      end

      doc = klass.new(status: :pending)

      assert doc.respond_to?(:status_approve)
      doc.status_approve
      assert_equal :approved, doc.status
    end

    it "extensions for different class don't apply" do
      # Register extension for Document
      Circulator.extension(:Document, :status) do
        state :pending do
          action :send_to_legal, to: :legal_review
        end
      end

      # Define flow for Task (different class)
      klass = Class.new do
        extend Circulator

        attr_accessor :status

        def initialize(status: nil)
          @status = status
        end

        def self.name
          "Task"
        end

        flow :status do
          state :pending do
            action :start, to: :in_progress
          end
        end
      end

      task = klass.new(status: :pending)

      # Should NOT have Document extension
      refute task.respond_to?(:status_send_to_legal)

      # Should have Task base action
      assert task.respond_to?(:status_start)
    end

    it "extensions can add actions to existing states" do
      # Extension adds action to state that exists in base
      Circulator.extension(:Order, :status) do
        state :pending do
          action :cancel, to: :cancelled
        end

        state :cancelled
      end

      klass = Class.new do
        extend Circulator

        attr_accessor :status

        def initialize(status: nil)
          @status = status
        end

        def self.name
          "Order"
        end

        flow :status do
          state :pending do
            action :process, to: :processing
          end

          state :processing do
            action :ship, to: :shipped
          end
        end
      end

      order = klass.new(status: :pending)

      # Should have both base and extension actions on :pending
      assert order.respond_to?(:status_process)
      assert order.respond_to?(:status_cancel)
    end

    describe "extensions registered after flow is defined" do
      it "applies extension to existing flow" do
        # Verify base flow works
        doc = LateExtendedDoc.new(status: :pending)
        assert doc.respond_to?(:status_approve)

        # Register extension AFTER flow is defined
        Circulator.extension(:LateExtendedDoc, :status) do
          state :pending do
            action :send_to_review, to: :reviewing
          end

          state :reviewing do
            action :finish_review, to: :approved
          end
        end

        # Extension should be applied immediately
        assert doc.respond_to?(:status_send_to_review), "Extension action should be available"

        # Execute extension action
        doc.status_send_to_review
        assert_equal :reviewing, doc.status

        # New state should have its predicate method
        assert doc.respond_to?(:status_reviewing?)
        assert doc.status_reviewing?

        # Actions from extension's new state should work
        assert doc.respond_to?(:status_finish_review)
        doc.status_finish_review
        assert_equal :approved, doc.status
      end

      it "applies multiple late extensions in order" do
        # Register first late extension
        Circulator.extension(:MultiLateExtensionDoc, :status) do
          state :submitted do
            action :review, to: :in_review
          end

          state :in_review
        end

        # Register second late extension
        Circulator.extension(:MultiLateExtensionDoc, :status) do
          state :in_review do
            action :approve, to: :approved
          end

          state :approved
        end

        obj = MultiLateExtensionDoc.new(status: :draft)

        # All actions should be available
        assert obj.respond_to?(:status_submit)
        assert obj.respond_to?(:status_review)
        assert obj.respond_to?(:status_approve)

        # Full workflow should work
        obj.status_submit
        assert_equal :submitted, obj.status

        obj.status_review
        assert_equal :in_review, obj.status

        obj.status_approve
        assert_equal :approved, obj.status
      end

      it "does not duplicate methods when extension defines same action from different state" do
        # Extension adds cancel from another state
        Circulator.extension(:NoDuplicatesDoc, :status) do
          state :processing do
            action :cancel, to: :cancelled
          end
        end

        obj = NoDuplicatesDoc.new(status: :processing)

        # Action should work from new state
        obj.status_cancel
        assert_equal :cancelled, obj.status
      end

      it "works with existing instances" do
        # Create instance before extension
        obj = ExistingInstanceDoc.new(status: :active)

        # Register extension
        Circulator.extension(:ExistingInstanceDoc, :status) do
          state :active do
            action :suspend, to: :suspended
          end

          state :suspended do
            action :reactivate, to: :active
          end
        end

        # Existing instance should have new methods
        assert obj.respond_to?(:status_suspend)
        obj.status_suspend
        assert_equal :suspended, obj.status

        assert obj.respond_to?(:status_reactivate)
        obj.status_reactivate
        assert_equal :active, obj.status
      end

      it "does nothing when class does not exist" do
        # This should not raise an error
        Circulator.extension(:NonExistentClass, :status) do
          state :pending do
            action :test, to: :tested
          end
        end

        # Extension should be stored for later
        assert_equal 1, Circulator.extensions["NonExistentClass:status"].length
      end

      it "does nothing when class exists but has no flows" do
        # Create a class without flows
        klass = Class.new do
          def self.name
            "NoFlowsClass"
          end
        end
        Object.const_set(:NoFlowsClass, klass)

        # This should not raise an error
        Circulator.extension(:NoFlowsClass, :status) do
          state :pending do
            action :test, to: :tested
          end
        end

        # Extension should be stored for later
        assert_equal 1, Circulator.extensions["NoFlowsClass:status"].length
      ensure
        Object.send(:remove_const, :NoFlowsClass) if defined?(NoFlowsClass)
      end

      it "does nothing when class has flows but not the specified attribute" do
        klass = Class.new do
          extend Circulator

          attr_accessor :status

          def initialize(status: nil)
            @status = status
          end

          def self.name
            "WrongAttribute"
          end

          flow :status do
            state :pending do
              action :approve, to: :approved
            end
          end
        end
        Object.const_set(:WrongAttribute, klass)

        # Register extension for different attribute
        Circulator.extension(:WrongAttribute, :other_status) do
          state :pending do
            action :test, to: :tested
          end
        end

        # Extension should be stored for later (in case attribute is added)
        assert_equal 1, Circulator.extensions["WrongAttribute:other_status"].length

        # Original flow should be unchanged
        obj = klass.new(status: :pending)
        assert obj.respond_to?(:status_approve)
        refute obj.respond_to?(:other_status_test)
      ensure
        Object.send(:remove_const, :WrongAttribute) if defined?(WrongAttribute)
      end
    end
  end
end
