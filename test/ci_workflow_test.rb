# frozen_string_literal: true

require "test_helper"
require "yaml"

# Pins the CI workflow's matrix behaviour.
class CiWorkflowTest < Minitest::Test
  CI = File.expand_path("../.github/workflows/ci.yml", __dir__)

  # One OS failing the smoke install must not cancel, and so hide, the other.
  def test_smoke_runs_every_os_to_the_end
    strategy = YAML.load_file(CI).fetch("jobs").fetch("smoke").fetch("strategy")

    assert_equal({ "fail-fast" => false, "matrix" => { "os" => %w[ubuntu-latest macos-latest] } }, strategy)
  end
end
