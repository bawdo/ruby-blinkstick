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

  def test_missing_documented_file_fails_validation
    Dir.mktmpdir do |dir|
      (%w[ruby-blinkstick.gemspec lib udev] + DOCUMENTED_FILES - ["LICENSE"]).each do |entry|
        FileUtils.cp_r(File.join(ROOT, entry), dir)
      end

      Dir.chdir(dir) do
        spec = Gem::Specification.load("ruby-blinkstick.gemspec")

        assert_raises(Gem::InvalidSpecificationException) { spec.validate }
      end
    end
  end
end
