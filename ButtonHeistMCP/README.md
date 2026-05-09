# ButtonHeist MCP Server

The buyer interface. This is the piece that lets an agent talk to ButtonHeist like it was born there.

## Build

```bash
cd ButtonHeistMCP
swift build -c release
# Binary at .build/release/buttonheist-mcp
```

## Tool Surface

ButtonHeistMCP currently exposes 23 tools backed by `TheFence`:

- `get_interface`
- `activate` (accepts optional `action` for increment/decrement/custom actions)
- `type_text`
- `get_screen`
- `wait_for`
- `wait_for_change`
- `start_recording`
- `stop_recording`
- `list_devices`
- `gesture` (grouped: `swipe`, `one_finger_tap`, `drag`, `long_press`, `pinch`, `rotate`, `two_finger_tap`, `draw_path`, `draw_bezier`)
- `scroll` (grouped: `mode` selects `page`, `to_visible`, `search`, or `to_edge`)
- `edit_action` (grouped: `copy`, `paste`, `cut`, `select`, `selectAll`, `dismiss`)
- `set_pasteboard`
- `get_pasteboard`
- `run_batch`
- `get_session_state`
- `connect`
- `list_targets`
- `get_session_log`
- `archive_session`
- `start_heist`
- `stop_heist`
- `play_heist`

`gesture`, `scroll`, and `edit_action` are grouped tools — their typed selector parameter routes to a canonical Fence command. All other tools map 1:1 to a Fence command name.

## Runtime Behavior

- Uses `StdioTransport`, so MCP traffic is JSON-RPC over stdin/stdout
- Reuses a single `TheFence` instance and auto-reconnects when the next tool call arrives
- Resets an idle timeout after every tool call and disconnects when inactive
- Returns screenshots as MCP image content
- Replaces raw base64 video payloads with a summary so recordings do not overwhelm MCP context; pass `output` to `stop_recording` to take the actual tape with you

## Environment

- `BUTTONHEIST_DEVICE` selects a specific discovered device
- `BUTTONHEIST_TOKEN` provides the auth token for driver connections
- `BUTTONHEIST_DRIVER_ID` is forwarded through `TheFence` for session locking
- `BUTTONHEIST_SESSION_TIMEOUT` controls the idle disconnect timeout (default: 60 seconds)

## See Also

- [API Reference](../docs/API.md) for the full tool schemas
- [Project Overview](../README.md) for setup and architecture
- [CLI Reference](../ButtonHeistCLI/) for direct terminal usage
