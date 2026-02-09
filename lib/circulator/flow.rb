# frozen_string_literal: true

module Circulator
  class Flow
    def initialize(klass, attribute_name, states = Set.new, extension: false, flows_proc: Circulator.default_flow_proc, &block)
      @klass = klass
      @attribute_name = attribute_name
      @states = states
      @action_missing = ->(attribute_name, action) { raise "No action found for the current state of #{attribute_name} (#{send(attribute_name)}): #{action}" }
      @flows_proc = flows_proc
      @transition_map = flows_proc.call

      # Execute the main flow block
      instance_eval(&block) if block

      # Apply any registered extensions (unless explicitly disabled)
      apply_extensions unless extension
    end
    attr_reader :transition_map

    # Declares a state in the flow. The block is evaluated in the context
    # of the flow, allowing you to define actions that transition from
    # this state. A state with no block acts as a terminal state.
    #
    #   flow(:status) do
    #     state :pending do
    #       action :approve, to: :approved
    #     end
    #
    #     state :approved # terminal state
    #   end
    #
    def state(name, &block)
      name = name.to_sym if name.respond_to?(:to_sym)
      @states.add(name)
      @current_state = name
      instance_eval(&block) if block
      remove_instance_variable(:@current_state)
    end

    # Declares a transition from one or more states to a destination state.
    # Must be called inside a +state+ block, or with an explicit +from:+ option.
    #
    # Generates a method named +<attribute>_<action>+ on the class that
    # performs the transition when called.
    #
    # ==== Options
    #
    # +to+::       The destination state (Symbol) or a callable that returns
    #              the destination state at runtime.
    # +from+::     One or more source states. Defaults to the enclosing
    #              +state+ block. Pass an Array to define the same action
    #              from multiple states.
    # +allow_if+:: A guard condition that must be truthy for the transition
    #              to proceed. Accepts a Proc, Symbol (method name), Hash
    #              (checks another flow's state), or Array of those.
    # +&block+::   A block executed on the instance during the transition,
    #              before the state is changed.
    #
    #   state :pending do
    #     action :approve, to: :approved, allow_if: :reviewer? do
    #       self.approved_at = Time.now
    #     end
    #   end
    #
    #   # Or with an explicit from:
    #   action :cancel, from: [:pending, :processing], to: :cancelled
    #
    def action(name, to:, from: :__not_specified__, allow_if: nil, &block)
      raise "You must be in a state block or have a `from` option to declare an action" unless defined?(@current_state) || from != :__not_specified__

      # Validate allow_if parameter
      if allow_if
        validate_allow_if(allow_if)
      end

      @transition_map[name] ||= @flows_proc.call
      selected_state = (from == :__not_specified__) ? @current_state : from

      # Handle nil case specially - convert to [nil] instead of []
      states_to_process = if selected_state.nil?
        [nil]
      else
        Array(selected_state)
      end

      states_to_process.each do |from_state|
        from_state = from_state.to_sym if from_state.respond_to?(:to_sym)
        @states.add(from_state)

        # Add the target state to @states if it's not a callable
        unless to.respond_to?(:call)
          to_state = to.respond_to?(:to_sym) ? to.to_sym : to
          @states.add(to_state)
        end

        # Build transition data hash with all keys at once
        transition_data = {to:, block:}
        transition_data[:allow_if] = allow_if if allow_if
        @transition_map[name][from_state] = transition_data
      end
    end

    # Attaches an +allow_if+ guard to an existing action after it has been
    # defined. This is useful when the guard logic needs to be defined
    # separately from the action itself, such as in an extension.
    #
    # Must be called inside a +state+ block, or with an explicit +from:+ option.
    # The action must already exist in the transition map.
    #
    # Example:
    #
    #   flow(:status) do
    #     state :pending do
    #       action :approve, to: :approved
    #       action_allowed(:approve) { current_user.admin? }
    #     end
    #   end
    #
    def action_allowed(name, from: :__not_specified__, &block)
      raise "You must be in a state block or have a `from` option to declare an action" unless defined?(@current_state) || from != :__not_specified__

      selected_state = (from == :__not_specified__) ? @current_state : from

      # Handle nil case specially - convert to [nil] instead of []
      states_to_process = if selected_state.nil?
        [nil]
      else
        Array(selected_state)
      end

      states_to_process.each do |from_state|
        from_state = from_state.to_sym if from_state.respond_to?(:to_sym)
        @states.add(from_state)
        @transition_map[name][from_state][:allow_if] = block
      end
    end

    # Called when an action is invoked but no transition is defined for the
    # current state. For example, if an object is in :approved and you call
    # an action that only has a transition from :pending, this block runs.
    #
    # By default, raises an error. Override to silently ignore, log, or
    # handle the missing transition however you like.
    #
    # The block receives two arguments: the attribute name and the action name.
    #
    # Example:
    #
    #   flow(:status) do
    #     action_missing do |attribute_name, action|
    #       Rails.logger.warn("No transition for #{attribute_name} in #{action}")
    #     end
    #   end
    def action_missing(&block)
      if block_given?
        @action_missing = block
      else
        @action_missing
      end
    end
    alias_method :no_action, :action_missing

    # Wraps every transition in this flow. The block receives a lambda that
    # executes the transition logic (guard check, state change, and any
    # transition block). You must call +transition.call+ for the transition
    # to actually happen — omitting it prevents the state change entirely.
    #
    # Useful for wrapping transitions in database transactions, logging,
    # instrumentation, or any before/after behavior.
    #
    # Example:
    #
    #   flow(:status) do
    #     around do |transition|
    #       ActiveRecord::Base.transaction do
    #         transition.call
    #       end
    #     end
    #
    #     state :pending do
    #       action :approve, to: :approved
    #     end
    #   end
    #
    def around(&block)
      if block_given?
        @around = block
      else
        @around
      end
    end

    # Merge an extension block into this flow
    #
    # Creates an extension flow from the block and merges its transitions
    # and states into this flow. Returns self for convenience.
    #
    # Example:
    #
    #   existing_flow.merge do
    #     state :pending do
    #       action :send_to_legal, to: :legal_review
    #     end
    #   end
    #
    def merge(&block)
      extension_flow = Flow.new(@klass, @attribute_name, @states, extension: true, flows_proc: @flows_proc, &block)

      # Merge transition map
      extension_flow.transition_map.each do |action, transitions|
        @transition_map[action] = if @transition_map[action]
          @transition_map[action].merge(transitions)
        else
          transitions
        end
      end

      self
    end

    private

    def validate_allow_if(allow_if)
      case allow_if
      in Proc
        # Valid, no additional validation needed
      in Symbol
        validate_symbol_allow_if(allow_if)
      in Hash
        validate_hash_allow_if(allow_if)
      in Array
        validate_array_allow_if(allow_if)
      else
        raise ArgumentError, "allow_if must be a Proc, Hash, Symbol, or Array, got: #{allow_if.class}"
      end
    end

    def validate_symbol_allow_if(method_name)
      unless @klass.method_defined?(method_name)
        raise ArgumentError, "allow_if references undefined method :#{method_name} on #{@klass}"
      end
    end

    def validate_hash_allow_if(allow_if_hash)
      # Must have exactly one key
      if allow_if_hash.size != 1
        raise ArgumentError, "allow_if hash must contain exactly one attribute, got: #{allow_if_hash.keys.inspect}"
      end

      attribute_name, valid_states = allow_if_hash.first

      # Convert attribute name to symbol
      attribute_name = attribute_name.to_sym if attribute_name.respond_to?(:to_sym)

      # Get model_key from the class name string, not the Class object
      model_key = Circulator.model_key(@klass.to_s)
      unless @klass.flows&.dig(model_key, attribute_name)
        available_flows = @klass.flows&.dig(model_key)&.keys || []
        raise ArgumentError, "allow_if references undefined flow attribute :#{attribute_name}. Available flows: #{available_flows.inspect}"
      end

      # Get the states from the referenced flow
      referenced_flow = @klass.flows.dig(model_key, attribute_name)
      referenced_states = referenced_flow.instance_variable_get(:@states)

      # Convert valid_states to array of symbols
      valid_states_array = Array(valid_states).map { |s| s.respond_to?(:to_sym) ? s.to_sym : s }

      # Check if all specified states exist in the referenced flow
      invalid_states = valid_states_array - referenced_states.to_a
      if invalid_states.any?
        raise ArgumentError, "allow_if references invalid states #{invalid_states.inspect} for :#{attribute_name}. Valid states: #{referenced_states.to_a.inspect}"
      end
    end

    def validate_array_allow_if(allow_if_array)
      # Array must not be empty
      if allow_if_array.empty?
        raise ArgumentError, "allow_if array must not be empty"
      end

      # First, validate all element types
      allow_if_array.each do |element|
        unless element.is_a?(Symbol) || element.is_a?(Proc)
          raise ArgumentError, "allow_if array elements must be Symbols or Procs, got: #{element.class}"
        end
      end

      # Then, validate that Symbol methods exist
      allow_if_array.each do |element|
        validate_symbol_allow_if(element) if element.is_a?(Symbol)
      end
    end

    def apply_extensions
      # Look up extensions for this class and attribute
      class_name = if @klass.is_a?(Class)
        @klass.name || @klass.to_s
      else
        Circulator.model_key(@klass)
      end
      key = "#{class_name}:#{@attribute_name}"
      extensions = Circulator.extensions[key]

      # Apply each extension using merge
      extensions.each do |extension_block|
        merge(&extension_block)
      end
    end
  end
end
