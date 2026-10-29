# ruby-blinkstick

[![CI](https://github.com/bawdo/ruby-blinkstick/actions/workflows/ci.yml/badge.svg)](https://github.com/bawdo/ruby-blinkstick/actions/workflows/ci.yml)
[![Gem](https://img.shields.io/gem/v/ruby-blinkstick)](https://rubygems.org/gems/ruby-blinkstick)
[![OpenSSF Scorecard](https://api.scorecard.dev/projects/github.com/bawdo/ruby-blinkstick/badge)](https://scorecard.dev/viewer/?uri=github.com/bawdo/ruby-blinkstick)
[![OpenSSF Best Practices](https://www.bestpractices.dev/projects/16044/badge)](https://www.bestpractices.dev/projects/16044)
[![codecov](https://codecov.io/gh/bawdo/ruby-blinkstick/branch/main/graph/badge.svg)](https://codecov.io/gh/bawdo/ruby-blinkstick)

Drive BlinkStick Nano and Square USB LEDs from Ruby.

This gem is unofficial. It is not made by, or affiliated with, Agile Innovative, the makers
of BlinkStick.

## Status

This gem finds a BlinkStick Nano or Square, opens it by serial or by name, sets every LED to a
colour, sets one LED or the whole frame, reads LEDs, the mode and the info blocks back, and
turns them off, on macOS and Linux. It can also name a stick, write the info blocks, set the
mode, limit the brightness, invert the output, pick random colours, run cancellable blink,
pulse and morph effects, and reconnect after an unplug. [CAPABILITIES.md](CAPABILITIES.md)
lists what is supported and the Ruby method for each feature.

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
#      model=#<data Blinkstick::Model name="Nano", leds=2>, release=514>]

Blinkstick.open do |stick|         # the first stick; the block form closes it, like File.open
  stick.colour = :cornflowerblue   # set every LED
  stick.colour = "#ff8800"
  stick.colour = [255, 136, 0]
  stick[0] = :red                  # set one LED, the others stay as they are
  stick.frame = Array.new(stick.info.model.leds) { |i| i.even? ? :red : :green }  # every LED at once, one colour each
  stick.off                        # every LED off
end

Blinkstick.open(name: "desk") do |stick|  # a stick you have named, see "Writing to the stick's memory"
  stick.brightness_limit = 128     # every colour written from now on is scaled to half
  stick.inverse = true             # for LEDs wired so 255 is off; set it before setting LEDs
  stick.colour = Blinkstick::Colour.random(vivid: true)  # any fully saturated hue
end

stick = Blinkstick.open(serial: "BS072777-3.0")  # without a block, you close it
stick.info                         # => Blinkstick::Info
stick.close
stick.closed?                      # => true

Blinkstick::Colour.parse("255,136,0").hex   # => "#ff8800"
Blinkstick::Colour.names.first(3)           # => ["aliceblue", "antiquewhite", "aqua"]
Blinkstick::Colour.parse("red").inverse     # => #<data Blinkstick::Colour red=0, green=255, blue=255>
Blinkstick::Colour.random                   # each channel picked from 0 to 255
```

A colour can be a CSS colour name (a string or symbol, any case), hex (`#rgb` or `#rrggbb`,
with or without the `#`), `"r,g,b"`, or an array of three integers.

`stick[i] = colour` sends one report and leaves the other LEDs alone. The index runs from 0
to one less than the model's LED count (a Nano takes 0 or 1, a Square 0 to 7), and a bad index raises
`IndexError`; negative indexes are refused, not counted from the end. `stick.frame = colours`
needs exactly one colour per LED, so a Nano takes 2 and a Square 8. A wrong count raises
`ArgumentError`, and something that is not an array raises `TypeError`. Every colour is checked
before anything is sent.

Failures raise subclasses of `Blinkstick::Error`: `NotFoundError`, `BusyError`,
`PermissionError`, `UnsupportedModelError`, `ClosedError`, `DisconnectedError` and
`DuplicateNameError`. A bad colour raises `Blinkstick::InvalidColourError`, which is an
`ArgumentError`.

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
- A read that keeps failing makes the stick try to reconnect (see "Reconnecting"), and raises
  `Blinkstick::DisconnectedError` if that fails too. A read after `close` raises `ClosedError`,
  as writes do.

### Brightness limit and inverse

```ruby
stick.brightness_limit = 128   # an Integer from 0 to 255; 255, the default, is no limit
stick.brightness_limit         # => 128
stick.colour = :white          # sent as 128, 128, 128
stick.frame.first              # => #<data Blinkstick::Colour red=128, green=128, blue=128>

stick.inverse = true           # sends 255 minus each channel, after the limit
stick.inverse?                 # => true
```

- The limit scales every channel of every colour written from then on, as `v * limit / 255`
  with integer division: `colour=`, `[]=`, `frame=`, `off` and the effects. It does not repaint
  what is already lit, and reads return what the stick holds, so they show the limited values.
- `inverse` is for LEDs wired so that 255 is off. Reads flip back, so `frame` and `stick[i]`
  return the colours you wrote. It does not repaint either, so set it before setting LEDs. It is
  not the firmware inverse mode (mode 1), which this gem refuses.
- Both belong to the `Stick` object. They are not stored on the device, and a second `Stick` on
  the same serial starts with no limit and no inverse.

### Random colours

```ruby
Blinkstick::Colour.random              # each channel picked from 0 to 255
Blinkstick::Colour.random(vivid: true) # one of the 1530 fully saturated hues
```

These use Ruby's `Random`, so they are for pretty lights and nothing security related. Pass
`random:` (anything with a `rand` method) to make them repeatable in tests.

### Writing to the stick's memory

A stick keeps a name, two 32 byte info blocks and its LED mode in EEPROM. **EEPROM wears out
with writes**, so set these once and never in a loop. `name=`, `write_info_block` and `mode=`
write EEPROM; the other calls here only read. An EEPROM call is retried like any transfer, so
on a flaky connection one call can send the same write up to six times (three attempts, a
reconnect, three more), as go-blinkstick does. That is one more reason not to call these in a
loop.

```ruby
Blinkstick.open do |stick|
  stick.name = "desk"                    # stored in info block 1
  stick.name                             # => "desk"
  stick.write_info_block(2, "my notes")  # padded with zeros to 32 bytes
  stick.info_block(2)                    # => "my notes"
  stick.mode = :ws2812_mirror            # reads first, writes only if the mode differs
end

Blinkstick.open(name: "desk") { |stick| stick.colour = :green }

Blinkstick.list(names: true)
# => [#<data Blinkstick::NamedInfo info=#<data Blinkstick::Info ...>, name="desk", busy=false>]
```

- A name is a String of valid UTF-8 with no NUL and at most 32 bytes. `""` clears it. A wrong
  type raises `TypeError` and a bad value raises `ArgumentError`, before anything is sent.
  Names are held in info block 1, as the official tools and the Go library do, so writing
  block 1 changes the name.
- `Blinkstick.open(name:)` opens each stick in turn, reads its name and keeps the one that
  matches byte for byte (the others are closed). A stick that cannot be opened or read is
  skipped. No match raises `NotFoundError` whose message says why each stick was skipped, and
  two matches raise `DuplicateNameError` naming their serials. `serial:` and `name:` together,
  or an empty name, raise `ArgumentError`. A match that is a model this gem does not support
  raises `UnsupportedModelError`.
- `Blinkstick.list(names: true)` opens every stick briefly to read its name. A stick it cannot
  open (another program has seized it, say) comes back with `busy?` true and an empty name.
  `Blinkstick.list` with no argument opens nothing.
- `write_info_block(number, bytes)` takes block 1 or 2 and a String of at most 32 bytes, written
  byte for byte whatever its encoding. Trailing NUL bytes read back as nothing, because reads
  strip them. A bad number or too many bytes raises `ArgumentError`, and a non String raises
  `TypeError`.
- `stick.mode =` takes `:ws2812` (or 2) or `:ws2812_mirror` (or 3). In mirror mode `colour=`
  still lights every LED, and reports 5 and 6 behave as in mode 2. The change needs no replug.
  The stick stops answering for a moment after a mode write (typically 12 to 15 ms), so
  `mode=` waits until it answers with the new mode, raising `DisconnectedError` if it has not
  within 250 ms. Modes 0 and 1 are for the BlinkStick Pro: they raise `ArgumentError`, as
  they can leave a Nano dark until it is replugged.
- Names and info block bytes are whatever any tool last wrote, so they may not be valid UTF-8
  and may hold control characters. They come back as they are. Treat them as untrusted input,
  and sanitise them before printing them to a terminal.

### Effects

```ruby
stick.blink(:red, period: 1.0, repeats: 3)   # on for 0.5 s, off for 0.5 s, three times
stick.pulse(:blue, duration: 2.0)            # off, fade up to blue, fade down to off
stick.morph(:green, duration: 1.5)           # fade from what the stick shows now to green
```

All three block the calling thread until they finish. Times are in seconds. Colours are
anything `Colour.parse` takes, checked before anything is sent. `blink` and `pulse` take
`repeats:` (an Integer of 1 or more) and end with the LEDs off, and `morph` ends on its colour.
`morph` fades in 20 ms steps, counted as the Go library counts them (0.58 s is 29 steps), and
a duration under one step jumps straight to the colour. The brightness limit applies once, so
a fade to full red with a limit of 128 ends at 128.

To stop an effect from another thread, give it a `Blinkstick::Cancellation`:

```ruby
cancel = Blinkstick::Cancellation.new
worker = Thread.new { stick.blink(:red, period: 1.0, repeats: 60, cancel: cancel) }

sleep 3
cancel.cancel        # wakes the effect straight away; calling it again does nothing
worker.value         # => false
cancel.cancelled?    # => true
```

- An effect returns `true` when it runs to the end and `false` when it was cancelled. A
  cancelled effect leaves the LEDs as they are, so turn them off yourself if you want that.
- With no `cancel:` the effect just pauses with plain timed waits.
- One `Cancellation` can be shared by several effects. Its `wait(seconds)` returns `true` as
  soon as it is cancelled and `false` after `seconds`.
- Each write takes the stick's lock on its own, so other calls can run in the middle of an
  effect. Two effects on one stick at the same time interleave their frames, and the gem does
  not stop you.
- Do not call a `Cancellation`'s methods from a `trap` handler: they take a Mutex, and Ruby
  refuses that inside a trap. Set a flag in the handler and cancel from a normal thread instead.

### Reconnecting

If a stick is unplugged, or stops answering for three attempts, the `Stick` closes its handle,
lists the attached sticks again and opens the one with its serial. When that works it repaints
the last frame it wrote, then repeats the call that failed. Plug the stick back in and the next
call just works, with the LEDs as you left them.

- The remembered frame is what the gem last wrote (after the brightness limit, before inverse).
  `colour=`, `frame=`, `off` and the effects replace it, and `[]=` updates one entry. Nothing
  is repainted if nothing has been written yet, or if the call that failed was itself a frame
  write (it is simply retried).
- The first `[]=` on a `Stick` that has written nothing reads the frame from the stick once, so
  the entries it does not touch are kept.
- It tries once per call. If the stick is missing, cannot be opened or the repaint fails, the
  call raises `DisconnectedError`, and the next call tries again. `close` on a disconnected
  stick succeeds.
- A `Stick` never reconnects onto a different stick. If more than one attached stick has its
  serial, it raises `DisconnectedError` rather than guess. (A stick with an empty serial, which
  Linux reports when there is no `HID_UNIQ`, is an unknown model and cannot be opened at all.)
- `BusyError`, `PermissionError` and `ClosedError` are raised as they are, without reconnecting.

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
