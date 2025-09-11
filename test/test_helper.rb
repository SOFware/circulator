# frozen_string_literal: true

if ENV["CI"]
  require "simplecov"
end

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "circulator"

require "minitest/autorun"
