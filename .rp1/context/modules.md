# ButtonHeist - Modules

> Generated: 2025-03-10 | Commit: ee2a60b | Strategy: parallel-map-reduce (incremental)

## Module Overview

| Module | Type | Files | LOC | Purpose |
|--------|------|-------|-----|---------|
| TheScore | Framework | 4 | 1,107 | Shared wire protocol types and message definitions |
| TheButtonHeist | Framework | 12 | 2,713 | macOS client: TheFence (3 files), TheMastermind, TheHandoff |
| TheInsideJob | Framework | 19 | 4,421 | iOS server: accessibility, gestures, recording, auth |
| TheGetaway | Framework | 2 | 565 | TCP server/client transport and Bonjour |
| ButtonHeistCLI | Executable | 21 | 1,932 | CLI tool with 29 commands |
| ButtonHeistMCP | Executable | 2 | 470 | MCP server with 14 AI agent tools |
| TestApp | App | 28 | 1,954 | SwiftUI + UIKit demo apps |
| Tests | Test Suite | 19 | 3,411 | Unit and integration tests |

## Module Details

### TheScore (Shared Protocol)

**Purpose**: Cross-platform wire protocol types. No UIKit dependency. Consumed by both iOS server and macOS clients.

**Key Files**:
- `ButtonHeist/Sources/TheScore/ClientMessages.swift` - 29 client-to-server message cases
- `ButtonHeist/Sources/TheScore/ServerMessages.swift` - 15 server-to-client message cases
- `ButtonHeist/Sources/TheScore/Elements.swift` - HeistElement, Interface, InterfaceDelta models
- `ButtonHeist/Sources/TheScore/Messages.swift` - RequestEnvelope, ResponseEnvelope, constants

**Public API**: ClientMessage, ServerMessage, RequestEnvelope, ResponseEnvelope, HeistElement, Interface, ActionResult, InterfaceDelta, ActionTarget, ScreenPayload, RecordingPayload, ServerInfo, InteractionEvent, ElementAction, RecordingConfig, buttonHeistServiceType, protocolVersion

**Contracts**: All types Codable + Sendable. Protocol v4.0. Service type: `_buttonheist._tcp`.

---

### TheButtonHeist (macOS Client Framework)

**Purpose**: Client-side framework. TheFence split into 3 files (core, handlers, formatting). TheMastermind (Observable coordinator), TheHandoff (discovery + connection lifecycle), ButtonHeistActor.

**Key Files**:
- `ButtonHeist/Sources/TheButtonHeist/TheFence.swift` - Command dispatch core (~303 lines)
- `ButtonHeist/Sources/TheButtonHeist/TheFence+Handlers.swift` - Command handler methods (329 lines)
- `ButtonHeist/Sources/TheButtonHeist/TheFence+Formatting.swift` - FenceResponse enum + formatting (360 lines)
- `ButtonHeist/Sources/TheButtonHeist/TheFence+CommandCatalog.swift` - Command catalog + version
- `ButtonHeist/Sources/TheButtonHeist/TheMastermind.swift` - Observable session orchestrator
- `ButtonHeist/Sources/TheButtonHeist/TheHandoff/TheHandoff.swift` - Session lifecycle manager
- `ButtonHeist/Sources/TheButtonHeist/TheHandoff/DeviceConnection.swift` - TCP client

**Components**:

| Component | Responsibility |
|-----------|---------------|
| **TheFence** | Core dispatch, connection management, sendAndAwait<T> pattern (~303 lines) |
| **TheFence+Handlers** | Command handler implementations for interface, screen, gestures, text, scroll, recording (329 lines) |
| **TheFence+Formatting** | FenceResponse enum with humanFormatted() and jsonDict() output (360 lines) |
| **CommandCatalog** | Canonical command list + version string (buttonHeistVersion). Source of truth for CLI/MCP. |
| **TheMastermind** | @Observable wrapper over TheHandoff. Async waitFor* methods with requestId correlation. Generic waitForResponse<T>. |
| **TheHandoff** | Device lifecycle: Bonjour discovery, TCP connect, keepalive (3s), auto-reconnect (60x1s). Persistent driver ID. |
| **DeviceDiscovery** | NWBrowser for `_buttonheist._tcp`. TXT record parsing. DiscoveryRegistry deduplication. |
| **DeviceConnection** | NWConnection TCP client. Auth handshake, NDJSON framing, 10MB buffer limit. |

**Public API**: TheFence, TheFence.Configuration, CommandCatalog, TheMastermind, TheHandoff, DeviceDiscovery, DeviceConnection, DiscoveredDevice, FenceResponse, FenceError, ButtonHeistActor, DisconnectReason, buttonHeistVersion

**Dependencies**: TheScore (@_exported import)

---

### TheInsideJob (iOS Server Framework)

**Purpose**: iOS-side server embedded in target apps. Dispatch extracted to TheInsideJob+Dispatch.swift. TheSafecracker split into 7 files. TheBagman conversion extracted. DEBUG builds only.

**Key Files**:
- `ButtonHeist/Sources/TheInsideJob/TheInsideJob.swift` - Server singleton, lifecycle (~547 lines)
- `ButtonHeist/Sources/TheInsideJob/TheInsideJob+Dispatch.swift` - Three-stage message dispatch (121 lines)
- `ButtonHeist/Sources/TheInsideJob/TheSafecracker/TheSafecracker.swift` - Touch injection core (~498 lines)
- `ButtonHeist/Sources/TheInsideJob/TheSafecracker/TheSafecracker+Actions.swift` - Action implementations
- `ButtonHeist/Sources/TheInsideJob/TheSafecracker/TheSafecracker+MultiTouch.swift` - Pinch, rotate, two-finger tap (119 lines)
- `ButtonHeist/Sources/TheInsideJob/TheSafecracker/TheSafecracker+TextEntry.swift` - Text input
- `ButtonHeist/Sources/TheInsideJob/TheSafecracker/TheSafecracker+IOHIDEventBuilder.swift` - HID events
- `ButtonHeist/Sources/TheInsideJob/TheBagman.swift` - Element cache, delta, screenshots (~421 lines)
- `ButtonHeist/Sources/TheInsideJob/TheBagman+Conversion.swift` - Element/tree/delta conversion (267 lines)
- `ButtonHeist/Sources/TheInsideJob/TheMuscle.swift` - Auth, sessions, client tracking
- `ButtonHeist/Sources/TheInsideJob/TheStakeout.swift` - Screen recording (H.264/MP4)
- `ButtonHeist/Sources/TheInsideJob/TheFingerprints.swift` - Visual touch indicators

**Components**:

| Component | Responsibility |
|-----------|---------------|
| **TheInsideJob** | Singleton coordinator. TCP server, Bonjour, app lifecycle. |
| **TheInsideJob+Dispatch** | Three-stage dispatch routing: accessibility -> touch -> text/scroll. |
| **TheSafecracker** | Core touch infrastructure (7 files total). |
| **TheSafecracker+MultiTouch** | Pinch, rotate, two-finger tap via IOKit HID. |
| **TheBagman** | Accessibility parsing, weak NSObject refs, animation detection, screenshot capture. |
| **TheBagman+Conversion** | Element conversion, trait mapping, InterfaceDelta computation. |
| **TheMuscle** | Token validation, UI approval, session lock (one driver, 30s timeout), observer management. |
| **TheStakeout** | AVAssetWriter H.264/MP4. Configurable FPS/scale. File size limit (7MB). Interaction event log. |
| **TheFingerprints** | Translucent touch circles on passthrough FingerprintWindow. |

**Public API**: TheInsideJob (configure, start, stop, notifyChange, startPolling, stopPolling)

**Dependencies**: TheScore, TheGetaway, AccessibilitySnapshotParser

---

### TheGetaway (Transport Layer)

**Purpose**: Server-side networking. TCP server + Bonjour advertisement. Used exclusively by TheInsideJob.

**Key Files**:
- `ButtonHeist/Sources/TheGetaway/ServerTransport.swift` - TCP + Bonjour wrapper
- `ButtonHeist/Sources/TheGetaway/SimpleSocketServer.swift` - Actor-isolated NWListener

**Components**:

| Component | Responsibility |
|-----------|---------------|
| **ServerTransport** | Combined TCP + Bonjour. Start/stop server, manage NetService, forward callbacks. |
| **SimpleSocketServer** | NWListener actor. Max 5 connections, NDJSON framing, 30 msg/s rate limit, auth gating, 10MB buffer. |

**Dependencies**: TheScore (buttonHeistServiceType)

---

### ButtonHeistCLI (CLI Tool)

**Purpose**: Command-line client using ArgumentParser. 18 subcommands + persistent REPL session mode. Canonical test client.

**Key Files**:
- `ButtonHeistCLI/Sources/Support/main.swift` - Entry point, command hierarchy
- `ButtonHeistCLI/Sources/Session/SessionCommand.swift` - Session command
- `ButtonHeistCLI/Sources/Session/SessionRepl.swift` - Interactive REPL
- `ButtonHeistCLI/Sources/Support/DeviceConnector.swift` - Connection helper
- `ButtonHeistCLI/Sources/Support/ElementTargetOptions.swift` - Shared --identifier/--index options
- `ButtonHeistCLI/Sources/Support/OutputOptions.swift` - Shared --format option

**Commands**: activate, list, action, scroll, scroll-to-visible, scroll-to-edge, touch, type, screenshot, session, record, stop-recording, copy, paste, cut, select, select-all, dismiss-keyboard

**Dependencies**: TheButtonHeist (TheFence), ArgumentParser

---

### ButtonHeistMCP (MCP Server)

**Purpose**: MCP server exposing 14 tools for AI agent interaction. Thin wrapper over TheFence with idle timeout.

**Key Files**:
- `ButtonHeistMCP/Sources/ToolDefinitions.swift` - 14 MCP tool definitions
- `ButtonHeistMCP/Sources/main.swift` - Server entry point, tool dispatch

**Tools**: get_interface, activate, type_text, swipe, get_screen, wait_for_idle, start_recording, stop_recording, list_devices, gesture, accessibility_action, scroll, scroll_to_visible, scroll_to_edge

**Dependencies**: TheButtonHeist (TheFence), MCP swift-sdk

---

### TestApp (Demo Apps)

**Purpose**: SwiftUI AccessibilityTestApp + UIKit UIKitTestApp embedding TheInsideJob for end-to-end testing.

**Key Files**:
- `TestApp/Sources/AccessibilityTestApp.swift` - SwiftUI app entry
- `TestApp/Sources/RootView.swift` - Root navigation
- `TestApp/UIKitSources/AppDelegate.swift` - UIKit app delegate
- `TestApp/Project.swift` - Tuist project definition

**Demo Views**: Calculator, TodoList, Settings, TouchCanvas, TextInput, Alerts/Sheets, Controls, LongList, CornerScroll, Display, Adjustable, DisclosureGrouping, TogglePicker, Notes, ButtonsActions

**Dependencies**: TheInsideJob, TheScore

---

### Tests

**Purpose**: Unit and integration tests across all framework modules.

**Test Suites**:
- `TheScoreTests` - Protocol encoding/decoding, element data, payloads, constants
- `ButtonHeistTests` - TheFence dispatch, TheMastermind state, session locking, auth flows, discovery dedup
- `TheInsideJobTests` - TheMuscle auth, bezier sampling

**Key Files**:
- `ButtonHeist/Tests/TheScoreTests/TheScoreTests.swift`
- `ButtonHeist/Tests/ButtonHeistTests/TheFenceTests.swift`
- `ButtonHeist/Tests/ButtonHeistTests/TheMastermindTests.swift`
- `ButtonHeist/Tests/ButtonHeistTests/AuthFailureTests.swift`
- `ButtonHeist/Tests/ButtonHeistTests/AuthFlowIntegrationTests.swift`
- `ButtonHeist/Tests/TheInsideJobTests/TheMuscleTests.swift`

## Dependency Graph

```
TheScore (shared, no dependencies)
  ↑
TheGetaway (imports TheScore)
  ↑
TheInsideJob (imports TheScore, TheGetaway, AccessibilitySnapshotParser)

TheScore (shared)
  ↑
TheButtonHeist (@_exported TheScore)
  ↑
ButtonHeistCLI (imports TheButtonHeist + ArgumentParser)
ButtonHeistMCP (imports TheButtonHeist + MCP)

TestApp (embeds TheInsideJob + TheScore)
```

## Cross-Module Patterns

| Pattern | Description | Modules |
|---------|-------------|---------|
| **Heist Crew Metaphor** | Every component named after a heist role | All |
| **Extension-Based File Splitting** | Large files decomposed into Type+Concern.swift extensions (TheFence 3 files, TheInsideJob 2, TheSafecracker 7, TheBagman 2) | TheButtonHeist, TheInsideJob |
| **Protocol Symmetry** | TheScore types used identically on both sides | TheScore, TheButtonHeist, TheInsideJob |
| **Layered Command Dispatch** | CLI/MCP -> TheFence -> TheMastermind -> TCP -> TheInsideJob | All |
| **Interaction Pipeline** | Refresh -> snapshot -> execute -> delta -> respond | TheInsideJob, TheSafecracker, TheBagman |
| **Three-Stage Dispatch** | Accessibility -> touch -> text/scroll routing chain | TheInsideJob |
| **Request-ID Correlation** | UUID requestIds threaded through envelopes for multiplexed responses | TheButtonHeist, TheScore, TheInsideJob |
| **Dual Client Architecture** | CLI + MCP both wrap TheFence with same CommandCatalog | ButtonHeistCLI, ButtonHeistMCP, TheButtonHeist |
| **Global Actor Isolation** | @ButtonHeistActor (macOS), @MainActor (iOS), actor (SimpleSocketServer) | All |
| **Warnings-as-Errors** | All SPM targets enforce zero-warning build policy | All |
