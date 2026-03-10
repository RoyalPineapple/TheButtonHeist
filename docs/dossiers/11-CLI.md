# ButtonHeistCLI - The CLI

> **Module:** `ButtonHeistCLI/Sources/`
> **Platform:** macOS 14.0+
> **Role:** User-facing command-line interface for interactive and batch operations

## Responsibilities

The CLI provides the canonical test client interface:

1. **Subcommand routing** via swift-argument-parser
2. **Three connection patterns**: direct (single command via DeviceConnector), session (REPL via TheFence), and watch (read-only observer via WatchStream)
3. **Output format auto-detection**: human for TTY, JSON for piped
4. **Exit code contract** for scripting (0-4, 99)
5. **All TheFence commands** accessible via CLI flags

## Architecture Diagram

```mermaid
graph TD
    subgraph CLI["ButtonHeistCLI"]
        Main["main.swift - @main ButtonHeist: AsyncParsableCommand"]
        Format["OutputFormat - auto / human / json"]
        Options["ConnectionOptions - --device, --token, --quiet"]

        subgraph Commands["Subcommands"]
            List["list"]
            Activate["activate"]
            Action["action (activate/increment/decrement/custom)"]
            Scroll["scroll / scroll_to_visible / scroll_to_edge"]
            Touch["touch (one_finger_tap/long_press/swipe/drag/ - pinch/rotate/two_finger_tap/ - draw_path/draw_bezier)"]
            TypeCmd["type"]
            Screenshot["screenshot"]
            GetInterface["get_interface"]
            WaitForIdle["wait_for_idle"]
            Record["record"]
            StopRec["stop_recording"]
            TextEdit["copy/paste/cut/select/select_all"]
            Dismiss["dismiss_keyboard"]
            Session["session (ReplSession)"]
            Watch["watch (WatchStream)"]
        end

        subgraph Patterns["Connection Patterns"]
            Direct["DeviceConnector - Connect → Send → Wait → Disconnect"]
            REPL["ReplSession → TheFence - persistent connection - stdin commands → stdout responses"]
            WatchPattern["WatchStream → TheMastermind - read-only observer - streams JSON events to stdout"]
        end
    end

    List --> Direct
    Activate --> Direct
    Action --> Direct
    Scroll --> Direct
    Touch --> Direct
    TypeCmd --> Direct
    Screenshot --> Direct
    GetInterface --> Direct
    WaitForIdle --> Direct
    Record --> Direct
    StopRec --> Direct
    TextEdit --> Direct
    Dismiss --> Direct
    Session --> REPL
    Watch --> WatchPattern

    Direct --> TheMastermind["TheMastermind"]
    REPL --> TheFence["TheFence"]
    WatchPattern --> TheMastermind
```

## Three Connection Patterns

```mermaid
flowchart LR
    subgraph Pattern1["Pattern 1: Direct (Most Commands)"]
        D1["DeviceConnector"] --> D2["discover + connect"]
        D2 --> D3["send single message"]
        D3 --> D4["wait for response"]
        D4 --> D5["disconnect + exit"]
    end

    subgraph Pattern2["Pattern 2: Session (REPL)"]
        S1["ReplSession"] --> S2["TheFence"]
        S2 --> S3["persistent connection"]
        S3 --> S4["read command from stdin"]
        S4 --> S5["execute via TheFence"]
        S5 --> S6["write response to stdout"]
        S6 --> S4
    end

    subgraph Pattern3["Pattern 3: Watch (Observer)"]
        W1["WatchStream"] --> W2["TheMastermind"]
        W2 --> W3["watch mode connection"]
        W3 --> W4["receive broadcasts"]
        W4 --> W5["emit JSON to stdout"]
        W5 --> W4
    end
```

## Exit Code Contract

| Code | Constant | Meaning |
|------|----------|---------|
| 0 | `.success` | Operation completed successfully |
| 1 | `.connectionFailed` | TCP connection failed |
| 2 | `.noDeviceFound` | No device found via Bonjour |
| 3 | `.timeout` | Operation timed out |
| 4 | `.authFailed` | Authentication rejected |
| 99 | `.unknown` | Unexpected error |

## Output Format Detection

```mermaid
flowchart TD
    Auto["OutputFormat.auto"] --> TTY{"isatty(STDIN_FILENO)?"}
    TTY -->|yes| Human[".human - Formatted text to stdout"]
    TTY -->|no| JSON[".json - Compact JSON to stdout"]

    Human --> Stderr["Status messages → stderr"]
    JSON --> Stderr
```

## Items Flagged for Review

### MEDIUM PRIORITY

**Leading space in import** (`ButtonHeistCLI/Tests/ActionCommandTests.swift:3`)
```swift
 import ButtonHeist  // leading space
```
- Cosmetic issue, compiles fine

**`testAllActionMethods` missing 4 ActionMethod cases** (`ActionCommandTests.swift:488-512`)
- Tests `.activate`, `.increment`, `.decrement`, `.syntheticTap`, `.syntheticLongPress`, etc.
- Missing: `.typeText`, `.editAction`, `.resignFirstResponder`, `.waitForIdle`
- These action methods exist in `ServerMessages.swift:214-233` but aren't tested

### LOW PRIORITY

**No `--timeout` flag for individual commands**
- Direct commands use `DeviceConnector` with hardcoded timeouts
- Users cannot override timeout per-invocation
- Only session mode inherits TheFence's configurable timeout
