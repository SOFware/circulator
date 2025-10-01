# frozen_string_literal: true

require "bundler/gem_tasks"
require "rake/testtask"

Rake::TestTask.new(:test) do |t|
  t.libs << "test"
  t.libs << "lib"
  t.test_files = FileList["test/**/*_test.rb"]
  t.verbose = true
  t.warning = true
end

require "standard/rake"

task default: %i[test standard]

require "reissue/gem"

Reissue::Task.create :reissue do |task|
  task.version_file = "lib/circulator/version.rb"
  task.changelog_file = "CHANGELOG.md"
  task.version_limit = 1
end
