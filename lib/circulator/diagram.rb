# frozen_string_literal: true

module Circulator
  class Diagram
    def initialize(model_class)
      unless model_class.respond_to?(:flows)
        raise ArgumentError, "Model class must extend Circulator"
      end

      flows = model_class.flows
      if flows.nil? || flows.empty?
        raise ArgumentError, "Model class has no flows defined"
      end

      @model_class = model_class
      @flows = flows
    end

    def generate
      output = []
      output << header

      # Collect all states and transitions
      states = Set.new
      transitions = []

      @flows.each do |model_key, attribute_flows|
        attribute_flows.each do |attribute_name, flow|
          # Extract states and transitions from the flow
          flow.transition_map.each do |action, state_transitions|
            state_transitions.each do |from_state, transition_info|
              states.add(from_state)

              to_state = transition_info[:to]
              if to_state.respond_to?(:call)
                states.add(:"?")
                transitions << dynamic_transition(action, from_state, :"?")
              else
                states.add(to_state)
                transitions << standard_transition(action, from_state, to_state, conditional: transition_info[:allow_if])
              end
            end
          end
        end
      end

      # Output state nodes
      states_output(states, output)

      # Output transition edges
      transitions_output(transitions, output)

      output << footer
      output.join("\n") + "\n"
    end

    private

    def graph_name
      # Use the model class name if available, otherwise use the model key
      class_name = @model_class.name
      model_key = @flows.keys.first

      # If class has no name or model_key differs from class_name (model-based flow),
      # use model_key, otherwise use class_name
      if class_name.nil? || (model_key && model_key != class_name)
        "#{model_key} flows"
      else
        "#{class_name} flows"
      end
    end

    def header
      raise NotImplementedError, "Subclasses must implement #{__method__}"
    end

    def footer
      raise NotImplementedError, "Subclasses must implement #{__method__}"
    end

    def transitions_output(transitions, output)
      raise NotImplementedError, "Subclasses must implement #{__method__}"
    end

    def states_output(states, output)
      raise NotImplementedError, "Subclasses must implement #{__method__}"
    end

    def standard_transition(action, from_state, to_state, conditional: nil)
      raise NotImplementedError, "Subclasses must implement #{__method__}"
    end

    def dynamic_transition(action, from_state, to_state = nil)
      raise NotImplementedError, "Subclasses must implement #{__method__}"
    end
  end
end
