# Capabilities

What the BlinkStick Nano and Square can do, and what this gem supports so far. The Ruby column
names the method or class that covers a row. Back to the [README](README.md).

This file is updated whenever a feature lands.

Key: **yes** supported, **no** not yet, **n/a** the device does not have it, **unverified** the
device may have it but it has not been confirmed on hardware.

## Device features

Features built into the BlinkStick firmware.

| Feature | Nano | Square | Ruby | Supported since | Notes |
|---|---|---|---|---|---|
| List attached sticks | yes | yes | `Blinkstick.list` | 0.1.0 | Enumerate every attached stick |
| Open the first stick or one by serial | yes | yes | `Blinkstick.open`, `Blinkstick.open(serial:)` | 0.1.0 | Open the first stick found, or a stick by its serial |
| Name a stick and open it by name | yes | yes | `stick.name`, `stick.name =`, `Blinkstick.open(name:)`, `Blinkstick.list(names: true)` | 0.3.0 | Stored in info block 1. Writes EEPROM. Two sticks with one name raise `DuplicateNameError` |
| Several sticks open at once | yes | yes | one `Stick` per `Blinkstick.open` | 0.1.0 |  |
| Serial and firmware version | yes | yes | `info.serial`, `info.version`, `info.release` | 0.1.0 | Read from the device info. `info.release` (the USB release number) since 0.3.0 |
| Manufacturer and product strings | yes | yes | `info.manufacturer`, `info.product` | 0.1.0 | Read from the device info |
| Set all LEDs | yes | yes | `stick.colour =`, `stick.off` | 0.1.0 | Set every LED to one colour, or turn them off |
| Set one LED | yes | yes | `stick[i] = colour` | 0.2.0 | Set a single LED by index, using report 5 |
| Set every LED at once | yes | yes | `stick.frame = colours` | 0.2.0 | Write a whole frame in one report |
| Read LED values back | yes | yes | `stick.frame`, `stick[i]` | 0.2.0 | Read the whole frame or a single LED |
| Info blocks 1 and 2 | yes | yes | `stick.info_block(n)`, `stick.write_info_block(n, bytes)` | 0.2.0 | 32 bytes each, stored in EEPROM. Reading since 0.2.0, writing (reports 2 and 3) since 0.3.0. Writes were checked on hardware by the manual EEPROM check (to be confirmed once the maintainer has run it) |
| Set one LED directly (report 5) | yes | yes | `stick[i] = colour` | 0.2.0 | `[5, channel, index, R, G, B]`, RGB order (the frame is GRB). Works in modes 2 and 3. The channel byte is ignored and the index is not range checked |
| Read device mode (report 4) | yes | yes | `stick.mode` | 0.2.0 | `[4, mode]`. Both read mode 2 |
| Set device mode (report 4) | yes | yes | `stick.mode =` | 0.3.0 | Stored in EEPROM, waits for the stick to answer again (12 to 15 ms seen, at most 250 ms), skipped when the mode is unchanged, takes effect without a replug. 2 to 3 to 2 checked on hardware by the manual EEPROM check (to be confirmed once the maintainer has run it) |
| Mode 2, WS2812 | yes | yes | `stick.mode = :ws2812` | 0.3.0 | The mode both are in, and the one every LED feature here needs. Probably the factory default |
| Mode 3, WS2812 mirror | yes | yes | `stick.mode = :ws2812_mirror` | 0.3.0 | Changes only report 1, whose colour goes to every LED. Reports 5 and 6 behave as in mode 2 |
| Modes 0 and 1, normal and inverse | n/a | n/a |  | n/a | For the BlinkStick Pro's RGB outputs. Upstream reports a Nano in mode 1 going dark until replugged. `stick.mode =` refuses them with `ArgumentError` |
| Set LED 0, or every LED in mode 3 (report 1) | yes | yes | `stick[0] =`, `stick.colour =` | n/a | `[1, R, G, B]`, RGB order. Used by other BlinkStick software. Report 1 is never sent: here `stick[0] =` and `stick.colour =` do the same job in either mode |
| Report 10 | n/a | unknown |  | no | Square only, 2 bytes, reads 00 00. Undocumented; waiting on the manufacturer |
| LED count setting (report 0x81) | n/a | n/a |  | n/a | BlinkStick Flex only |
| 16, 32 and 64 LED frames (reports 7 to 9) | n/a | n/a |  | n/a | For longer strips |

## Host features

Features this gem adds in software. They work the same on every supported device.

| Feature | Ruby | Supported since | Notes |
|---|---|---|---|
| Model detection | `info.model` | 0.1.0 | From the serial and USB release number |
| Colour from hex or `r,g,b` | `Colour.parse` | 0.1.0 | Parse a colour from hex, with or without the `#`, or `r,g,b` |
| Brightness limit | `stick.brightness_limit`, `stick.brightness_limit =` | 0.3.0 | Cap the brightness of every colour written from then on. Per `Stick`, not stored on the device |
| Blink, pulse and morph | `stick.blink`, `stick.pulse`, `stick.morph`, `Blinkstick::Cancellation` | 0.3.0 | Cancellable. Return `true` when finished and `false` when cancelled |
| CSS colour names | `Colour.parse` | 0.1.0 | All 148 from CSS Color Level 4 |
| List CSS colour names | `Colour.names` | 0.1.0 | Sorted, for shell completion |
| Colour as hex | `Colour#hex`, `Colour#to_s` | 0.1.0 | Lower case `#rrggbb` |
| Random colour | `Colour.random`, `Colour.random(vivid: true)` | 0.3.0 | Any colour, or a vivid one |
| Inverse colours | `Colour#inverse`, `stick.inverse =`, `stick.inverse?` | 0.3.0 | Invert a colour or the whole frame. Not the firmware inverse mode |
| Reconnect after unplug | automatic | 0.3.0 | Repaints the last frame. Raises `DisconnectedError` when it fails. Never moves onto a different stick |

## Platforms

| Platform | Supported since |
|---|---|
| macOS | 0.1.0 |
| Linux | 0.1.0 |
| Windows | no |
