# TheFence - The Boss

> **File:** `ButtonHeist/Sources/TheButtonHeist/TheFence.swift`
> **Platform:** macOS 14.0+
> **Role:** Centralized command dispatch for CLI and MCP - the single orchestration layer

## Responsibilities

TheFence is the brain of the outside operation:

1. **Command dispatch** - routes 35 commands via TheHandoff
2. **Auto-discovery and connection** - finds and connects to devices automatically
3. **Auto-reconnect** - retries connection on disconnect via TheHandoff
4. **Request-response correlation** - tracks pending requests via requestId-keyed continuation dictionaries, matches responses to waiting async callers
5. **Async wait methods** - `waitForActionResult`, `waitForInterface`, `waitForScreen`, `waitForRecording` with timeout handling
6. **Argument parsing** - extracts typed args from JSON dictionaries
7. **Response formatting** - produces both human-readable and JSON responses (`FenceResponse`)
8. **Session management** - persistent connection for CLI session and MCP modes
9. **Output path validation** - rejects `..` path components in `get_screen` and `stop_recording` output paths to prevent path traversal; resolves paths via `URL.standardized` before writing
10. **Outcome signals** - parses `expect` field from requests, checks `ActionExpectation` against `ActionResult` after each action, reports what happened in responses and batch summaries
11. **Batch early stop** - with `stop_on_error` (default), halts the batch at the first mismet expectation so `failedIndex` points at the action that broke, not a downstream symptom

## Architecture Diagram

```mermaid
graph TD
    subgraph TheFence["TheFence (@ButtonHeistActor)"]
        Config["Configuration - deviceFilter, connectionTimeout, - token, autoReconnect"]
        Execute["execute(request:) - Main entry point"]
        Dispatch["dispatch(command:args:) - 35-command switch"]
        Reconnect["Auto-Reconnect - via TheHandoff.setupAutoReconnect"]

        subgraph Commands["Command Catalog (35)"]
            Conn["help, status, quit, exit, list_devices"]
            IF["get_interface, get_screen, wait_for_idle"]
            Access["activate (with optional action param), - increment, decrement, - perform_custom_action"]
            Gesture["one_finger_tap, long_press, swipe, drag, - pinch, rotate, two_finger_tap, - draw_path, draw_bezier"]
            Scroll["scroll, scroll_to_visible, scroll_to_edge"]
            Text["type_text, edit_action, dismiss_keyboard"]
            Pasteboard["set_pasteboard, get_pasteboard"]
            Rec["start_recording, stop_recording"]
            Batch["run_batch, get_session_state"]
            Target["connect, list_targets"]
        end

        subgraph Response["FenceResponse"]
            Ok["ok(message)"]
            Err["error(String)"]
            Help["help([String])"]
            Status["status(connected, deviceName)"]
            DevList["devices([DiscoveredDevice])"]
            IFResp["interface(Interface)"]
            Action["action(result: ActionResult, expectation: ExpectationResult?)"]
            Screenshot["screenshot(path) / screenshotData(png)"]
            Recording["recording(path) / recordingData(payload)"]
            Targets["targets([String: TargetConfig], defaultTarget)"]
        end
    end

    CLI["ButtonHeistCLI - ReplSession"] --> Execute
    MCP["ButtonHeistMCP - handleToolCall"] --> Execute
    Execute --> Dispatch
    Dispatch --> Client["TheHandoff - send/receive"]
```

## Command Execution Flow

```mermaid
flowchart TD
    Request["execute(request: [String: Any])"]
    Request --> ExtractCmd["Extract 'command' key"]
    ExtractCmd --> MetaCmd{command type?}

    MetaCmd -->|help| ReturnHelp["Return help(commands)"]
    MetaCmd -->|quit/exit| ReturnOk["Return ok, set shouldExit"]
    MetaCmd -->|connect/list_targets| TargetCmd["Target commands - bypass auto-start"]
    MetaCmd -->|other| CheckConn{connected?}

    CheckConn -->|no| Start["start() → discover + connect"]
    CheckConn -->|yes| DispatchCmd

    Start --> DispatchCmd["dispatch(command, args)"]

    DispatchCmd --> Response["FenceResponse"]
    Response --> HasExpect{has expect field?}
    HasExpect -->|yes| Validate["check expectation\nagainst ActionResult"]
    HasExpect -->|no| Return["return response"]
    Validate --> Return

    DispatchCmd --> Route{command name}

    Route -->|get_interface| ReqIF["requestInterface (10s timeout)"]
    Route -->|get_screen| ReqScreen["send .requestScreen, - waitForScreen (30s)"]
    Route -->|one_finger_tap/swipe/etc| SendAction["sendAction (15s timeout)"]
    Route -->|type_text| TypeText["send .typeText, - waitForActionResult (30s)"]
    Route -->|start_recording| StartRec["send .startRecording, - return ok"]
    Route -->|stop_recording| StopRec["send .stopRecording, - waitForRecording (30s)"]
    Route -->|list_devices| ListDev["scan 3s, return devices"]
    Route -->|connect| Connect["stop + reconnect to target"]
    Route -->|list_targets| ListTargets["return config file targets"]
    Route -->|status| ReturnStatus["return connection status"]
```

## Auto-Reconnect Mechanism

```mermaid
stateDiagram-v2
    [*] --> Connected: initial connection

    Connected --> Disconnected: connection lost
    Disconnected --> Attempting: auto-reconnect enabled

    state Attempting {
        [*] --> WaitDevice: poll discoveredDevices
        WaitDevice --> TryConnect: device found
        TryConnect --> WaitResult: client.connect()
        WaitResult --> WaitDevice: connect failed (10s timeout)
        WaitResult --> [*]: connected!
        WaitDevice --> WaitDevice: sleep 1s, retry
    }

    Attempting --> Failed: 60 attempts exhausted
    Attempting --> Connected: reconnected

    Note left of Attempting: 60 attempts x 1s = 60s max
```

## Timeout Matrix

| Operation | Timeout | Source |
|-----------|---------|--------|
| Connection (discovery) | configurable (default 30s) | `TheFence.Configuration.connectionTimeout` |
| Action result (general) | 15s | `TheFence.Timeouts.actionSeconds` |
| Action result (type_text) | 30s | `TheFence.Timeouts.longActionSeconds` |
| Screenshot | 30s | `TheFence.Timeouts.longActionSeconds` |
| Recording | 30s | `TheFence.handleStopRecording` |
| Interface request | 10s | `TheFence.handleGetInterface` |

## Items Flagged for Review

### HIGH PRIORITY

**`dispatch` method cyclomatic complexity** (`TheFence.swift:497`)
- Large switch statement over 35 command strings
- Each case has its own argument extraction and TheHandoff interaction
- The largest single method in the codebase
- Consider: could the individual command handlers be extracted into separate methods?

### MEDIUM PRIORITY

**Interface request timeout differs from other operations** (`TheFence.swift`)
- 10 seconds hardcoded vs 15s for actions, 30s for screenshots/recordings

**TheFence test coverage is improving but incomplete**
- `TheFenceTests` covers command enum exhaustiveness (case count guard + wire-format verification for all 35 commands) and `FenceResponse` formatting
- `TheFenceHandlerTests` covers command routing (`testAllCatalogCommandsAreRouted`) and handler-level argument validation
- Timeout behavior and auto-reconnect logic remain untested

### LOW PRIORITY

**`FenceResponse` recording cases include interaction count**
- `humanFormatted()` appends "Interactions: N" line when `interactionLog` is non-nil
- `jsonDict()` includes `interactionCount` key (0 when nil)
- Well-tested: `FenceResponseTests` covers both human formatting and JSON serialization

**`supportedCommands` derived from `Command` enum** (`TheFence+CommandCatalog.swift`)
- `TheFence.Command` is a `String`-backed `CaseIterable` enum with 35 cases
- Commands are matched by enum case in the dispatch switch (compile-time exhaustiveness)
- `supportedCommands` is `Command.allCases.map(\.rawValue)` — no hand-maintained list

**Screenshot file saving uses temp directory** (`TheFence.swift`)
- Screenshots and recordings are saved to `FileManager.default.temporaryDirectory`
- These files persist until the OS cleans them up
- No explicit cleanup mechanism
