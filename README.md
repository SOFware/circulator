# Circulator

A lightweight and flexible state machine implementation for Ruby that allows you to define and manage state transitions with an simple DSL. Circulator provides a simple yet powerful way to add state machine functionality to your Ruby classes without the complexity of larger frameworks.

## Key Features

- **Lightweight**: Minimal dependencies and simple implementation
- **Flexible DSL**: Intuitive syntax for defining states and transitions
- **Dynamic Method Generation**: Automatically creates helper methods for state transitions
- **Conditional Transitions**: Support for guards and conditional logic
- **Transition Callbacks**: Execute code before, during, or after transitions
- **Multiple State Machines**: Define multiple independent state machines per class
- **Framework Agnostic**: Works with plain Ruby objects, no Rails or ActiveRecord required
- **100% Test Coverage**: Thoroughly tested with comprehensive test suite

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'circulator'
```

And then execute:

```bash
bundle install
```

Or install it yourself as:

```bash
gem install circulator
```

## Usage

### Basic Example

```ruby
class Order
  extend Circulator

  attr_accessor :status

  circulator :status do
    state :pending do
      action :process, to: :processing
      action :cancel, to: :cancelled
    end

    state :processing do
      action :ship, to: :shipped
      action :cancel, to: :cancelled
    end

    state :shipped do
      action :deliver, to: :delivered
    end

    state :delivered
    state :cancelled
  end
end

order = Order.new
order.status = :pending

order.status_process  # => :processing
order.status_ship     # => :shipped
order.status_deliver  # => :delivered
```

### Advanced Features

#### Conditional Transitions with Guards

```ruby
class Document
  extend Circulator

  attr_accessor :state, :reviewed_by

  circulator :state do
    state :draft do
      action :submit, to: :review

      action :publish, to: :published, allow_if: -> { reviewed_by.present? } do
        puts "Publishing document reviewed by #{reviewed_by}"
      end
    end
  end
end
```

#### Dynamic Destination States

```ruby
class Task
  extend Circulator

  attr_accessor :priority, :urgency_level

  circulator :priority do
    state :normal do
      # Destination determined at runtime
      action :escalate, to: -> { urgency_level > 5 ? :critical : :high }
    end
  end
end
```

#### Multiple State Machines

```ruby
class Server
  extend Circulator

  attr_accessor :power_state, :network_state

  # First state machine for power management
  circulator :power_state do
    state :off do
      action :boot, to: :booting
    end
    state :booting do
      action :ready, to: :on
    end
    state :on do
      action :shutdown, to: :off
    end
  end

  # Second state machine for network status
  circulator :network_state do
    state :disconnected do
      action :connect, to: :connected
    end
    state :connected do
      action :disconnect, to: :disconnected
    end
  end
end
```

#### Transition Callbacks

```ruby
class Payment
  extend Circulator

  attr_accessor :status, :processed_at

  circulator :status do
    state :pending do
      action :process, to: :completed do
        self.processed_at = Time.now
        send_confirmation_email
      end
    end
  end

  private

  def send_confirmation_email
    # Send email logic here
  end
end
```

### Generating Diagrams

You can generate diagrams for your Circulator models using the `circulator-diagram` executable. By default, it will generate a DOT file. You can also generate a PlantUML file by passing the `-f plantuml` option.

```bash
bundle exec circulator-diagram MODEL_NAME
```

```bash
bundle exec circulator-diagram MODEL_NAME -f plantuml
```

## Why Circulator?

Circulator distinguishes itself from other Ruby state machine libraries through its simplicity and flexibility:

### Advantages Over Other Libraries

- **Minimal Magic**: Unlike AASM and state_machines, Circulator uses straightforward Ruby metaprogramming without complex DSL magic
- **No Dependencies**: Works with plain Ruby objects without requiring Rails, ActiveRecord, or other frameworks
- **Lightweight**: Smaller footprint compared to feature-heavy alternatives
- **Clear Method Names**: Generated methods follow predictable naming patterns (`status_approve`, `priority_escalate`)
- **Flexible Architecture**: Easy to extend and customize for specific needs

### When to Use Circulator

Choose Circulator when you need:
- A simple, lightweight state machine without framework dependencies
- Clear, predictable method naming conventions
- Multiple independent state machines on the same object
- Easy-to-understand code without DSL complexity
- Full control over state transition logic

## Related Projects

If Circulator doesn't meet your needs, consider these alternatives:

- **[AASM](https://github.com/aasm/aasm)** - Full-featured state machine with ActiveRecord integration and extensive callbacks
- **[state_machines](https://github.com/state-machines/state_machines)** - Comprehensive state machine library with GraphViz visualization support
- **[workflow](https://github.com/geekq/workflow)** - Workflow-focused state machine with emphasis on business processes
- **[statesman](https://github.com/gocardless/statesman)** - Database-backed state machines with transition history
- **[finite_machine](https://github.com/piotrmurach/finite_machine)** - Minimal finite state machine with a simple DSL

Each library has its strengths:
- Use **AASM** for Rails applications needing ActiveRecord integration
- Use **state_machines** for complex state logic with visualization needs
- Use **workflow** for business process modeling
- Use **statesman** when audit trails and transition history are critical
- Use **finite_machine** for thread-safe state machines
- Use **Circulator** for lightweight, flexible state management without dependencies

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake test` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run bundle exec rake install.

This project is managed with [Reissue](https://github.com/SOFware/reissue).

To release a new version, make your changes and be sure to update the CHANGELOG.md.

To release a new version:

    bundle exec rake build:checksum
    bundle exec rake release

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/SOFware/circulator.
