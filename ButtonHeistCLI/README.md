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
buttonheist --device "BH Demo" screenshot --output screen.png
```

Without `--device`, direct commands expect exactly one reachable target. No guessing, no roulette.

## Top-Level Commands

| Command | Purpose |
|---------|---------|
| `list` | Discover reachable devices |
| `activate` | Primary element interaction command |
| `touch` | Low-level gesture escape hatch (9 subcommands) |
| `type` | Type text and/or delete characters via keyboard injection |
| `screenshot` | Capture a PNG screenshot |
| `get_interface` | Fetch the current accessibility hierarchy |
| `wait_for_idle` | Wait until UI animations settle |
| `session` | Start a persistent REPL / JSON session |
| `record` | Record MP4 video and save it locally |
| `stop_recording` | Stop an in-progress recording session |
| `scroll` | Scroll a view by one page |
| `scroll_to_visible` | Scroll until an element is visible |
| `scroll_to_edge` | Scroll to a scroll-view edge |
| `swipe` | Convenience alias for `touch swipe` |
| `action` | Accessibility actions: edit (copy/paste/cut/select/selectAll), increment, decrement, custom actions, dismiss keyboard |

### activate

Activate an element via accessibility or synthetic tap.

```bash
buttonheist activate --identifier loginButton
buttonheist activate --index 3
buttonheist activate --identifier loginButton --timeout 15
```

Flags: `--identifier <id>`, `--index <n>`, `-t/--timeout` (default 10s), `-f/--format`, `-q/--quiet`.

### action

Perform accessibility actions beyond activate.

```bash
buttonheist action --type increment --identifier volumeSlider
buttonheist action --type decrement --identifier volumeSlider
buttonheist action --type custom --custom-action "Delete" --identifier myCell
```

Flags: `--type` (activate/increment/decrement/custom, default "activate"), `--custom-action <name>`, `--identifier`, `--index`, `-t/--timeout` (default 10s).

### type

Type text into a focused field via keyboard injection.

```bash
buttonheist type --text "Hello World" --identifier nameField
buttonheist type --delete 5 --identifier nameField
buttonheist type --delete 4 --text "orld" --identifier nameField   # Correct a typo
```

Flags: `--text <text>`, `--delete <n>`, `--identifier`, `--index`, `-t/--timeout` (default 30s). Outputs the action result to stdout (includes the field's current value when available).

### screenshot

Capture a PNG screenshot.

```bash
buttonheist screenshot --output screen.png
buttonheist screenshot | imgcat
```

Flags: `-o/--output <path>` (default: raw PNG to stdout), `--timeout` (default 10s).

### record

Record the screen as H.264/MP4.

```bash
buttonheist record --output demo.mp4
buttonheist record --output demo.mp4 --fps 15 --scale 0.5 --action-log demo-actions.json
```

Flags: `-o/--output` (default "recording.mp4"), `--fps` (default 8), `--scale`, `--inactivity-timeout` (default 5s), `--max-duration` (default 60s), `--action-log <path>`.

### list

Discover devices on the network.

```bash
buttonheist list                  # Human-readable table
buttonheist list --format json    # JSON for scripting
```

Flags: `-t/--timeout` (default 3s), `-f/--format` (auto/human/json).

### get_interface

Fetch the current accessibility hierarchy.

```bash
buttonheist get_interface
buttonheist get_interface --format json
```

Flags: `-f/--format`, `-t/--timeout` (default 10s).

### scroll / scroll_to_visible / scroll_to_edge

```bash
buttonheist scroll --direction up --identifier scrollView
buttonheist scroll_to_visible --identifier submitButton
buttonheist scroll_to_edge --edge bottom --identifier scrollView
```

`scroll` flags: `--direction` (required: up/down/left/right/next/previous), `--identifier`, `--index`.
`scroll_to_edge` flags: `--edge` (required: top/bottom/left/right), `--identifier`, `--index`.
`scroll_to_visible` flags: `--identifier`, `--index`.

## Touch Subcommands

`buttonheist touch` is the low-level gesture toolkit. Nine subcommands for coordinate-precise touch injection when `activate` isn't enough:

| Subcommand | Key Flags | Description |
|------------|-----------|-------------|
| `one_finger_tap` | `--identifier`, `--x/--y` | Tap at a point or element |
| `long_press` | `--identifier`, `--x/--y`, `--duration` (default 0.5) | Long press with configurable hold |
| `swipe` | `--identifier`, `--direction`, `--from-x/y`, `--to-x/y`, `--distance`, `--duration` | Swipe by direction or between coordinates |
| `drag` | `--from-x/y`, `--to-x/y` (required), `--duration` | Drag between two points (slower, for sliders/reordering) |
| `pinch` | `--identifier`, `--x/--y`, `--scale` (required), `--spread`, `--duration` | Pinch/zoom gesture |
| `rotate` | `--identifier`, `--x/--y`, `--angle` (required, radians), `--radius`, `--duration` | Two-finger rotation |
| `two_finger_tap` | `--identifier`, `--x/--y`, `--spread` | Simultaneous two-finger tap |
| `draw_path` | `--points "x1,y1 x2,y2"` or `--path-file`, `--duration`, `--velocity` | Draw along a sequence of waypoints |
| `draw_bezier` | `--bezier-file` (required), `--samples`, `--duration`, `--velocity` | Draw along cubic bezier curves |

All touch subcommands also accept `--identifier`, `--index`, `--timeout` (default 10s, 30s for draw commands), `--format`, and `--device`.

```bash
buttonheist touch one_finger_tap --identifier loginButton
buttonheist touch one_finger_tap --x 100 --y 200
buttonheist touch long_press --identifier myButton --duration 1.0
buttonheist touch swipe --identifier list --direction up
buttonheist touch swipe --from-x 200 --from-y 400 --to-x 200 --to-y 100
buttonheist touch drag --from-x 100 --from-y 200 --to-x 300 --to-y 200
buttonheist touch pinch --identifier mapView --scale 2.0
buttonheist touch rotate --x 200 --y 300 --angle 1.57
buttonheist touch two_finger_tap --identifier zoomControl
buttonheist touch draw_path --points "100,400 200,300 300,400" --duration 1.0
buttonheist touch draw_bezier --bezier-file curve.json --velocity 300
```

## Session Mode

`buttonheist session` keeps a single connection open and accepts either:

- human-friendly commands such as `tap loginButton`, `ui`, `idle`, and `status`
- JSON requests with canonical Fence command names

```bash
buttonheist session
buttonheist session --format json
echo '{"command":"get_interface"}' | buttonheist session --format json
echo '{"command":"get_session_state"}' | buttonheist session --format json
echo '{"command":"run_batch","steps":[{"command":"get_interface"},{"command":"wait_for_idle","timeout":2}]}' | buttonheist session --format json
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
- `wait_for_idle`
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
buttonheist list
buttonheist activate --identifier loginButton
buttonheist action --type increment --identifier volumeSlider
buttonheist type --text "user@example.com" --identifier emailField
buttonheist get_interface --format json
buttonheist screenshot --output screen.png
buttonheist record --output demo.mp4 --action-log demo-actions.json
buttonheist scroll_to_visible --identifier submitButton
```

## See Also

- [MCP Server](../ButtonHeistMCP/) — AI agent integration (spawns `session` under the hood)
- [API Reference](../docs/API.md) — Complete API documentation
- [Project Overview](../README.md) — Architecture and quick start
