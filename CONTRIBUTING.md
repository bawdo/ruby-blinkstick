# Contributing

Thanks for helping. Bug reports, fixes and support for more BlinkStick
models are all welcome.

## Before you start

For anything bigger than a small fix, open an issue or a discussion first,
so we can agree on the approach before you spend time on it. Report
security problems privately, as [SECURITY.md](SECURITY.md) describes.

## Setting up

You need Ruby 3.4 or later.

```sh
bundle install
bundle exec rake                 # RuboCop, then the tests
COVERAGE=1 bundle exec rake test # the tests with an lcov report in coverage/
sh scripts/smoke-gem.sh          # build, install and require the packaged gem
```

CI runs these on macOS and Linux with Ruby 3.4 and 4.0, and a pull request
needs them to pass before it can merge.

## Hardware

Hardware tests arrive with the implementation. None are needed for most
changes.

Automated tests must never write EEPROM on a real stick: no name, info block
or mode writes against hardware. EEPROM wears out, and a contributor's stick
is theirs.

## Changes

- Keep a change to one concern, with tests for new behaviour.
- Update `CHANGELOG.md` under a heading for the next version, and README or
  CAPABILITIES.md if behaviour changes.
- Write commit subjects and pull request titles in the past tense, 60
  characters or fewer, for example "Added Strip support". Pull requests are
  squash merged, so the title becomes the commit on `main`.

## Licence

By contributing, you agree that your contribution is licensed under the MIT
licence in [LICENSE](LICENSE).
