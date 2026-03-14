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
buttonheist --device "AccessibilityTestApp" screenshot --output screen.png
```

Without `--device`, direct commands expect exactly one reachable target. No guessing, no roulette.

## Top-Level Commands

| Command | Purpose |
|---------|---------|
| `list` | Discover reachable devices |
| `activate` | Primary element interaction command |
| `action` | Increment, decrement, or invoke custom accessibility actions |
| `touch` | Low-level gesture escape hatch |
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
| `copy`, `paste`, `cut`, `select`, `select_all` | Text edit actions via the responder chain |
| `dismiss_keyboard` | Resign first responder |

## Touch Subcommands

`buttonheist touch` is the lockpick set. It exposes these exact subcommands:

- `one_finger_tap`
- `long_press`
- `swipe`
- `drag`
- `pinch`
- `rotate`
- `two_finger_tap`
- `draw_path`
- `draw_bezier`

Examples:

```bash
buttonheist touch one_finger_tap --identifier loginButton
buttonheist touch one_finger_tap --x 100 --y 200
buttonheist touch long_press --identifier myButton --duration 1.0
buttonheist touch swipe --identifier list --direction up
buttonheist touch drag --from-x 100 --from-y 200 --to-x 300 --to-y 200
buttonheist touch pinch --identifier mapView --scale 2.0
buttonheist touch rotate --x 200 --y 300 --angle 1.57
buttonheist touch two_finger_tap --identifier zoomControl
buttonheist touch draw_path --points "100,400 200,300 300,400"
buttonheist touch draw_bezier --bezier-file curve.json
```

For ordinary controls, prefer `activate`. Reach for `touch` when you need the crowbar instead of the key.

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

- [MCP Server](../ButtonHeistMCP/) for agent-facing MCP usage
- [API Reference](../docs/API.md) for wire and command details
- [Project Overview](../README.md) for full setup
