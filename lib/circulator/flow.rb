# frozen_string_literal: true

require_relative "diverter"

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
  end
end
