# Changelog

All notable changes to this project are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project uses
[semantic versioning](https://semver.org/).

## [Unreleased]

## [0.1.0] - 2026-10-28

### Added

- `Blinkstick.list` lists every attached BlinkStick as an `Info` value with its serial, firmware version, manufacturer, product and model.
- `Blinkstick.open` opens the first stick or one by serial, with or without a block. Several sticks can be open at once.
- `Stick#colour=` sets every LED to one colour and `Stick#off` turns them off. A stick is safe to share between threads, and `close` and `closed?` manage its lifetime.
- `Colour.parse` accepts hex, `r,g,b`, an array of three integers and the 148 CSS colour names (strings or symbols, any case). `Colour#hex` and `Colour#to_s` give lower case `#rrggbb`, and `Colour.names` lists the names.
- Model detection for the BlinkStick Nano (2 LEDs) and Square (8 LEDs). Other models are listed as `Model::UNKNOWN` and refused by `open`.
- Errors under `Blinkstick::Error` for a missing stick, a stick seized by another program, a refused permission, an unsupported model, a closed stick and a disconnected stick. `InvalidColourError` is an `ArgumentError`.
- macOS support through IOKit (via `ffi`, loaded only on macOS) and Linux support through `hidraw`, with nothing to install but the gem. Sticks are opened shared, so other programs can use them too.

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
