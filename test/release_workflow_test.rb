# frozen_string_literal: true

require "test_helper"
require "yaml"

# Pins the release workflow's security shape, so a pull request that gives
# the attest job an environment, the publish job a checkout, either job
# holding an id-token another action or an installed gem, or any job an
# extra permission turns CI red.
class ReleaseWorkflowTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)
  WORKFLOWS = File.join(ROOT, ".github", "workflows")
  PINNED_USES = /uses: \S+@[0-9a-f]{40} # v\d+\.\d+\.\d+$/
  INSTALLS = /\b(gem (install|exec|update)|bundle (install|exec|update)|bundler)\b/

  def test_jobs_run_build_attest_publish_release
    assert_equal %w[build attest publish github-release], jobs.keys
    assert_equal({ "attest" => %w[build], "publish" => %w[build attest], "github-release" => %w[publish] },
                 jobs.except("build").transform_values { |job| Array(job["needs"]) })
  end

  def test_attest_job_cannot_mint_a_publish_credential
    assert_equal({ "environment" => :none, "bundler-cache" => false, "continue-on-error" => false, "installs" => 0,
                   "actions" => %w[actions/download-artifact actions/attest actions/upload-artifact],
                   "permissions" => { "contents" => "read", "id-token" => "write", "attestations" => "write" } },
                 shape(jobs.fetch("attest")))
  end

  def test_publish_job_runs_no_repository_code
    publish = jobs.fetch("publish")

    assert_equal({ "environment" => "rubygems", "bundler-cache" => false, "continue-on-error" => false,
                   "installs" => 0,
                   "actions" => %w[actions/download-artifact actions/download-artifact ruby/setup-ruby
                                   rubygems/configure-rubygems-credentials],
                   "permissions" => { "contents" => "read", "id-token" => "write" } },
                 shape(publish))
    assert(publish["steps"].any? { |step| step["run"].to_s.include?("gem push --attestation") })
  end

  def test_other_jobs_keep_their_permissions
    assert_equal({ "build" => { "contents" => "read" }, "github-release" => { "contents" => "write" } },
                 jobs.slice("build", "github-release").transform_values { |job| job["permissions"] })
  end

  def test_every_action_is_pinned_to_a_sha
    Dir[File.join(WORKFLOWS, "*.yml")].each do |path|
      File.foreach(path).grep(/uses:/).each do |line|
        assert_match PINNED_USES, line.strip, "#{File.basename(path)}: #{line.strip}"
      end
    end
  end

  private

  def jobs
    @jobs ||= YAML.load_file(File.join(WORKFLOWS, "release.yml")).fetch("jobs")
  end

  # The properties that decide whether a job can mint a publish credential
  # or run repository code. Pinning the exact actions rules out a checkout
  # or any other action, and continue-on-error would let a failed check,
  # such as the attestation verify, pass.
  def shape(job)
    steps = job["steps"]
    {
      "environment" => job.fetch("environment", :none),
      "bundler-cache" => steps.any? { |step| step.fetch("with", {}).key?("bundler-cache") },
      "continue-on-error" => ([job] + steps).any? { |entry| entry.key?("continue-on-error") },
      "installs" => steps.count { |step| step["run"].to_s.match?(INSTALLS) },
      "actions" => actions(steps),
      "permissions" => job["permissions"]
    }
  end

  # Each step's action without its pinned SHA, in order.
  def actions(steps)
    steps.filter_map { |step| step["uses"]&.split("@")&.first }
  end
end
