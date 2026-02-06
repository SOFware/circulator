# Circulator

A lightweight and flexible state machine implementation for Ruby that allows you to define and manage state transitions with an simple DSL. Circulator provides a simple yet powerful way to add state machine functionality to your Ruby classes without the complexity of larger frameworks.

## Key Features

- **Lightweight**: Minimal dependencies and simple implementation
- **Flexible DSL**: Intuitive syntax for defining states and transitions
- **Dynamic Method Generation**: Automatically creates action methods for transitions and predicate methods for state checks
- **Conditional Transitions**: Support for guards and conditional logic
- **Nested State Dependencies**: State machines can depend on the state of other attributes
- **Transition Callbacks**: Execute code before, during, or after transitions
- **Around Wrapping**: Wrap all transitions in a flow with shared logic (e.g., `with_lock`)
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

### Generated Methods

Circulator automatically generates two types of helper methods for your state machines:

#### Action Methods

For each action defined in your state machine, Circulator creates a method that performs the transition:

```ruby
order.status_process  # Transitions from :pending to :processing
order.status_cancel   # Transitions to :cancelled
```

#### State Predicate Methods

For each state in your state machine, Circulator creates a predicate method to check the current state:

```ruby
order.status = :pending

order.status_pending?     # => true
order.status_processing?  # => false
order.status_shipped?     # => false

order.status_process
order.status_processing?  # => true
order.status_pending?     # => false
```

These predicate methods work with both symbol and string values, automatically converting strings to symbols for comparison.

#### Query Available Actions

Circulator provides methods to query which actions are available from the current state:

```ruby
order.status = :pending

# Get all available actions
order.available_flows(:status)  # => [:approve, :reject]

# Check if a specific action is available
order.available_flow?(:status, :approve)  # => true
order.available_flow?(:status, :ship)     # => false
```

These methods respect all `allow_if` conditions and can accept arguments to pass through to guard conditions:

```ruby
# With conditional guards
order.available_flow?(:status, :approve, level: 5)  # => true
```

### Advanced Features

#### Conditional Transitions with Guards

You can control when transitions are allowed using the `allow_if` option. Circulator supports three types of guards:

**Proc-based guards** evaluate a block of code:

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

**Symbol-based guards** call a method on the object:

```ruby
class Document
  extend Circulator

  attr_accessor :state, :reviewed_by

  circulator :state do
    state :draft do
      action :publish, to: :published, allow_if: :ready_to_publish?
    end
  end

  def ready_to_publish?
    reviewed_by.present?
  end
end
```

This is equivalent to the proc-based approach but cleaner when you have a dedicated method for the condition.

You can also use an array of symbols to represent multiple conditions:

```ruby
action :publish, to: :published, allow_if: [:ready_to_publish?, :reviewed_by_present?]
```

This is equivalent to the proc-based approach but cleaner when you have multiple conditions.

**Hash-based guards** check the state of another attribute:

You can make one state machine depend on another using hash-based `allow_if`:

```ruby
class Document
  extend Circulator

  attr_accessor :status, :review_status

  # Review must be completed first
  flow :review_status do
    state :pending do
      action :approve, to: :approved
    end
    state :approved
  end

  # Document status depends on review status
  flow :status do
    state :draft do
      # Can only publish if review is approved
      action :publish, to: :published, allow_if: {review_status: [:approved]}
    end
  end
end

doc = Document.new
doc.status = :draft
doc.review_status = :pending

doc.status_publish  # => blocked, status remains :draft

doc.review_status_approve  # => :approved
doc.status_publish         # => :published ✓
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

#### Wrapping Transitions with `around`

Use the `around` block to wrap all transitions in a flow with shared logic. The block receives a `transition` proc that you must call for the transition to execute:

```ruby
class Order
  extend Circulator

  attr_accessor :status

  flow :status do
    around do |transition|
      puts "before transition"
      transition.call
      puts "after transition"
    end

    state :pending do
      action :approve, to: :approved
    end
  end
end
```

The `around` block is `instance_exec`'d on the instance (consistent with transition blocks and `allow_if` procs), so `self` is the object being transitioned.

**Transactional safety with ActiveRecord:**

This is particularly useful for wrapping transitions in a database lock to prevent race conditions:

```ruby
class Order < ApplicationRecord
  extend Circulator

  flow :status do
    around do |transition|
      with_lock { transition.call }
    end

    state :pending do
      action :approve, to: :approved do
        self.approved_at = Time.current
      end
    end

    state :approved do
      action :ship, to: :shipped
    end
  end
end

# The guard check, transition block, state change, and caller block
# all execute inside the lock — no wrapper methods needed
order.status_approve
```

**Key behaviors:**

- The state read, guard checks (`allow_if`), and state change all run **inside** the wrapper, so the entire check-then-act sequence is atomic
- If `transition.call` is never called, the transition does not execute
- Each flow can have its own `around` block (or none) — flows without one behave exactly as before

#### Extending Flows

You can extend existing flows using `Circulator.extension`. This is useful for plugins, multi-tenant applications, or conditional feature enhancement. Extensions are registered globally and automatically applied when a class defines its flow.

**Basic Extension Example:**

```ruby
class Document
  extend Circulator

  attr_accessor :status

  flow :status do
    state :draft do
      action :submit, to: :review
    end

    state :review do
      action :approve, to: :approved
    end

    state :approved
  end
end

# Register extension - can be in a separate file or initializer
Circulator.extension(:Document, :status) do
  state :review do
    action :reject, to: :rejected
  end

  state :rejected do
    action :revise, to: :draft
  end
end

# Extensions are automatically applied when class is loaded
doc = Document.new
doc.status = :review
doc.status_reject  # => :rejected (from extension)
doc.status_revise  # => :draft (from extension)
```

**How Extensions Work:**

Extensions are registered globally using `Circulator.extension(class_name, attribute)` and are automatically applied when the class defines its flow. Multiple extensions can be registered for the same class/attribute and are applied in registration order. Extensions can be registered before or after the class definition—if registered after, they are applied immediately to the existing flow.

By default, when an extension defines the same action from the same state as the base flow, the extension completely replaces the base definition (last-defined wins). To implement intelligent composition where extensions add their conditions/blocks additively, your application can configure a custom `flows_proc` that uses a Hash-like object with merge logic. Circulator remains dependency-free and supports any compatible Hash implementation.

**Plugin-Style Extensions:**

Extensions are perfect for gems that want to extend Circulator workflows without modifying the host application:

```ruby
# gem_name/lib/gem_name.rb
Circulator.extension(:BlogPost, :status) do
  state :draft do
    action :generate_seo, to: :draft do
      generate_meta_tags
    end
  end

  state :published do
    action :schedule_social, to: :published do
      queue_social_sharing
    end
  end
end

# Host application doesn't need to know about the plugin's extensions
class BlogPost
  extend Circulator

  flow :status do
    state :draft do
      action :publish, to: :published
    end
    state :published
  end
end

# Plugin actions are automatically available
post = BlogPost.new
post.status = :draft
post.status_generate_seo  # From plugin extension
post.status_publish       # From base flow
```

**Conditional Extensions Based on Feature Flags:**

```ruby
# config/initializers/circulator_extensions.rb
if ENV['ENABLE_APPROVAL_WORKFLOW']
  Circulator.extension(:Document, :status) do
    state :draft do
      action :submit_for_approval, to: :approval
    end

    state :approval do
      action :approve, to: :approved
      action :reject, to: :draft
    end

    state :approved
  end
end

# Base flow always available, additional workflow only when enabled
class Document
  extend Circulator

  flow :status do
    state :draft do
      action :save, to: :draft
    end
  end
end
```

### Generating Diagrams

You can generate diagrams for your Circulator models using the `circulator-diagram` executable. By default, it will generate a DOT file. You can also generate a PlantUML file by passing the `-f plantuml` option.

#### Generate a diagram for a specific model:

```bash
bundle exec circulator-diagram MODEL_NAME
```

```bash
bundle exec circulator-diagram MODEL_NAME -f plantuml
```

#### Generate diagrams for all models with Circulator flows:

Use the `--all` option to automatically find and generate diagrams for all classes that have Circulator flows defined:

```bash
bundle exec circulator-diagram --all
```

```bash
bundle exec circulator-diagram --all -f plantuml
```

The `--all` option will:
- Automatically discover all classes with Circulator flows (including classes that inherit from a parent that extends Circulator)
- Eager load Rails application classes if running in a Rails environment
- Generate diagrams for each class found
- Use the same output directory and format options as single-model generation

#### Other options:

- `-d, --directory DIRECTORY` - Specify output directory (default: `docs`)
- `-s, --separate` - Generate separate diagram files for each flow attribute
- `-r, --require FILE` - Require a file before loading models (e.g., `config/environment`)

## Why Circulator?

Circulator distinguishes itself from other Ruby state machine libraries through its simplicity and flexibility:

### Advantages Over Other Libraries

- **Minimal Magic**: Unlike AASM and state_machines, Circulator uses straightforward Ruby metaprogramming without complex DSL magic
- **No Dependencies**: Works with plain Ruby objects without requiring Rails, ActiveRecord, or other frameworks
- **Lightweight**: Smaller footprint compared to feature-heavy alternatives
- **Clear Method Names**: Generated methods follow predictable naming patterns (`status_approve`, `status_pending?`)
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

Releases are automated via the [shared release workflow](https://github.com/SOFware/reissue/blob/main/.github/workflows/SHARED_WORKFLOW_README.md). Trigger a release by running the "Release gem to RubyGems.org" workflow from the Actions tab.

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/SOFware/circulator.
