# Troubleshooting

Common errors and how to recover from them during fuzzing.

## No devices found

`list_devices` returns empty or errors.

- The iOS app must be running with InsideMan embedded
- The simulator must be booted and the app must be in the foreground
- The MCP server discovers devices via Bonjour — give it 2-3 seconds after app launch
- Try calling `list_devices` again after a short wait

**If persistent**: Stop and tell the user to launch the app.

## get_interface returns empty elements

The response has `elements: []` and `tree: []`.

- The app may not have finished loading. Wait 2 seconds and call `get_interface` again.
- If you just navigated to a new screen, the accessibility tree may still be building. Retry once.
- If persistent after 3 retries: the accessibility tree may be broken. Try tapping the screen center to trigger a layout pass, then retry.
- As a last resort, navigate to a different screen and back, then retry.

**Record as**: ERROR if it never resolves on a screen that clearly has elements (verify via `get_screen`).

## get_interface times out

The tool call returns a timeout error (typically after 10 seconds).

- The app may be stuck processing a previous request.
- Try a simple action first (tap at screen center) to "wake" the app, then retry `get_interface`.
- If persistent after 3 retries: fall back to coordinate-based exploration using `get_screen` for visual observation and `tap(x, y)` for interaction.

**Record as**: ERROR with details about which screen and what preceded the timeout.

## elementNotFound

An action targeting an element by identifier or order fails because the element can't be found.

- The screen likely changed between your `get_interface` call and the action.
- Call `get_interface` again to get the current state.
- Find the element in the new interface (it may have a different order index).
- Retry the action with the updated reference.

**Record as**: ERROR only if the element was present in the interface and still can't be found after refresh.

## elementDeallocated

The element existed but its underlying object was freed.

- This happens when SwiftUI redraws the view between the interface read and the action.
- Call `get_interface` again — the element should reappear with a fresh reference.
- Retry the action.

**Record as**: ANOMALY if it happens repeatedly on the same element. This may indicate a SwiftUI lifecycle bug.

## MCP server won't start

The MCP server binary fails to launch.

- Verify the binary exists: the path in `.mcp.json` must point to a valid executable
- Rebuild if needed: `cd ButtonHeistMCP && swift build -c release`
- Check that no other MCP server instance is already running

**Action**: Stop and tell the user to rebuild the MCP server.

## App crashes (connection lost)

If any MCP tool call fails with a connection error after previously working:

1. **This is a CRASH** — the most valuable finding
2. Stop the fuzzing loop immediately
3. Record the exact action, screen state, and last 5-10 actions
4. Generate the report with what you have
5. Tell the user the app crashed and they need to relaunch it
6. The MCP server connection is dead — a new session is needed
