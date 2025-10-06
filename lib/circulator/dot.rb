# frozen_string_literal: true

require_relative "diagram"

module Circulator
  class Dot < Diagram
    private

    def flows_output(flows_data, output)
      if flows_data.size == 1
        # Single flow: no grouping needed
        flow = flows_data.first
        states_output(flow[:states], output)
        transitions_output(flow[:transitions], output)
      else
        # Multiple flows: use subgraph clusters
        flows_data.each_with_index do |flow, index|
          output << ""
          output << "  subgraph cluster_#{index} {"
          output << "    label=\":#{flow[:attribute_name]}\";"
          output << "    style=dashed;"
          output << "    color=blue;"
          output << ""

          # Output states within this cluster
          flow[:states].sort_by(&:to_s).each do |state|
            state_label = state.nil? ? "nil" : state.to_s
            # Prefix state names with attribute to avoid conflicts
            prefixed_name = "#{flow[:attribute_name]}_#{state_label}"
            output << "    #{prefixed_name} [label=\"#{state_label}\", shape=circle];"
          end

          output << "  }"
        end

        # Output all transitions after clusters
        output << ""
        output << "  // Transitions"
        flows_data.each do |flow|
          flow[:transitions].sort_by { |t| [t[:from].to_s, t[:to].to_s, t[:label]] }.each do |transition|
            from_label = transition[:from].nil? ? "nil" : transition[:from].to_s
            to_label = transition[:to].nil? ? "nil" : transition[:to].to_s
            # Use prefixed names
            prefixed_from = "#{flow[:attribute_name]}_#{from_label}"
            prefixed_to = "#{flow[:attribute_name]}_#{to_label}"
            output << "  #{prefixed_from} -> #{prefixed_to} [label=\"#{transition[:label]}\"];"
          end
        end
      end
    end

    # def graph_name
    #   # Use the model class name if available, otherwise use the model key
    #   class_name = @model_class.name
    #   model_key = @flows.keys.first

    #   # If class has no name or model_key differs from class_name (model-based flow),
    #   # use model_key, otherwise use class_name
    #   if class_name.nil? || (model_key && model_key != class_name)
    #     "#{model_key} flows"
    #   else
    #     "#{class_name} flows"
    #   end
    # end

    def states_output(states, output)
      output << "  // States"
      states.sort_by { |s| s.to_s }.each do |state|
        state_label = state.nil? ? "nil" : state.to_s
        output << "  #{state_label} [shape=circle];"
      end
    end

    def transitions_output(transitions, output)
      output << ""
      output << "  // Transitions"
      transitions.sort_by { |t| [t[:from].to_s, t[:to].to_s, t[:label]] }.each do |transition|
        from_label = transition[:from].nil? ? "nil" : transition[:from].to_s
        to_label = transition[:to].nil? ? "nil" : transition[:to].to_s
        output << "  #{from_label} -> #{to_label} [label=\"#{transition[:label]}\"];"
      end
    end

    def header
      <<~DOT
        digraph "#{graph_name}" {
          rankdir=LR;
      DOT
    end

    def header_for_attribute(attribute_name)
      class_name = @model_class.name || "diagram"
      <<~DOT
        digraph "#{class_name} :#{attribute_name} flow" {
          rankdir=LR;
      DOT
    end

    def footer
      "}"
    end

    def dynamic_transition(action, from_state, to_state = nil)
      {
        from: from_state,
        to: to_state,
        label: "  #{action} (dynamic)"
      }
    end

    def standard_transition(action, from_state, to_state, conditional: nil)
      label = action.to_s
      label += " (conditional)" if conditional

      {
        from: from_state,
        to: to_state,
        label: label
      }
    end
  end
end
