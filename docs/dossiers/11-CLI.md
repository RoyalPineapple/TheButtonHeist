# ButtonHeistCLI - The CLI

> **Module:** `ButtonHeistCLI/Sources/`
> **Platform:** macOS 14.0+
> **Role:** User-facing command-line interface for interactive and batch operations

## Responsibilities

The CLI provides the canonical test client interface:

1. **Subcommand routing** via swift-argument-parser
2. **Three connection patterns**: direct (single command), watch (streaming), session (REPL)
3. **Output format auto-detection**: human for TTY, JSON for piped
4. **Exit code contract** for scripting (0-4, 99)
5. **All TheMastermind commands** accessible via CLI flags

## Architecture Diagram

```mermaid
graph TD
    subgraph CLI["ButtonHeistCLI"]
        Main["main.swift - @main ButtonHeist: AsyncParsableCommand"]
        Format["OutputFormat - auto / human / json"]
        Options["ConnectionOptions - --device, --token, --quiet, --force"]

        subgraph Commands["Subcommands"]
            List["list"]
            Watch["watch (CLIRunner)"]
            Action["action (activate/increment/decrement)"]
            Touch["touch (tap/longpress/swipe/drag/ - pinch/rotate/two-finger-tap/ - draw-path/draw-bezier)"]
            TypeCmd["type"]
            Screenshot["screenshot"]
            Record["record"]
            StopRec["stop-recording"]
            TextEdit["copy/paste/cut/select/select-all"]
            Dismiss["dismiss-keyboard"]
            Session["session (SessionRunner)"]
        end

        subgraph Patterns["Connection Patterns"]
            Direct["DeviceConnector - Connect → Send → Wait → Disconnect"]
            Stream["CLIRunner - Connect → Stream updates → Ctrl-C"]
            REPL["SessionRunner - TheMastermind persistent connection - stdin JSON → stdout JSON"]
        end
    end

    List --> Direct
    Action --> Direct
    Touch --> Direct
    TypeCmd --> Direct
    Screenshot --> Direct
    Record --> Direct
    StopRec --> Direct
    TextEdit --> Direct
    Dismiss --> Direct
    Watch --> Stream
    Session --> REPL

    Direct --> TheClient["TheClient"]
    Stream --> TheClient
    REPL --> TheMastermind["TheMastermind"]
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

    subgraph Pattern2["Pattern 2: Watch (Streaming)"]
        W1["CLIRunner"] --> W2["discover + connect"]
        W2 --> W3["auto-subscribe"]
        W3 --> W4["stream interface updates"]
        W4 --> W5["Ctrl-C or 'q' to exit"]
    end

    subgraph Pattern3["Pattern 3: Session (REPL)"]
        S1["SessionRunner"] --> S2["TheMastermind"]
        S2 --> S3["persistent connection"]
        S3 --> S4["read JSON from stdin"]
        S4 --> S5["execute via TheMastermind"]
        S5 --> S6["write JSON to stdout"]
        S6 --> S4
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

**Duplicate error type: `CLIError`** (`DeviceConnector.swift:102-150`)
- `CLIError` duplicates most of `MastermindError` with nearly identical descriptions
- The CLI has two connection code paths:
  - Direct commands use `DeviceConnector` → `CLIError`
  - Session mode uses `TheMastermind` → `MastermindError`
- Consider consolidating to `MastermindError` only

**`CLIRunner.startKeyboardMonitoring` data race** (`CLIRunner.swift:249`)
```swift
// Task.detached reads @MainActor property:
while await self.isRunning {  // potential data race
```
- `isRunning` is a stored property on `@MainActor CLIRunner`
- The detached task reads it without MainActor isolation
- The subsequent `await MainActor.run` at line 254 correctly hops for the body

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

**Watch mode keyboard handling**
- `CLIRunner` reads raw terminal input for `r` (refresh) and `q` (quit)
- Uses `termios` directly to set raw mode
- This is standard POSIX terminal handling but adds complexity

**No `--timeout` flag for individual commands**
- Direct commands use `DeviceConnector` with hardcoded timeouts
- Users cannot override timeout per-invocation
- Only session mode inherits TheMastermind's configurable timeout
