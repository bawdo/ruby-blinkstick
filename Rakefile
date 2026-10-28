# frozen_string_literal: true

require "bundler/gem_helper"
require "rake/testtask"
require "rubocop/rake_task"

Rake::TestTask.new(:test) do |t|
  t.libs << "test"
  t.pattern = "test/**/*_test.rb"
end

RuboCop::RakeTask.new

# Only the build task from Bundler: releases are published by the release
# workflow, never with `rake release` from a local machine.
gem_helper = Bundler::GemHelper.new(__dir__)
desc "Build ruby-blinkstick-#{gem_helper.gemspec.version}.gem into the pkg directory"
task(:build) { gem_helper.build_gem }

task default: %i[rubocop test]
