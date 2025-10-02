# frozen_string_literal: true

if ENV["CI"]
  require "simplecov"
end

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "circulator"
require "circulator/dot"
require "circulator/plantuml"

require "minitest/autorun"
require "minitest/hell"  # Enable parallel test execution
