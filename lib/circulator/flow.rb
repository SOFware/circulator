# frozen_string_literal: true

module Circulator
  class Flow
    def initialize(klass, attribute_name, states = Set.new, &block)
      @klass = klass
      @attribute_name = attribute_name
      @states = states
      @no_action = ->(attribute_name, action) { raise "No action found for the current state of #{attribute_name} (#{send(attribute_name)}): #{action}" }
      @transition_map = {}
      instance_eval(&block)
    end
    attr_reader :transition_map

    def state(name, &block)
      name = name.to_sym if name.respond_to?(:to_sym)
      @states.add(name)
      @current_state = name
      instance_eval(&block) if block
      remove_instance_variable(:@current_state)
    end

    def action(name, to:, from: :__not_specified__, allow_if: nil, &block)
      raise "You must be in a state block or have a `from` option to declare an action" unless defined?(@current_state) || from != :__not_specified__

      # Validate allow_if parameter
      if allow_if
        validate_allow_if(allow_if)
      end

      @transition_map[name] ||= {}
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

        @transition_map[name][from_state] = {to:, block:}
        @transition_map[name][from_state][:allow_if] = allow_if if allow_if
      end
    end

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

    def no_action(&block)
      if block_given?
        @no_action = block
      else
        @no_action
      end
    end

    private

    def validate_allow_if(allow_if)
      # Must be either a Proc, Hash, or Symbol
      unless allow_if.is_a?(Proc) || allow_if.is_a?(Hash) || allow_if.is_a?(Symbol)
        raise ArgumentError, "allow_if must be a Proc, Hash, or Symbol, got: #{allow_if.class}"
      end

      # If it's a Hash, validate the structure
      if allow_if.is_a?(Hash)
        validate_hash_allow_if(allow_if)
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
  end
end
