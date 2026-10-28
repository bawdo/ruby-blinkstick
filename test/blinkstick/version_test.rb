# frozen_string_literal: true

require "test_helper"

class VersionTest < Minitest::Test
  def test_version_is_semver
    assert_match(/\A\d+\.\d+\.\d+\z/, Blinkstick::VERSION)
  end

  def test_version_is_frozen
    assert_predicate Blinkstick::VERSION, :frozen?
  end
end
