# ButtonHeist - Modules

> Generated: 2026-03-10 | Commit: 402d50e | Strategy: parallel-map-reduce (incremental)

## Module Overview

| Module | Type | Files | LOC | Purpose |
|--------|------|-------|-----|---------|
| TheScore | Framework | 4 | 1,111 | Shared wire protocol types and message definitions |
| TheButtonHeist | Framework | 12 | 2,769 | macOS client: TheFence (3 files), TheMastermind, TheHandoff (TLS-aware) |
| TheInsideJob | Framework | 19 | 4,460 | iOS server: accessibility, gestures, recording, auth, TLS config |
| *(Transport layer)* | *(merged)* | — | — | *TLS transport (TLSIdentity, ServerTransport, SimpleSocketServer) merged into TheInsideJob* |
| ButtonHeistCLI | Executable | 21 | 1,932 | CLI tool with 29 commands |
| ButtonHeistMCP | Executable | 2 | 470 | MCP server with 14 AI agent tools |
| TestApp | App | 28 | 1,954 | SwiftUI + UIKit demo apps |
| Tests | Test Suite | 22 | 3,397 | Unit and integration tests |

## Module Details

### TheScore (Shared Protocol)

**Purpose**: Cross-platform wire protocol types. No UIKit dependency. Consumed by both iOS server and macOS clients.

**Key Files**:
- `ButtonHeist/Sources/TheScore/ClientMessages.swift` - 29 client-to-server message cases
- `ButtonHeist/Sources/TheScore/ServerMessages.swift` - 15 server-to-client message cases, ServerInfo.tlsActive
- `ButtonHeist/Sources/TheScore/Elements.swift` - HeistElement, Interface, InterfaceDelta models
- `ButtonHeist/Sources/TheScore/Messages.swift` - RequestEnvelope, ResponseEnvelope, constants, protocolVersion 5.0

**Public API**: ClientMessage, ServerMessage, RequestEnvelope, ResponseEnvelope, HeistElement, Interface, ActionResult, InterfaceDelta, ActionTarget, ScreenPayload, RecordingPayload, ServerInfo (tlsActive), InteractionEvent, ElementAction, RecordingConfig, buttonHeistServiceType, protocolVersion

**Contracts**: All types Codable + Sendable. Protocol v5.0. Service type: `_buttonheist._tcp`.

---

### TheButtonHeist (macOS Client Framework)

**Purpose**: Client-side framework. TheFence split into 3 files (core, handlers, formatting). TheMastermind (Observable coordinator), TheHandoff (TLS-aware discovery + connection lifecycle), ButtonHeistActor.

**Key Files**:
- `ButtonHeist/Sources/TheButtonHeist/TheFence.swift` - Command dispatch core (~303 lines)
- `ButtonHeist/Sources/TheButtonHeist/TheFence+Handlers.swift` - Command handler methods (329 lines)
- `ButtonHeist/Sources/TheButtonHeist/TheFence+Formatting.swift` - FenceResponse enum + formatting (360 lines)
- `ButtonHeist/Sources/TheButtonHeist/TheFence+CommandCatalog.swift` - Command catalog + version
- `ButtonHeist/Sources/TheButtonHeist/TheMastermind.swift` - Observable session orchestrator
- `ButtonHeist/Sources/TheButtonHeist/TheHandoff/TheHandoff.swift` - Session lifecycle manager
- `ButtonHeist/Sources/TheButtonHeist/TheHandoff/DeviceConnection.swift` - TLS TCP client with fingerprint pinning
- `ButtonHeist/Sources/TheButtonHeist/TheHandoff/DeviceDiscovery.swift` - Bonjour discovery with certfp extraction
- `ButtonHeist/Sources/TheButtonHeist/TheHandoff/DiscoveredDevice.swift` - Device model with certFingerprint

**Components**:

| Component | Responsibility |
|-----------|---------------|
| **TheFence** | Core dispatch, connection management, sendAndAwait<T> pattern (~303 lines) |
| **TheFence+Handlers** | Command handler implementations for interface, screen, gestures, text, scroll, recording (329 lines) |
| **TheFence+Formatting** | FenceResponse enum with humanFormatted() and jsonDict() output (360 lines) |
| **CommandCatalog** | Canonical command list + version string (buttonHeistVersion). Source of truth for CLI/MCP. |
| **TheMastermind** | @Observable wrapper over TheHandoff. Async waitFor* methods with requestId correlation. Generic waitForResponse<T>. |
| **TheHandoff** | Device lifecycle: Bonjour discovery, TLS connect, keepalive (3s), auto-reconnect (60x1s). Persistent driver ID. |
| **DeviceDiscovery** | NWBrowser for `_buttonheist._tcp`. TXT record parsing including certfp extraction. DiscoveryRegistry deduplication. |
| **DeviceConnection** | TLS-encrypted NWConnection client. Fingerprint pinning via sec_protocol_options_set_verify_block. Refuses plain TCP. Auth handshake, NDJSON framing, 10MB buffer. DisconnectReason.certificateMismatch. |
| **DiscoveredDevice** | Device metadata: service name, endpoint, simulator UDID, installation ID, session status, certFingerprint (sha256:hex). |

**Public API**: TheFence, TheFence.Configuration, CommandCatalog, TheMastermind, TheHandoff, DeviceDiscovery, DeviceConnection, DiscoveredDevice (certFingerprint), FenceResponse, FenceError, ButtonHeistActor, DisconnectReason (certificateMismatch), buttonHeistVersion

**Dependencies**: TheScore (@_exported import), Crypto (swift-crypto)

---

### TheInsideJob (iOS Server Framework)

**Purpose**: iOS-side server embedded in target apps. Creates TLSIdentity on start, configures TLS-encrypted transport. Dispatch extracted to TheInsideJob+Dispatch.swift. TheSafecracker split into 7 files. TheBagman conversion extracted. DEBUG builds only.

**Key Files**:
- `ButtonHeist/Sources/TheInsideJob/TheInsideJob.swift` - Server singleton, lifecycle, TLS identity creation (~547 lines)
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
| **TheInsideJob** | Singleton coordinator. Creates TLSIdentity (persistent or ephemeral), initializes ServerTransport with TLS, tracks tlsActive, handles suspend/resume. |
| **TheInsideJob+Dispatch** | Three-stage dispatch routing: accessibility -> touch -> text/scroll. |
| **TheSafecracker** | Core touch infrastructure (7 files total). |
| **TheSafecracker+MultiTouch** | Pinch, rotate, two-finger tap via IOKit HID. |
| **TheBagman** | Accessibility parsing, weak NSObject refs, animation detection, screenshot capture. |
| **TheBagman+Conversion** | Element conversion, trait mapping, InterfaceDelta computation. |
| **TheMuscle** | Token validation, UI approval, session lock (one driver, 30s timeout), observer management. Auth after TLS handshake. |
| **TheStakeout** | AVAssetWriter H.264/MP4. Configurable FPS/scale. File size limit (7MB). Interaction event log. |
| **TheFingerprints** | Translucent touch circles on passthrough FingerprintWindow. |

**Public API**: TheInsideJob (configure, start, stop, notifyChange, startPolling, stopPolling)

**Dependencies**: TheScore, AccessibilitySnapshotParser, X509, Crypto, SwiftASN1

---

### Transport Layer (in TheInsideJob)

**Purpose**: Server-side networking with TLS encryption. TCP server + Bonjour advertisement + TLS identity management. Formerly a separate module (TheGetaway), now merged into TheInsideJob.

**Key Files**:
- `ButtonHeist/Sources/TheInsideJob/TLSIdentity.swift` - Self-signed cert generation, Keychain persistence, fingerprint computation, certificate expiry tracking
- `ButtonHeist/Sources/TheInsideJob/ServerTransport.swift` - TCP + TLS + Bonjour wrapper, publishes certfp in TXT record
- `ButtonHeist/Sources/TheInsideJob/SimpleSocketServer.swift` - Actor-isolated NWListener with TLS parameter support

**Components**:

| Component | Responsibility |
|-----------|---------------|
| **TLSIdentity** | Actor: ECDSA P-256 X.509 cert generation, Keychain getOrCreate, ephemeral fallback, SHA-256 fingerprint, NWParameters for TLS 1.3, certificate expiry tracking with auto-renewal. |
| **ServerTransport** | Combined TCP + TLS + Bonjour. Injects TLSIdentity NWParameters into SimpleSocketServer. Publishes certfp and transport=tls in Bonjour TXT record. |
| **SimpleSocketServer** | NWListener actor. Max 5 connections, NDJSON framing, 30 msg/s rate limit, auth gating, 10MB buffer. Accepts optional TLS NWParameters. |

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

**Purpose**: Unit and integration tests across all framework modules. 22 files.

**Test Suites**:
- `TheScoreTests` - Protocol encoding/decoding, element data, payloads, constants
- `ButtonHeistTests` - TheFence dispatch, TheMastermind state, session locking, auth flows, discovery dedup, TLS connection tests
- `TheInsideJobTests` - TheMuscle auth, bezier sampling, TLS identity tests, TLS integration tests

**Key Files**:
- `ButtonHeist/Tests/TheScoreTests/TheScoreTests.swift`
- `ButtonHeist/Tests/TheScoreTests/ConstantsTests.swift`
- `ButtonHeist/Tests/ButtonHeistTests/TheFenceTests.swift`
- `ButtonHeist/Tests/ButtonHeistTests/TheMastermindTests.swift`
- `ButtonHeist/Tests/ButtonHeistTests/AuthFailureTests.swift` - Refactored to use direct message injection
- `ButtonHeist/Tests/ButtonHeistTests/AuthFlowIntegrationTests.swift`
- `ButtonHeist/Tests/ButtonHeistTests/DeviceConnectionTLSTests.swift` - TLS disconnect reasons and fingerprint handling
- `ButtonHeist/Tests/ButtonHeistTests/DiscoveredDeviceTests.swift`
- `ButtonHeist/Tests/ButtonHeistTests/SessionLockTests.swift`
- `ButtonHeist/Tests/TheInsideJobTests/TheMuscleTests.swift`
- `ButtonHeist/Tests/TheInsideJobTests/TLSIdentityTests.swift` - Cert generation, fingerprint format, Keychain round-trip
- `ButtonHeist/Tests/TheInsideJobTests/TLSIntegrationTests.swift` - Real TLS handshake, data exchange, wrong-fingerprint rejection

## Dependency Graph

```
TheScore (shared, no dependencies)
  ↑
TheInsideJob (imports TheScore, X509, Crypto, SwiftASN1, AccessibilitySnapshotParser)

TheScore (shared)
  ↑
TheButtonHeist (@_exported TheScore, imports Crypto)
  ↑
ButtonHeistCLI (imports TheButtonHeist + ArgumentParser)
ButtonHeistMCP (imports TheButtonHeist + MCP)

TestApp (embeds TheInsideJob + TheScore)
```

## Cross-Module Patterns

| Pattern | Description | Modules |
|---------|-------------|---------|
| **TLS Transport Encryption** | End-to-end TLS 1.3 with self-signed ECDSA P-256 certificates and SHA-256 fingerprint pinning via Bonjour TXT records. No CA required. | TheInsideJob, TheButtonHeist, TheScore |
| **Heist Crew Metaphor** | Every component named after a heist role | All |
| **Extension-Based File Splitting** | Large files decomposed into Type+Concern.swift extensions (TheFence 3 files, TheInsideJob 2, TheSafecracker 7, TheBagman 2) | TheButtonHeist, TheInsideJob |
| **Protocol Symmetry** | TheScore types used identically on both sides | TheScore, TheButtonHeist, TheInsideJob |
| **Layered Command Dispatch** | CLI/MCP -> TheFence -> TheMastermind -> TLS/TCP -> TheInsideJob | All |
| **Interaction Pipeline** | Refresh -> snapshot -> execute -> delta -> respond | TheInsideJob, TheSafecracker, TheBagman |
| **Three-Stage Dispatch** | Accessibility -> touch -> text/scroll routing chain | TheInsideJob |
| **Request-ID Correlation** | UUID requestIds threaded through envelopes for multiplexed responses | TheButtonHeist, TheScore, TheInsideJob |
| **Dual Client Architecture** | CLI + MCP both wrap TheFence with same CommandCatalog | ButtonHeistCLI, ButtonHeistMCP, TheButtonHeist |
| **Global Actor Isolation** | @ButtonHeistActor (macOS), @MainActor (iOS), actor (SimpleSocketServer, TLSIdentity) | All |
| **Warnings-as-Errors** | All SPM targets enforce zero-warning build policy | All |
