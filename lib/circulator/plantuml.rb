# frozen_string_literal: true

require_relative "diagram"

module Circulator
  class PlantUml < Diagram
    private

    def flows_output(flows_data, output)
      if flows_data.size == 1
        # Single flow: no grouping needed
        flow = flows_data.first
        states_output(flow[:states], output)
        transitions_output(flow[:transitions], output)
      else
        # Multiple flows: use composite states (state containers) with visible labels
        flows_data.each do |flow|
          output << ""
          output << "state \":#{flow[:attribute_name]}\" as #{flow[:attribute_name]}_group {"

          # Output states for this flow
          flow[:states].reject(&:nil?).sort_by(&:to_s).each do |state|
            # Replace characters that PlantUML doesn't like in identifiers
            safe_state = state.to_s.gsub("?", "unknown")
            prefixed_name = "#{flow[:attribute_name]}_#{safe_state}"
            output << "  state \"#{state}\" as #{prefixed_name}"
          end

          output << "}"
        end

        # Output all transitions after composite states
        output << ""
        flows_data.each do |flow|
          flow[:transitions].sort_by { |t| [t[:from].to_s, t[:to].to_s, t[:label]] }.each do |transition|
            from_label = transition[:from].nil? ? "[*]" : transition[:from].to_s
            to_label = transition[:to].nil? ? "[*]" : transition[:to].to_s
            # Use prefixed names for non-nil states
            # Replace characters that PlantUML doesn't like in identifiers
            safe_from = from_label.gsub("?", "unknown")
            safe_to = to_label.gsub("?", "unknown")
            prefixed_from = transition[:from].nil? ? "[*]" : "#{flow[:attribute_name]}_#{safe_from}"
            prefixed_to = transition[:to].nil? ? "[*]" : "#{flow[:attribute_name]}_#{safe_to}"
            output << "#{prefixed_from} --> #{prefixed_to} : #{transition[:label]}"

            # Add note if present
            if transition[:note]
              output << "note on link"
              output << "  #{transition[:note]}"
              output << "end note"
            end
          end
        end
      end
    end

    def header
      <<~PLANTUML
        @startuml #{graph_name}
        title #{graph_name}
      PLANTUML
    end

    def header_for_attribute(attribute_name)
      class_name = @model_class.name || "diagram"
      <<~PLANTUML
        @startuml #{class_name}_#{attribute_name}
        title #{class_name} :#{attribute_name} flow
      PLANTUML
    end

    def footer
      <<~PLANTUML

        @enduml
      PLANTUML
    end

    def dynamic_transition(action, from_state, to_state = nil)
      {
        from: from_state,
        to: to_state,
        label: action.to_s,
        note: "dynamic target state"
      }
    end

    def standard_transition(action, from_state, to_state, conditional: nil)
      note = if conditional
        "conditional transition"
      end

      {
        from: from_state,
        to: to_state,
        label: action.to_s,
        note:
      }
    end

    def states_output(states, output)
      states.reject(&:nil?).sort_by(&:to_s).each do |state|
        # Replace characters that PlantUML doesn't like in identifiers
        safe_state = state.to_s.gsub("?", "unknown")
        output << if safe_state != state.to_s
          "state \"#{state}\" as #{safe_state}"
        else
          "state #{state}"
        end
      end
    end

    def transitions_output(transitions, output)
      transitions.sort_by { |t| [t[:from].to_s, t[:to].to_s, t[:label]] }.each do |transition|
        from_label = transition[:from].nil? ? "[*]" : transition[:from].to_s
        to_label = transition[:to].nil? ? "[*]" : transition[:to].to_s
        # Replace characters that PlantUML doesn't like in identifiers
        safe_from = (from_label == "[*]") ? from_label : from_label.gsub("?", "unknown")
        safe_to = (to_label == "[*]") ? to_label : to_label.gsub("?", "unknown")
        output << "#{safe_from} --> #{safe_to} : #{transition[:label]}"

        # Add note if present
        if transition[:note]
          output << "note on link"
          output << "  #{transition[:note]}"
          output << "end note"
        end
      end
    end
  end
end
