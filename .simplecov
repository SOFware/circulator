# SimpleCov configuration
# This file is loaded automatically by SimpleCov when tests run

# Start SimpleCov with configuration
SimpleCov.start do
  # Configure formatters - use both HTML and JSON
  require "simplecov-html"
  require "simplecov_json_formatter"
  formatter SimpleCov::Formatter::MultiFormatter.new([
    SimpleCov::Formatter::HTMLFormatter,
    SimpleCov::Formatter::JSONFormatter
  ])

  # Track all library files
  track_files "lib/**/*.rb"

  # Enable coverage types
  enable_coverage :line
  enable_coverage :branch

  # Filters
  add_filter "/test/"
  add_filter "/lib/circulator/version.rb"
  add_filter "/exe/"

  # Minimum coverage thresholds
  # Note: define_method blocks cannot be tracked by SimpleCov
  # See test/circulator/metaprogramming_coverage_test.rb for proof of execution
  minimum_coverage line: 95, branch: 85
end
