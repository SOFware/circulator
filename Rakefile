# frozen_string_literal: true

require "bundler/gem_tasks"
require "minitest/test_task"

Minitest::TestTask.create

require "standard/rake"

task default: %i[test standard]

require "reissue/gem"

Reissue::Task.create :reissue do |task|
  task.version_file = "lib/circulator/version.rb"
  task.changelog_file = "CHANGELOG.md"
  task.version_limit = 1
end
