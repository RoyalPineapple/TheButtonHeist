# Troubleshooting

Common errors and how to recover from them during fuzzing.

## Connection failed (direct connect)

A command with `--host`/`--port` (or `BUTTONHEIST_HOST`/`BUTTONHEIST_PORT` env vars) fails with "Connection timed out" or "Connection failed".

**Causes & fixes:**
- **App not running**: The app must be launched and InsideMan must be active. Verify with `buttonheist list` (which uses Bonjour, not direct connect).
- **Wrong host/port**: For simulators, the address is always `127.0.0.1:1455`. For physical devices, use the host/port shown by `buttonheist list --format json`.
- **Only one of host/port set**: Both `BUTTONHEIST_HOST` and `BUTTONHEIST_PORT` must be set together. If only one is set, the CLI silently falls back to Bonjour discovery.
- **Port changed after app relaunch**: The port is fixed at `1455` for simulators, but physical devices may get a different port after relaunch. Re-run `buttonheist list --format json` to get the current address.
- **Token mismatch**: If the app requires authentication, set `BUTTONHEIST_TOKEN` or pass the correct token.

**Recovery**: Unset the env vars (`unset BUTTONHEIST_HOST BUTTONHEIST_PORT`) to fall back to Bonjour discovery and confirm the app is reachable, then re-set them with the correct values.

## No devices found

`buttonheist list` returns empty or errors.

- The iOS app must be running with InsideMan embedded
- The simulator must be booted and the app must be in the foreground
- The CLI discovers devices via Bonjour — give it 2-3 seconds after app launch
- Try running `buttonheist list` again after a short wait

**If persistent**: Stop and tell the user to launch the app.

## buttonheist watch --once returns empty elements

The response has `elements: []` and `tree: []`.

- The app may not have finished loading. Wait 2 seconds and run `buttonheist watch --once` again.
- If you just navigated to a new screen, the accessibility tree may still be building. Retry once.
- If persistent after 3 retries: the accessibility tree may be broken. Try tapping the screen center to trigger a layout pass, then retry.
- As a last resort, navigate to a different screen and back, then retry.

**Record as**: ERROR if it never resolves on a screen that clearly has elements (verify via `buttonheist screenshot`).

## buttonheist watch --once times out

The command returns a timeout error (typically after 10 seconds).

- The app may be stuck processing a previous request.
- Try a simple action first (tap at screen center) to "wake" the app, then retry `buttonheist watch --once`.
- If persistent after 3 retries: fall back to coordinate-based exploration using `buttonheist screenshot` for visual observation and `buttonheist touch tap --x X --y Y` for interaction.

**Record as**: ERROR with details about which screen and what preceded the timeout.

## elementNotFound

An action targeting an element by identifier or order fails because the element can't be found.

- The screen likely changed between your `buttonheist watch --once` call and the action.
- Run `buttonheist watch --once` again to get the current state.
- Find the element in the new interface (it may have a different order index).
- Retry the action with the updated reference.

**Record as**: ERROR only if the element was present in the interface and still can't be found after refresh.

## elementDeallocated

The element existed but its underlying object was freed.

- This happens when SwiftUI redraws the view between the interface read and the action.
- Run `buttonheist watch --once` again — the element should reappear with a fresh reference.
- Retry the action.

**Record as**: ANOMALY if it happens repeatedly on the same element. This may indicate a SwiftUI lifecycle bug.

## CLI not found

The `buttonheist` command fails with "command not found".

- Build the CLI and add to PATH from the repo root:
  ```bash
  cd ButtonHeistCLI && swift build -c release && cd ..
  export PATH="$PWD/ButtonHeistCLI/.build/release:$PATH"
  ```
- This uses a repo-relative path so it works in any workspace.

**Action**: Run the commands above and retry. If the build fails, stop and tell the user.

## App crashes (connection lost)

If any CLI command fails with a connection error after previously working:

1. **This is a CRASH** — the most valuable finding
2. Stop the fuzzing loop immediately
3. Record the exact action, screen state, and last 5-10 actions
4. Generate the report with what you have
5. Tell the user the app crashed and they need to relaunch it
6. The app connection is dead — the app needs to be relaunched

## Connection lost mid-session (not a crash)

If a command fails with a connection error but the app didn't crash (e.g., network interruption, simulator reset):

- Try the command again — the CLI creates a fresh connection each time
- If using direct connect, verify the app is still listening: `buttonheist list --format json`
- If the simulator was reset or the app was relaunched, the port stays the same (`1455`) but the app needs a moment to start the server — wait 2-3 seconds
- If on a physical device, the port may have changed — re-run `buttonheist list --format json` and update `BUTTONHEIST_PORT`

**Record as**: Only record as CRASH if the connection was working, you performed an action, and the connection died immediately after. Transient connection issues are not findings.
