# ButtonHeist MCP Server Implementation Plan

## Overview

Build an MCP (Model Context Protocol) server that wraps the existing HeistClient, enabling Claude and other AI agents to discover, inspect, and interact with iOS apps through standard MCP tools. The server runs on macOS, connects to an iOS device/simulator via the existing ButtonHeist protocol, and exposes all capabilities as MCP tools over stdio.

## Current State Analysis

- `HeistClient` (`ButtonHeist/Sources/ButtonHeist/HeistClient.swift`) provides the full Mac-side API: discovery, connection, `send()`, `waitForActionResult()`, `waitForScreenshot()`
- `TheGoods/Messages.swift` defines all `ClientMessage` and `ServerMessage` types
- `ButtonHeistCLI/` demonstrates the pattern: create HeistClient, discover, connect, send commands, read results
- No MCP integration exists in the codebase today
- Official Swift MCP SDK available at `github.com/modelcontextprotocol/swift-sdk`

### Key Discoveries:
- HeistClient is `@MainActor` — MCP server needs to run on main actor or bridge calls
- Swift MCP SDK requires Swift 6.0+ — new package can declare its own tools version
- Screenshots are already base64 PNG — maps directly to MCP `.image()` content
- HeistClient auto-sends `subscribe`, `requestSnapshot`, `requestScreenshot` on connect

## Desired End State

A working `buttonheist-mcp` executable that:
1. Auto-discovers and connects to the first available iOS device running InsideMan
2. Exposes MCP tools for reading UI state (snapshot, screenshot) and performing interactions (tap, swipe, etc.)
3. Can be configured in Claude Code's `.mcp.json` and used to drive any iOS app

Verification: Build the executable, configure it in MCP settings, and have Claude use it to read a snapshot and tap an element.

## What We're NOT Doing

- Not replacing or modifying the CLI, InsideMan, or Wheelman
- Not implementing MCP Resources or Prompts (tools only for now)
- Not adding multi-device selection (auto-connects to first device)
- Not adding HTTP/SSE transport (stdio only)

## Implementation Approach

New Swift package `ButtonHeistMCP/` at workspace root, alongside `ButtonHeistCLI/`. Depends on `ButtonHeist` (which re-exports `TheGoods` + `Wheelman`) and the Swift MCP SDK. Single executable target.

---

## Phase 1: Package Scaffolding & Device Connection

### Overview
Create the package, establish MCP server startup, and connect to an iOS device.

### Changes Required:

#### 1. Package.swift
**File**: `ButtonHeistMCP/Package.swift`

Create new Swift package with MCP SDK dependency.

#### 2. Entry point with device connection
**File**: `ButtonHeistMCP/Sources/main.swift`

Create entry point that:
- Creates HeistClient
- Starts Bonjour discovery
- Waits for and connects to first device
- Creates MCP Server with tool capabilities
- Starts StdioTransport and waits

### Success Criteria:

#### Automated Verification:
- [x] Package resolves dependencies: `cd ButtonHeistMCP && swift package resolve`
- [x] Package builds: `cd ButtonHeistMCP && swift build`
- [x] Binary exists and runs (exits cleanly when no device available)

---

## Phase 2: Read Tools (Snapshot + Screenshot)

### Overview
Implement `get_snapshot` and `get_screenshot` tools so Claude can see the UI.

### Changes Required:

#### 1. get_snapshot tool
Returns the current UI element hierarchy as JSON. Each element includes order, label, value, identifier, frame, and available actions.

#### 2. get_screenshot tool
Returns a PNG screenshot as an MCP image content block.

### Success Criteria:

#### Automated Verification:
- [x] Builds cleanly: `cd ButtonHeistMCP && swift build`
- [x] Tool definitions include correct input schemas

---

## Phase 3: Interaction Tools

### Overview
Implement all interaction tools: tap, long_press, swipe, drag, pinch, rotate, two_finger_tap, activate, increment, decrement, perform_custom_action.

### Changes Required:

#### 1. Touch gesture tools
Each tool accepts element targeting (identifier/order) OR screen coordinates, plus gesture-specific parameters.

#### 2. Accessibility action tools
Activate, increment, decrement target by identifier/order. Custom action adds actionName parameter.

### Success Criteria:

#### Automated Verification:
- [x] Builds cleanly: `cd ButtonHeistMCP && swift build`
- [x] All 13 tools defined with correct schemas

---

## Phase 4: MCP Configuration & End-to-End Test

### Overview
Wire the MCP server into Claude Code configuration and verify end-to-end.

### Changes Required:

#### 1. MCP configuration
**File**: `.mcp.json` at project root

#### 2. Build and test
Build release binary, configure path, verify Claude can discover tools.

### Success Criteria:

#### Automated Verification:
- [x] Release build succeeds: `cd ButtonHeistMCP && swift build -c release`
- [x] Binary exists at `ButtonHeistMCP/.build/release/buttonheist-mcp` (3.7MB)

#### Manual Verification:
- [ ] Claude Code shows buttonheist tools after configuration
- [ ] Claude can call get_snapshot and see UI elements
- [ ] Claude can call tap to interact with an element

---

## References

- Research: `thoughts/shared/research/2026-02-12-mcp-server-feasibility.md`
- Research: `thoughts/shared/research/2026-02-12-insideman-element-interactions.md`
- HeistClient API: `ButtonHeist/Sources/ButtonHeist/HeistClient.swift`
- Wire protocol types: `ButtonHeist/Sources/TheGoods/Messages.swift`
- CLI reference: `ButtonHeistCLI/Sources/`
- Swift MCP SDK: `https://github.com/modelcontextprotocol/swift-sdk`
