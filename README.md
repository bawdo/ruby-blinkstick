# ruby-blinkstick

[![CI](https://github.com/bawdo/ruby-blinkstick/actions/workflows/ci.yml/badge.svg)](https://github.com/bawdo/ruby-blinkstick/actions/workflows/ci.yml)
[![Gem](https://img.shields.io/gem/v/ruby-blinkstick)](https://rubygems.org/gems/ruby-blinkstick)
[![OpenSSF Scorecard](https://api.scorecard.dev/projects/github.com/bawdo/ruby-blinkstick/badge)](https://scorecard.dev/viewer/?uri=github.com/bawdo/ruby-blinkstick)
[![codecov](https://codecov.io/gh/bawdo/ruby-blinkstick/branch/main/graph/badge.svg)](https://codecov.io/gh/bawdo/ruby-blinkstick)

Drive BlinkStick Nano and Square USB LEDs from Ruby.

This gem is unofficial. It is not made by, or affiliated with, Agile Innovative, the makers
of BlinkStick.

## Status

`0.0.1` reserves the gem name and does nothing else. The implementation will port
[go-blinkstick](https://github.com/bawdo/go-blinkstick). See [CAPABILITIES.md](CAPABILITIES.md)
for the features it will cover.

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

The rule only grants the `hidraw` node, which is all this gem uses. If you use a tool that talks
to the stick through libusb (such as the official Python `blinkstick` package), add this line to
the rule as well:

```
SUBSYSTEM=="usb", ATTR{idVendor}=="20a0", ATTR{idProduct}=="41e5", TAG+="uaccess"
```

## Licence

MIT. See [LICENSE](LICENSE).
