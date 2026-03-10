# ButtonHeist - Architecture

> Generated: 2026-03-10 | Commit: 402d50e | Strategy: parallel-map-reduce (incremental)

## Architecture Diagram

```mermaid
graph TB
    subgraph consumers["Consumer Interfaces"]
        Agent["AI Agent<br/>(Claude Code)"] -->|MCP tool calls| MCP["ButtonHeistMCP<br/>14 tools"]
        Agent -->|Bash| CLI["buttonheist CLI<br/>29 commands"]
    end

    subgraph dispatch["Command Dispatch"]
        MCP --> TF["TheFence<br/>@ButtonHeistActor"]
        CLI --> TF
        TF --> TFH["TheFence+Handlers<br/>command handlers"]
        TF --> TFF["TheFence+Formatting<br/>response formatting"]
        TF --> TM["TheMastermind<br/>@Observable"]
    end

    subgraph transport["Transport"]
        TM --> DD["DeviceDiscovery<br/>NWBrowser / Bonjour"]
        DD -->|extracts certfp<br/>from TXT record| FP["TLS Fingerprint"]
        TM --> DC["DeviceConnection<br/>NWConnection + TLS"]
        DC -->|verifies fingerprint<br/>during handshake| FP
    end

    DC <-->|"TLS 1.3 (P-256 ECDSA)<br/>Newline-delimited JSON<br/>WiFi or USB"| SS

    subgraph ios["iOS App Process"]
        TLSI["TLSIdentity<br/>Self-signed cert<br/>Keychain persistence"] -->|NWParameters| SS
        TLSI -->|sha256 fingerprint| ST
        SS["SimpleSocketServer<br/>NWListener + TLS"] --> IJ["TheInsideJob<br/>@MainActor coordinator"]
        ST["ServerTransport<br/>TCP + TLS + Bonjour"] --> SS
        ST -->|certfp in TXT record| Bonjour["NetService<br/>_buttonheist._tcp"]
        IJ --> IJD["TheInsideJob+Dispatch<br/>message routing"]
        IJD --> TBag["TheBagman<br/>Element cache + delta"]
        IJD --> TSC["TheSafecracker<br/>Touch + text injection"]
        TBag --> TBC["TheBagman+Conversion<br/>element/tree/delta"]
        TSC --> TSCM["TheSafecracker+MultiTouch<br/>pinch/rotate/two-finger"]
        IJ --> TSt["TheStakeout<br/>Screen recording"]
        IJ --> TMu["TheMuscle<br/>Auth + sessions"]
        IJ --> TFP["TheFingerprints<br/>Visual overlay"]
        TP["ThePlant<br/>ObjC +load"] -->|auto-start| IJ
        TBag --> ASP["AccessibilitySnapshot<br/>Hierarchy parser"]
    end

    subgraph shared["Shared"]
        TS["TheScore<br/>Wire protocol types"]
        TG["TheGetaway<br/>Server transport + TLS"]
    end

    TS -.->|used by| IJ
    TS -.->|used by| TM
    TG -.->|used by| SS
```

## Architectural Patterns

| Pattern | Description |
|---------|-------------|
| **Client-Server (Distributed)** | iOS framework embeds as TLS-encrypted TCP server; macOS tooling discovers, connects with certificate fingerprint pinning, and sends commands over newline-delimited JSON. |
| **Trust-on-First-Sight (TOFU) TLS** | Self-signed ECDSA P-256 certificates with fingerprint pinning via Bonjour TXT records. No CA required. Server generates identity, publishes SHA-256 fingerprint; client verifies during TLS handshake. |
| **Facade / Command Dispatch** | TheFence centralizes all 29 commands. CLI and MCP are thin wrappers over TheFence.execute(). Handlers extracted to TheFence+Handlers.swift. |
| **Observer Pattern (Reactive)** | TheMastermind uses @Observable for SwiftUI. iOS server uses polling-and-broadcast for hierarchy changes. |
| **Layered Architecture** | Strict dependency direction: TheScore -> TheGetaway -> TheInsideJob / TheButtonHeist -> TheFence -> CLI/MCP. |
| **Heist Crew Metaphor** | Domain-driven naming where each component is a heist crew role with clear responsibility. |
| **Extension-Based File Organization** | Large types decomposed into focused Swift extensions using Type+Concern.swift naming. Each extension file owns a single responsibility. Keeps files under ~350 lines while preserving public API. |
| **Warnings-as-Errors Build Policy** | All SPM targets treat warnings as errors (`-warnings-as-errors`), enforcing a zero-warning policy as a build quality gate. |

## Layers

### 1. Shared Protocol Layer
- **Components**: TheScore
- **Purpose**: Cross-platform wire protocol types, message definitions, data models
- **Dependencies**: None

### 2. Transport Layer
- **Components**: TheGetaway (SimpleSocketServer, ServerTransport, TLSIdentity), DeviceConnection, DeviceDiscovery
- **Purpose**: TLS-encrypted TCP server/client networking, Bonjour discovery, certificate identity management, connection lifecycle
- **Dependencies**: Shared Protocol Layer

### 3. iOS Server Layer
- **Components**: TheInsideJob + TheInsideJob+Dispatch, TheBagman + TheBagman+Conversion, TheSafecracker (7 files incl. +MultiTouch), TheStakeout, TheMuscle, TheFingerprints, ThePlant
- **Purpose**: In-app server for UI hierarchy capture, gesture simulation, screen recording, auth
- **Dependencies**: Shared Protocol Layer, Transport Layer, AccessibilitySnapshotParser

### 4. macOS Client Layer
- **Components**: ButtonHeist framework, TheMastermind (@Observable)
- **Purpose**: Observable client API wrapping discovery, TLS connection, and state management
- **Dependencies**: Shared Protocol Layer, Transport Layer

### 5. Command Dispatch Layer
- **Components**: TheFence + TheFence+Handlers + TheFence+Formatting, CommandCatalog
- **Purpose**: Centralized command routing, session management, auto-reconnect
- **Dependencies**: macOS Client Layer

### 6. Consumer Interface Layer
- **Components**: ButtonHeistCLI, ButtonHeistMCP
- **Purpose**: User-facing CLI and AI agent MCP tool interfaces
- **Dependencies**: Command Dispatch Layer

## Key Interaction Flows

### TLS Connection Establishment
1. TheInsideJob calls TLSIdentity.getOrCreate() to obtain or generate a self-signed ECDSA P-256 certificate with Keychain persistence
2. ServerTransport creates NWListener with TLS parameters from TLSIdentity.makeTLSParameters() (TLS 1.3 minimum)
3. ServerTransport advertises Bonjour service with TXT record containing certfp (sha256:hex fingerprint) and transport=tls
4. DeviceDiscovery extracts certfp from Bonjour TXT record into DiscoveredDevice.certFingerprint
5. DeviceConnection.connect() refuses plain TCP if no fingerprint available, builds TLS NWParameters with sec_protocol_options_set_verify_block
6. During TLS handshake, verify block extracts leaf certificate, computes SHA-256 fingerprint, compares against expected value from discovery
7. On match: TLS connection established, auth flow proceeds; On mismatch: connection rejected with .certificateMismatch

### Command Execution (activate element)
1. CLI/MCP calls `TheFence.execute(request:)` with command dictionary
2. TheFence auto-connects via TheMastermind if needed (discovery + TLS + auth)
3. TheFence dispatches to handler in TheFence+Handlers.swift, sends ClientMessage over TLS-encrypted TCP
4. TheInsideJob receives message, routes via TheInsideJob+Dispatch.swift (three-stage dispatch)
5. TheBagman refreshes accessibility data, TheSafecracker executes action
6. TheInsideJob computes interface delta via TheBagman+Conversion and returns ActionResult
7. Response propagates back: TLS/TCP -> TheMastermind -> TheFence -> TheFence+Formatting -> CLI/MCP

### Device Discovery
1. TheInsideJob starts SimpleSocketServer with TLS parameters on OS-assigned port
2. TheInsideJob publishes Bonjour service (`_buttonheist._tcp`) with TXT record including certfp and transport=tls
3. TheMastermind starts NWBrowser for `_buttonheist._tcp`
4. NWBrowser discovers service, DeviceDiscovery extracts TXT record metadata including certFingerprint
5. Device added to discoveredDevices array with TLS fingerprint

### Authentication
1. TLS connection established with fingerprint verification
2. Server sends `authRequired` challenge
3. Client sends `authenticate(token)` or `watch(token)`
4. TheMuscle validates token or presents UI approval dialog
5. On success: server sends `info(ServerInfo)` with tlsActive=true, client subscribes
6. On failure: server sends `authFailed`, disconnects after 100ms

### Interface Polling & Broadcasting
1. Polling timer fires (default 1.0s interval)
2. TheBagman parses accessibility hierarchy via elementVisitor
3. Elements flattened via TheBagman+Conversion and hashed
4. If hash changed: broadcast interface + screen to all subscribed clients over TLS
5. Debounced by 300ms for UI notification coalescing

### Touch Dispatch Pipeline
1. TheInsideJob+Dispatch receives ClientMessage over TLS
2. Routes through dispatchAccessibilityInteraction, dispatchTouchInteraction, or dispatchTextAndScrollInteraction
3. Each dispatcher delegates to TheSafecracker methods
4. Multi-touch gestures (pinch, rotate, two-finger tap) handled by TheSafecracker+MultiTouch

## Data Flow

### State Management
- **Strategy**: In-memory state with TLS-encrypted network synchronization
- **iOS**: TheInsideJob singleton holds element cache (TheBagman), auth state (TheMuscle), recording state (TheStakeout), TLS identity (TLSIdentity persisted in Keychain)
- **macOS**: TheMastermind (@Observable) holds client-side state
- **Lifecycle**: Server state = app process lifetime; client state = TLS connection duration; session locks released after 30s timeout; TLS identity persists across launches via Keychain

### Data Pipelines

| Pipeline | Input | Processing | Output |
|----------|-------|-----------|--------|
| TLS Identity Provisioning | Keychain lookup or ECDSA P-256 key generation | TLSIdentity.getOrCreate() -> Keychain load or generate X.509 cert -> DER serialize -> SHA-256 fingerprint | SecIdentity for NWListener TLS, fingerprint for Bonjour TXT |
| TLS Fingerprint Distribution | TLSIdentity.fingerprint (sha256:hex) | ServerTransport publishes certfp in Bonjour TXT -> DeviceDiscovery extracts to DiscoveredDevice.certFingerprint | Client-side expectedFingerprint for TLS verification |
| UI Element Extraction | Live view hierarchy | AccessibilityHierarchyParser -> elementVisitor -> TheBagman+Conversion -> flatten -> hash | Interface (JSON) broadcast over TLS |
| Screen Capture | Window hierarchy | drawHierarchy -> PNG -> base64 | ScreenPayload broadcast over TLS |
| Action Execution | ClientMessage + target | TheInsideJob+Dispatch routes -> TheSafecracker executes -> TheBagman+Conversion.computeDelta | ActionResult with InterfaceDelta over TLS |
| Response Formatting | FenceResponse enum | TheFence+Formatting: humanFormatted() or jsonDict() | Text or JSON for CLI/MCP |
| Screen Recording | startRecording config | Frame capture loop -> AVAssetWriter H.264 -> interaction log | RecordingPayload (base64 MP4) over TLS |

## Technology Stack

| Category | Technologies |
|----------|-------------|
| **Languages** | Swift 6.0 (strict concurrency), Objective-C (ThePlant, touch synthesis) |
| **Platforms** | iOS 17.0+, macOS 14.0 |
| **Build Tools** | Tuist (Xcode project gen), SPM (CLI, MCP), SwiftLint |
| **Build Policy** | `-warnings-as-errors` on all SPM targets (zero-warning gate) |
| **Networking** | Network.framework (TCP, TLS 1.3, Bonjour), custom wire protocol v5.0 (NDJSON) |
| **TLS** | Self-signed ECDSA P-256 via swift-certificates (X509), SHA-256 fingerprints via swift-crypto (Crypto), Keychain persistence via Security.framework |
| **Media** | AVFoundation (AVAssetWriter for H.264/MP4), UIGraphicsImageRenderer (screenshots) |
| **Touch** | IOKit (HID events via private API), UIKeyboardImpl (text input) |
| **Concurrency** | @MainActor (iOS), @ButtonHeistActor (macOS), async/await, actor (TLSIdentity, SimpleSocketServer), GCD (socket I/O) |
| **Protocols** | Custom wire protocol v5.0, Bonjour/mDNS, MCP (Model Context Protocol) |

## Deployment Model

- **Type**: Local development tooling (framework + CLI + MCP server)
- **iOS**: Embed TheInsideJob framework in target app (auto-starts via ObjC +load, DEBUG only)
- **macOS CLI**: Build with `cd ButtonHeistCLI && swift build -c release`
- **macOS MCP**: Build with `cd ButtonHeistMCP && swift build -c release`, configure `.mcp.json`
- **Distribution**: Source code with Tuist project generation
- **Versioning**: SemVer via `scripts/release.sh` (updates 5 version references)

## External Integrations

| Integration | Type | Details |
|------------|------|---------|
| Apple Security Framework / Keychain | System | TLS identity persistence — certificates and private keys stored in Keychain |
| swift-certificates (X509) | SPM (1.0.0+) | X.509 certificate generation for self-signed TLS identities |
| swift-crypto (Crypto) | SPM (3.0.0+) | SHA-256 fingerprint computation for TLS certificate pinning |
| AccessibilitySnapshot | Git submodule (fork) | Hierarchy parsing with elementVisitor closure + Hashable |
| Apple Network Framework | System | NWListener, NWConnection, NWBrowser, NWProtocolTLS for TCP + TLS 1.3 + Bonjour |
| AVFoundation | System | AVAssetWriter for H.264/MP4 screen recording |
| IOKit (Private) | System (dlsym) | Multi-finger HID event creation for touch synthesis |
| MCP Swift SDK | SPM (0.11.0+) | Model Context Protocol server for AI agent tools |
| Swift Argument Parser | SPM (1.3.0+) | CLI command/option parsing |
| Tuist | Build tooling | Xcode project generation and dependency management |
