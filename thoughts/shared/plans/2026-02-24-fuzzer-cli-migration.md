# Fuzzer CLI Migration — Remove MCP Server

## Overview

Migrate the AI fuzzer from using the ButtonHeist MCP server to using the `buttonheist` CLI directly via Bash. Then remove the MCP server entirely from the project.

## Current State Analysis

The fuzzer (`ai-fuzzer/`) is an agent-driven system composed entirely of Markdown (commands, references, strategies). It currently interacts with iOS apps through the MCP server (`ButtonHeistMCP`), which spawns `buttonheist session --format json` as a persistent subprocess and exposes a single `run` tool.

The `buttonheist` CLI already has standalone commands for everything the fuzzer needs: `watch --once`, `action`, `touch`, `type`, `screenshot`, `list`. However, the CLI's action/touch/type commands currently output only "success"/"failed" text — they discard the `ActionResult.interfaceDelta` that InsideMan already computed and sent over the wire.

**Important**: Interface deltas are computed server-side by InsideMan on the iOS device. InsideMan diffs the before/after accessibility tree locally and sends only the minimal delta over TCP as part of the `ActionResult`. The CLI already *receives* this delta via `HeistClient.waitForActionResult()` — it just doesn't output it. Phase 1 surfaces this existing data; no client-side diffing is needed and no extra wire traffic is added.

### Key Discoveries:
- `ActionCommand.swift:87-88` — receives full ActionResult (with delta from InsideMan) but outputs only "success"
- `TouchCommand.swift:580-581` — same, discards the InsideMan-computed delta and value
- `TypeCommand.swift:72-74` — outputs value but not delta
- `SessionCommand.swift:746-760` — has the JSON serialization logic we need to reuse for surfacing the delta
- `DeviceConnector.swift:13` — 5-second discovery timeout per connection (acceptable since agent reasoning time >> connection time)
- Missing CLI commands: `edit_action` and `dismiss_keyboard` are session-only (no standalone CLI command); `wait_for_idle` is internal-only

## Desired End State

- The fuzzer uses `buttonheist` CLI commands via Bash tool instead of MCP tools
- CLI action/touch/type commands output rich JSON (status, method, value, delta) when `--format json` is used
- The MCP server (`ButtonHeistMCP/`) is removed from the project
- All `.mcp.json` files are removed
- All documentation reflects the CLI-only architecture

### Verification:
- `xcodebuild -workspace ButtonHeist.xcworkspace -scheme ButtonHeist build` succeeds (no MCP dependency)
- `swift build -c release` in `ButtonHeistCLI/` succeeds
- `buttonheist action --identifier X --format json` outputs `{"status":"ok","method":"...","delta":{...}}`
- All fuzzer commands reference CLI commands, not MCP tools
- `grep -r "mcp\|MCP\|buttonheist-mcp" ai-fuzzer/` returns no results (except in historical reports)

## What We're NOT Doing

- Exposing `wait_for_idle` as a CLI command (internal concern — the CLI handles idle-waiting internally)
- Changing the fuzzer's testing strategies, behavioral modeling, or session notes format
- Modifying InsideMan, Wheelman, TheGoods, or the ButtonHeist framework
- Changing the wire protocol between CLI and iOS app

## Implementation Approach

Three phases: (1) enhance CLI output, (2) rewrite fuzzer to use CLI, (3) remove MCP server.

---

## Phase 1: Surface InsideMan's Delta in CLI Output

### Overview
Add `--format json` to `ActionCommand`, all `TouchCommand` subcommands, and `TypeCommand`. In JSON mode, output the full `ActionResult` — including the interface delta that InsideMan already computes and sends over the wire. This is purely a presentation change: the delta data already flows from InsideMan → TCP → HeistClient → ActionResult; we just need the CLI to print it instead of discarding it.

### Changes Required:

#### 1. Shared JSON Formatting Helper
**File**: `ButtonHeistCLI/Sources/CLIRunner.swift`
**Changes**: Add a function to serialize `ActionResult` to JSON, surfacing the InsideMan-computed delta. Reuses the same format as SessionCommand.

```swift
/// Format an ActionResult as a JSON string matching the session protocol format.
func formatActionResultJSON(_ result: ActionResult) -> String {
    var d: [String: Any] = [
        "status": result.success ? "ok" : "error",
        "method": result.method.rawValue,
    ]
    if let msg = result.message { d["message"] = msg }
    if let value = result.value { d["value"] = value }
    if result.animating == true { d["animating"] = true }
    if let delta = result.interfaceDelta {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        if let data = try? encoder.encode(delta),
           let deltaObj = try? JSONSerialization.jsonObject(with: data) {
            d["delta"] = deltaObj
        }
    }
    if let data = try? JSONSerialization.data(withJSONObject: d, options: [.sortedKeys]),
       let json = String(data: data, encoding: .utf8) {
        return json
    }
    return "{\"status\":\"error\",\"message\":\"Serialization failed\"}"
}
```

#### 2. ActionCommand
**File**: `ButtonHeistCLI/Sources/ActionCommand.swift`
**Changes**: Add `--format` option. In JSON mode, output the full ActionResult JSON instead of bare "success"/"failed".

Add the `--format` option:
```swift
@Option(name: .shortAndLong, help: "Output format: human, json")
var format: OutputFormat = .human
```

Replace the output section (lines 86-98) with format-aware output:
```swift
switch format {
case .json:
    writeOutput(formatActionResultJSON(result))
    if !result.success { Darwin.exit(1) }
case .human:
    if result.success {
        if !quiet { logStatus("Action succeeded (method: \(result.method.rawValue))") }
        writeOutput("success")
    } else {
        let errorMessage = result.message ?? result.method.rawValue
        if !quiet { logStatus("Action failed: \(errorMessage)") }
        writeOutput("failed: \(errorMessage)")
        Darwin.exit(1)
    }
}
```

#### 3. Touch Command — Shared Helper
**File**: `ButtonHeistCLI/Sources/TouchCommand.swift`
**Changes**: Add `format` parameter to the `sendTouchGesture` helper function (line 566). Update all 9 touch subcommands to pass `format` through.

Update `sendTouchGesture` signature:
```swift
private func sendTouchGesture(message: ClientMessage, timeout: Double, quiet: Bool, device: String? = nil, format: OutputFormat = .human) async throws {
```

Replace output section (lines 580-593):
```swift
switch format {
case .json:
    writeOutput(formatActionResultJSON(result))
    if !result.success { Darwin.exit(1) }
case .human:
    // existing human output code
}
```

Add `--format` option to each of the 9 touch subcommands (`TapSubcommand`, `LongPressSubcommand`, `SwipeSubcommand`, `DragSubcommand`, `PinchSubcommand`, `RotateSubcommand`, `TwoFingerTapSubcommand`, `DrawPathSubcommand`, `DrawBezierSubcommand`) and pass it to `sendTouchGesture`.

#### 4. TypeCommand
**File**: `ButtonHeistCLI/Sources/TypeCommand.swift`
**Changes**: Add `--format` option. In JSON mode, output the full ActionResult JSON.

Add the `--format` option:
```swift
@Option(name: .shortAndLong, help: "Output format: human, json")
var format: OutputFormat = .human
```

Replace output section (lines 69-83) with format-aware output matching ActionCommand.

#### 5. New Command: `copy`, `paste`, `cut`, `select`, `select-all`
**File**: `ButtonHeistCLI/Sources/TextEditCommands.swift` (new file)
**Changes**: Add 5 top-level commands that dispatch standard edit actions through the iOS responder chain.

Each command follows the same pattern — connect, send `.editAction(EditActionTarget(action: "..."))`, output the result:

```swift
struct CopyCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "copy",
        abstract: "Copy selected text via the responder chain"
    )

    @Option(name: .shortAndLong, help: "Output format: human, json")
    var format: OutputFormat = .human

    @Option(name: .shortAndLong, help: "Timeout in seconds")
    var timeout: Double = 10.0

    @Flag(name: .shortAndLong, help: "Suppress status messages")
    var quiet: Bool = false

    @Option(name: .long, help: "Target device by name, ID prefix, or index from 'list'")
    var device: String?

    @MainActor
    mutating func run() async throws {
        try await sendEditAction("copy", timeout: timeout, quiet: quiet, device: device, format: format)
    }
}
```

Repeat for `PasteCommand` ("paste"), `CutCommand` ("cut"), `SelectCommand` ("select"), `SelectAllCommand` ("select-all" commandName, sends "selectAll" action).

Add a shared helper:
```swift
@MainActor
func sendEditAction(_ action: String, timeout: Double, quiet: Bool, device: String?, format: OutputFormat) async throws {
    let connector = DeviceConnector(deviceFilter: device, quiet: quiet)
    try await connector.connect()
    defer { connector.disconnect() }
    let client = connector.client

    if !quiet { logStatus("Sending \(action)...") }
    client.send(.editAction(EditActionTarget(action: action)))
    let result = try await client.waitForActionResult(timeout: timeout)

    switch format {
    case .json:
        writeOutput(formatActionResultJSON(result))
        if !result.success { Darwin.exit(1) }
    case .human:
        if result.success {
            if !quiet { logStatus("\(action) succeeded") }
            writeOutput("success")
        } else {
            let msg = result.message ?? "failed"
            if !quiet { logStatus("\(action) failed: \(msg)") }
            writeOutput("failed: \(msg)")
            Darwin.exit(1)
        }
    }
}
```

Register all 5 commands in `main.swift`'s subcommands array.

#### 6. New Command: `dismiss-keyboard`
**File**: `ButtonHeistCLI/Sources/DismissKeyboardCommand.swift` (new file)
**Changes**: Add a top-level command that resigns the first responder (dismisses the keyboard).

```swift
struct DismissKeyboardCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "dismiss-keyboard",
        abstract: "Dismiss the keyboard by resigning first responder"
    )

    @Option(name: .shortAndLong, help: "Output format: human, json")
    var format: OutputFormat = .human

    @Option(name: .shortAndLong, help: "Timeout in seconds")
    var timeout: Double = 10.0

    @Flag(name: .shortAndLong, help: "Suppress status messages")
    var quiet: Bool = false

    @Option(name: .long, help: "Target device by name, ID prefix, or index from 'list'")
    var device: String?

    @MainActor
    mutating func run() async throws {
        let connector = DeviceConnector(deviceFilter: device, quiet: quiet)
        try await connector.connect()
        defer { connector.disconnect() }
        let client = connector.client

        if !quiet { logStatus("Dismissing keyboard...") }
        client.send(.resignFirstResponder)
        let result = try await client.waitForActionResult(timeout: timeout)

        switch format {
        case .json:
            writeOutput(formatActionResultJSON(result))
            if !result.success { Darwin.exit(1) }
        case .human:
            if result.success {
                if !quiet { logStatus("Keyboard dismissed") }
                writeOutput("success")
            } else {
                let msg = result.message ?? "No first responder found"
                if !quiet { logStatus("Failed: \(msg)") }
                writeOutput("failed: \(msg)")
                Darwin.exit(1)
            }
        }
    }
}
```

Register in `main.swift`'s subcommands array.

#### 7. Update main.swift — Register New Commands
**File**: `ButtonHeistCLI/Sources/main.swift`
**Changes**: Add the 6 new commands to the subcommands array:

```swift
subcommands: [ListCommand.self, WatchCommand.self, ActionCommand.self,
               TouchCommand.self, TypeCommand.self, ScreenshotCommand.self,
               SessionCommand.self,
               CopyCommand.self, PasteCommand.self, CutCommand.self,
               SelectCommand.self, SelectAllCommand.self,
               DismissKeyboardCommand.self],
```

### Success Criteria:

#### Automated Verification:
- [ ] CLI builds: `cd ButtonHeistCLI && swift build -c release`
- [ ] Action JSON output works: `buttonheist action --identifier testButton --format json` outputs valid JSON with status, method, and delta fields
- [ ] Touch JSON output works: `buttonheist touch tap --x 200 --y 400 --format json` outputs valid JSON
- [ ] Type JSON output works: `buttonheist type --text "hello" --format json` outputs valid JSON
- [ ] Copy works: `buttonheist copy --format json` outputs valid JSON
- [ ] Dismiss keyboard works: `buttonheist dismiss-keyboard --format json` outputs valid JSON
- [ ] Human format unchanged: `buttonheist action --identifier testButton` still outputs "success"/"failed"
- [ ] Existing tests pass: `cd ButtonHeistCLI && swift test`

---

## Phase 2: Migrate Fuzzer to CLI

### Overview
Rewrite all fuzzer commands and references to use `buttonheist` CLI via Bash tool instead of MCP tool calls. The fuzzer agent will call CLI commands via the Bash tool and parse JSON output.

### CLI Command Mapping

| MCP (current) | CLI (new) |
|---|---|
| `run({"command":"list_devices"})` | `buttonheist list --format json` |
| `run({"command":"get_interface"})` | `buttonheist watch --once --format json --quiet` |
| `run({"command":"get_screen"})` | `buttonheist screenshot --output /tmp/bh-screen.png` then Read the PNG |
| `run({"command":"activate","identifier":"X"})` | `buttonheist action --identifier X --format json` |
| `run({"command":"activate","order":3})` | `buttonheist action --index 3 --format json` |
| `run({"command":"increment","identifier":"X"})` | `buttonheist action --identifier X --type increment --format json` |
| `run({"command":"decrement","identifier":"X"})` | `buttonheist action --identifier X --type decrement --format json` |
| `run({"command":"perform_custom_action","identifier":"X","actionName":"Y"})` | `buttonheist action --identifier X --type custom --custom-action Y --format json` |
| `run({"command":"tap","identifier":"X"})` | `buttonheist touch tap --identifier X --format json` |
| `run({"command":"tap","x":100,"y":200})` | `buttonheist touch tap --x 100 --y 200 --format json` |
| `run({"command":"long_press","identifier":"X","duration":1.0})` | `buttonheist touch longpress --identifier X --duration 1.0 --format json` |
| `run({"command":"swipe","identifier":"X","direction":"up"})` | `buttonheist touch swipe --identifier X --direction up --format json` |
| `run({"command":"swipe","startX":0,"startY":400,"direction":"right","distance":200})` | `buttonheist touch swipe --from-x 0 --from-y 400 --direction right --distance 200 --format json` |
| `run({"command":"drag","identifier":"X","endX":300,"endY":200})` | `buttonheist touch drag --identifier X --to-x 300 --to-y 200 --format json` |
| `run({"command":"pinch","identifier":"X","scale":2.0})` | `buttonheist touch pinch --identifier X --scale 2.0 --format json` |
| `run({"command":"rotate","identifier":"X","angle":1.57})` | `buttonheist touch rotate --identifier X --angle 1.57 --format json` |
| `run({"command":"two_finger_tap","identifier":"X"})` | `buttonheist touch two-finger-tap --identifier X --format json` |
| `run({"command":"type_text","text":"hello","identifier":"X"})` | `buttonheist type --text "hello" --identifier X --format json` |
| `run({"command":"type_text","deleteCount":5,"text":"new","identifier":"X"})` | `buttonheist type --delete 5 --text "new" --identifier X --format json` |
| `run({"command":"draw_path","points":[...]})` | `buttonheist touch draw-path --points "x1,y1 x2,y2 ..." --format json` |
| `run({"command":"draw_bezier",...})` | `buttonheist touch draw-bezier --bezier-file curve.json --format json` |
| `run({"command":"edit_action","action":"copy"})` | `buttonheist copy --format json` |
| `run({"command":"edit_action","action":"paste"})` | `buttonheist paste --format json` |
| `run({"command":"edit_action","action":"cut"})` | `buttonheist cut --format json` |
| `run({"command":"edit_action","action":"select"})` | `buttonheist select --format json` |
| `run({"command":"edit_action","action":"selectAll"})` | `buttonheist select-all --format json` |
| `run({"command":"dismiss_keyboard"})` | `buttonheist dismiss-keyboard --format json` |

### Key Behavioral Changes for the Fuzzer Agent

1. **Tool usage**: Instead of calling MCP tools directly, the agent uses the `Bash` tool to run `buttonheist` commands
2. **JSON parsing**: The agent parses JSON from stdout (same structure as MCP responses for actions; raw Interface JSON for `watch`)
3. **Screenshots**: Two-step process — run `buttonheist screenshot --output /tmp/file.png`, then `Read` the PNG file to view it
4. **Device targeting**: Use `--device` flag on each command instead of MCP server's `BUTTONHEIST_DEVICE` env var
5. **Crash detection**: Instead of MCP connection errors, crashes manifest as non-zero exit codes or connection timeout errors from the CLI
6. **No persistent connection**: Each CLI command connects and disconnects independently. This is slower but acceptable since agent reasoning time dominates
7. **Deltas are still server-computed**: InsideMan computes deltas on the iOS device and sends only the diff over TCP — the CLI just surfaces them. No client-side diffing, no extra wire traffic.

### Changes Required:

#### 1. SKILL.md (Core Agent Persona)
**File**: `ai-fuzzer/SKILL.md`
**Changes**:
- Replace all references to "MCP tools" with "CLI commands via Bash tool"
- Update the architecture description (remove buttonheist-mcp from the stack)
- Update "Core Loop" examples to show CLI commands
- Update crash detection: "If a CLI command fails with a connection error or non-zero exit code..." instead of "If an MCP tool call fails..."
- Update the `## Reference Files` table (update `references/examples.md` description)
- Update all mentions of `get_interface`, `get_screen`, tool calls, etc. to show CLI equivalents

#### 2. fuzz.md (Main Fuzz Command)
**File**: `ai-fuzzer/.claude/commands/fuzz.md`
**Changes**:
- Step 0: Replace `list_devices` MCP call with `buttonheist list --format json` via Bash
- Step 2: Replace `get_screen` + `get_interface` with CLI equivalents
- Step 4: Replace all MCP action calls with CLI commands
- Update crash handling: CLI errors instead of MCP disconnection

#### 3. fuzz-explore.md
**File**: `ai-fuzzer/.claude/commands/fuzz-explore.md`
**Changes**: Same pattern as fuzz.md — replace MCP references with CLI commands.

#### 4. fuzz-map-screens.md
**File**: `ai-fuzzer/.claude/commands/fuzz-map-screens.md`
**Changes**: Same pattern.

#### 5. fuzz-stress-test.md
**File**: `ai-fuzzer/.claude/commands/fuzz-stress-test.md`
**Changes**: Same pattern.

#### 6. fuzz-reproduce.md
**File**: `ai-fuzzer/.claude/commands/fuzz-reproduce.md`
**Changes**: Same pattern.

#### 7. fuzz-report.md
**File**: `ai-fuzzer/.claude/commands/fuzz-report.md`
**Changes**:
- Replace `list_devices` + `get_interface` with CLI equivalents
- Minor — this command mostly reads files and generates reports

#### 8. references/examples.md
**File**: `ai-fuzzer/references/examples.md`
**Changes**:
- Update the title from "MCP Tool Response Examples" to "CLI Response Examples"
- Update all examples to show CLI command syntax and output format
- `get_interface` response now comes from `buttonheist watch --once --format json --quiet`
- Action responses now come from `buttonheist action/touch --format json`
- Crash detection: CLI exit code / connection error instead of MCP disconnection
- Delta interpretation examples stay the same (same JSON format from Phase 1)

#### 9. references/troubleshooting.md
**File**: `ai-fuzzer/references/troubleshooting.md`
**Changes**:
- Replace "MCP server" references with "CLI" references
- Remove "MCP server won't start" section
- Update "No devices found" to reference CLI discovery
- Update crash detection section

#### 10. README.md
**File**: `ai-fuzzer/README.md`
**Changes**:
- Update "How It Works" architecture diagram to remove MCP layer
- Update prerequisites: remove "ButtonHeist MCP server built"
- Update setup: remove MCP build step, replace with CLI build
- Remove `.mcp.json` references and device targeting via env var
- Update to show `--device` flag for targeting

### Success Criteria:

#### Automated Verification:
- [ ] No MCP references in fuzzer commands: `grep -r "mcp\|MCP\|buttonheist-mcp" ai-fuzzer/.claude/ ai-fuzzer/SKILL.md ai-fuzzer/README.md ai-fuzzer/references/troubleshooting.md ai-fuzzer/references/examples.md` returns no results
- [ ] All fuzzer markdown files reference CLI commands (Bash tool + buttonheist)
- [ ] `.mcp.json` removed from `ai-fuzzer/`

---

## Phase 3: Remove MCP Server and Update Project Docs

### Overview
Remove the `ButtonHeistMCP/` package entirely and update all project-level documentation to reflect the CLI-only architecture.

### Changes Required:

#### 1. Delete MCP Server Package
**Action**: Remove the `ButtonHeistMCP/` directory entirely.

#### 2. Delete MCP Configuration Files
- Delete `/.mcp.json` (root)
- Delete `/ai-fuzzer/.mcp.json`

#### 3. Update CLAUDE.md
**File**: `CLAUDE.md`
**Changes**:
- Remove the "Build the MCP server" step from Simulator Quick Start
- Update pre-commit checklist: remove any MCP build verification (currently not listed, but ensure it stays clean)

#### 4. Update README.md
**File**: `README.md`
**Changes**:
- Update the tagline to remove MCP reference
- Remove "MCP server" from Features list
- Update Architecture diagram: remove the MCP layer, show CLI directly connecting agents
- Remove `ButtonHeistMCP` from Modules table
- Replace "Connect with an AI Agent (MCP)" section with "Connect with an AI Agent (CLI)" — show using `buttonheist` CLI commands instead
- Remove `.mcp.json` examples
- Update directory tree to remove `ButtonHeistMCP/`
- Update data flow description

#### 5. Update docs/API.md
**File**: `docs/API.md`
**Changes**:
- Remove the "MCP Server (AI Agent Interface)" section entirely (lines 5-178 approximately)
- Update the opening line to remove MCP reference
- Update `buttonheist session` docs to remove MCP proxy references
- Keep the CLI Reference section as the primary API docs

#### 6. Update docs/ARCHITECTURE.md
**File**: `docs/ARCHITECTURE.md`
**Changes**:
- Remove `ButtonHeistMCP` from the component list and architecture diagram
- Remove the "ButtonHeistMCP (AI Agent Interface)" section
- Remove "MCP Agent Flow" section or replace with "CLI Agent Flow"
- Update data flow diagrams
- Update all references to MCP in remaining sections

### Success Criteria:

#### Automated Verification:
- [ ] MCP directory gone: `test ! -d ButtonHeistMCP`
- [ ] No .mcp.json files: `find . -name ".mcp.json" -not -path "./.git/*" | wc -l` returns 0
- [ ] Project builds: `xcodebuild -workspace ButtonHeist.xcworkspace -scheme ButtonHeist build` succeeds
- [ ] CLI builds: `cd ButtonHeistCLI && swift build -c release`
- [ ] All tests pass: `xcodebuild -workspace ButtonHeist.xcworkspace -scheme ButtonHeistTests test`
- [ ] No stale MCP references in main docs: `grep -l "buttonheist-mcp\|ButtonHeistMCP\|\.mcp\.json" README.md CLAUDE.md docs/API.md docs/ARCHITECTURE.md` returns no results

---

## Testing Strategy

### Unit Tests:
- Existing `ButtonHeistCLI/Tests/` should pass unchanged (they test the existing CLI behavior)
- No new unit tests needed for the `--format json` addition — the JSON serialization reuses the proven session format

### Integration Tests:
- After Phase 1: manually verify JSON output by running CLI commands against a running simulator app
- After Phase 2: run `/fuzz-explore` in the `ai-fuzzer/` workspace to verify the full loop works

### Manual Testing:
After all phases complete:
1. Build CLI: `cd ButtonHeistCLI && swift build -c release`
2. Launch the test app in a simulator
3. Run: `buttonheist action --identifier someButton --format json --device <UDID>` — verify JSON output with delta
4. Start a fuzzer session in `ai-fuzzer/` and run `/fuzz-explore` to verify end-to-end

## References

- Current MCP server: `ButtonHeistMCP/Sources/main.swift`
- Session JSON format: `ButtonHeistCLI/Sources/SessionCommand.swift:706-771`
- CLI commands: `ButtonHeistCLI/Sources/*.swift`
- Fuzzer agent: `ai-fuzzer/SKILL.md`, `ai-fuzzer/.claude/commands/*.md`
