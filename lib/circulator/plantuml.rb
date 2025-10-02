# frozen_string_literal: true

module Circulator
  class PlantUml
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
      output << "@startuml"
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
                # Dynamic state - use [*] as placeholder (end state)
                label = action.to_s
                transitions << {
                  from: from_state,
                  to: nil,
                  label: label,
                  note: "dynamic target state"
                }
              else
                states.add(to_state)
                label = action.to_s
                note = nil
                note = "conditional transition" if transition_info[:allow_if]
                transitions << {
                  from: from_state,
                  to: to_state,
                  label: label,
                  note: note
                }
              end
            end
          end
        end
      end

      # Output state declarations (except nil which is represented as [*])
      states.reject(&:nil?).sort_by(&:to_s).each do |state|
        output << "state #{state}"
      end

      output << ""

      # Output transitions
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

      output << ""
      output << "@enduml"
      output.join("\n") + "\n"
    end
  end
end
