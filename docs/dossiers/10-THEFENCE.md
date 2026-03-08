# TheFence - The Boss

> **File:** `ButtonHeist/Sources/TheButtonHeist/TheFence.swift`
> **Platform:** macOS 14.0+
> **Role:** Centralized command dispatch for CLI and MCP - the single orchestration layer

## Responsibilities

TheFence is the brain of the outside operation:

1. **Command dispatch** - routes 29 commands via TheMastermind/TheWheelman
2. **Auto-discovery and connection** - finds and connects to devices automatically
3. **Auto-reconnect** - retries connection on disconnect via TheWheelman
4. **Argument parsing** - extracts typed args from JSON dictionaries
5. **Response formatting** - produces both human-readable and JSON responses (`FenceResponse`)
6. **Session management** - persistent connection for CLI session and MCP modes

## Architecture Diagram

```mermaid
graph TD
    subgraph TheFence["TheFence (@ButtonHeistActor)"]
        Config["Configuration - deviceFilter, connectionTimeout, - forceSession, token, autoReconnect"]
        Execute["execute(request:) - Main entry point"]
        Dispatch["dispatch(command:args:) - 29-command switch"]
        Reconnect["Auto-Reconnect - via TheWheelman.setupAutoReconnect"]

        subgraph Commands["Command Catalog (29)"]
            Conn["help, status, quit, exit, list_devices"]
            IF["get_interface, get_screen, wait_for_idle"]
            Access["activate, increment, decrement, - perform_custom_action"]
            Gesture["one_finger_tap, long_press, swipe, drag, - pinch, rotate, two_finger_tap, - draw_path, draw_bezier"]
            Scroll["scroll, scroll_to_visible, scroll_to_edge"]
            Text["type_text, edit_action, dismiss_keyboard"]
            Rec["start_recording, stop_recording"]
        end

        subgraph Response["FenceResponse"]
            Ok["ok(message)"]
            Err["error(String)"]
            Help["help([String])"]
            Status["status(connected, deviceName)"]
            DevList["devices([DiscoveredDevice])"]
            IFResp["interface(Interface)"]
            Action["action(result: ActionResult)"]
            Screenshot["screenshot(path) / screenshotData(png)"]
            Recording["recording(path) / recordingData(payload)"]
        end
    end

    CLI["ButtonHeistCLI - ReplSession"] --> Execute
    MCP["ButtonHeistMCP - handleToolCall"] --> Execute
    Execute --> Dispatch
    Dispatch --> Client["TheMastermind - send/wait"]
```

## Command Execution Flow

```mermaid
flowchart TD
    Request["execute(request: [String: Any])"]
    Request --> ExtractCmd["Extract 'command' key"]
    ExtractCmd --> MetaCmd{command type?}

    MetaCmd -->|help| ReturnHelp["Return help(commands)"]
    MetaCmd -->|quit/exit| ReturnOk["Return ok, set shouldExit"]
    MetaCmd -->|other| CheckConn{connected?}

    CheckConn -->|no| Start["start() → discover + connect"]
    CheckConn -->|yes| DispatchCmd

    Start --> DispatchCmd["dispatch(command, args)"]

    DispatchCmd --> Route{command name}

    Route -->|get_interface| ReqIF["requestInterface (10s timeout)"]
    Route -->|get_screen| ReqScreen["send .requestScreen, - waitForScreen (30s)"]
    Route -->|one_finger_tap/swipe/etc| SendAction["sendAction (15s timeout)"]
    Route -->|type_text| TypeText["send .typeText, - waitForActionResult (30s)"]
    Route -->|start_recording| StartRec["send .startRecording, - return ok"]
    Route -->|stop_recording| StopRec["send .stopRecording, - waitForRecording (30s)"]
    Route -->|list_devices| ListDev["scan 3s, return devices"]
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
- Large switch statement over 29 command strings
- Each case has its own argument extraction and TheMastermind interaction
- The largest single method in the codebase
- Consider: could the individual command handlers be extracted into separate methods?

### MEDIUM PRIORITY

**Interface request timeout differs from other operations** (`TheFence.swift`)
- 10 seconds hardcoded vs 15s for actions, 30s for screenshots/recordings

**No tests for TheFence**
- The primary integration point for CLI and MCP has zero unit tests
- Command dispatch, argument parsing, timeout behavior, and auto-reconnect are all untested

### LOW PRIORITY

**`FenceResponse` recording cases include interaction count**
- `humanFormatted()` appends "Interactions: N" line when `interactionLog` is non-nil
- `jsonDict()` includes `interactionCount` key (0 when nil)
- Well-tested: `SessionResponseTests` covers both human formatting and JSON serialization

**`supportedCommands` is a String array** (`TheFence+CommandCatalog.swift`)
- Commands are matched by string comparison in the dispatch switch
- A typo in the catalog wouldn't be caught at compile time
- No enum-based type safety for command names

**Screenshot file saving uses temp directory** (`TheFence.swift`)
- Screenshots and recordings are saved to `FileManager.default.temporaryDirectory`
- These files persist until the OS cleans them up
- No explicit cleanup mechanism
