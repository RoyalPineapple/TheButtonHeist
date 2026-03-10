# ButtonHeist - Concept Map

> Generated: 2026-03-10 | Commit: 402d50e | Strategy: parallel-map-reduce (incremental)

## Core Concepts

### Product

- **Button Heist**: Remote iOS UI automation system structured as a heist crew metaphor. An iOS framework embeds inside a target app as a TLS-encrypted TCP server, while macOS tooling discovers, connects with certificate fingerprint pinning, and sends commands to interact with the app's UI programmatically.

### Crew Members (Components)

| Crew Member | Role | Side | Description |
|------------|------|------|-------------|
| **TheScore** | The Plan | Shared | Cross-platform wire protocol types. 29 client messages, 15 server messages, element models, action results. Protocol v5.0. ServerInfo includes tlsActive field. |
| **TheInsideJob** | Inside Operative | iOS | TCP server singleton (@MainActor). Creates TLSIdentity on start, manages server lifecycle, accessibility polling, app lifecycle. Dispatch logic split into TheInsideJob+Dispatch.swift with three-stage routing. |
| **TheSafecracker** | Specialist | iOS | Synthetic touch/input engine. Split into 7 files by concern. Multi-touch gestures (pinch, rotate, two-finger tap) in TheSafecracker+MultiTouch.swift. Text input via UIKeyboardImpl. |
| **TheBagman** | Score Handler | iOS | Element cache and UI observer. Conversion logic (element/tree/delta) split into TheBagman+Conversion.swift. Computes InterfaceDelta diffs, captures screenshots. |
| **TheMuscle** | Bouncer | iOS | Auth and session management. Token validation, UI approval (Allow/Deny), session locking (one driver at a time with timeout), observer tracking. Auth occurs after TLS handshake. |
| **TheStakeout** | Lookout | iOS | Screen recording engine. H.264/MP4 via AVAssetWriter. Configurable FPS, scale, inactivity timeout, file size limits. Tracks interaction events. |
| **TheFingerprints** | Evidence | iOS | Visual touch indicators. Translucent circles on a passthrough overlay window. |
| **ThePlant** | Advance Man | iOS | ObjC +load hook that auto-starts TheInsideJob on framework load (DEBUG only). |
| **TheMastermind** | Coordinator | macOS | Observable client API wrapping TheHandoff. @Observable state for SwiftUI, async waitFor* methods with request-ID correlation. |
| **TheFence** | Fence/Dealer | macOS | Centralized command dispatch facade. Split into TheFence.swift (core), TheFence+Handlers.swift (command handlers), TheFence+Formatting.swift (FenceResponse + output). |
| **TheHandoff** | Handoff | macOS | Client-side session manager. Bonjour discovery, TLS connection with fingerprint pinning, keepalive (ping 3s), auto-reconnect (60 attempts at 1s). |
| **Transport Layer** | *(in TheInsideJob)* | iOS | TLS-encrypted TCP server transport and Bonjour advertisement. Contains TLSIdentity (certificate management + expiry tracking), SimpleSocketServer (TCP with TLS), ServerTransport (unified server+Bonjour layer). Formerly a separate module (TheGetaway). |

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
| **DiscoveredDevice** | Discovered iOS device: service name, endpoint, simulator UDID, installation ID, session status, certFingerprint |
| **TLSIdentity** | Actor managing self-signed ECDSA P-256 certificates, Keychain persistence, SHA-256 fingerprint computation |
| **ServerInfo** | Server metadata including tlsActive boolean indicating TLS encryption status |

## Terminology

| Term | Definition |
|------|-----------|
| **Wire Protocol** | Newline-delimited JSON over TLS/TCP (v5.0). RequestEnvelope/ResponseEnvelope for request-response correlation via requestId. Service: `_buttonheist._tcp`. All connections encrypted with TLS 1.3. |
| **TLS Fingerprint Pinning** | Client-side certificate verification where the server's TLS certificate SHA-256 hash is compared against the fingerprint advertised in the Bonjour TXT record (certfp field). Format: `sha256:<64 hex chars>`. Prevents MITM attacks. |
| **Trust-On-First-Discovery (TOFU)** | Security model where the server's TLS certificate fingerprint is discovered via Bonjour mDNS and trusted on first connection. Acceptable for local development tool threat model. |
| **TLSIdentity** | Actor that manages a self-signed ECDSA P-256 X.509v3 certificate with 1-year validity. Stored in Keychain with getOrCreate semantics. Falls back to ephemeral (in-memory) identity if Keychain unavailable. |
| **Ephemeral Identity** | A TLSIdentity created by temporarily storing key material in the Keychain for SecIdentity creation, then immediately deleting the Keychain entries. Used as fallback when persistent Keychain storage fails. |
| **certfp** | Bonjour TXT record key containing the server's TLS certificate SHA-256 fingerprint in `sha256:<hex>` format. Published by ServerTransport, read by clients pre-connection for fingerprint pinning. |
| **DisconnectReason.certificateMismatch** | Connection disconnect reason when the server's TLS certificate fingerprint does not match the expected value from Bonjour discovery, or when no fingerprint is available (plain TCP refused). |
| **Protocol Version 5.0** | Wire protocol version introducing mandatory TLS transport encryption. Bumped from v4.0. ServerInfo includes tlsActive field. Bonjour TXT records include certfp and transport fields. |
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
         → TheMastermind → TheHandoff → DeviceDiscovery (extracts certfp from Bonjour TXT)
                                      → DeviceConnection (TLS + fingerprint pinning)
                                        ←TLS/TCP→ SimpleSocketServer (TLS via NWParameters)
                                                   → ServerTransport (publishes certfp in TXT)
                                                   → TLSIdentity (cert generation, Keychain, fingerprint)
                                                   → TheInsideJob
                                                     → TheInsideJob+Dispatch
                                                     ├→ TheSafecracker → TheSafecracker+MultiTouch
                                                     │                 → TheFingerprints
                                                     │                 → TheBagman (target resolution)
                                                     ├→ TheBagman → TheBagman+Conversion
                                                     │            → AccessibilitySnapshotParser
                                                     ├→ TheMuscle (auth after TLS handshake)
                                                     └→ TheStakeout

CLI → TheFence
MCP → TheFence
```

## Domain Boundaries

### 1. Wire Protocol (TheScore)
- **Scope**: Cross-platform shared module
- **Concepts**: ClientMessage (29 cases), ServerMessage (15 cases), HeistElement, Interface, InterfaceDelta, ActionResult, ServerInfo.tlsActive
- **Boundary**: No UIKit/AppKit dependency. Consumed by both sides. Protocol v5.0. Defines tlsActive field for TLS status reporting.

### 2. Transport Layer (in TheInsideJob)
- **Scope**: Shared networking module
- **Concepts**: TLSIdentity, SimpleSocketServer, ServerTransport, TLSIdentityError, Bonjour TXT (certfp, transport)
- **Boundary**: Owns TLS certificate lifecycle (generation, Keychain storage, fingerprint computation), TCP server with TLS, and Bonjour advertisement with TLS metadata. Does not handle auth or application messages.

### 3. iOS Server (TheInsideJob)
- **Scope**: iOS 17.0+, DEBUG builds, @MainActor
- **Concepts**: TheInsideJob, TheInsideJob+Dispatch, TheMuscle, TheSafecracker, TheSafecracker+MultiTouch, TheBagman, TheBagman+Conversion, TheStakeout, TheFingerprints, ThePlant
- **Boundary**: Runs inside target app. Uses ServerTransport for TLS-encrypted networking. Owns accessibility hierarchy, interaction execution.

### 4. macOS Client (ButtonHeist framework)
- **Scope**: macOS 14.0+, @ButtonHeistActor
- **Concepts**: TheFence, TheFence+Handlers, TheFence+Formatting, TheMastermind, TheHandoff, DeviceConnection, DiscoveredDevice, DisconnectReason.certificateMismatch
- **Boundary**: Discovery, TLS connection with fingerprint pinning, command dispatch, response formatting. Refuses plain TCP.

### 5. CLI (ButtonHeistCLI)
- **Scope**: macOS command-line tool
- **Concepts**: CLI Commands (18 subcommands), REPL Session, ElementTargetOptions, OutputOptions
- **Boundary**: Thin interface over TheFence. Canonical test client.

### 6. MCP Server (ButtonHeistMCP)
- **Scope**: macOS MCP tool server
- **Concepts**: 14 MCP Tools, Tool Definitions
- **Boundary**: Maps MCP tool calls to TheFence. Omits large video data from responses.

## Cross-Cutting Concerns

| Concern | Approach |
|---------|----------|
| **TLS Transport Encryption** | Mandatory TLS 1.3 with self-signed ECDSA P-256 certificates. Server generates via TLSIdentity, publishes fingerprint in Bonjour TXT. Client verifies fingerprint during handshake. No plaintext TCP fallback. |
| **Concurrency** | @MainActor (iOS), @ButtonHeistActor (macOS), async/await, CheckedContinuation for request-response. TLSIdentity is an actor for isolation of security material. |
| **Authentication** | Token-based with 3 modes: direct match, UI approval, observer auto-approve. Rate limiting 30 msg/s, max 5 connections. Auth occurs after TLS handshake completes. |
| **Error Handling** | Layered: FenceError (user-facing), ConnectionError (lifecycle), ActionError/RecordingError (async waits), TLSIdentityError (certificate/Keychain failures), DisconnectReason.certificateMismatch (TLS verification). |
| **Auto-Reconnect** | 60 attempts at 1s intervals on disconnect. Match by installation identity. TLS re-verification on each reconnect attempt. |
| **Configuration** | Environment variables (highest priority) -> Info.plist keys (fallback). Both client and server sides. |
| **Keychain Integration** | TLSIdentity persists certificates in Keychain (kSecAttrAccessibleWhenUnlockedThisDeviceOnly). Ephemeral fallback if unavailable. |
| **App Lifecycle** | TheInsideJob suspends on background, resumes on foreground with TLS identity recreation. Prevents idle screen lock. |
| **Hierarchy Observation** | Notification-driven (300ms debounce) + polling (configurable interval, hash comparison). |
| **Extension-Based Organization** | Large types split into focused extension files (Type+Feature.swift) for maintainability without changing public API. |
