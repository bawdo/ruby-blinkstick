# Changelog

All notable changes to this project are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project uses
[semantic versioning](https://semver.org/).

## [Unreleased]

### Changed

- The documented `gh attestation verify` command checks the release workflow, not just the repository.
- The release workflow also checks that the attestation names the tagged commit, and a re-run refuses to go on if rubygems.org has a different gem for the version.

## [0.0.2] - 2026-10-28

### Added

- Releases carry SLSA build provenance, attached on rubygems.org and the GitHub release, and checked by the release workflow before publishing.

### Fixed

- The gem build now fails if a documented file is missing, instead of shipping without it.

## [0.0.1] - 2026-10-28

### Added

- Reserved the `ruby-blinkstick` gem name. This release defines `Blinkstick::VERSION` and nothing else.
