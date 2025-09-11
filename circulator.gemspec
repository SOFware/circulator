# frozen_string_literal: true

require_relative "lib/circulator/version"

Gem::Specification.new do |spec|
  spec.name = "circulator"
  spec.version = Circulator::VERSION
  spec.authors = ["Jim Gay"]
  spec.email = ["jim@saturnflyer.com"]

  spec.summary = "Simple state machine"
  spec.description = "Simple declarative state machine"
  spec.homepage = "https://github.com/SOFware/circulator"
  spec.required_ruby_version = ">= 3.2.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/SOFware/circulator"

  File.basename(__FILE__)
  spec.files = Dir["lib/**/*.rb", "README.md", "LICENSE.txt", "Rakefile", "CHANGELOG.md"]
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]
end
