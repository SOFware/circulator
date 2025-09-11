require_relative "../lib/circulator"

class Sampler
  extend Circulator::Diverter

  attr_accessor :status, :priority, :workflow_state, :processing_state
  attr_accessor :approval_count, :notes, :user_role, :resolver, :reason
  attr_accessor :block_executed, :execution_order, :transition_log

  def initialize
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
  extend Circulator::Diverter

  attr_accessor :managed_status

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
