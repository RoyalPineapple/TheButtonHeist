# AI Fuzzer

AI-powered iOS app fuzzing framework built on [ButtonHeist](../README.md). An autonomous Claude agent explores your app, interacts with every element, and discovers crashes, errors, and edge cases — all through ButtonHeist's MCP tools.

## How It Works

The Claude agent **is** the fuzzer. CLAUDE.md teaches it how to observe screens, reason about what to try, execute gestures, detect failures, and report findings. No scripts, no test harnesses — just an AI agent with eyes and hands for your iOS app.

```
Claude Agent (fuzzer brain)
    │ reads CLAUDE.md + strategy files
    │ calls MCP tools as native capabilities
    ▼
buttonheist-mcp (MCP server)
    │ persistent TCP connection
    ▼
InsideMan (embedded in your iOS app)
    │ accessibility parsing + gesture injection
    ▼
Your iOS App (simulator or device)
```

## Prerequisites

- Xcode 15+
- An iOS app with InsideMan embedded (see [main README](../README.md#1-add-insideman-to-your-ios-app))
- ButtonHeist MCP server built

## Setup

### 1. Build the MCP server

```bash
cd ../ButtonHeistMCP
swift build -c release
```

### 2. Run your iOS app

Launch your app in the iOS Simulator (or on a USB-connected device). InsideMan auto-starts when the app loads.

### 3. Start the fuzzer

```bash
cd ai-fuzzer
claude
```

Claude Code reads `.mcp.json`, spawns the MCP server, and connects to your running app automatically.

## Commands

| Command | Description |
|---------|-------------|
| `/fuzz` | Autonomous fuzzing loop — explores the app and finds bugs |
| `/explore` | Deep-dive on the current screen — catalogs every element and tries every action |
| `/map-screens` | Builds a navigation graph of all reachable screens |
| `/stress-test` | Rapid-fire interaction testing on elements |
| `/report` | Generates a structured findings report |

### Quick Start

```
> /fuzz
```

This starts the default fuzzing strategy (systematic traversal). The agent will:
1. Capture the screen and read the interface hierarchy
2. Try every interactive element
3. Navigate to new screens when discovered
4. Detect crashes, errors, and anomalies
5. Generate a report when done

### Targeted Exploration

```
> /explore
```

Deep-dives on whatever screen is currently showing. Catalogs every element, tries every action, and reports what it finds.

### Stress Testing

```
> /stress-test
```

Rapidly hammers elements with repeated taps, swipes, pinches, and rotations to find stability issues.

## Strategies

Strategy files in `strategies/` define how the agent explores:

| Strategy | Focus |
|----------|-------|
| `systematic-traversal` | Every element, every action, breadth-first (default) |
| `boundary-testing` | Edge coordinates, extreme values, out-of-bounds taps |
| `gesture-fuzzing` | Unusual gestures on elements that don't expect them |
| `state-exploration` | Deep navigation, back-navigation, path coverage |

Pass a strategy to `/fuzz`:
```
> /fuzz boundary-testing
```

## Findings

Findings are categorized by severity:

| Severity | Meaning |
|----------|---------|
| **CRASH** | App died — MCP connection lost after an action |
| **ERROR** | Action failed unexpectedly (not just "element not found") |
| **ANOMALY** | Unexpected state change, visual glitch, or missing element |
| **INFO** | Interesting behavior worth noting |

Reports are saved to `reports/` as timestamped markdown files.

## Works With Any App

This fuzzer is **app-agnostic**. It discovers the UI dynamically via `get_interface` and doesn't rely on hard-coded identifiers or screen layouts. Any iOS app with InsideMan embedded can be fuzzed.
