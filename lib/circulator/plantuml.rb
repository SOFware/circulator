# frozen_string_literal: true

require_relative "diagram"

module Circulator
  class PlantUml < Diagram
    private

    # def graph_name
    #   @model_class.name || "diagram"
    # end

    def header
      <<~PLANTUML
        @startuml #{graph_name}
        title #{graph_name}
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
        output << "state #{state}"
      end
    end

    def transitions_output(transitions, output)
      transitions.sort_by { |t| [t[:from].to_s, t[:to].to_s, t[:label]] }.each do |transition|
        from_label = transition[:from].nil? ? "[*]" : transition[:from].to_s
        to_label = transition[:to].nil? ? "[*]" : transition[:to].to_s
        output << "#{from_label} --> #{to_label} : #{transition[:label]}"

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
