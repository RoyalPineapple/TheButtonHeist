# AI Fuzzing Framework Implementation Plan

## Overview

Build a standalone AI-based fuzzing framework as the full-stack demonstration of ButtonHeist's MCP technology. The framework is an autonomous Claude agent that explores any iOS app with InsideMan installed, discovers crashes, errors, and edge cases, and generates structured reports — all through ButtonHeist's 15 MCP tools. No Swift code required; the entire framework is composed of Claude agent configuration files.

## Current State Analysis

ButtonHeist provides the complete infrastructure:
- **MCP server** (`ButtonHeistMCP/Sources/main.swift`) — 15 tools over JSON-RPC 2.0 via stdio
- **Persistent TCP connection** — tool calls complete in milliseconds
- **InsideMan** — auto-starts in any app via ObjC `+load`, provides UI hierarchy + gesture injection
- **Existing demo** (`demos/apple-hello.md`) — agent-executable markdown, but scripted (not autonomous)

### Key Discoveries:
- MCP tools: 2 read (`get_snapshot`, `get_screenshot`) + 13 interaction (tap, swipe, drag, pinch, rotate, draw, etc.) — `ButtonHeistMCP/Sources/main.swift:13-273`
- `get_snapshot` returns flat element array + optional tree with containers — `ButtonHeist/Sources/TheGoods/Messages.swift:464-475`
- Elements have identifier, label, value, frame, and actions — `Messages.swift:523-561`
- ActionResult reports success/failure with method used — `Messages.swift:388-434`
- Crash detection: MCP connection drops when app dies — the server process exits
- No "type text" MCP tool exists — keyboard interaction requires coordinate taps (out of scope)
- Project-local `.claude/commands/` is supported by Claude Code

## Desired End State

A self-contained `ai-fuzzer/` directory at the repo root that:
1. A user can `cd ai-fuzzer && claude` to start fuzzing any app with InsideMan
2. Five slash commands (`/fuzz`, `/explore`, `/map-screens`, `/stress-test`, `/report`) drive the agent
3. Four swappable strategy files define exploration approaches
4. CLAUDE.md teaches the agent to be an autonomous fuzzer with crash detection and finding categorization
5. Reports are saved to `reports/` as timestamped markdown

### Verification:
- [x] MCP server builds: `cd ButtonHeistMCP && swift build -c release`
- [x] All 13 files exist in `ai-fuzzer/` directory
- [x] `.mcp.json` correctly references `../ButtonHeistMCP/.build/release/buttonheist-mcp`
- [ ] Running `claude` from `ai-fuzzer/` picks up the 5 slash commands
- [ ] `/explore` successfully catalogs the test app's current screen via MCP tools
- [ ] `/fuzz` runs an autonomous exploration loop, navigates between screens, records findings
- [ ] `/report` generates a structured report in `reports/`

## What We're NOT Doing

- **No Swift/iOS code** — the framework is purely agent configuration consuming existing MCP tools
- **No text input** — keyboard interaction will be a separate iteration
- **No app state reset** — will be built into InsideMan/HeistClient separately
- **No parallel fuzzing** — single agent, single app instance
- **No modifications to ButtonHeist/InsideMan/MCP server** — framework is a pure consumer

## Implementation Approach

The Claude agent IS the fuzzer. Instead of writing a test harness, we teach an AI agent how to explore apps through well-structured instructions (CLAUDE.md), callable commands (.claude/commands/), and strategy documents (strategies/).

## Phase 1: Project Scaffold

### Overview
Create the directory structure, MCP config, and README.

### Changes Required:

#### 1. Directory Structure
Create `ai-fuzzer/` at repo root with subdirectories:
```
ai-fuzzer/
├── .claude/commands/
├── strategies/
└── reports/
```

#### 2. MCP Configuration
**File**: `ai-fuzzer/.mcp.json`
```json
{
  "mcpServers": {
    "buttonheist": {
      "command": "../ButtonHeistMCP/.build/release/buttonheist-mcp",
      "args": []
    }
  }
}
```

#### 3. README
**File**: `ai-fuzzer/README.md`
- Setup instructions (build MCP server, launch app, cd into ai-fuzzer)
- Command reference table (/fuzz, /explore, /map-screens, /stress-test, /report)
- Strategy overview table
- Finding severity level definitions

#### 4. Reports placeholder
**File**: `ai-fuzzer/reports/.gitkeep`

### Success Criteria:
- [x] Directory structure exists
- [x] `.mcp.json` points to valid relative path for MCP server binary
- [x] README documents all commands and setup steps

---

## Phase 2: Core Agent Instructions (CLAUDE.md)

### Overview
The most critical file. Teaches the agent its identity, available tools, core observation loop, state tracking, crash detection, finding severity levels, and reporting format.

### Changes Required:

**File**: `ai-fuzzer/CLAUDE.md`

Key sections:
1. **Identity** — "You are an autonomous iOS app fuzzer"
2. **Tool Reference** — Table of all 15 MCP tools with when-to-use guidance
3. **Element Targeting** — Three methods: identifier, order, coordinates
4. **Core Loop** — OBSERVE → REASON → ACT → VERIFY → RECORD
5. **State Tracking** — Mental model of screens visited, actions tried, transitions found
6. **Screen Identification** — Fingerprint screens by element identifiers + labels, not single values
7. **Crash Detection** — MCP connection failure = app crashed = CRASH severity finding
8. **Finding Severity Levels**:
   - CRASH: app died (connection lost)
   - ERROR: action failed unexpectedly
   - ANOMALY: unexpected state change or visual glitch
   - INFO: interesting behavior worth noting
9. **Finding Format** — Structured template with screen, action, expected, actual, reproduction steps
10. **Strategy System** — Load strategy files from `strategies/` when specified
11. **Exploration Heuristics** — Prefer untried actions, navigation elements, state-affecting elements
12. **Back Navigation** — Back buttons → swipe-right → top-left elements → fallback
13. **Report Format** — Where and how to write reports
14. **Rules** — Always observe before/after, don't assume app structure, record everything, skip text input

### Success Criteria:
- [x] CLAUDE.md covers all 15 MCP tools with usage guidance
- [x] Core loop is clearly defined (OBSERVE → REASON → ACT → VERIFY → RECORD)
- [x] Crash detection instructions are explicit
- [x] Finding severity levels are defined with examples
- [x] Text input explicitly marked as out of scope

---

## Phase 3: Strategy Files

### Overview
Four swappable strategy documents that define exploration approaches. Referenced by `/fuzz` command.

### Changes Required:

#### 1. Systematic Traversal (default)
**File**: `ai-fuzzer/strategies/systematic-traversal.md`
- Element selection: in order, actions first, then tappable
- Action selection: tap → activate → long_press → swipe (all 4) → increment/decrement → custom actions
- Screen traversal: breadth-first, depth limit 10
- Termination: all elements tried, or 30 actions without new findings
- Look for: missing back nav, broken transitions, disappearing elements, unresponsive elements, crashes

#### 2. Boundary Testing
**File**: `ai-fuzzer/strategies/boundary-testing.md`
- Coordinate boundary taps: 4 corners + 4 outside-edge taps per element
- Screen edge interactions: corner taps, edge swipes
- Value boundaries: increment 20x, decrement 20x, rapid alternation
- Extreme gesture params: pinch 0.01/100.0, rotate 2π/100×2π, swipe 2000pt, long_press 10s
- Look for: hit-testing failures, ghost taps, value overflow, layout breakage, crashes from extremes

#### 3. Gesture Fuzzing
**File**: `ai-fuzzer/strategies/gesture-fuzzing.md`
- Target elements least likely to handle complex gestures (buttons, labels, toggles)
- Full gesture matrix per element: 13 gesture types + 4 rapid sequences + random coordinates
- Look for: crashes from unexpected gestures, recognizer conflicts, unintended actions, state corruption, UI freezes

#### 4. State Exploration
**File**: `ai-fuzzer/strategies/state-exploration.md`
- Depth-first with backtracking
- Screen fingerprinting by element identifiers + labels + container structure
- State consistency checks: navigate away and back, verify state preserved
- Limits: 15 depth, 50 screens
- Look for: dead ends, orphan screens, asymmetric transitions, state leaks, inconsistent paths, deep nesting

### Success Criteria:
- [x] All 4 strategy files exist with consistent structure (goal, element selection, action selection, termination, what to look for)
- [x] Default strategy (systematic-traversal) covers all basic interaction types
- [x] Boundary testing includes coordinate math using element frame data
- [x] Gesture fuzzing includes multi-touch gestures (pinch, rotate, two_finger_tap)
- [x] State exploration defines screen fingerprinting algorithm

---

## Phase 4: Slash Commands

### Overview
Five commands that drive the agent. Each has YAML frontmatter (`description:` field) and structured step-by-step instructions.

### Changes Required:

#### 1. `/explore` — Screen Explorer
**File**: `ai-fuzzer/.claude/commands/explore.md`
- Step 1: Screenshot + snapshot, print element summary
- Step 2: Record baseline state
- Step 3: Interact with each element (tap, activate, long_press, swipe, increment/decrement, custom actions)
- Step 4: Print structured report with transitions discovered, findings, and element catalog table

#### 2. `/fuzz` — Autonomous Fuzzer
**File**: `ai-fuzzer/.claude/commands/fuzz.md`
- Arguments: strategy name (default: systematic-traversal), max iterations (default: 100)
- Step 0: Load strategy file from `strategies/`
- Step 1: Initial observation (screenshot + snapshot)
- Step 2: Initialize tracking (screens_visited, transitions, actions_taken, findings)
- Step 3: Fuzzing loop (observe → select action per strategy → execute → verify → record)
- Step 4: Generate report to `reports/`
- Progress updates every 10 actions
- Crash handling: stop, record, generate partial report

#### 3. `/map-screens` — Screen Graph Builder
**File**: `ai-fuzzer/.claude/commands/map-screens.md`
- Step 1: Fingerprint start screen
- Step 2: Depth-first exploration with backtracking
- Step 3: Build and print navigation graph (tree format + transition table)
- Step 4: Save to `reports/YYYY-MM-DD-HHMM-screen-map.md`
- Limits: 50 screens, 15 depth, 200 total actions

#### 4. `/stress-test` — Stress Tester
**File**: `ai-fuzzer/.claude/commands/stress-test.md`
- Arguments: element identifier or "all" (default)
- 6 sequences: rapid taps (20x), rapid swipes (10x alternating), pinch cycles (5x), rotate cycles (5x), mixed rapid gestures, increment/decrement hammering (20x each)
- Full-screen stress pass: random taps, directional swipes, extreme pinch/rotate
- Health check: compare before/after element count, visual state, responsiveness

#### 5. `/report` — Report Generator
**File**: `ai-fuzzer/.claude/commands/report.md`
- Gathers all findings from the session
- Writes to `reports/YYYY-MM-DD-HHMM-fuzz-report.md`
- Structured format: summary table, findings by severity, screen map, coverage stats
- Handles "no findings" case with positive-signal messaging

### Success Criteria:
- [x] All 5 command files have YAML frontmatter with `description:` field
- [x] `/explore` catalogs elements and tries all available actions
- [x] `/fuzz` accepts strategy argument and runs autonomous loop with progress reporting
- [x] `/map-screens` builds a navigation graph with transition tracking
- [x] `/stress-test` includes rapid repetition sequences for each gesture type
- [x] `/report` generates timestamped markdown files in `reports/`
- [x] All commands include crash handling instructions

---

## Testing Strategy

### Automated Verification:
- [x] MCP server builds successfully: `cd ButtonHeistMCP && swift build -c release`
- [x] All 13 files exist: `find ai-fuzzer -type f | wc -l` returns 13
- [x] `.mcp.json` is valid JSON: `python3 -c "import json; json.load(open('ai-fuzzer/.mcp.json'))"`
- [x] All command files have YAML frontmatter: `head -1 ai-fuzzer/.claude/commands/*.md` all show `---`
- [x] Strategy files all exist: `ls ai-fuzzer/strategies/*.md | wc -l` returns 4

### End-to-End Verification:
1. Build MCP server: `cd ButtonHeistMCP && swift build -c release`
2. Boot simulator and launch test app with InsideMan
3. `cd ai-fuzzer && claude`
4. Run `/explore` — verify it calls `get_snapshot`, catalogs elements, tries interactions
5. Run `/fuzz` — verify it runs the observation loop, navigates between screens, accumulates findings
6. Run `/map-screens` — verify it discovers multiple screens and builds a graph
7. Run `/stress-test` — verify it performs rapid gesture sequences
8. Run `/report` — verify it generates a report file in `reports/`

## References

- Research document: `thoughts/shared/research/2026-02-12-ai-fuzzing-framework-research.md`
- MCP server implementation: `ButtonHeistMCP/Sources/main.swift`
- Wire protocol spec: `docs/WIRE-PROTOCOL.md`
- API reference: `docs/API.md`
- Architecture: `docs/ARCHITECTURE.md`
- Existing demo pattern: `demos/apple-hello.md`
