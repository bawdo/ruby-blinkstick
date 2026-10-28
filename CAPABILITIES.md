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
| Name a stick and open it by name | no | no |  | not yet | Store a name, read it back, open and list sticks by name. Stored in info block 1 |
| Several sticks open at once | yes | yes | one `Stick` per `Blinkstick.open` | 0.1.0 |  |
| Serial and firmware version | yes | yes | `info.serial`, `info.version` | 0.1.0 | Read from the device info |
| Manufacturer and product strings | yes | yes | `info.manufacturer`, `info.product` | 0.1.0 | Read from the device info |
| Set all LEDs | yes | yes | `stick.colour =`, `stick.off` | 0.1.0 | Set every LED to one colour, or turn them off |
| Set one LED | no | no |  | not yet | Set a single LED by index, using report 5 |
| Set every LED at once | no | no |  | not yet | Write a whole frame in one report |
| Read LED values back | no | no |  | not yet | Read the whole frame or a single LED |
| Info blocks 1 and 2 | no | no |  | not yet | Read and write the info blocks. 32 bytes each, stored in EEPROM |
| Set one LED directly (report 5) | no | no |  | not yet | `[5, channel, index, R, G, B]`, RGB order (the frame is GRB). Works in modes 2 and 3. The channel byte is ignored and the index is not range checked |
| Read device mode (report 4) | no | no |  | not yet | `[4, mode]`. Both read mode 2 |
| Set device mode (report 4) | no | no |  | not yet | Stored in EEPROM, blocks about 50 ms, skipped when the mode is unchanged, takes effect without a replug. 2 to 3 to 2 verified on both |
| Mode 2, WS2812 | no | no |  | not yet | The mode both are in, and the one every LED feature here needs. Probably the factory default |
| Mode 3, WS2812 mirror | no | no |  | not yet | Changes only report 1, whose colour goes to every LED. Reports 5 and 6 behave as in mode 2 |
| Modes 0 and 1, normal and inverse | n/a | n/a |  | n/a | For the BlinkStick Pro's RGB outputs. Upstream reports a Nano in mode 1 going dark until replugged. Setting the mode refuses them |
| Set LED 0, or every LED in mode 3 (report 1) | no | no |  | not yet | `[1, R, G, B]`, RGB order. Used by other BlinkStick software. Setting LED 0 or all LEDs does the same job in either mode |
| Report 10 | n/a | unknown |  | no | Square only, 2 bytes, reads 00 00. Undocumented; waiting on the manufacturer |
| LED count setting (report 0x81) | n/a | n/a |  | n/a | BlinkStick Flex only |
| 16, 32 and 64 LED frames (reports 7 to 9) | n/a | n/a |  | n/a | For longer strips |

## Host features

Features this gem adds in software. They work the same on every supported device.

| Feature | Ruby | Supported since | Notes |
|---|---|---|---|
| Model detection | `info.model` | 0.1.0 | From the serial and USB release number |
| Colour from hex or `r,g,b` | `Colour.parse` | 0.1.0 | Parse a colour from hex, with or without the `#`, or `r,g,b` |
| Brightness limit |  | not yet | Cap the brightness of every colour written |
| Blink, pulse and morph |  | not yet | Cancellable |
| CSS colour names | `Colour.parse` | 0.1.0 | All 148 from CSS Color Level 4 |
| List CSS colour names | `Colour.names` | 0.1.0 | Sorted, for shell completion |
| Colour as hex | `Colour#hex`, `Colour#to_s` | 0.1.0 | Lower case `#rrggbb` |
| Random colour |  | not yet | Any colour, or a vivid one |
| Inverse colours |  | not yet | Invert a colour or the whole frame. Not the firmware inverse mode |
| Reconnect after unplug |  | not yet | Automatic, repaints the last frame |

## Platforms

| Platform | Supported since |
|---|---|
| macOS | 0.1.0 |
| Linux | 0.1.0 |
| Windows | no |
