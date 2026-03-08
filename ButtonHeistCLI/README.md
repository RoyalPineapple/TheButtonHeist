# ButtonHeist CLI

Command-line tool for inspecting and interacting with iOS apps running TheInsideJob. List devices, inspect the UI hierarchy, tap buttons, swipe lists, type text, capture screenshots — all from the terminal.

## Building

```bash
cd ButtonHeistCLI
swift build -c release
# Binary at .build/release/buttonheist
```

Or via the Xcode workspace:

```bash
xcodebuild -workspace ButtonHeist.xcworkspace -scheme ButtonHeistCLI build
```

## Device Targeting

All subcommands accept `--device <filter>` to target a specific instance. The filter matches case-insensitively against:

- Device name (`"iPhone 15 Pro"`)
- App name (`"A11y SwiftUI"`)
- Short ID prefix (`a1b2`)
- Simulator UDID (`DEADBEEF-1234-5678-9ABC-DEF012345678`)
- Vendor identifier

```bash
buttonheist --device a1b2 activate --identifier myButton
buttonheist --device "iPhone 15 Pro" screenshot --output screen.png
```

Without `--device`, connects to the first discovered device.

## Commands

### list

Discover devices on the network.

```
buttonheist list [--timeout <seconds>] [--format human|json]
```

```bash
buttonheist list                  # Human-readable table
buttonheist list --format json    # JSON for scripting
```

### action

Perform accessibility actions on elements.

```
buttonheist action [--identifier <id>] [--index <n>] [--type activate|increment|decrement|tap|custom] [--custom-action <name>] [--x <x>] [--y <y>] [--timeout <seconds>] [--quiet] [--device <filter>]
```

```bash
buttonheist action --identifier loginButton                              # Activate (default)
buttonheist action --type tap --x 196.5 --y 659                         # Tap coordinates
buttonheist action --type increment --identifier volumeSlider            # Increment slider
buttonheist action --type custom --custom-action "Delete" --identifier myCell  # Custom action
```

### touch

Simulate touch gestures. Nine subcommands:

| Subcommand | Description |
|------------|-------------|
| `tap` | Tap at a point or element |
| `longpress` | Long press with configurable duration |
| `swipe` | Swipe by direction or between coordinates |
| `drag` | Drag between two points (slower, for sliders/reordering) |
| `pinch` | Pinch/zoom gesture |
| `rotate` | Two-finger rotation |
| `two-finger-tap` | Simultaneous two-finger tap |
| `draw-path` | Draw along a sequence of waypoints |
| `draw-bezier` | Draw along cubic bezier curves |

All accept `--identifier`, `--index`, or coordinate options, plus `--device`.

```bash
# Tap
buttonheist touch tap --identifier loginButton
buttonheist touch tap --x 100 --y 200

# Long press
buttonheist touch longpress --identifier myButton --duration 1.0

# Swipe
buttonheist touch swipe --identifier list --direction up
buttonheist touch swipe --from-x 200 --from-y 400 --to-x 200 --to-y 100

# Drag
buttonheist touch drag --from-x 100 --from-y 200 --to-x 300 --to-y 200

# Multi-touch
buttonheist touch pinch --identifier mapView --scale 2.0
buttonheist touch rotate --x 200 --y 300 --angle 1.57
buttonheist touch two-finger-tap --identifier zoomControl

# Drawing
buttonheist touch draw-path --points "100,400 200,300 300,400" --duration 1.0
buttonheist touch draw-bezier --bezier-file curve.json --velocity 300
```

### type

Type text into a focused field via keyboard injection.

```
buttonheist type [--text <text>] [--delete <n>] [--identifier <id>] [--index <n>] [--timeout <seconds>] [--quiet] [--device <filter>]
```

```bash
buttonheist type --text "Hello World" --identifier nameField
buttonheist type --delete 5 --identifier nameField                 # Delete 5 chars
buttonheist type --delete 4 --text "orld" --identifier nameField   # Correct a typo
```

Outputs the field's current value to stdout after the operation.

### screenshot

Capture a PNG screenshot.

```
buttonheist screenshot [--output <path>] [--timeout <seconds>] [--quiet] [--device <filter>]
```

```bash
buttonheist screenshot --output screen.png    # Save to file
buttonheist screenshot | imgcat               # Pipe to viewer
```

### session

Persistent interactive session — the backbone of the MCP server. Maintains a single TCP connection to the device and accepts commands on stdin. Interactive mode accepts plain-text commands; JSON input is always accepted.

```
buttonheist session [--format human|json] [--timeout <seconds>] [--device <filter>]
```

```bash
buttonheist session                    # Interactive (human-readable)
buttonheist session --format json      # JSON mode (used by MCP server)
echo 'tap myButton' | buttonheist session --format json
echo '{"command":"get_interface"}' | buttonheist session --format json
```

**Available session commands:**

| Command | Description |
|---------|-------------|
| `get_interface` | Read the UI element hierarchy |
| `get_screen` | Capture a PNG screenshot |
| `tap` | Tap an element or coordinate |
| `long_press` | Long press |
| `swipe` | Swipe gesture |
| `drag` | Drag gesture |
| `pinch` | Pinch/zoom |
| `rotate` | Rotation |
| `two_finger_tap` | Two-finger tap |
| `draw_path` | Draw along waypoints |
| `draw_bezier` | Draw along bezier curves |
| `activate` | Accessibility activate (VoiceOver double-tap) |
| `increment` / `decrement` | Adjust sliders, steppers, pickers |
| `perform_custom_action` | Invoke a named custom accessibility action |
| `type_text` | Type text / delete characters |
| `edit_action` | Copy, paste, cut, select, selectAll |
| `dismiss_keyboard` | Dismiss the software keyboard |
| `wait_for_idle` | Wait until animations settle |
| `list_devices` | List discovered devices |
| `status` | Connection status |
| `help` | List all commands |

The session auto-reconnects if the TCP connection drops (up to 60 attempts at 1-second intervals).

## See Also

- [MCP Server](../ButtonHeistMCP/) — AI agent integration (spawns `session` under the hood)
- [API Reference](../docs/API.md) — Complete API documentation
- [Project Overview](../README.md) — Architecture and quick start
