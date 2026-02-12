---
date: 2026-02-12T19:35:11Z
researcher: Claude
git_commit: f032d9d31ba8d4349915770d120770744bafb536
branch: RoyalPineapple/heist-rebrand
repository: accra
topic: "Could ButtonHeist Be an MCP Server?"
tags: [research, codebase, mcp, protocol, integration, insideman, wheelman]
status: complete
last_updated: 2026-02-12
last_updated_by: Claude
---

# Research: Could ButtonHeist Be an MCP Server?

**Date**: 2026-02-12T19:35:11Z
**Researcher**: Claude
**Git Commit**: f032d9d31ba8d4349915770d120770744bafb536
**Branch**: RoyalPineapple/heist-rebrand
**Repository**: accra

## Research Question
Could ButtonHeist's capabilities be exposed as an MCP (Model Context Protocol) server?

## Summary

ButtonHeist's existing capabilities map cleanly onto MCP primitives. Its read operations (snapshots, screenshots) map to MCP **Resources**, and its write operations (actions, touch gestures) map to MCP **Tools**. There is an official Swift MCP SDK available (requires Swift 6.0+), and real-world precedent exists for hardware/device-control MCP servers. The main architectural consideration is that ButtonHeist currently runs on-device (InsideMan inside the iOS app), while an MCP server would need to run on the host Mac — meaning the MCP server would be a thin adapter wrapping the existing Wheelman client, not a replacement for InsideMan itself.

## Detailed Findings

### 1. How ButtonHeist Operations Map to MCP Primitives

#### MCP Tools (model-invoked actions)

Every interaction command in ButtonHeist maps directly to an MCP tool:

| Current ClientMessage | MCP Tool Name | Parameters |
|----------------------|---------------|------------|
| `activate(ActionTarget)` | `activate_element` | `identifier?: string, order?: int` |
| `increment(ActionTarget)` | `increment_element` | `identifier?: string, order?: int` |
| `decrement(ActionTarget)` | `decrement_element` | `identifier?: string, order?: int` |
| `performCustomAction(CustomActionTarget)` | `perform_custom_action` | `identifier?: string, order?: int, actionName: string` |
| `touchTap(TouchTapTarget)` | `tap` | `identifier?: string, order?: int, x?: number, y?: number` |
| `touchLongPress(LongPressTarget)` | `long_press` | `identifier?: string, order?: int, x?: number, y?: number, duration?: number` |
| `touchSwipe(SwipeTarget)` | `swipe` | `identifier?: string, startX?: number, startY?: number, endX?: number, endY?: number, direction?: string, distance?: number, duration?: number` |
| `touchDrag(DragTarget)` | `drag` | `identifier?: string, startX?: number, startY?: number, endX: number, endY: number, duration?: number` |
| `touchPinch(PinchTarget)` | `pinch` | `identifier?: string, centerX?: number, centerY?: number, scale: number, spread?: number, duration?: number` |
| `touchRotate(RotateTarget)` | `rotate` | `identifier?: string, centerX?: number, centerY?: number, angle: number, radius?: number, duration?: number` |
| `touchTwoFingerTap(TwoFingerTapTarget)` | `two_finger_tap` | `identifier?: string, centerX?: number, centerY?: number, spread?: number` |

All of these return `ActionResult { success, method, message }` which maps to MCP tool response content.

#### MCP Resources (data the model can read)

| Current Operation | MCP Resource URI | Content Type |
|------------------|-----------------|--------------|
| `requestSnapshot` → `Snapshot` | `buttonheist://device/snapshot` | JSON (elements array + tree) |
| `requestScreenshot` → `ScreenshotPayload` | `buttonheist://device/screenshot` | image/png (base64) |
| `ServerInfo` (auto on connect) | `buttonheist://device/info` | JSON (device name, screen size, app info) |

The subscription model (`subscribe` for auto-push on UI changes) maps to MCP's resource subscription mechanism, where clients can subscribe to resource updates.

#### MCP Prompts (optional, for common workflows)

| Potential Prompt | Description |
|-----------------|-------------|
| `inspect_element` | "Describe the UI element at [identifier/index]" |
| `find_element` | "Find an element matching [label/description]" |
| `navigate_to` | "Navigate to [screen/view] by tapping elements" |

### 2. Architecture: Where the MCP Server Would Live

```
Current Architecture:
  iOS Device                          Mac
  ┌─────────────┐                   ┌──────────────┐
  │ InsideMan   │ ◄──TCP/JSON──►    │ Wheelman     │
  │ (TCP server)│                   │ (client lib) │
  └─────────────┘                   ├──────────────┤
                                    │ CLI / GUI    │
                                    └──────────────┘

With MCP Server:
  iOS Device                          Mac
  ┌─────────────┐                   ┌──────────────────┐
  │ InsideMan   │ ◄──TCP/JSON──►    │ MCP Server       │
  │ (unchanged) │                   │ ┌──────────────┐ │
  └─────────────┘                   │ │ Wheelman     │ │    ┌──────────┐
                                    │ │ (client lib) │ │◄──►│ Claude / │
                                    │ └──────────────┘ │    │ AI Agent │
                                    └──────────────────┘    └──────────┘
```

The MCP server runs on the Mac as a **wrapper around the existing Wheelman client**. InsideMan on the iOS device stays unchanged. The MCP server would:
1. Accept MCP connections via stdio (launched by Claude Code / AI client)
2. Internally create a Wheelman instance to connect to the iOS device
3. Translate MCP tool calls → ClientMessage → send to InsideMan
4. Translate ServerMessage responses → MCP tool results / resource content

### 3. Swift MCP SDK

An official Swift SDK exists: [github.com/modelcontextprotocol/swift-sdk](https://github.com/modelcontextprotocol/swift-sdk)

- Requires Swift 6.0+ (Xcode 16+)
- Supports stdio transport (ideal for local tool integration with Claude Code)
- Supports HTTP+SSE transport
- Implements MCP spec version 2025-03-26
- Provides both client and server components

Basic server setup:
```swift
let server = Server(
    name: "ButtonHeist MCP",
    version: "1.0.0",
    capabilities: .init(tools: .init(listChanged: false), resources: .init(subscribe: true))
)
let transport = StdioTransport()
try await server.start(transport: transport)
```

### 4. Precedent: Device-Control MCP Servers

Several MCP servers exist that expose hardware/device control:
- **UnitMCP**: Raspberry Pi GPIO control (LEDs, buttons, sensors)
- **serial-mcp-server**: Bridge between serial port devices (Arduino, ESP32) and AI models
- **Pi-Controller MCP**: Manages Raspberry Pi clusters via AI assistants
- **mcp2serial**: Serial port read/write for hardware interaction

These follow the same pattern: a host-side MCP server that bridges between the MCP protocol and a device-specific communication channel.

### 5. Current State: No MCP Integration Exists

- No references to MCP, Model Context Protocol, or JSON-RPC in the codebase
- No MCP SDK in any Package.swift dependency list
- No stdio-based protocol server patterns
- The existing protocol is custom TCP with newline-delimited JSON (not JSON-RPC 2.0)

### 6. Key Architectural Considerations

**Transport**: MCP typically uses stdio (client launches server as subprocess). The MCP server would be a separate Mac-side executable that internally uses Wheelman to connect to the iOS device. This is different from the current TCP server model where InsideMan listens for connections.

**Statefulness**: ButtonHeist's subscription model (subscribe → receive streaming updates) is stateful. MCP supports stateful connections with resource subscriptions, so this maps naturally.

**Connection lifecycle**: The MCP server would need to handle device discovery and connection as part of its initialization, since the AI client won't know about Bonjour. The server could auto-discover the first available device on startup, or expose a `connect_device` tool.

**Binary data**: Screenshots are base64-encoded PNG. MCP supports both text and binary (base64) content in tool responses, so screenshots can be returned as image content blocks.

**Latency**: Adding MCP as a layer adds one more hop (AI → MCP server → Wheelman → InsideMan → iOS). For interactive gestures this is negligible since the bottleneck is the gesture animation duration (0.15s–0.5s), not protocol overhead.

## Code References

- `ButtonHeist/Sources/TheGoods/Messages.swift:12-64` — ClientMessage enum (maps to MCP tools)
- `ButtonHeist/Sources/TheGoods/Messages.swift:277-295` — ServerMessage enum (maps to MCP tool responses / resources)
- `ButtonHeist/Sources/TheGoods/Messages.swift:69-268` — Target structs (map to MCP tool input schemas)
- `ButtonHeist/Sources/Wheelman/Wheelman.swift:192-219` — send() and waitForActionResult() (the API the MCP server would wrap)
- `ButtonHeist/Sources/Wheelman/DeviceConnection.swift:146-162` — Socket transmission (unchanged, internal to Wheelman)
- `ButtonHeistCLI/Sources/ActionCommand.swift` — Existing CLI pattern for actions (reference for MCP tool implementation)
- `ButtonHeistCLI/Sources/TouchCommand.swift` — Existing CLI pattern for touch gestures
- `docs/WIRE-PROTOCOL.md` — Wire protocol documentation
- `docs/API.md` — Public API documentation

## Architecture Documentation

### Current Protocol Stack
```
AI Agent → (manual CLI invocation) → ButtonHeist CLI → Wheelman → TCP/JSON → InsideMan → iOS UIKit
```

### Proposed MCP Protocol Stack
```
AI Agent → (MCP/stdio) → MCP Server → Wheelman → TCP/JSON → InsideMan → iOS UIKit
```

The MCP server is a thin translation layer. All existing components remain unchanged. The MCP server is a new Mac-side executable in the workspace, likely a new Swift package target that depends on Wheelman and the Swift MCP SDK.

## Related Research

- `thoughts/shared/research/2026-02-12-insideman-element-interactions.md` — Full interaction system documentation
- `thoughts/shared/research/2026-02-12-external-api-surface-review.md` — External API surface review

## Open Questions

- Should the MCP server auto-discover and connect to the first device, or expose device management as tools?
- Should screenshots be returned as base64 image content blocks or as resource URIs?
- Should the subscription/streaming model be exposed, or should each snapshot/screenshot be a one-shot resource read?
- Would this be a standalone executable or integrated into the existing ButtonHeistCLI?
