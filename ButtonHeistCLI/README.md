# ButtonHeist CLI

The front counter. When you want to run the job by hand, this is how you talk to the crew.

## Build

```bash
cd ButtonHeistCLI
swift build -c release
# Binary at .build/release/buttonheist
```

## Device Targeting

All commands accept `--device <filter>`. The filter matches case-insensitively against discovered metadata such as:

- service name
- app name
- device name
- short ID prefix
- installation ID prefix
- instance ID prefix
- simulator UDID prefix

```bash
buttonheist --device a1b2 activate --identifier loginButton
buttonheist --device "BH Demo" get_screen --output screen.png
```

Without `--device`, direct commands expect exactly one reachable target. No guessing, no roulette.

## Top-Level Commands

| Command | Purpose |
|---------|---------|
| `list_devices` | Discover reachable devices |
| `connect` | Establish a configured session and print session state |
| `session` | Start a persistent REPL / JSON session |
| `activate` | Primary element interaction command |
| `rotor` | Move through a VoiceOver rotor |
| `type_text` | Type non-empty text via keyboard injection |
| `get_screen` | Capture a PNG screenshot |
| `get_interface` | Fetch the current app accessibility state |
| `wait_for_change` | Wait for the UI hierarchy to change |
| `wait_for` | Wait for an element to appear or disappear |
| `start_recording` | Start MP4 screen recording |
| `stop_recording` | Stop an in-progress recording session |
| `scroll` | Scroll a view by one page |
| `scroll_to_visible` | Scroll until an element is visible |
| `element_search` | Search scrollable containers for an unseen element |
| `scroll_to_edge` | Scroll to a scroll-view edge |
| `one_finger_tap` | Low-level tap gesture |
| `long_press` | Low-level long-press gesture |
| `swipe` | Low-level swipe gesture |
| `drag` | Low-level drag gesture |
| `pinch` | Low-level pinch/zoom gesture |
| `rotate` | Low-level rotate gesture |
| `two_finger_tap` | Low-level two-finger tap gesture |
| `draw_path` | Draw a touch path through waypoints |
| `draw_bezier` | Draw a touch path along cubic Bezier segments |
| `edit_action` | Responder-chain edit actions: copy, paste, cut, select, selectAll, delete |
| `dismiss_keyboard` | Resign first responder and dismiss the keyboard |
| `set_pasteboard` | Write text to the general pasteboard |
| `get_pasteboard` | Read text from the general pasteboard |
| `run_batch` | Execute multiple commands in one request |
| `get_session_state` | Inspect client connection/session state |
| `list_targets` | List named targets from Button Heist config |
| `get_session_log` | Return the current session manifest |
| `archive_session` | Close and archive the current session directory |
| `start_heist` | Start recording a replayable `.heist` script |
| `stop_heist` | Stop and save a `.heist` script |
| `play_heist` | Play back a `.heist` script |

### activate

Activate an element via accessibility or synthetic tap.

```bash
buttonheist activate --identifier loginButton
buttonheist activate --index 3
buttonheist activate --identifier loginButton --timeout 15
```

Flags: `--identifier <id>`, `--index <n>`, `-t/--timeout` (default 10s), `-f/--format`, `-q/--quiet`.

Named accessibility actions are routed through `activate --action`.

### type_text

Type non-empty text into a focused field via keyboard injection.

```bash
buttonheist type_text "Hello World" --identifier nameField
```

Flags: positional text, `--identifier`, `--index`, `-t/--timeout` (default 30s). Outputs the action result to stdout (includes the field's current value when available). Use `edit_action delete`, `cut`, or `selectAll` for destructive text edits.

### get_screen

Capture a PNG screenshot.

```bash
buttonheist get_screen --output screen.png
buttonheist get_screen | imgcat
```

Flags: `-o/--output <path>` (default: raw PNG to stdout).

### start_recording

Record the screen as H.264/MP4.

```bash
buttonheist start_recording
buttonheist start_recording --output demo.mp4 --fps 15 --scale 0.5 --action-log demo-actions.json
```

Flags: `-o/--output` (default "recording.mp4"), `--fps` (default 8), `--scale`, `--inactivity-timeout` (optional early-stop; omitted follows `--max-duration`), `--max-duration` (default 60s), `--action-log <path>`.

### list_devices

Discover devices on the network.

```bash
buttonheist list_devices                  # Human-readable table
buttonheist list_devices --format json    # JSON for scripting
```

Flags: `-t/--timeout` (default 3s), `-f/--format` (auto/human/json).

### get_interface

Fetch the current app accessibility state.

```bash
buttonheist get_interface
buttonheist get_interface --format json
buttonheist get_interface --scope visible
```

Flags: `--scope visible` for a diagnostic on-screen parse, `-f/--format`, `-t/--timeout` (default 10s).

### scroll / scroll_to_visible / scroll_to_edge

```bash
buttonheist scroll --direction up --identifier scrollView
buttonheist scroll_to_visible --identifier submitButton
buttonheist scroll_to_edge --edge bottom --identifier scrollView
```

`scroll` flags: `--direction` (required: up/down/left/right/next/previous), `--identifier`, `--index`.
`scroll_to_edge` flags: `--edge` (required: top/bottom/left/right), `--identifier`, `--index`.
`scroll_to_visible` flags: `--identifier`, `--index`.

## Gesture Commands

Low-level gestures are top-level commands for coordinate-precise touch injection when `activate` isn't enough:

| Command | Key Flags | Description |
|---------|-----------|-------------|
| `one_finger_tap` | `--identifier`, `--x/--y` | Tap at a point or element |
| `long_press` | `--identifier`, `--x/--y`, `--duration` (default 0.5) | Long press with configurable hold |
| `swipe` | `--identifier`, `--direction`, `--from-x/y`, `--to-x/y`, `--distance`, `--duration` | Swipe by direction or between coordinates |
| `drag` | `--from-x/y`, `--to-x/y` (required), `--duration` | Drag between two points (slower, for sliders/reordering) |
| `pinch` | `--identifier`, `--x/--y`, `--scale` (required), `--spread`, `--duration` | Pinch/zoom gesture |
| `rotate` | `--identifier`, `--x/--y`, `--angle` (required, radians), `--radius`, `--duration` | Two-finger rotation |
| `two_finger_tap` | `--identifier`, `--x/--y`, `--spread` | Simultaneous two-finger tap |
| `draw_path` | `--points "x1,y1 x2,y2"` or `--path-file`, `--duration`, `--velocity` | Draw along a sequence of waypoints |
| `draw_bezier` | `--bezier-file` (required), `--samples`, `--duration`, `--velocity` | Draw along cubic bezier curves |

All gesture commands also accept `--identifier`, `--index`, `--timeout` (default 10s, 30s for draw commands), `--format`, and `--device`.

```bash
buttonheist one_finger_tap --identifier loginButton
buttonheist one_finger_tap --x 100 --y 200
buttonheist long_press --identifier myButton --duration 1.0
buttonheist swipe --identifier list --direction up
buttonheist swipe --from-x 200 --from-y 400 --to-x 200 --to-y 100
buttonheist drag --from-x 100 --from-y 200 --to-x 300 --to-y 200
buttonheist pinch --identifier mapView --scale 2.0
buttonheist rotate --x 200 --y 300 --angle 1.57
buttonheist two_finger_tap --identifier zoomControl
buttonheist draw_path --points "100,400 200,300 300,400" --duration 1.0
buttonheist draw_bezier --bezier-file curve.json --velocity 300
```

## Session Mode

`buttonheist session` keeps a single connection open and accepts either:

- human-friendly commands such as `tap loginButton`, `ui`, `idle`, and `status`
- JSON requests with TheFence command names

```bash
buttonheist session
buttonheist session --format json
echo '{"command":"get_interface"}' | buttonheist session --format json
echo '{"command":"get_session_state"}' | buttonheist session --format json
echo '{"command":"run_batch","steps":[{"command":"get_interface"},{"command":"wait_for_change","timeout":2}]}' | buttonheist session --format json
```

Flags: `--device`, `--token`, `-t/--timeout` (default 30s), `-f/--format`, `--session-timeout` (default 60s).

The session auto-reconnects if the connection drops (up to 60 attempts at 1-second intervals).

Common JSON session commands:

- `get_interface`
- `get_screen`
- `activate`
- `one_finger_tap`
- `long_press`
- `swipe`
- `drag`
- `pinch`
- `rotate`
- `two_finger_tap`
- `draw_path`
- `draw_bezier`
- `increment`
- `decrement`
- `perform_custom_action`
- `type_text`
- `edit_action`
- `dismiss_keyboard`
- `wait_for_change`
- `wait_for`
- `list_devices`
- `run_batch`
- `get_session_state`

## Output Format

Output format is auto-detected when not specified:

- **TTY** (interactive terminal) → human-readable formatted text
- **Piped** (stdin is not a terminal) → compact JSON

Override with `-f/--format human` or `-f/--format json`. Status messages always go to stderr.

## Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Success |
| 1 | Connection failed |
| 2 | No device found |
| 3 | Timeout |
| 4 | Authentication failed |
| 99 | Unexpected error |

## Examples

```bash
buttonheist list_devices
buttonheist activate --identifier loginButton
buttonheist activate --action increment --identifier volumeSlider
buttonheist type_text "user@example.com" --identifier emailField
buttonheist get_interface --format json
buttonheist get_screen --output screen.png
buttonheist start_recording --output demo.mp4 --action-log demo-actions.json
buttonheist scroll_to_visible --identifier submitButton
```

## See Also

- [MCP Server](../ButtonHeistMCP/) — AI agent integration (spawns `session` under the hood)
- [API Reference](../docs/API.md) — Complete API documentation
- [Project Overview](../README.md) — Architecture and quick start
