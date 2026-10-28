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

Hardware tests drive real sticks and are opt-in. `bundle exec rake` runs
`test/hardware/hardware_test.rb` too, but every test in it skips unless
`BLINKSTICK_HARDWARE=1`, so ordinary runs and CI never touch a device. To run
them for real:

```sh
bundle exec rake hardware
```

The tests list sticks, open one by serial, set it red and turn it off, and
(with a Nano and a Square both attached) colour each and turn both off. For
every attached stick they also check that a frame reads back equal to what was
written, that setting one LED changes only that LED, that the mode is
`:ws2812`, and that info blocks 1 and 2 are Strings of at most 32 bytes. On
macOS they also start two Ruby processes that each open the same stick and
hold it open at the same time before writing, and a third check where one
process writes a frame and holds the stick open while a second process, with
its own open handle, reads that frame back. Those shared opens are the checks
that decide a release: if the shared open or the shared read fails on macOS,
the release stops. Attach a Nano and a Square for the full run; without both,
the pair test skips with a message.

The 0.3.0 checks cover, for every attached stick, the brightness limit (a
limited write reads back scaled), inverse (the frame reads back as written
while a second, plain handle on the same serial reads the flipped bytes), morph
ending on its colour, blink and pulse ending off, an effect given an already
cancelled `Blinkstick::Cancellation` returning `false` and changing nothing,
`Blinkstick.list(names: true)` returning one entry per stick, and `info.release`
matching the model (Nano `0x0202`, Square `0x0201`). They write colours only.

Automated tests must never write EEPROM on a real stick: no name, info block
or mode writes against hardware. EEPROM wears out, and a contributor's stick
is theirs. These tests set colours and turn the stick off, nothing else.

On Linux you need the udev rule from the `## Linux` section of the
[README](README.md), then a replug, or the tests fail with a permission error.

### EEPROM check before a release

The automated tests never write EEPROM, so name, info block and mode writes get
a manual check, once on each OS (macOS and Linux), with one stick attached. Only
the maintainer runs it; `rake`, `rake hardware` and CI never do.

```sh
ruby -Ilib scripts/eeprom-check.rb SERIAL --yes-write-eeprom
```

It exits 2 with a usage message unless it gets both the serial and the
`--yes-write-eeprom` flag. It also exits 2, writing nothing, when the serial
matches no stick or more than one (it refuses an ambiguous serial rather than
picking the first), and when the stick is not in mode 2 or 3 (`mode=` cannot
restore modes 0 or 1).

It saves both info blocks (block 1 holds the name) and the mode. It then writes
the name `eeprom-check`, info block 2 `eeprom-check-2`, and the mode it is not
in followed by its own, so two real mode writes happen, reading each back. It
restores the saved blocks and mode last, byte for byte (including a name that
is not valid UTF-8), even if a step fails, and prints a line for every write,
read and restore. It exits 1 on any mismatch or failed restore, or when the gem
raises an error (the stick is busy, say). A stick has been seen refusing
transfers for 12 to 15 ms after each mode write, which `mode=` waits out (for up
to 250 ms) before the script reads the mode back.

Ctrl-C before the first write stops the script as usual. Ctrl-C during the
writes stops them, the restore still runs, and the script then ends as
interrupted, with no summary line. Ctrl-C during the restore is noted and the
restore still runs to the end, then the script reports it and exits 1. The
script is not part of the gem.

### Manual check before a release

Run this once on each OS (macOS and Linux) with a stick attached.

1. In `irb -Ilib -rblinkstick`, run `stick = Blinkstick.open`, unplug the
   stick, then run `stick.colour = :red`. Expect a `Blinkstick::DisconnectedError`,
   not a raw `Errno` or ffi error.
2. Plug the stick back in and run `serial = Blinkstick.list.first.serial`.
   Unplug it again, then run `Blinkstick.open(serial: serial)`. Expect a
   `Blinkstick::NotFoundError`.
3. Plug the stick back in, then run `stick = Blinkstick.open` and
   `stick.colour = :green`. Unplug the stick and plug it back in, then run
   `stick.mode`. Expect it to reconnect and return the mode, with the green
   frame back on the LEDs.

## Changes

- Keep a change to one concern, with tests for new behaviour.
- Add an entry under `## [Unreleased]` in `CHANGELOG.md`, and update README or
  CAPABILITIES.md if behaviour changes.
- Write commit subjects and pull request titles in the past tense, 60
  characters or fewer, for example "Added Strip support". Pull requests are
  squash merged, so the title becomes the commit on `main`.

## Releasing

1. In a pull request, set `Blinkstick::VERSION` in `lib/blinkstick/version.rb`
   and rename `## [Unreleased]` in `CHANGELOG.md` to `## [x.y.z] - YYYY-MM-DD`,
   with a fresh, empty `## [Unreleased]` above it.
2. Once it merges, `git switch main && git pull --ff-only`.
3. `git tag -s vx.y.z -m "Released x.y.z"`, then `git push origin vx.y.z`.

Check the new section has entries before tagging: the release workflow refuses
a tag that does not match `Blinkstick::VERSION`, or whose CHANGELOG section is
missing or empty, and tags cannot be moved or reused once pushed. Everything
else (build, attest, publish, GitHub release) the workflow does itself, and it
stops before publishing if the attestation does not verify.

If a release run fails, use "Re-run failed jobs" within a day, while the
run's artifacts are kept. Publish skips the push when rubygems.org already has
the version, and goes on to check the attestation and create the GitHub
release. After a day, "Re-run all jobs" rebuilds instead, and publish refuses
to go on if the rebuilt gem differs from the one on rubygems.org.

## Licence

By contributing, you agree that your contribution is licensed under the MIT
licence in [LICENSE](LICENSE).
