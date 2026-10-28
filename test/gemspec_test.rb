# frozen_string_literal: true

require "test_helper"
require "fileutils"
require "tmpdir"

class GemspecTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)
  DOCUMENTED_FILES = %w[LICENSE README.md CHANGELOG.md CAPABILITIES.md].freeze

  def test_documented_files_are_packaged
    spec = Gem::Specification.load(File.join(ROOT, "ruby-blinkstick.gemspec"))

    DOCUMENTED_FILES.each { |file| assert_includes spec.files, file }
  end

  # scripts/ holds maintainer tools, among them one that writes EEPROM.
  def test_scripts_are_not_packaged
    spec = Gem::Specification.load(File.join(ROOT, "ruby-blinkstick.gemspec"))

    refute_includes spec.files, "scripts/eeprom-check.rb"
    assert_empty spec.files.grep(%r{\Ascripts/})
  end

  def test_missing_documented_file_fails_validation
    Dir.mktmpdir do |dir|
      copy_gem_without(dir, "LICENSE")

      assert_match(/"LICENSE"\] are not files/, validation_error(dir).message)
    end
  end

  private

  def copy_gem_without(dir, missing)
    (%w[ruby-blinkstick.gemspec lib udev] + DOCUMENTED_FILES - [missing]).each do |entry|
      FileUtils.cp_r(File.join(ROOT, entry), dir)
    end
  end

  # Loading the copy re-runs its require_relative of version.rb and makes
  # RubyGems warn, so capture that output. The absolute path also keeps
  # Gem::Specification.load from returning a spec cached for another copy.
  def validation_error(dir)
    error = nil
    capture_io do
      Dir.chdir(dir) do
        spec = Gem::Specification.load(File.join(dir, "ruby-blinkstick.gemspec"))
        error = assert_raises(Gem::InvalidSpecificationException) { spec.validate }
      end
    end
    error
  end
end
