---
date: 2026-02-12T22:16:02Z
researcher: aodawa
git_commit: d6714810753f9b02487064ddc179e8838faf6d9f
branch: RoyalPineapple/ai-fuzz-framework
repository: accra (minnetonka)
topic: "AI Fuzzing Framework - Full Stack ButtonHeist MCP Demo"
tags: [research, codebase, mcp, fuzzing, ai-agent, demo, claude-agent]
status: complete
last_updated: 2026-02-12
last_updated_by: aodawa
---

# Research: AI Fuzzing Framework - Full Stack ButtonHeist MCP Demo

**Date**: 2026-02-12T22:16:02Z
**Researcher**: aodawa
**Git Commit**: d6714810753f9b02487064ddc179e8838faf6d9f
**Branch**: RoyalPineapple/ai-fuzz-framework
**Repository**: accra (minnetonka)

## Research Question

What exists in the ButtonHeist codebase that would inform building a standalone AI-based fuzzing framework as a full-stack demo for the MCP server? The framework should live outside the existing code, work on any app with InsideMan installed, and be composed of Claude agent and command files that use ButtonHeist MCP tools to explore apps and discover edge cases.

## Summary

ButtonHeist provides a complete stack for AI agents to drive iOS apps: an MCP server exposing 15 tools (2 read, 13 interaction), a wire protocol over TCP with newline-delimited JSON, and an iOS framework (InsideMan) that auto-starts via ObjC `+load`. The MCP server maintains a persistent connection to the iOS device, making tool calls complete in milliseconds. The existing demo pattern (`demos/apple-hello.md`) shows agent-executable markdown scripts. The codebase has all the infrastructure needed for a fuzzing framework - the framework would consume the MCP tools as a client, requiring no changes to the existing code.

## Detailed Findings

### 1. MCP Server - The Agent Interface

**Location**: `ButtonHeistMCP/Sources/main.swift`
**SDK**: MCP Swift SDK v0.10.0+ from `https://github.com/modelcontextprotocol/swift-sdk.git`
**Transport**: JSON-RPC 2.0 over stdio (stdin/stdout)
**Binary**: `ButtonHeistMCP/.build/release/buttonheist-mcp`

**Configuration** (`.mcp.json` in project root):
```json
{
  "mcpServers": {
    "buttonheist": {
      "command": "./ButtonHeistMCP/.build/release/buttonheist-mcp",
      "args": []
    }
  }
}
```

**15 Tools Available**:

| # | Tool | Type | Required Args | Description |
|---|------|------|---------------|-------------|
| 1 | `get_snapshot` | Read | none | Full UI element hierarchy with labels, values, identifiers, frames, actions |
| 2 | `get_screenshot` | Read | none | PNG screenshot as base64 image |
| 3 | `tap` | Touch | identifier/order OR x,y | Tap element or coordinate |
| 4 | `long_press` | Touch | identifier/order OR x,y | Long press (default 0.5s) |
| 5 | `swipe` | Touch | start + end/direction | Swipe between points or in direction |
| 6 | `drag` | Touch | start + endX,endY | Slow drag (for sliders, reordering) |
| 7 | `pinch` | Touch | scale (required) | Zoom in/out (scale >1 = in, <1 = out) |
| 8 | `rotate` | Touch | angle (required, radians) | Two-finger rotation |
| 9 | `two_finger_tap` | Touch | center coords | Simultaneous two-finger tap |
| 10 | `draw_path` | Touch | points[] (min 2) | Trace polyline path |
| 11 | `draw_bezier` | Touch | startX,Y + segments[] | Trace cubic bezier curves |
| 12 | `activate` | A11y | identifier/order | VoiceOver double-tap equivalent |
| 13 | `increment` | A11y | identifier/order | Increment adjustable (slider/stepper) |
| 14 | `decrement` | A11y | identifier/order | Decrement adjustable (slider/stepper) |
| 15 | `perform_custom_action` | A11y | identifier/order + actionName | Named custom accessibility action |

**Connection Lifecycle**:
1. MCP client spawns `buttonheist-mcp` process
2. Server starts Bonjour discovery for `_buttonheist._tcp`
3. Discovers iOS device within ~2 seconds
4. Establishes persistent TCP connection to InsideMan on port 1455
5. Reports 15 tools via MCP `initialize` handshake
6. Tool calls dispatch to HeistClient -> TCP -> InsideMan -> ActionResult -> MCP response

**Timeouts**:
- Device discovery: 30 seconds
- Connection establishment: 10 seconds
- Snapshot wait: 10 seconds
- Screenshot wait: 30 seconds
- Action result wait: 15 seconds

### 2. Wire Protocol (v2.0)

**Transport**: Newline-delimited JSON over TCP (BSD sockets, IPv6 dual-stack)
**Port**: 1455 (configurable via Info.plist `InsideManPort`)
**Discovery**: Bonjour `_buttonheist._tcp` or USB IPv6 tunnel

**Client -> Server Messages (18 types)**:
- Lifecycle: `requestSnapshot`, `subscribe`, `unsubscribe`, `ping`, `requestScreenshot`
- Element actions: `activate`, `increment`, `decrement`, `performCustomAction`
- Touch gestures: `touchTap`, `touchLongPress`, `touchSwipe`, `touchDrag`, `touchPinch`, `touchRotate`, `touchTwoFingerTap`, `touchDrawPath`, `touchDrawBezier`

**Server -> Client Messages (6 types)**:
- `info` - ServerInfo on connect (app name, bundle ID, device name, screen dimensions)
- `hierarchy` - Snapshot with flat elements array + optional tree
- `screenshot` - Base64 PNG with dimensions and timestamp
- `actionResult` - success/failure with method used and optional message
- `error` - Error string
- `pong` - Keepalive response

### 3. Data Model - What the Fuzzer Will See

**UIElement** (flat list, VoiceOver traversal order):
```
order: Int           - 0-based reading order
description: String  - VoiceOver text
label: String?       - Accessibility label
value: String?       - Current value (slider position, text content, etc.)
identifier: String?  - Accessibility identifier (stable across runs)
frameX/Y/Width/Height: Double - Screen coordinates in points
actions: [String]    - Available actions ("activate", "increment", "decrement", custom names)
```

**ElementNode** (tree structure, optional):
- `element(order: Int)` - Leaf referencing flat array index
- `container(Group, children: [ElementNode])` - Grouped children
- Group types: `semanticGroup`, `list`, `landmark`, `dataTable`, `tabBar`

**ServerInfo** (received on connect):
- `appName`, `bundleIdentifier`, `deviceName`, `systemVersion`
- `screenWidth`, `screenHeight` (in points)

**ActionResult**:
- `success: Bool`, `method: ActionMethod`, `message: String?`
- Methods: `activate`, `increment`, `decrement`, `customAction`, `syntheticTap`, `syntheticLongPress`, `syntheticSwipe`, `syntheticDrag`, `syntheticPinch`, `syntheticRotate`, `syntheticTwoFingerTap`, `syntheticDrawPath`, `elementNotFound`, `elementDeallocated`

**Target Resolution** (how elements are found):
1. By `identifier` - searches cached elements for matching identifier (preferred, stable)
2. By `order` - uses zero-based index in snapshot array (positional, can shift)
3. By coordinates - uses explicit `x,y` screen points (pixel-precise)

### 4. CLI (Wheelman/ButtonHeistCLI)

**Binary**: `buttonheist` (built from `ButtonHeistCLI/`)
**Location**: `ButtonHeistCLI/Sources/`

Four subcommands:
- `buttonheist watch` - Live UI hierarchy (default mode, `--once` for single snapshot, `--format json` for scripting)
- `buttonheist action` - Element actions (`--identifier`, `--index`, `--type activate|increment|decrement|tap|custom`)
- `buttonheist touch <subcommand>` - 9 gesture subcommands (tap, longpress, swipe, drag, pinch, rotate, two-finger-tap, draw-path, draw-bezier)
- `buttonheist screenshot` - Capture PNG (`--output path` or stdout)

The CLI connects via Bonjour discovery same as MCP server but creates a new connection per invocation (no persistent connection). For the fuzzing framework, the MCP server is preferred over CLI.

### 5. App Integration (InsideMan)

**How apps integrate**: Add ButtonHeist package, `import InsideMan`, add Info.plist entries. InsideMan auto-starts via ObjC `+load` - no code changes needed.

**What InsideMan provides**:
- TCP server on port 1455
- Bonjour advertisement as `_buttonheist._tcp`
- Accessibility hierarchy parsing (via AccessibilitySnapshot submodule)
- Polling for UI changes (default 1.0s interval, hash-based change detection)
- Screenshot capture via `UIGraphicsImageRenderer`
- SafeCracker gesture injection (synthetic UITouch + IOHIDEvent via private APIs)
- Tap visualization overlay

**The fuzzer doesn't need to know InsideMan internals** - it only interacts via the MCP server's 15 tools.

### 6. Existing Demo Pattern

**`demos/apple-hello.md`** - Agent-executable markdown script:
- Header explains purpose and prerequisites
- Numbered steps with tool calls in fenced `tool` code blocks
- Conditional logic described in natural language ("If on main menu, tap Touch Canvas")
- Complex data inline (48 bezier segments for the Apple "hello" cursive)
- Verification steps (screenshot after actions)

This is the exact pattern the fuzzing framework should follow for its agent commands.

### 7. Architecture End-to-End

```
AI Fuzzing Agent (Claude Code)
    │
    │ Reads .claude/ commands and CLAUDE.md instructions
    │ Calls MCP tools as native capabilities
    │
    ▼
buttonheist-mcp (MCP Server)
    │
    │ JSON-RPC 2.0 over stdio
    │ Persistent TCP connection
    │
    ▼
HeistClient (macOS framework)
    │
    │ Bonjour discovery + BSD socket TCP
    │
    ▼
InsideMan (iOS framework, auto-started)
    │
    │ Accessibility parsing + SafeCracker gestures
    │
    ▼
Target iOS App (any app with InsideMan installed)
```

## Key Insights for Fuzzing Framework Design

### What the Framework Needs

1. **Claude agent configuration** (`.claude/` commands or CLAUDE.md instructions) that define fuzzing strategies
2. **MCP tool access** via `.mcp.json` pointing to the ButtonHeist MCP server
3. **No new Swift/iOS code** - the framework is purely an AI agent workflow consuming existing MCP tools
4. **Stateful exploration** - the agent needs to track visited screens, discovered elements, and tested interactions

### Available Information Per Screen

From `get_snapshot`, the fuzzer gets:
- Every interactive element with its identifier, label, value, frame, and available actions
- Tree structure showing container groupings (lists, landmarks, semantic groups)
- Element ordering matching VoiceOver traversal

From `get_screenshot`, the fuzzer gets:
- Visual state of the entire screen as a PNG image
- The agent can visually verify state transitions

### Possible Fuzzing Actions

For each element, based on its `actions` array:
- Elements with no actions: tap at frame center (coordinate-based)
- Elements with `activate`: call `activate` or `tap`
- Elements with `increment`/`decrement`: try incrementing/decrementing
- Elements with custom actions: enumerate and try each custom action
- All elements: try `long_press`, `swipe` in all 4 directions
- Input fields (value is editable text): need keyboard interaction via taps on keys
- Map-like views: try `pinch`, `rotate`, `two_finger_tap`

### Edge Case Discovery Strategies

1. **Systematic traversal** - Visit every element on every screen
2. **Boundary testing** - Tap at element edges, outside bounds, at screen corners
3. **Rapid interaction** - Fast repeated taps, overlapping gestures
4. **State exploration** - Map screen transitions as a state machine, find unreachable states
5. **Value boundary testing** - Increment sliders to max, decrement to min, check wrapping
6. **Gesture fuzzing** - Random swipe directions, extreme pinch scales, full rotation
7. **Deep navigation** - Navigate as deep as possible, then verify back navigation works
8. **Screenshot diffing** - Detect visual anomalies by comparing before/after screenshots

### Framework File Structure (Proposed)

```
ai-fuzzer/
├── .mcp.json                    # Points to ButtonHeist MCP server
├── CLAUDE.md                    # Agent instructions and fuzzing strategies
├── .claude/
│   ├── commands/
│   │   ├── fuzz.md              # Main fuzzing command
│   │   ├── explore.md           # Screen exploration command
│   │   ├── stress-test.md       # Stress testing command
│   │   ├── map-screens.md       # Screen state machine mapping
│   │   └── report.md            # Generate findings report
│   └── settings.json            # Agent settings
├── strategies/
│   ├── systematic-traversal.md  # Try every element on every screen
│   ├── boundary-testing.md      # Edge/boundary coordinate testing
│   ├── gesture-fuzzing.md       # Random gesture generation
│   ├── state-exploration.md     # Screen graph traversal
│   └── value-boundary.md        # Slider/stepper boundary testing
├── reports/                     # Generated test reports
└── README.md                    # Setup and usage instructions
```

## Code References

- `.mcp.json:1-8` - MCP server configuration
- `ButtonHeistMCP/Sources/main.swift:13-273` - All 15 tool definitions
- `ButtonHeistMCP/Sources/main.swift:311-564` - Tool call dispatch logic
- `ButtonHeistMCP/Sources/main.swift:583-614` - Device discovery and connection
- `ButtonHeistMCP/Package.swift:11` - MCP Swift SDK dependency (v0.10.0+)
- `ButtonHeist/Sources/TheGoods/Messages.swift:12-70` - All ClientMessage cases
- `ButtonHeist/Sources/TheGoods/Messages.swift:366-384` - All ServerMessage cases
- `ButtonHeist/Sources/TheGoods/Messages.swift:523-561` - UIElement structure
- `ButtonHeist/Sources/TheGoods/Messages.swift:464-475` - Snapshot structure
- `ButtonHeist/Sources/TheGoods/Messages.swift:513-518` - ElementNode tree
- `ButtonHeist/Sources/TheGoods/Messages.swift:388-434` - ActionResult + ActionMethod
- `ButtonHeist/Sources/InsideMan/InsideMan.swift:421-429` - Element target resolution
- `ButtonHeist/Sources/InsideMan/InsideMan.swift:741-762` - Point target resolution
- `demos/apple-hello.md:1-108` - Existing agent demo script pattern
- `scripts/buttonheist_usb.py:1-380` - Python USB connection module
- `scripts/usb-connect.sh:1-73` - Shell USB connection script

## Architecture Documentation

### Component Interaction

The fuzzing framework would sit at the top of the stack as a pure MCP client:

```
┌─────────────────────────────────────────────────────┐
│ AI Fuzzing Framework (Claude Agent + Commands)       │
│  - .claude/commands/ define fuzzing strategies        │
│  - CLAUDE.md defines agent behavior                  │
│  - Reports generated to reports/                     │
│  - Reads MCP tools via .mcp.json                     │
└──────────────────────┬──────────────────────────────┘
                       │ MCP (JSON-RPC 2.0 / stdio)
┌──────────────────────┴──────────────────────────────┐
│ buttonheist-mcp (existing, no changes)               │
│  - 15 tools: get_snapshot, get_screenshot, tap, ...  │
│  - Persistent TCP connection to iOS device           │
└──────────────────────┬──────────────────────────────┘
                       │ TCP (Bonjour / USB IPv6)
┌──────────────────────┴──────────────────────────────┐
│ InsideMan (embedded in target iOS app)               │
│  - Accessibility parsing, gesture injection          │
│  - Auto-starts on framework load                     │
└─────────────────────────────────────────────────────┘
```

### Key Design Constraints

1. **The fuzzer is app-agnostic** - it works on any app with InsideMan, so it cannot hard-code identifiers or screen layouts
2. **Element identifiers vary by app** - the fuzzer must discover elements dynamically via `get_snapshot`
3. **Screen state is observable** - via `get_screenshot` (visual) and `get_snapshot` (structural)
4. **Actions have observable results** - `ActionResult` reports success/failure with method used
5. **No text input tool exists** - typing requires tapping keyboard keys individually (coordinates)
6. **Connection is persistent** - no need to reconnect between tool calls

## Open Questions

1. **Keyboard interaction** - No dedicated "type text" MCP tool exists. Fuzzing text inputs requires tapping keyboard keys by coordinate. Should the framework include a keyboard map utility?
2. **Alert handling** - System alerts (permissions, crashes) may obscure the app. How should the fuzzer detect and handle these?
3. **App state reset** - Between fuzzing runs, the app state may need resetting. Options: kill and relaunch via `xcrun simctl`, or navigate to a known starting screen.
4. **Crash detection** - If the app crashes, the MCP connection drops. The fuzzer needs to detect this and report it as a finding.
5. **Simulator vs device** - The framework should work with both. Simulator allows `xcrun simctl` for app lifecycle management; devices need different approaches.
6. **Parallel fuzzing** - Can multiple fuzzer instances target different simulator instances simultaneously?
