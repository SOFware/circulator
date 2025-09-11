require "test_helper"
require_relative "../sampler"

class SamplerTest < Minitest::Test
  describe "Sampler comprehensive feature tests" do
    let(:sampler) { Sampler.new }
    
    describe "Basic state transitions" do
      it "transitions through basic flow" do
        sampler.status = :pending
        
        # Test approve action with block
        sampler.status_approve
        assert_equal :approved, sampler.status
        assert_equal 1, sampler.approval_count
        assert_includes sampler.execution_order, "approve_block"
        
        # Test publish action
        sampler.status_publish
        assert_equal :published, sampler.status
      end
      
      it "executes reject action with block" do
        sampler.status = :pending
        sampler.notes = "Initial"
        
        sampler.status_reject
        assert_equal :rejected, sampler.status
        assert_equal "Rejected: Initial", sampler.notes
        assert_includes sampler.execution_order, "reject_block"
      end
      
      it "handles hold and resume actions" do
        sampler.status = :pending
        
        sampler.status_hold
        assert_equal :on_hold, sampler.status
        
        sampler.status_resume
        assert_equal :pending, sampler.status
      end
      
      it "transitions from approved to archived" do
        sampler.status = :approved
        
        sampler.status_archive
        assert_equal :archived, sampler.status
      end
      
      it "cancels from on_hold state" do
        sampler.status = :on_hold
        
        sampler.status_cancel
        assert_equal :cancelled, sampler.status
      end
    end
    
    describe "allow_if conditions" do
      it "blocks transition when allow_if returns false" do
        sampler.status = :rejected
        sampler.user_role = "user"
        
        sampler.status_reconsider
        assert_equal :rejected, sampler.status
        assert_empty sampler.execution_order
      end
      
      it "allows transition when allow_if returns true" do
        sampler.status = :rejected
        sampler.user_role = "admin"
        
        sampler.status_reconsider
        assert_equal :pending, sampler.status
        assert_includes sampler.execution_order, "reconsider_block"
      end
    end
    
    describe "no_action handler" do
      it "calls no_action when transition doesn't exist" do
        sampler.status = :published
        
        # Try an action that doesn't exist for published state
        sampler.status_approve
        
        assert_equal :published, sampler.status
        assert_includes sampler.transition_log, "No action: status.approve"
      end
    end
    
    describe "Callable to: option" do
      it "determines state based on condition" do
        sampler.priority = :normal
        sampler.approval_count = 2
        
        sampler.priority_escalate
        assert_equal :high, sampler.priority
        assert_includes sampler.execution_order, "escalate_block"
      end
      
      it "uses different state based on condition" do
        sampler.priority = :normal
        sampler.approval_count = 5
        
        sampler.priority_escalate
        assert_equal :critical, sampler.priority
        assert_includes sampler.execution_order, "escalate_block"
      end
      
      it "resolves critical priority" do
        sampler.priority = :critical
        
        sampler.priority_resolve
        assert_equal :normal, sampler.priority
        assert_includes sampler.execution_order, "resolve_block"
      end
      
      it "reduces priority from high to normal" do
        sampler.priority = :high
        
        sampler.priority_reduce
        assert_equal :normal, sampler.priority
      end
    end
    
    describe "from: option without state blocks" do
      it "starts workflow from nil" do
        sampler.workflow_state = nil
        
        sampler.workflow_state_start
        assert_equal :in_progress, sampler.workflow_state
      end
      
      it "completes workflow" do
        sampler.workflow_state = :in_progress
        
        sampler.workflow_state_complete
        assert_equal :completed, sampler.workflow_state
      end
      
      it "fails from in_progress" do
        sampler.workflow_state = :in_progress
        
        sampler.workflow_state_fail
        assert_equal :failed, sampler.workflow_state
      end
      
      it "fails from completed" do
        sampler.workflow_state = :completed
        
        sampler.workflow_state_fail
        assert_equal :failed, sampler.workflow_state
      end
      
      it "retries from failed" do
        sampler.workflow_state = :failed
        
        sampler.workflow_state_retry
        assert_equal :in_progress, sampler.workflow_state
      end
      
      it "resets to nil from completed" do
        sampler.workflow_state = :completed
        
        sampler.workflow_state_reset
        assert_nil sampler.workflow_state
      end
      
      it "resets to nil from failed" do
        sampler.workflow_state = :failed
        
        sampler.workflow_state_reset
        assert_nil sampler.workflow_state
      end
    end
    
    describe "action_allowed in state block" do
      it "blocks begin_processing when not processor" do
        sampler.processing_state = :idle
        sampler.user_role = "user"
        
        sampler.processing_state_begin_processing
        assert_equal :idle, sampler.processing_state
      end
      
      it "allows begin_processing when processor" do
        sampler.processing_state = :idle
        sampler.user_role = "processor"
        
        sampler.processing_state_begin_processing
        assert_equal :processing, sampler.processing_state
      end
    end
    
    describe "Actions with arguments" do
      it "processes with result argument" do
        sampler.processing_state = :processing
        
        sampler.processing_state_complete("success")
        assert_equal :processed, sampler.processing_state
        assert_equal "Processed with result: success", sampler.notes
      end
      
      it "handles error with message" do
        sampler.processing_state = :processing
        
        sampler.processing_state_error("Connection timeout")
        assert_equal :error_state, sampler.processing_state
        assert_equal "Error: Connection timeout", sampler.notes
      end
    end
    
    describe "action_allowed with from option" do
      it "blocks reprocess when not admin" do
        sampler.processing_state = :processed
        sampler.user_role = "user"
        
        sampler.processing_state_reprocess
        assert_equal :processed, sampler.processing_state
      end
      
      it "allows reprocess when admin" do
        sampler.processing_state = :processed
        sampler.user_role = "admin"
        
        sampler.processing_state_reprocess
        assert_equal :processing, sampler.processing_state
      end
    end
    
    describe "flow method usage" do
      it "works with flow method for transitions" do
        sampler.status = :pending
        
        sampler.flow(:approve, :status)
        assert_equal :approved, sampler.status
        assert_equal 1, sampler.approval_count
      end
      
      it "passes arguments through flow method" do
        sampler.processing_state = :processing
        
        sampler.flow(:complete, :processing_state, "test result")
        assert_equal :processed, sampler.processing_state
        assert_equal "Processed with result: test result", sampler.notes
      end
      
      it "respects allow_if through flow method" do
        sampler.status = :rejected
        sampler.user_role = "user"
        
        sampler.flow(:reconsider, :status)
        assert_equal :rejected, sampler.status
        
        sampler.user_role = "admin"
        sampler.flow(:reconsider, :status)
        assert_equal :pending, sampler.status
      end
    end
    
    describe "Block passing to transitions" do
      it "executes additional blocks passed to transition methods" do
        sampler.status = :pending
        additional_executed = false
        
        sampler.status_approve do
          additional_executed = true
          @execution_order << "additional_block"
        end
        
        assert additional_executed
        assert_equal :approved, sampler.status
        assert_equal ["approve_block", "additional_block"], sampler.execution_order
      end
      
      it "executes blocks through flow method" do
        sampler.status = :pending
        flow_block_executed = false
        
        sampler.flow(:approve, :status) do
          flow_block_executed = true
          @execution_order << "flow_additional_block"
        end
        
        assert flow_block_executed
        assert_equal :approved, sampler.status
        assert_includes sampler.execution_order, "flow_additional_block"
      end
      
      it "passes arguments to additional blocks" do
        sampler.processing_state = :processing
        captured_args = nil
        
        sampler.processing_state_complete("result_value") do |*args|
          captured_args = args
        end
        
        assert_equal ["result_value"], captured_args
        assert_equal :processed, sampler.processing_state
      end
    end
  end
  
  describe "SamplerManager model-based flows" do
    let(:manager) { SamplerManager.new }
    let(:task) { SamplerTask.new }
    
    it "manages external model through flow" do
      task.status = :pending
      
      # Manager controls task's status
      manager.sampler_task_status_start(flow_target: task)
      assert_equal :in_progress, task.status
      
      manager.sampler_task_status_complete(flow_target: task)
      assert_equal :done, task.status
      
      manager.sampler_task_status_archive(flow_target: task)
      assert_equal :archived, task.status
    end
    
    it "uses flow method with flow_target" do
      task.status = :pending
      
      manager.flow(:start, :status, flow_target: task)
      assert_equal :in_progress, task.status
    end
    
    it "manages its own status separately" do
      manager.managed_status = :active
      
      manager.managed_status_pause
      assert_equal :paused, manager.managed_status
      
      manager.managed_status_resume
      assert_equal :active, manager.managed_status
    end
  end
  
  describe "Edge cases and error conditions" do
    let(:sampler) { Sampler.new }
    
    it "handles invalid action gracefully with no_action" do
      sampler.status = :archived
      
      # archived has no actions defined
      sampler.status_approve
      
      assert_equal :archived, sampler.status
      assert_includes sampler.transition_log, "No action: status.approve"
    end
    
    it "handles string status values" do
      sampler.status = "pending"
      
      sampler.status_approve
      assert_equal :approved, sampler.status
    end
    
    it "handles integer-like states" do
      # Test that non-symbol states work
      sampler.workflow_state = 0
      
      # This should call no_action since 0 isn't a defined state
      # Expect an error since we have default no_action behavior
      assert_raises(RuntimeError) do
        sampler.workflow_state_complete
      end
      assert_equal 0, sampler.workflow_state
    end
  end
  
  describe "Complex interaction scenarios" do
    let(:sampler) { Sampler.new }
    
    it "performs complete workflow" do
      # Start with nil workflow
      assert_nil sampler.workflow_state
      sampler.workflow_state_start
      assert_equal :in_progress, sampler.workflow_state
      
      # Process something
      sampler.processing_state = :idle
      sampler.user_role = "processor"
      sampler.processing_state_begin_processing
      assert_equal :processing, sampler.processing_state
      
      sampler.processing_state_complete("Done")
      assert_equal :processed, sampler.processing_state
      
      # Complete workflow
      sampler.workflow_state_complete
      assert_equal :completed, sampler.workflow_state
      
      # Verify processing
      sampler.processing_state_verify
      assert_equal :verified, sampler.processing_state
      
      # Reset workflow
      sampler.workflow_state_reset
      assert_nil sampler.workflow_state
    end
    
    it "handles error recovery flow" do
      sampler.workflow_state = :in_progress
      sampler.processing_state = :processing
      
      # Error occurs
      sampler.processing_state_error("Network issue")
      assert_equal :error_state, sampler.processing_state
      
      # Fail workflow
      sampler.workflow_state_fail
      assert_equal :failed, sampler.workflow_state
      
      # Retry workflow
      sampler.workflow_state_retry
      assert_equal :in_progress, sampler.workflow_state
      
      # Fix processing
      sampler.processing_state = :idle
      sampler.user_role = "processor"
      sampler.processing_state_begin_processing
      sampler.processing_state_complete("Success on retry")
      assert_equal :processed, sampler.processing_state
      
      # Complete workflow
      sampler.workflow_state_complete
      assert_equal :completed, sampler.workflow_state
    end
  end
end