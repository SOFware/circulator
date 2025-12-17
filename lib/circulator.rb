require "circulator/version"
require "circulator/flow"

module Circulator
  # Global registry for extensions
  @extensions = Hash.new { |h, k| h[k] = [] }

  @default_flow_proc = ::Hash.method(:new)
  class << self
    attr_reader :extensions
    attr_reader :default_flow_proc

    # Register an extension for a specific class and attribute
    #
    # Example:
    #
    #   Circulator.extension(:Document, :status) do
    #     state :pending do
    #       action :send_to_legal, to: :legal_review
    #     end
    #   end
    #
    # Extensions are automatically applied when the class defines its flow
    def extension(class_name, attribute_name, &block)
      raise ArgumentError, "Block required for extension" unless block_given?

      key = "#{class_name}:#{attribute_name}"
      @extensions[key] << block
    end
  end
  # Declare a flow for an attribute.
  #
  # Specify the attribute to be used for states and actions.
  #
  # Example:
  #
  #   flow(:status) do
  #     state :pending do
  #       action :approve, to: :approved
  #     end
  #   end
  #
  # The above declares a flow for the `status` attribute. When in the `pending`
  # state, the `approve` action will transition the `status` to `approved`.
  #
  # This creates a `status_approve` method which will change the state in memory.
  #
  # You will also have a instance method `flow` which will allow you to specify
  # the action to take on the attribute.
  #
  # Example:
  #
  #   test_object.status_approve
  #   # OR
  #   test_object.flow(:approve, :status)
  #
  # You can also provide a block to receive arguments
  #
  # Example:
  #
  #   flow(:status) do
  #     state :pending do
  #       action :approve, to: :approved do |*args, **kwargs|
  #         @args_received = {args: args, kwargs: kwargs}
  #       end
  #       action_allowed(:approve) { true } # Optional. Check some value on self
  #     end
  #   end
  #
  # The block will be evalutaed on the instance of the class declaring the flow.
  # So `self` inside that action block will be the instance of the class.
  #
  # Example:
  #
  #   test_object.status_approve("arg1", "arg2", key: "value")
  #   # @args_received will be {args: ["arg1", "arg2"], kwargs: {key: "value"}}
  #
  # If the action is not allowed, the transition will not be executed.
  #
  # Example:
  #
  #  flow(:status) do
  #    state :pending do
  #      action :approve, to: :approved do
  #        @args_received = {args: args, kwargs: kwargs}
  #      end
  #      action_allowed(:approve) { false }
  #    end
  #  end
  #
  #  test_object.status_approve
  #  # Will not transition because the action is not allowed
  #
  # You may also specify the `allow_if` option to check a condition before
  # the action is allowed. The callable will be evaluated on the instance of
  # the class declaring the flow. So `self` inside that block will be the
  # instance of the class.
  #
  # Example:
  #
  #  flow(:status) do
  #    state :pending do
  #      action :approve, to: :approved, allow_if: -> { true }
  #    end
  #  end
  #
  #  test_object.status_approve
  #  # Will transition to :approved if the condition is true
  #
  # If you declare states separately, for example in an enum, you can use the
  # `action` method to declare the action on the attribute.
  #
  # Example:
  #
  #  enum :status, {pending: 0, approved: 1, rejected: 2}
  #  flow(:status) do
  #    action :approve, to: :approved, from: :pending
  #    action :reject, to: :rejected, from: :approved do |rejected_at|
  #      self.rejected_at = rejected_at
  #    end
  #  end
  #
  #  test_object.status_approve
  #  # Will transition to :approved
  #  test_object.status_reject
  #  # Will transition to :rejected and set the rejected_at attribute
  #
  # By default, if there is no transition for the current state, the flow will
  # raise an error. You can specify a no_action block to handle this case.
  #
  # Example:
  #
  #  flow(:status) do
  #    no_action { |attribute_name, action| raise "Nope!" }
  #  end
  #
  #  test_object.status_approve
  #  # Will raise an error
  #
  # You can also provide a custom action for other behavior for a set of states and
  # use the `to` option as a callable to set the attribute.
  #
  # Example:
  #
  #  flow(:status) do
  #    action :unknown, to: -> { status }, from: [:enforcing, :monitoring, :ignoring] do |signal|
  #      raise UnhandledSignalError, signal
  #    end
  #  end
  #
  #  test_object.flow(:unknown, :status, "signal")
  #  # Will raise an UnhandledSignalError
  #
  def flow(attribute_name, model: to_s, flows_proc: Circulator.default_flow_proc, &block)
    @flows ||= flows_proc.call
    model_key = Circulator.model_key(model)
    @flows[model_key] ||= flows_proc.call
    # Pass the flows_proc to Flow so it can create transition_maps of the same type
    @flows[model_key][attribute_name] = Flow.new(self, attribute_name, flows_proc:, &block)

    flow_module = ancestors.find { |ancestor|
      ancestor.name.to_s =~ /FlowMethods/
    } || Module.new.tap do |mod|
      include mod

      const_set(:FlowMethods, mod)
    end

    object = if model == to_s
      nil
    else
      Circulator.methodize_name(model)
    end

    states = Set.new
    @flows.dig(model_key, attribute_name).transition_map.each do |action, transitions|
      transitions.each do |from_state, transition_data|
        states.add(from_state)
        # Add the 'to' state if it's not a callable
        unless transition_data[:to].respond_to?(:call)
          states.add(transition_data[:to])
        end
      end
      define_flow_method(attribute_name:, action:, transitions:, object:, owner: flow_module)
    end

    # Define predicate methods for each state (skip nil)
    states.each do |state|
      next if state.nil?
      define_state_method(attribute_name:, state:, object:, owner: flow_module)
    end
  end
  alias_method :circulator, :flow

  def define_state_method(attribute_name:, state:, object:, owner:)
    object_attribute_method = [object, attribute_name, state].compact.join("_") << "?"
    return if owner.method_defined?(object_attribute_method)

    owner.define_method(object_attribute_method) do
      current_value = send(attribute_name)
      # Convert to symbol for comparison if possible
      current_value = current_value.to_sym if current_value.respond_to?(:to_sym)
      current_value == state
    end
  end

  def define_flow_method(attribute_name:, action:, transitions:, object:, owner:)
    object_attribute_method = [object, attribute_name, action].compact.join("_")
    raise ArgumentError, "Method already defined: #{object_attribute_method}" if owner.method_defined?(object_attribute_method)

    owner.define_method(object_attribute_method) do |*args, flow_target: self, **kwargs, &block|
      current_value = flow_target.send(attribute_name)

      transition = if current_value.respond_to?(:to_sym)
        transitions[current_value.to_sym]
      else
        transitions[current_value]
      end

      unless transition
        flow_target.instance_exec(attribute_name, action, &flows.dig(Circulator.model_key(flow_target), attribute_name).no_action)
        return
      end

      if transition[:allow_if]
        # Handle array-based allow_if (array of symbols and/or procs)
        if transition[:allow_if].is_a?(Array)
          return unless transition[:allow_if].all? do |guard|
            case guard
            when Symbol
              flow_target.send(guard, *args, **kwargs)
            when Proc
              flow_target.instance_exec(*args, **kwargs, &guard)
            end
          end
        # Handle hash-based allow_if (checking other attribute states)
        elsif transition[:allow_if].is_a?(Hash)
          attribute_name_to_check, valid_states = transition[:allow_if].first
          current_state = flow_target.send(attribute_name_to_check)

          # Convert current state to symbol if possible
          current_state = current_state.to_sym if current_state.respond_to?(:to_sym)

          # Convert valid_states to array of symbols
          valid_states_array = Array(valid_states).map { |s| s.respond_to?(:to_sym) ? s.to_sym : s }

          # Return early if current state is not in the valid states
          return unless valid_states_array.include?(current_state)
        elsif transition[:allow_if].is_a?(Symbol)
          # Handle symbol-based allow_if (method name)
          return unless flow_target.send(transition[:allow_if])
        else
          # Handle proc-based allow_if (original behavior)
          return unless flow_target.instance_exec(*args, **kwargs, &transition[:allow_if])
        end
      end

      if transition[:block]
        flow_target.instance_exec(*args, **kwargs, &transition[:block])
      end

      if transition[:to].respond_to?(:call)
        flow_target.send("#{attribute_name}=", flow_target.instance_exec(*args, **kwargs, &transition[:to]))
      else
        flow_target.send("#{attribute_name}=", transition[:to])
      end.tap do
        if block
          flow_target.instance_exec(*args, **kwargs, &block)
        end
      end
    end
  end

  module_function def model_key(object)
    if object.is_a?(String)
      if object.start_with?("#<Class:")
        "anonymous_#{object.split("0x")[1]}".sub(">", "")
      else
        object
      end
    else
      model_key(object.class.name || object.class.to_s)
    end
  end

  module_function def methodize_name(name)
    name.split("::").map { |part| part.gsub(/([a-z])([A-Z])/, '\1_\2') }.join("_").downcase
  end

  def self.extended(base)
    base.include(InstanceMethods)
    base.singleton_class.attr_reader :flows
  end

  module InstanceMethods
    # Use this method to call an action on the attribute.
    #
    # Example:
    #
    #   test_object.flow(:approve, :status)
    #   test_object.flow(:approve, :status, "arg1", "arg2", key: "value")
    def flow(action, attribute, *args, flow_target: self, **kwargs, &block)
      target_name = if flow_target != self
        Circulator.methodize_name(Circulator.model_key(flow_target))
      end
      external_attribute_name = [target_name, attribute].compact.join("_")
      method_name = "#{external_attribute_name}_#{action}"
      if respond_to?(method_name)
        send(method_name, *args, flow_target:, **kwargs, &block)
      elsif flow_target.respond_to?(method_name)
        flow_target.send(method_name, *args, **kwargs, &block)
      else
        raise "Invalid action for the current state of #{attribute} (#{flow_target.send(attribute).inspect}): #{action}"
      end
    end

    # Get available actions for an attribute based on current state
    #
    # Example:
    #
    #   test_object.available_flows(:status)
    #   # => [:approve, :reject]
    def available_flows(attribute, *args, **kwargs)
      model_key = Circulator.model_key(self)
      flow = flows.dig(model_key, attribute)
      return [] unless flow

      current_value = send(attribute)
      current_state = current_value.respond_to?(:to_sym) ? current_value.to_sym : current_value

      flow.transition_map.select do |action, transitions|
        transition = transitions[current_state]
        next false unless transition

        # Check allow_if condition if present
        if transition[:allow_if]
          check_allow_if(transition[:allow_if], *args, **kwargs)
        else
          true
        end
      end.keys
    end

    # Check if a specific action is available for an attribute
    #
    # Example:
    #
    #   test_object.available_flow?(:status, :approve)
    #   # => true
    def available_flow?(attribute, action, *args, **kwargs)
      available_flows(attribute, *args, **kwargs).include?(action)
    end

    # Get the guard methods for a specific transition
    #
    # Returns an array of Symbol method names if the guard is an array of symbols,
    # or nil if no guard or guard is not an array.
    #
    # Example:
    #
    #   class Order
    #     extend Circulator
    #     flow(:status) do
    #       state :pending do
    #         action :approve, to: :approved, allow_if: [:approved?, :in_budget?]
    #       end
    #     end
    #   end
    #
    #   order = Order.new
    #   order.guards_for(:status, :approve)
    #   # => [:approved?, :in_budget?]
    def guards_for(attribute, action)
      model_key = Circulator.model_key(self)
      flow = flows.dig(model_key, attribute)
      return nil unless flow

      current_value = send(attribute)
      current_state = current_value.respond_to?(:to_sym) ? current_value.to_sym : current_value

      transition = flow.transition_map.dig(action, current_state)
      return nil unless transition

      guard = transition[:allow_if]
      return nil unless guard

      # If guard is an array, return only the Symbol elements
      if guard.is_a?(Array)
        guard.select { |g| g.is_a?(Symbol) }
      end
    end

    private

    def flows
      self.class.flows
    end

    def check_allow_if(allow_if, *args, **kwargs)
      case allow_if
      when Array
        # All guards in array must be true (AND logic)
        allow_if.all? do |guard|
          case guard
          when Symbol
            send(guard, *args, **kwargs)
          when Proc
            instance_exec(*args, **kwargs, &guard)
          end
        end
      when Hash
        attribute_name, valid_states = allow_if.first
        current_state = send(attribute_name)
        current_state = current_state.to_sym if current_state.respond_to?(:to_sym)
        valid_states_array = Array(valid_states).map { |s| s.respond_to?(:to_sym) ? s.to_sym : s }
        valid_states_array.include?(current_state)
      when Symbol
        send(allow_if, *args, **kwargs)
      else # Proc
        instance_exec(*args, **kwargs, &allow_if)
      end
    end
  end
end
