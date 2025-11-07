require "test_helper"

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
      doc = klass.new
      doc.status = :pending

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

      task = klass.new
      task.status = :todo

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

        def self.name
          "SimpleDoc"
        end

        flow :status do
          state :pending do
            action :approve, to: :approved
          end
        end
      end

      doc = klass.new
      doc.status = :pending

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

        def self.name
          "Task"
        end

        flow :status do
          state :pending do
            action :start, to: :in_progress
          end
        end
      end

      task = klass.new
      task.status = :pending

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

      order = klass.new
      order.status = :pending

      # Should have both base and extension actions on :pending
      assert order.respond_to?(:status_process)
      assert order.respond_to?(:status_cancel)
    end
  end
end
