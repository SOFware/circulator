# frozen_string_literal: true

module Circulator
  class Dot
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
      output << "digraph #{graph_name} {"
      output << "  rankdir=LR;"
      output << ""

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
                # Dynamic state - use ? as placeholder
                states.add(:"?")
                label = "#{action} (dynamic)"
                transitions << {from: from_state, to: :"?", label: label}
              else
                states.add(to_state)
                label = action.to_s
                label += " (conditional)" if transition_info[:allow_if]
                transitions << {from: from_state, to: to_state, label: label}
              end
            end
          end
        end
      end

      # Output state nodes
      output << "  // States"
      states.sort_by { |s| s.to_s }.each do |state|
        state_label = state.nil? ? "nil" : state.to_s
        output << "  #{state_label} [shape=circle];"
      end

      output << ""
      output << "  // Transitions"

      # Output transition edges
      transitions.sort_by { |t| [t[:from].to_s, t[:to].to_s, t[:label]] }.each do |transition|
        from_label = transition[:from].nil? ? "nil" : transition[:from].to_s
        to_label = transition[:to].nil? ? "nil" : transition[:to].to_s
        output << "  #{from_label} -> #{to_label} [label=\"#{transition[:label]}\"];"
      end

      output << "}"
      output.join("\n") + "\n"
    end

    private

    def graph_name
      # Use the model class name if available, otherwise use the model key
      class_name = @model_class.name
      model_key = @flows.keys.first

      # If class has no name, use the model_key which will be like "anonymous_XXX"
      # If model_key differs from class_name, it's a model-based flow, use model_key
      if class_name.nil?
        "#{model_key}_flows"
      elsif model_key && model_key != class_name
        "#{model_key}_flows"
      else
        "#{class_name}_flows"
      end
    end
  end
end
