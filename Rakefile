# frozen_string_literal: true

require "bundler/gem_helper"
require "rake/testtask"
require "rubocop/rake_task"

Rake::TestTask.new(:test) do |t|
  t.libs << "test"
  t.pattern = "test/**/*_test.rb"
end

# Runs only the opt-in hardware tests; the test process gets BLINKSTICK_HARDWARE=1.
Rake::TestTask.new(:hardware_tests) do |t|
  t.libs << "test"
  t.test_files = FileList["test/hardware/hardware_test.rb"]
  t.description = "Run the hardware tests (internal; use the hardware task)"
end

desc "Run the hardware tests against attached BlinkSticks (writes colours only, never EEPROM)"
task :hardware do
  ENV["BLINKSTICK_HARDWARE"] = "1"
  Rake::Task[:hardware_tests].invoke
end

RuboCop::RakeTask.new

# Only the build task from Bundler: releases are published by the release
# workflow, never with `rake release` from a local machine.
gem_helper = Bundler::GemHelper.new(__dir__)
desc "Build ruby-blinkstick-#{gem_helper.gemspec.version}.gem into the pkg directory"
task(:build) { gem_helper.build_gem }

task default: %i[rubocop test]
