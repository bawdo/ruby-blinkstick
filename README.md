# ruby-blinkstick

[![CI](https://github.com/bawdo/ruby-blinkstick/actions/workflows/ci.yml/badge.svg)](https://github.com/bawdo/ruby-blinkstick/actions/workflows/ci.yml)
[![Gem](https://img.shields.io/gem/v/ruby-blinkstick)](https://rubygems.org/gems/ruby-blinkstick)
[![OpenSSF Scorecard](https://api.scorecard.dev/projects/github.com/bawdo/ruby-blinkstick/badge)](https://scorecard.dev/viewer/?uri=github.com/bawdo/ruby-blinkstick)
[![codecov](https://codecov.io/gh/bawdo/ruby-blinkstick/branch/main/graph/badge.svg)](https://codecov.io/gh/bawdo/ruby-blinkstick)

Drive BlinkStick Nano and Square USB LEDs from Ruby.

This gem is unofficial. It is not made by, or affiliated with, Agile Innovative, the makers
of BlinkStick.

## Status

This gem finds a BlinkStick Nano or Square, opens it, sets every LED to a colour, sets one
LED or the whole frame, reads LEDs, the mode and the info blocks back, and turns them off, on
macOS and Linux. Effects, setting the mode and writing the info blocks are still to come. The
per LED, frame and reading calls arrive in 0.2.0. [CAPABILITIES.md](CAPABILITIES.md) lists
what is supported and the Ruby method for each feature.

## Install

```sh
gem install ruby-blinkstick
```

Or in a Gemfile:

```ruby
gem "ruby-blinkstick"
```

The gem is called `ruby-blinkstick` because `blinkstick` was already taken on rubygems.org, so
you `require "blinkstick"` and use the `Blinkstick` module.

## Requirements

- Ruby 3.4 or later.
- macOS or Linux (Windows is not supported).
- Nothing else to install. The gem needs no system library and no compiler: its one
  dependency, `ffi`, installs as a prebuilt gem, and it is only loaded on macOS. Linux talks
  to the stick through `hidraw` using Ruby's standard library alone. Linux also needs the
  udev rule described below.

## Quick start

```ruby
require "blinkstick"

Blinkstick.list
# => [#<data Blinkstick::Info serial="BS072777-3.0", version="3.0",
#      manufacturer="Agile Innovative Ltd", product="BlinkStick",
#      model=#<data Blinkstick::Model name="Nano", leds=2>>]

Blinkstick.open do |stick|         # the first stick; the block form closes it, like File.open
  stick.colour = :cornflowerblue   # set every LED
  stick.colour = "#ff8800"
  stick.colour = [255, 136, 0]
  stick[0] = :red                  # set one LED, the others stay as they are
  stick.frame = [:red, "#00ff00"]  # every LED at once, one colour each (a Nano has 2)
  stick.off                        # every LED off
end

stick = Blinkstick.open(serial: "BS072777-3.0")  # without a block, you close it
stick.info                         # => Blinkstick::Info
stick.close
stick.closed?                      # => true

Blinkstick::Colour.parse("255,136,0").hex   # => "#ff8800"
Blinkstick::Colour.names.first(3)           # => ["aliceblue", "antiquewhite", "aqua"]
```

A colour can be a CSS colour name (a string or symbol, any case), hex (`#rgb` or `#rrggbb`,
with or without the `#`), `"r,g,b"`, or an array of three integers.

`stick[i] = colour` sends one report and leaves the other LEDs alone. The index runs from 0
up to the model's LED count (a Nano has 2 LEDs, a Square 8), and a bad index raises
`IndexError`; negative indexes are refused, not counted from the end. `stick.frame = colours`
needs exactly one colour per LED, so a Nano takes 2 and a Square 8. A wrong count raises
`ArgumentError`, and something that is not an array raises `TypeError`. Every colour is checked
before anything is sent.

Failures raise subclasses of `Blinkstick::Error`: `NotFoundError`, `BusyError`,
`PermissionError`, `UnsupportedModelError`, `ClosedError` and `DisconnectedError`. A bad
colour raises `Blinkstick::InvalidColourError`, which is an `ArgumentError`.

### Reading a stick

```ruby
Blinkstick.open do |stick|
  stick.frame            # => [#<data Blinkstick::Colour red=255, green=0, blue=0>, ...]
  stick[0]               # => #<data Blinkstick::Colour red=255, green=0, blue=0>
  stick.mode             # => :ws2812
  stick.info_block(1)    # => "" or up to 32 bytes, a binary String
end
```

- `stick.frame` returns a frozen Array with one `Colour` per LED of the model (2 for a Nano,
  8 for a Square), and `stick[i]` returns one of them.
- Reads always ask the stick. Nothing is cached, so you see what the stick shows now, even if
  another program changed it.
- `stick.mode` is `:rgb`, `:rgb_inverse`, `:ws2812` or `:ws2812_mirror`. A byte the gem does
  not know comes back as an Integer.
- `stick.info_block(1)` and `stick.info_block(2)` return the 32 byte user data blocks with
  trailing NUL bytes removed, as a frozen binary String. Any other number raises
  `ArgumentError`. The bytes are whatever any tool last wrote there, so treat them as
  untrusted input.
- Nothing in this release writes EEPROM: the mode and info blocks are read only.
- A read that keeps failing raises `Blinkstick::DisconnectedError`, and a read after `close`
  raises `ClosedError`, as writes do.

### Sharing a stick

Sticks are shared on both platforms, so several programs (and several Ruby processes) can
drive the same stick at once, and the last write is what shows. The exception is a program
that seizes the stick for itself, as ones built on hidapi do on macOS. While that program has
it, this gem raises `Blinkstick::BusyError`. Close the other program and try again.

## Linux

BlinkStick devices are owned by root by default, so opening one needs a udev rule. Install the
one shipped with this gem:

```sh
sudo cp udev/60-blinkstick.rules /etc/udev/rules.d/
sudo udevadm control --reload-rules
sudo udevadm trigger
```

Then unplug and replug the stick (or reboot). This grants access to whoever is logged in at the
desktop (via systemd-logind's `uaccess`), not a udev group, so no group membership or new login
session is needed beyond replugging the device.

The rule only grants the `hidraw` node, which is all this gem will use. If you use a tool that
talks to the stick through libusb (such as the official Python `blinkstick` package), add this
line to the rule as well:

```
SUBSYSTEM=="usb", ATTR{idVendor}=="20a0", ATTR{idProduct}=="41e5", TAG+="uaccess"
```

## Verifying a release

From 0.0.2, every release carries build provenance from the release workflow. To check that a gem
came from this repository's workflow, with the [GitHub CLI](https://cli.github.com/):

```sh
gem fetch ruby-blinkstick -v 0.0.2
gh attestation verify ruby-blinkstick-0.0.2.gem --repo bawdo/ruby-blinkstick \
  --signer-workflow bawdo/ruby-blinkstick/.github/workflows/release.yml
```

Swap in the version you are checking. [SECURITY.md](SECURITY.md) has the details.

## Licence

MIT. See [LICENSE](LICENSE).
