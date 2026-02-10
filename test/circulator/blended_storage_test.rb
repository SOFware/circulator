require "test_helper"
require "contours"

# TransitionData - BlendedHash for a single transition's data
# Handles blending :to, :block, and :allow_if
class TransitionData < Contours::BlendedHash
  @blended_keys = [:block, :allow_if]

  # Chain blocks so both execute
  blend :block do |original, extra|
    return extra unless original
    return original unless extra
    proc { |*args, **kwargs|
      instance_exec(*args, **kwargs, &original)
      instance_exec(*args, **kwargs, &extra)
    }
  end

  # AND allow_if conditions
  blend :allow_if do |original, extra|
    return extra unless original
    return original unless extra
    proc { |*args, **kwargs|
      instance_exec(*args, **kwargs, &original) &&
        instance_exec(*args, **kwargs, &extra)
    }
  end

  # Override the default blend for :to - take the new value
  def blend(original, extra)
    extra
  end
end

# CirculatorBlendedHash - BlendedHash for transitions (from_state => TransitionData)
# Since from_states are dynamic, we override blend to handle any key
class CirculatorBlendedHash < Contours::BlendedHash
  # Override merge to blend ALL keys (since state names are dynamic)
  def merge(overrides)
    return self if overrides.nil? || overrides.empty?

    self.class.new(overrides.each_with_object(to_hash.dup) do |(key, value), hash|
      hash[key] = if hash[key]
        # Both have this key - blend the transition data
        TransitionData.init(hash[key]).merge(value)
      else
        # Only new hash has this key
        value
      end
    end)
  end
end

class CirculatorBlendedStorageTest < Minitest::Test
  describe "BlendedHash Storage via flows_proc" do
    # Reset extensions before each test
    before do
      Circulator.instance_variable_set(:@extensions, Hash.new { |h, k| h[k] = [] })
    end

    describe "Basic BlendedHash Usage" do
      it "uses flows_proc to create storage" do
        # Create a simple flows_proc that returns a hash with a marker
        test_flows_proc = proc do
          {}.tap { |h| h.instance_variable_set(:@test_marker, true) }
        end

        test_class = Class.new do
          extend Circulator

          attr_accessor :status

          def self.name
            "BasicTest"
          end

          def self.to_s
            name
          end

          def initialize(status: nil)
            @status = status
          end

          flow :status, flows_proc: test_flows_proc do
            state :pending do
              action :approve, to: :approved
            end
          end
        end

        # Verify the flows hash exists
        assert test_class.flows, "flows should not be nil"

        # Get the actual model_key - the flow method uses to_s, which uses name if available
        model_key = Circulator.model_key(test_class.name)
        assert test_class.flows[model_key], "flows should have model_key '#{model_key}', keys: #{test_class.flows.keys.inspect}"

        # Verify the transition_map was created using flows_proc
        flow = test_class.flows[model_key][:status]
        assert flow, "flow should not be nil"
        transition_map = flow.transition_map
        assert transition_map.instance_variable_get(:@test_marker), "transition_map should have test marker"
      end

      it "passes flows_proc to nested transition maps" do
        call_count = 0
        counting_proc = proc do
          call_count += 1
          {}
        end

        Class.new do
          extend Circulator

          attr_accessor :status

          def self.name
            "CountingTest"
          end

          def self.to_s
            name
          end

          def initialize(status: nil)
            @status = status
          end

          flow :status, flows_proc: counting_proc do
            state :pending do
              action :approve, to: :approved
            end
          end
        end

        # Should have been called at least once for the main transition_map
        assert call_count >= 1
      end
    end

    describe "BlendedHash with Custom Merge" do
      it "uses BlendedHash merge when extensions are applied" do
        blended_proc = proc { CirculatorBlendedHash.new({}) }

        # Register an extension
        Circulator.extension(:Document, :status) do
          state :pending do
            action :send_to_legal, to: :legal_review
          end
        end

        test_class = Class.new do
          extend Circulator

          attr_accessor :status

          def self.name
            "Document"
          end

          def self.to_s
            name
          end

          def initialize(status: nil)
            @status = status
          end

          flow :status, flows_proc: blended_proc do
            state :pending do
              action :approve, to: :approved
            end
          end
        end

        # Verify merge was called during extension application
        model_key = Circulator.model_key(test_class.name)
        flow = test_class.flows[model_key][:status]
        assert flow, "flow should not be nil, flows keys: #{test_class.flows.keys.inspect}"

        # The nested hashes (transitions for each action) should have used merge
        # We can verify this by checking the structure
        assert flow.transition_map[:approve], "approve action should exist"
        assert flow.transition_map[:send_to_legal], "send_to_legal action should exist"
      end
    end

    describe "Transition Data Merging" do
      it "merges transitions when base and extension define same action from same state" do
        blended_proc = proc { CirculatorBlendedHash.new({}) }

        # Register extension that defines same action
        Circulator.extension(:Document, :status) do
          state :pending do
            action :approve, to: :approved do
              @extension_called = true
            end
          end
        end

        test_class = Class.new do
          extend Circulator

          attr_accessor :status, :base_called, :extension_called

          def self.name
            "Document"
          end

          def self.to_s
            name
          end

          def initialize(status: nil)
            @status = status
          end

          flow :status, flows_proc: blended_proc do
            state :pending do
              action :approve, to: :approved do
                @base_called = true
              end
            end
          end
        end

        # Test that both blocks are executed
        instance = test_class.new(status: :pending)
        instance.status_approve

        assert instance.base_called, "Base block should be called"
        assert instance.extension_called, "Extension block should be called"
        assert_equal :approved, instance.status
      end

      it "chains allow_if conditions with AND logic" do
        blended_proc = proc { CirculatorBlendedHash.new({}) }

        # Register extension with allow_if
        Circulator.extension(:Document, :status) do
          state :pending do
            action :approve, to: :approved, allow_if: -> { @is_approved }
          end
        end

        test_class = Class.new do
          extend Circulator

          attr_accessor :status, :is_ready, :is_approved

          def self.name
            "Document"
          end

          def self.to_s
            name
          end

          def initialize(status: nil)
            @status = status
          end

          flow :status, flows_proc: blended_proc do
            state :pending do
              action :approve, to: :approved, allow_if: -> { @is_ready }
            end
          end
        end

        # Should not approve if only base condition is true
        instance = test_class.new(status: :pending)
        instance.is_ready = true
        instance.is_approved = false
        instance.status_approve
        assert_equal :pending, instance.status

        # Should not approve if only extension condition is true
        instance = test_class.new(status: :pending)
        instance.is_ready = false
        instance.is_approved = true
        instance.status_approve
        assert_equal :pending, instance.status

        # Should approve if both conditions are true
        instance = test_class.new(status: :pending)
        instance.is_ready = true
        instance.is_approved = true
        instance.status_approve
        assert_equal :approved, instance.status
      end

      it "chains action blocks in execution order" do
        blended_proc = proc { CirculatorBlendedHash.new({}) }

        # Register extension with block
        Circulator.extension(:Document, :status) do
          state :pending do
            action :approve, to: :approved do
              @execution_order << :extension
            end
          end
        end

        test_class = Class.new do
          extend Circulator

          attr_accessor :status, :execution_order

          def initialize(status: nil)
            @execution_order = []
            @status = status
          end

          def self.name
            "Document"
          end

          def self.to_s
            name
          end

          flow :status, flows_proc: blended_proc do
            state :pending do
              action :approve, to: :approved do
                @execution_order << :base
              end
            end
          end
        end

        instance = test_class.new(status: :pending)
        instance.status_approve

        # Base block should execute first, then extension block
        assert_equal [:base, :extension], instance.execution_order
        assert_equal :approved, instance.status
      end

      it "handles :to target from last definition when both define it" do
        blended_proc = proc { CirculatorBlendedHash.new({}) }

        # Register extension with different :to target
        Circulator.extension(:Document, :status) do
          state :pending do
            action :approve, to: :published  # Extension specifies different target
          end
        end

        test_class = Class.new do
          extend Circulator

          attr_accessor :status

          def self.name
            "Document"
          end

          def self.to_s
            name
          end

          def initialize(status: nil)
            @status = status
          end

          flow :status, flows_proc: blended_proc do
            state :pending do
              action :approve, to: :approved  # Base specifies one target
            end
          end
        end

        instance = test_class.new(status: :pending)
        instance.status_approve

        # With our merge logic, extension's :to takes precedence if defined
        # In this case, published should win (from extension)
        # But our merge logic uses: new_data[:to] || existing[:to]
        # Since extension defines :to, it should use :published
        assert_equal :published, instance.status
      end

      it "preserves extension :to when base doesn't define it" do
        blended_proc = proc { CirculatorBlendedHash.new({}) }

        # Register extension that only has a block
        Circulator.extension(:Document, :status) do
          state :pending do
            action :approve, to: :approved do
              @extension_executed = true
            end
          end
        end

        test_class = Class.new do
          extend Circulator

          attr_accessor :status, :extension_executed

          def self.name
            "Document"
          end

          def self.to_s
            name
          end

          def initialize(status: nil)
            @status = status
          end

          flow :status, flows_proc: blended_proc do
            state :pending do
              action :approve, to: :approved do
                @base_executed = true
              end
            end
          end
        end

        instance = test_class.new(status: :pending)
        instance.status_approve

        assert_equal :approved, instance.status
      end
    end

    describe "Real-world Blending Scenarios" do
      it "handles multi-tenant workflow customization" do
        blended_proc = proc { CirculatorBlendedHash.new({}) }

        # Enterprise tenant extension adds legal review
        Circulator.extension(:Document, :status) do
          state :pending do
            action :send_to_legal, to: :legal_review
          end

          state :legal_review do
            action :approve, to: :approved
            action :reject, to: :rejected
          end
        end

        test_class = Class.new do
          extend Circulator

          attr_accessor :status

          def self.name
            "Document"
          end

          def self.to_s
            name
          end

          def initialize(status: nil)
            @status = status
          end

          flow :status, flows_proc: blended_proc do
            state :pending do
              action :approve, to: :approved
              action :reject, to: :rejected
            end

            state :approved
            state :rejected
          end
        end

        # Can use base actions
        instance = test_class.new(status: :pending)
        instance.status_reject
        assert_equal :rejected, instance.status

        # Can use extension actions
        instance = test_class.new(status: :pending)
        instance.status_send_to_legal
        assert_equal :legal_review, instance.status

        # Can transition through extended states
        instance.status_approve
        assert_equal :approved, instance.status
      end

      it "combines multiple extensions additively" do
        blended_proc = proc { CirculatorBlendedHash.new({}) }

        # First extension adds logging
        Circulator.extension(:Document, :status) do
          state :pending do
            action :approve, to: :approved do
              @logs ||= []
              @logs << "Extension 1: Approval logged"
            end
          end
        end

        # Second extension adds notification
        Circulator.extension(:Document, :status) do
          state :pending do
            action :approve, to: :approved do
              @logs ||= []
              @logs << "Extension 2: Notification sent"
            end
          end
        end

        test_class = Class.new do
          extend Circulator

          attr_accessor :status, :logs

          def self.name
            "Document"
          end

          def self.to_s
            name
          end

          def initialize(status: nil)
            @status = status
          end

          flow :status, flows_proc: blended_proc do
            state :pending do
              action :approve, to: :approved do
                @logs ||= []
                @logs << "Base: Status updated"
              end
            end
          end
        end

        instance = test_class.new(status: :pending)
        instance.status_approve

        # All three blocks should have executed
        assert_equal 3, instance.logs.length
        assert_includes instance.logs, "Base: Status updated"
        assert_includes instance.logs, "Extension 1: Approval logged"
        assert_includes instance.logs, "Extension 2: Notification sent"
        assert_equal :approved, instance.status
      end
    end

    describe "Comparison with Default Hash Storage" do
      it "default Hash storage uses last-defined wins for same action" do
        # Using default Hash.method(:new)
        default_proc = Hash.method(:new)

        Circulator.extension(:Task, :status) do
          state :pending do
            action :approve, to: :approved do
              @extension_called = true
            end
          end
        end

        test_class = Class.new do
          extend Circulator

          attr_accessor :status, :base_called, :extension_called

          def self.name
            "Task"
          end

          def self.to_s
            name
          end

          def initialize(status: nil)
            @status = status
          end

          flow :status, flows_proc: default_proc do
            state :pending do
              action :approve, to: :approved do
                @base_called = true
              end
            end
          end
        end

        instance = test_class.new(status: :pending)
        instance.status_approve

        # With regular Hash, the extension's transition data completely replaces base
        # So only extension block is called
        refute instance.base_called, "Base block should NOT be called with default Hash"
        assert instance.extension_called, "Extension block should be called"
        assert_equal :approved, instance.status
      end
    end
  end
end
