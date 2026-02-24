# Fix PR #37 Review Issues

## Overview

Fix the 3 issues identified in the code review of PR #37 ("Add persistent CLI session, slim MCP server to thin proxy"):

1. **Concurrency bug** — Race condition in MCP server's `LineReader` and pipe I/O when concurrent tool calls arrive
2. **Documentation drift** — `docs/API.md`, `docs/ARCHITECTURE.md`, and `README.md` are stale after the MCP server rewrite
3. **Missing tests** — No tests for the new 771-line `SessionCommand.swift`

## Current State Analysis

### Issue 1: Concurrency Bug

`ButtonHeistMCP/Sources/main.swift:11-28` defines `LineReader` as `@unchecked Sendable` with a mutable `var buffer = Data()` and no synchronization. The `CallTool` handler at line 130 writes to `writer` and reads from `reader` without serialization. The MCP SDK's `Server` actor dispatches each request in its own `Task` (Server.swift:269), and the handler's `await Task.detached { reader.readLine() }` at line 145 suspends the actor, allowing concurrent handler invocations. This causes:

- Data race on `buffer` (undefined behavior)
- Response-request mismatch (wrong response returned to wrong caller)
- Potential write interleaving on stdin pipe

The fix must serialize the entire write→read round-trip so only one tool call owns the pipe at a time. Additionally, `screenFile` at line 128 uses a fixed path that would race on concurrent `get_screen` calls — this is subsumed by the serialization fix.

### Issue 2: Documentation Drift

The MCP server went from ~880 lines with 17 individual tools and a direct `HeistClient` dependency to ~170 lines with 1 `run` tool proxying to a `buttonheist session` subprocess. No docs were updated. Stale sections:

- **`docs/API.md`** lines 11-265: Overview mentions "17 tools", "How it works" diagram shows "persistent TCP connection" and "17 tools appear in agent's tool palette", and all 17 individual tool definitions
- **`docs/ARCHITECTURE.md`** lines 218-294: ButtonHeistMCP architecture block diagram shows `HeistClient`, `DeviceDiscovery`, and "17 tool definitions"; connection lifecycle describes direct HeistClient flows; design decisions mention `ButtonHeist` dependency and `@MainActor`
- **`docs/ARCHITECTURE.md`** lines 337-378: MCP Agent Flow describes "17 tools", direct HeistClient.send() calls
- **`README.md`** lines 23-60: Architecture diagram shows MCP server connecting directly to `ButtonHeist (HeistClient)`
- **`README.md`** line 167: "exposes 16 tools"
- **`README.md`** lines 169-194: "How it works" and agent interaction examples use individual tool names
- **`README.md`** lines 198-216: "Available tools" table lists 17 individual MCP tools
- **`README.md`** line 238: CLI has "six subcommands" — now seven with `session`
- **`README.md`** lines 468-470: Project structure says "depends on ButtonHeist + MCP SDK" and "MCP server with 15 tools"

### Issue 3: Missing Tests

`ButtonHeistCLI/Sources/SessionCommand.swift` is 771 lines of new code with no accompanying tests. The existing `ButtonHeistCLITests` target (at `ButtonHeistCLI/Tests/`) uses XCTest and tests protocol types from the `ButtonHeist` framework (it cannot import the CLI executable target directly). Tests duplicate local formatting functions since the executable isn't importable.

Key constraint: `SessionRunner` is `@MainActor` and depends on `HeistClient` for device connections, making it hard to unit test without a running iOS device. However, we can test:
- `SessionResponse` formatting (human and JSON output)
- Command dispatch argument parsing/validation
- Response correlation (id passthrough)

## Desired End State

1. The MCP server serializes all tool calls through the subprocess pipe — no concurrent access to `LineReader` or `writer`
2. All documentation accurately reflects the new architecture (single `run` tool, subprocess proxy, no `ButtonHeist` dependency)
3. The new `session` subcommand has unit tests covering response formatting and JSON output

### Verification:
- `cd ButtonHeistMCP && swift build` succeeds
- `cd ButtonHeistCLI && swift build` succeeds
- `cd ButtonHeistCLI && swift test` passes (including new tests)
- `docs/API.md`, `docs/ARCHITECTURE.md`, and `README.md` correctly describe the single `run` tool and subprocess proxy architecture

## What We're NOT Doing

- Adding integration tests that require a running iOS simulator
- Refactoring `SessionRunner` for testability (would require extracting a protocol for `HeistClient`)
- Updating `docs/WIRE-PROTOCOL.md` or `docs/USB_DEVICE_CONNECTIVITY.md` (not affected by this change)
- Adding the `session` subcommand to `docs/API.md` CLI reference (the session command is an implementation detail used by the MCP proxy, not a primary user-facing CLI command)

## Implementation Approach

Fix the concurrency bug first (it's the most critical), then update documentation, then add tests.

---

## Phase 1: Fix Concurrency Bug in MCP Server

### Overview
Serialize the write→read round-trip in the `CallTool` handler so concurrent tool calls don't race on the pipe or `LineReader`.

### Changes Required:

#### 1. Add a serial queue actor for pipe I/O
**File**: `ButtonHeistMCP/Sources/main.swift`

Replace the `LineReader` class with a `SessionPipe` actor that owns both the writer and reader, serializing all access:

```swift
/// Serializes write→read round-trips to the session subprocess.
/// The MCP SDK dispatches CallTool handlers concurrently (Server is an actor
/// but handlers suspend at await points, allowing re-entrancy). Without
/// serialization, concurrent tool calls would race on the pipe I/O and
/// LineReader's mutable buffer.
actor SessionPipe {
    private let writer: FileHandle
    private let handle: FileHandle
    private var buffer = Data()

    init(writer: FileHandle, reader: FileHandle) {
        self.writer = writer
        self.handle = reader
    }

    /// Send a JSON line and read one response line, atomically.
    func roundTrip(_ data: Data) -> String? {
        writer.write(data)
        return readLine()
    }

    private func readLine() -> String? {
        while true {
            if let i = buffer.firstIndex(of: 0x0A) {
                let line = String(data: buffer[buffer.startIndex..<i], encoding: .utf8)
                buffer.removeSubrange(buffer.startIndex...i)
                return line
            }
            let chunk = handle.availableData
            if chunk.isEmpty { return nil }
            buffer.append(chunk)
        }
    }
}
```

Then update the `CallTool` handler to use the actor:

```swift
let pipe = SessionPipe(writer: inPipe.fileHandleForWriting,
                       reader: outPipe.fileHandleForReading)

// ... in the CallTool handler:
var data = try JSONEncoder().encode(dict)
data.append(0x0A)
guard let line = await pipe.roundTrip(data) else {
    return CallTool.Result(content: [.text("Session closed")], isError: true)
}
```

This eliminates:
- The `@unchecked Sendable` `LineReader` class entirely
- The `Task.detached` call (no longer needed — the actor handles serialization)
- The standalone `writer` variable (owned by the actor)
- The standalone `reader` variable (owned by the actor)

#### 2. Use unique screenshot temp file paths
**File**: `ButtonHeistMCP/Sources/main.swift`

Move the `screenFile` generation inside the handler so each call gets a unique path:

```swift
let isScreenshot = dict["command"]?.stringValue == "get_screen"
let screenFile = isScreenshot
    ? NSTemporaryDirectory() + "buttonheist-screen-\(UUID().uuidString).png"
    : ""
if isScreenshot { dict["output"] = .string(screenFile) }
```

This is belt-and-suspenders — the actor already serializes calls, but unique paths make the code resilient to future changes.

### Success Criteria:

#### Automated Verification:
- [ ] `cd ButtonHeistMCP && swift build -c debug 2>&1` succeeds with no errors
- [ ] No `@unchecked Sendable` on any class in `main.swift`
- [ ] No `Task.detached` calls in the `CallTool` handler
- [ ] The `roundTrip` method is the only way to write to / read from the pipe

---

## Phase 2: Update Documentation

### Overview
Update `docs/API.md`, `docs/ARCHITECTURE.md`, and `README.md` to reflect the new MCP architecture: single `run` tool, subprocess proxy, no `ButtonHeist` dependency.

### Changes Required:

#### 1. Update `docs/API.md`
**File**: `docs/API.md`

**Lines 11-16 (Overview paragraph)**: Replace "17 tools as native agent capabilities" and the "discovers via Bonjour, connects over TCP" description with:
- The MCP server spawns a `buttonheist session` subprocess
- Exposes a single `run` tool that accepts `{"command": "<name>", ...params}`
- The session subprocess handles Bonjour discovery and TCP connection

**Lines 59-66 (How it works diagram)**: Replace "17 tools appear" and "persistent TCP connection" with:
- Spawns `buttonheist session --format json`
- Single `run` tool appears in agent's tool palette
- Commands dispatched via JSON on subprocess stdin/stdout

**Lines 71-265 (17 individual tool definitions)**: Replace with:
- Documentation of the single `run` tool
- Table of available command names and their parameters
- Examples using the `run` tool invocation pattern

#### 2. Update `docs/ARCHITECTURE.md`
**File**: `docs/ARCHITECTURE.md`

**Lines 218-235 (ButtonHeistMCP architecture block diagram)**: Replace with new architecture showing:
- `buttonheist-mcp` spawns `buttonheist session` subprocess
- Single `run` tool definition
- Pipe-based communication (JSON lines on stdin/stdout)
- No `HeistClient`, no `DeviceDiscovery`

**Lines 237-287 (How MCP Clients Connect + Connection lifecycle)**: Update to reflect:
- Server responds with capabilities (1 tool: `run`)
- Tool calls are serialized through subprocess pipe
- Session subprocess handles device discovery and connection

**Lines 289-294 (Key Design Decisions)**: Update:
- Remove references to `HeistClient`, `@MainActor`, and `ButtonHeist` dependency
- Add: subprocess proxy architecture, single `run` tool for token efficiency, `SessionPipe` actor for serialization

**Lines 337-378 (MCP Agent Flow)**: Update to reflect proxy architecture

#### 3. Update `README.md`
**File**: `README.md`

**Lines 23-60 (Architecture diagram)**: Update to show MCP server connecting to CLI session subprocess, not directly to HeistClient

**Line 167**: Change "exposes 16 tools" to "exposes a single `run` tool"

**Lines 169-194 (How it works + agent interaction)**: Update to show the `run` tool pattern

**Lines 198-216 (Available tools table)**: Replace with description of the `run` tool and its available commands

**Line 238**: Update "six subcommands" to "seven subcommands" (add `session`)

**Lines 468-470 (Project structure)**: Fix "depends on ButtonHeist + MCP SDK" → "depends on MCP SDK" and "15 tools" → "single `run` tool"

### Success Criteria:

#### Automated Verification:
- [ ] No occurrences of "17 tools" or "16 tools" or "15 tools" in `docs/API.md`, `docs/ARCHITECTURE.md`, or `README.md` when referring to the MCP server
- [ ] No references to `HeistClient` or `DeviceDiscovery` in the ButtonHeistMCP sections of `docs/ARCHITECTURE.md`
- [ ] `docs/API.md` documents the `run` tool, not individual tool names as MCP tools
- [ ] `README.md` architecture diagram shows subprocess proxy, not direct HeistClient connection
- [ ] `README.md` project structure reflects correct MCP package dependency

---

## Phase 3: Add Tests for SessionCommand

### Overview
Add unit tests for `SessionResponse` formatting (both human and JSON output formats) to the existing `ButtonHeistCLITests` target.

### Approach

Since the CLI is an executable target and cannot be imported, existing tests duplicate helper functions locally (see `FormattingTests.swift:142-178`). We'll follow this same pattern: duplicate the `SessionResponse` enum and its formatting methods into the test file for testing.

However, `SessionResponse` depends on SDK types like `Interface`, `ActionResult`, `DiscoveredDevice`, etc. The test target already imports `ButtonHeist`, which provides these types. We can:
1. Copy the `SessionResponse` enum (and its formatting helpers) into the test file
2. Test all formatting paths with constructed test data

### Changes Required:

#### 1. Add SessionResponseTests.swift
**File**: `ButtonHeistCLI/Tests/SessionResponseTests.swift`

Create a new test file that duplicates `SessionResponse` and tests:

**Human formatting tests:**
- `.ok(message:)` → plain text
- `.error(_:)` → "Error: ..." prefix
- `.help(commands:)` → command list formatting
- `.status(connected:deviceName:)` → connected/disconnected strings
- `.devices(_:)` → device list with indices and short IDs
- `.interface(_:)` → element count, separator lines, element formatting
- `.action(result:)` → success/failure with method, value, delta formatting
- `.screenshot(path:width:height:)` → file path and dimensions

**JSON formatting tests:**
- Each response case produces valid JSON with correct `status` field
- `.error` has `status: "error"`
- `.action` with failed result has `status: "error"` and `method` field
- `.interface` includes serialized interface object
- Request ID passthrough (id field preserved in JSON output)

### Success Criteria:

#### Automated Verification:
- [ ] `cd ButtonHeistCLI && swift test 2>&1` passes with no failures
- [ ] New test file exists at `ButtonHeistCLI/Tests/SessionResponseTests.swift`
- [ ] Tests cover both human and JSON formatting for all `SessionResponse` cases

---

## Testing Strategy

### Automated Tests:
- MCP server builds cleanly: `cd ButtonHeistMCP && swift build`
- CLI builds cleanly: `cd ButtonHeistCLI && swift build`
- CLI tests pass: `cd ButtonHeistCLI && swift test`
- Existing workspace tests pass: `xcodebuild -workspace ButtonHeist.xcworkspace -scheme TheGoodsTests test`

### What We Don't Test:
- End-to-end MCP server with real subprocess (requires iOS simulator)
- SessionRunner connection/dispatch logic (requires HeistClient with real device)
- These are covered by manual testing in the PR test plan

## References

- PR #37: https://github.com/RoyalPineapple/accra/pull/37
- MCP SDK Server dispatch: `ButtonHeistMCP/.build/checkouts/swift-sdk/Sources/MCP/Server/Server.swift:269`
- Existing test patterns: `ButtonHeistCLI/Tests/FormattingTests.swift`
- CLAUDE.md Pre-Commit Checklist: `/Users/aodawa/conductor/workspaces/accra/sarajevo/CLAUDE.md`
