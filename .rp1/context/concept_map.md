# ButtonHeist - Concept Map

> Generated: 2025-03-10 | Commit: ee2a60b | Strategy: parallel-map-reduce (incremental)

## Core Concepts

### Product

- **Button Heist**: Remote iOS UI automation system structured as a heist crew metaphor. An iOS framework embeds inside a target app as a TCP server, while macOS tooling discovers, connects, and sends commands to interact with the app's UI programmatically.

### Crew Members (Components)

| Crew Member | Role | Side | Description |
|------------|------|------|-------------|
| **TheScore** | The Plan | Shared | Cross-platform wire protocol types. 29 client messages, 15 server messages, element models, action results. The contract between iOS and macOS. |
| **TheInsideJob** | Inside Operative | iOS | TCP server singleton (@MainActor). Manages server lifecycle, accessibility polling, app lifecycle. Dispatch logic split into TheInsideJob+Dispatch.swift with three-stage routing. |
| **TheSafecracker** | Specialist | iOS | Synthetic touch/input engine. Split into 7 files by concern. Multi-touch gestures (pinch, rotate, two-finger tap) in TheSafecracker+MultiTouch.swift. Text input via UIKeyboardImpl. |
| **TheBagman** | Score Handler | iOS | Element cache and UI observer. Conversion logic (element/tree/delta) split into TheBagman+Conversion.swift. Computes InterfaceDelta diffs, captures screenshots. |
| **TheMuscle** | Bouncer | iOS | Auth and session management. Token validation, UI approval (Allow/Deny), session locking (one driver at a time with timeout), observer tracking. |
| **TheStakeout** | Lookout | iOS | Screen recording engine. H.264/MP4 via AVAssetWriter. Configurable FPS, scale, inactivity timeout, file size limits. Tracks interaction events. |
| **TheFingerprints** | Evidence | iOS | Visual touch indicators. Translucent circles on a passthrough overlay window. |
| **ThePlant** | Advance Man | iOS | ObjC +load hook that auto-starts TheInsideJob on framework load (DEBUG only). |
| **TheMastermind** | Coordinator | macOS | Observable client API wrapping TheHandoff. @Observable state for SwiftUI, async waitFor* methods with request-ID correlation. |
| **TheFence** | Fence/Dealer | macOS | Centralized command dispatch facade. Split into TheFence.swift (core), TheFence+Handlers.swift (command handlers), TheFence+Formatting.swift (FenceResponse + output). |
| **TheHandoff** | Handoff | macOS | Client-side session manager. Bonjour discovery, TCP connection, keepalive (ping 3s), auto-reconnect (60 attempts at 1s). |
| **TheGetaway** | Escape Vehicle | Shared | TCP server/client transport and Bonjour advertisement. SimpleSocketServer with rate limiting and auth gating. |

### Data Types

| Type | Description |
|------|-------------|
| **HeistElement** | Wire-friendly UI element: order, label, value, identifier, traits, frame, activation point, actions |
| **Interface** | Timestamped snapshot of complete UI hierarchy (flat list + optional tree) |
| **InterfaceDelta** | Compact diff: noChange, valuesChanged, elementsChanged, or screenChanged |
| **ActionResult** | Result with success/failure, method used (18 cases), message, delta, animation status |
| **ActionTarget** | Element targeting by accessibility identifier (string) or traversal order (int) |
| **InteractionEvent** | Record of single interaction during recording: timestamp, command, result, delta |
| **FenceResponse** | Typed response enum (in TheFence+Formatting.swift) with humanFormatted() and jsonDict() output methods |
| **DiscoveredDevice** | Discovered iOS device: service name, endpoint, simulator UDID, installation ID, session status |

## Terminology

| Term | Definition |
|------|-----------|
| **Wire Protocol** | Newline-delimited JSON over TCP (v4.0). RequestEnvelope/ResponseEnvelope for request-response correlation via requestId. Service: `_buttonheist._tcp`. |
| **ActionTarget** | Element targeting by accessibility identifier or traversal order (0-based index). |
| **Session Lock** | Exclusive driver access. One driver identity controls the app at a time. Auto-releases after 30s inactivity on disconnect. |
| **Watch Mode** | Read-only observer connections. Auto-subscribed to broadcasts, cannot send commands or claim sessions. |
| **Activation-First Pattern** | Try accessibilityActivate() first, fall back to synthetic tap at activation point. |
| **Synthetic Touch Injection** | IOKit HID events + private UIKit APIs for programmatic touch synthesis (based on KIF). |
| **PerformInteraction Pipeline** | Standard flow: refresh -> snapshot before -> execute -> snapshot after -> compute delta -> respond. |
| **Three-Stage Dispatch** | TheInsideJob routes interaction messages through three dispatch methods: accessibility, touch, then text/scroll. Each returns Bool; first match wins. |
| **UI Approval** | On-device Allow/Deny UIAlertController prompt for tokenless client connections. |
| **Keepalive** | Client sends ping every 3s. Server responds with pong. Prevents session timeout. |
| **Hierarchy Hash Polling** | Server polls accessibility hierarchy at configurable intervals (default 1s), broadcasts only when hash changes. |
| **Debounced Broadcast** | Accessibility notifications trigger hierarchy update after 300ms debounce. |

## Relationships

```
TheFence → TheFence+Handlers (command dispatch)
         → TheFence+Formatting (response output)
         → TheMastermind → TheHandoff → DeviceDiscovery
                                      → DeviceConnection ←TCP→ SimpleSocketServer → TheInsideJob
                                                                                    → TheInsideJob+Dispatch
                                                                                    ├→ TheSafecracker → TheSafecracker+MultiTouch
                                                                                    │                 → TheFingerprints
                                                                                    │                 → TheBagman (target resolution)
                                                                                    ├→ TheBagman → TheBagman+Conversion
                                                                                    │            → AccessibilitySnapshotParser
                                                                                    ├→ TheMuscle
                                                                                    └→ TheStakeout

CLI → TheFence
MCP → TheFence
```

## Domain Boundaries

### 1. Wire Protocol (TheScore)
- **Scope**: Cross-platform shared module
- **Concepts**: ClientMessage (29 cases), ServerMessage (15 cases), HeistElement, Interface, InterfaceDelta, ActionResult
- **Boundary**: No UIKit/AppKit dependency. Consumed by both sides. Protocol v4.0.

### 2. iOS Server (TheInsideJob)
- **Scope**: iOS 17.0+, DEBUG builds, @MainActor
- **Concepts**: TheInsideJob, TheInsideJob+Dispatch, TheMuscle, TheSafecracker, TheSafecracker+MultiTouch, TheBagman, TheBagman+Conversion, TheStakeout, TheFingerprints, ThePlant
- **Boundary**: Runs inside target app. Owns TCP server, Bonjour, accessibility hierarchy, interaction execution.

### 3. macOS Client (ButtonHeist framework)
- **Scope**: macOS 14.0+, @ButtonHeistActor
- **Concepts**: TheFence, TheFence+Handlers, TheFence+Formatting, TheMastermind, TheHandoff, DeviceDiscovery, DeviceConnection, DiscoveredDevice
- **Boundary**: Discovery, connection management, command dispatch, response formatting.

### 4. CLI (ButtonHeistCLI)
- **Scope**: macOS command-line tool
- **Concepts**: CLI Commands (18 subcommands), REPL Session, ElementTargetOptions, OutputOptions
- **Boundary**: Thin interface over TheFence. Canonical test client.

### 5. MCP Server (ButtonHeistMCP)
- **Scope**: macOS MCP tool server
- **Concepts**: 14 MCP Tools, Tool Definitions
- **Boundary**: Maps MCP tool calls to TheFence. Omits large video data from responses.

## Cross-Cutting Concerns

| Concern | Approach |
|---------|----------|
| **Concurrency** | @MainActor (iOS), @ButtonHeistActor (macOS), async/await, CheckedContinuation for request-response |
| **Authentication** | Token-based with 3 modes: direct match, UI approval, observer auto-approve. Rate limiting 30 msg/s, max 5 connections. |
| **Error Handling** | Layered: FenceError (user-facing), ConnectionError (lifecycle), ActionError/RecordingError (async waits). Force-disconnect on timeout. |
| **Auto-Reconnect** | 60 attempts at 1s intervals on disconnect. Match by installation identity. |
| **Configuration** | Environment variables (highest priority) -> Info.plist keys (fallback). Both client and server sides. |
| **App Lifecycle** | TheInsideJob suspends on background, resumes on foreground. Prevents idle screen lock. |
| **Hierarchy Observation** | Notification-driven (300ms debounce) + polling (configurable interval, hash comparison). |
| **Extension-Based Organization** | Large types split into focused extension files (Type+Feature.swift) for maintainability without changing public API. |
