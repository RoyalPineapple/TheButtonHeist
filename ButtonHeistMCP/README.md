# ButtonHeist MCP Server

The buyer interface. This is the piece that lets an agent talk to ButtonHeist like it was born there.

## Build

```bash
cd ButtonHeistMCP
swift build -c release
# Binary at .build/release/buttonheist-mcp
```

## Tool Surface

ButtonHeistMCP currently exposes 16 tools backed by `TheFence`:

- `get_interface`
- `activate`
- `type_text`
- `swipe`
- `get_screen`
- `wait_for_idle`
- `start_recording`
- `stop_recording`
- `list_devices`
- `gesture`
- `accessibility_action`
- `scroll`
- `scroll_to_visible`
- `scroll_to_edge`
- `run_batch`
- `get_session_state`

`gesture` and `accessibility_action` are grouped tools - a couple of aliases for the crew members who do the rougher work:

- `gesture.type` maps to canonical Fence commands such as `one_finger_tap`, `long_press`, `pinch`, `rotate`, `draw_path`, and `draw_bezier`
- `accessibility_action.type` maps to `increment`, `decrement`, `perform_custom_action`, `edit_action`, and `dismiss_keyboard`

All other tools map 1:1 to a Fence command name.

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
