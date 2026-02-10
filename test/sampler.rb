require_relative "../lib/circulator"

class SamplerBase
  def initialize(**kwargs)
    kwargs.each do |k, v|
      instance_variable_set(:"@#{k}", v)
      self.class.attr_reader(k) unless self.class.method_defined?(k)
    end
  end
end

class Sampler
  extend Circulator

  attr_accessor :status, :priority, :workflow_state, :processing_state
  attr_accessor :approval_count, :notes, :user_role, :resolver, :reason
  attr_accessor :block_executed, :execution_order, :transition_log

  def initialize(status: nil, priority: nil, workflow_state: nil, processing_state: nil)
    @status = status
    @priority = priority
    @workflow_state = workflow_state
    @processing_state = processing_state
    @approval_count = 0
    @execution_order = []
    @transition_log = []
    @block_executed = false
  end

  # Basic flow with multiple states and actions
  circulator :status do
    state :pending do
      action :approve, to: :approved do
        @approval_count += 1
        @execution_order << "approve_block"
      end
      action :reject, to: :rejected do
        @notes = "Rejected: #{@notes}"
        @execution_order << "reject_block"
      end
      action :hold, to: :on_hold
    end

    state :approved do
      action :publish, to: :published
      action :archive, to: :archived
    end

    state :on_hold do
      action :resume, to: :pending
      action :cancel, to: :cancelled
    end

    # Action with allow_if condition
    state :rejected do
      action :reconsider, to: :pending, allow_if: -> { @user_role == "admin" } do
        @execution_order << "reconsider_block"
      end
    end

    # No action handler
    no_action do |attribute_name, action|
      @transition_log << "No action: #{attribute_name}.#{action}"
    end
  end

  # Flow with callable to: option
  flow :priority do
    state :normal do
      action :escalate, to: -> { (@approval_count > 3) ? :critical : :high } do
        @execution_order << "escalate_block"
      end
    end

    state :high do
      action :escalate, to: :critical
      action :reduce, to: :normal
    end

    state :critical do
      action :resolve, to: -> { :normal } do
        @execution_order << "resolve_block"
      end
    end
  end

  # Flow with from: option (no state blocks)
  flow :workflow_state do
    action :start, to: :in_progress, from: nil
    action :complete, to: :completed, from: :in_progress
    action :fail, to: :failed, from: [:in_progress, :completed]
    action :retry, to: :in_progress, from: :failed
    action :reset, to: nil, from: [:completed, :failed]
  end

  # Flow with action_allowed
  flow :processing_state do
    state :idle do
      action :begin_processing, to: :processing
      action_allowed(:begin_processing) { @user_role == "processor" }
    end

    state :processing do
      action :complete, to: :processed do |result|
        @notes = "Processed with result: #{result}"
      end
      action :error, to: :error_state do |error_msg|
        @notes = "Error: #{error_msg}"
      end
    end

    state :processed do
      action :verify, to: :verified, allow_if: -> { true }
      action :reprocess, to: :processing
    end

    # Using action_allowed with from option
    action_allowed(:reprocess, from: :processed) { @user_role == "admin" }
  end
end

# Additional class for testing model-based flows
class SamplerTask
  attr_accessor :status, :completion_state

  def initialize
    @status = :pending
    @completion_state = nil
  end
end

class SamplerManager
  extend Circulator

  attr_accessor :managed_status

  def initialize(managed_status: nil)
    @managed_status = managed_status
  end

  # Flow that manages another model
  flow :status, model: "SamplerTask" do
    state :pending do
      action :start, to: :in_progress
    end

    state :in_progress do
      action :complete, to: :done do
        # This block should execute on the flow_target
      end
    end

    state :done do
      action :archive, to: :archived
    end
  end

  # Flow for self
  flow :managed_status do
    state :active do
      action :pause, to: :paused
    end

    state :paused do
      action :resume, to: :active
    end
  end
end

# Class demonstrating nested state dependencies with hash-based allow_if
class NestedDependencySampler
  extend Circulator

  attr_accessor :document_status, :review_status, :approval_count

  def initialize(document_status: nil, review_status: nil)
    @document_status = document_status
    @review_status = review_status
    @approval_count = 0
  end

  # Review flow must be completed before document can be published
  flow :review_status do
    state :pending do
      action :start_review, to: :in_review
    end

    state :in_review do
      action :approve, to: :approved
      action :reject, to: :rejected
    end

    state :rejected do
      action :revise, to: :pending
    end

    state :approved do
      action :finalize, to: :final
    end
  end

  # Document status depends on review status
  flow :document_status do
    state :draft do
      action :submit, to: :submitted
    end

    state :submitted do
      # Can only publish if review is approved or final
      action :publish, to: :published, allow_if: {review_status: [:approved, :final]} do
        @approval_count += 1
      end
      # Can reject document anytime
      action :reject, to: :rejected
    end

    state :published do
      action :unpublish, to: :draft
    end

    state :rejected do
      action :resubmit, to: :draft
    end
  end
end

# Complex multi-state approval workflow with role-based permissions
# Extracted from flow_test.rb let(:flow_class)
class FlowClassSampler
  extend Circulator

  attr_accessor :status, :counter, :user_role, :notes, :approval_count

  def initialize(status: nil, counter: 0, approval_count: 0, notes: nil)
    @status = status
    @counter = counter
    @approval_count = approval_count
    @notes = notes
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

# Symbol-based allow_if with predicate methods
# Extracted from flow_test.rb let(:symbol_allow_if_class)
class SymbolAllowIfSampler
  extend Circulator

  attr_accessor :status, :active, :premium_user
  attr_accessor :proc_status, :block_status, :activated_count

  def initialize(status: nil, active: nil, premium_user: nil,
    proc_status: nil, block_status: nil)
    @status = status
    @active = active
    @premium_user = premium_user
    @proc_status = proc_status
    @block_status = block_status
    @activated_count = 0
  end

  def active?
    @active == true
  end

  def premium?
    @premium_user == true
  end

  circulator :status do
    state :pending do
      action :activate, to: :active, allow_if: :active?
      action :upgrade, to: :premium, allow_if: :premium?
    end

    state :active do
      action :deactivate, to: :inactive
    end

    state :premium
    state :inactive
  end

  circulator :proc_status do
    state :pending do
      action :activate, to: :active, allow_if: -> { active? }
    end
  end

  circulator :block_status do
    state :pending do
      action :activate, to: :active, allow_if: :active? do
        @activated_count += 1
      end
    end
  end
end

# Two independent flows (status + priority)
# Extracted from flow_test.rb let(:multi_flow_class)
class MultiFlowSampler
  extend Circulator

  attr_accessor :status, :priority, :counter

  def initialize(status: nil, priority: nil, counter: 0)
    @status = status
    @priority = priority
    @counter = counter
  end

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

# Custom no_action handler
# Extracted from flow_test.rb let(:no_action_flow_class)
class NoActionFlowSampler
  extend Circulator

  attr_accessor :status, :no_action_called, :no_action_args

  def initialize(status: nil)
    @status = status
    @no_action_called = false
    @no_action_args = nil
  end

  circulator :status do
    state :pending do
      action :approve, to: :approved
      action :reject, to: :rejected, from: :approved
    end

    no_action do |attribute_name, action|
      @no_action_called = true
      @no_action_args = {attribute_name: attribute_name, action: action}
    end
  end
end

# Callable to: with lambdas and arguments
# Extracted from flow_test.rb let(:callable_to_class)
class CallableToSampler
  extend Circulator

  attr_accessor :status, :counter, :transition_args, :transition_kwargs

  def initialize(status: nil, counter: 0)
    @status = status
    @counter = counter
    @transition_args = nil
    @transition_kwargs = nil
  end

  circulator :status do
    state :pending do
      action :approve, to: -> { :approved }

      action :increment, to: -> {
        @counter += 1
        :incremented
      }

      action :custom, to: ->(*args, **kwargs) do
        @transition_args = args
        @transition_kwargs = kwargs
        :custom_state
      end
    end

    state :approved do
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
      action :resolve, to: ->(resolver, reason = "default") do
        @resolver = resolver
        @reason = reason
        :resolved
      end
    end

    action :reset, to: -> { :pending }, from: [:approved, :urgent, :normal, :resolved]
    action :escalate, to: ->(level) { :"level_#{level}" }, from: [:normal, :pending]
  end
end

# Transitions to/from nil
# Extracted from flow_test.rb let(:nil_behavior_class)
class NilBehaviorSampler
  extend Circulator

  attr_accessor :status, :transition_log

  def initialize(status: nil)
    @status = status
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

# Block passing with transition and method blocks
# Extracted from flow_test.rb let(:block_flow_class)
class BlockFlowSampler
  extend Circulator

  attr_accessor :status, :block_executed, :block_args, :block_kwargs, :execution_order

  def initialize(status: nil)
    @status = status
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

# Around wrapper DSL
# Extracted from around_flow_test.rb let(:around_class)
class AroundFlowSampler
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

    state :approved do
      action :publish, to: :published
    end
  end
end

# Class for testing empty flows error condition
# This class extends Circulator but has no flows defined
class EmptyFlowsSampler
  extend Circulator

  # Clear the flows that Circulator creates
  @flows&.clear
end

# Class for testing Symbol and Array allow_if conditionals
class ConditionalSampler
  extend Circulator

  attr_accessor :status

  def initialize(status: nil)
    @status = status
  end

  def can_approve?
    true
  end

  def is_admin?
    true
  end

  circulator :status do
    state :pending do
      action :approve, to: :approved, allow_if: :can_approve?
      action :force_approve, to: :approved, allow_if: [:can_approve?, :is_admin?]
      action :custom_approve, to: :approved, allow_if: [:can_approve?, -> { true }]
    end
  end
end
