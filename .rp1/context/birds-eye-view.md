# Button Heist -- Bird's-Eye View

> Generated: 2026-03-10 | Commit: 1693db0 | Branch: RoyalPineapple/tallinn-v1

## 1) Summary

Button Heist gives AI agents and humans full programmatic control over iOS apps by embedding a TCP server framework (TheInsideJob) inside the target app and connecting from macOS via an MCP server or CLI. It exposes the accessibility hierarchy, executes gestures via synthetic touch injection, captures screenshots and screen recordings, and returns compact UI diffs after every interaction -- enabling fully automated, agent-driven iOS testing and exploration.

- Domain: `iOS UI Automation` | Tech stack: `Swift 6.0 (strict concurrency), Obj-C, iOS 17.0+, macOS 14.0` | Repos: `RoyalPineapple/TheButtonHeist`
- Wire protocol: `Newline-delimited JSON over TCP v4.0` | Discovery: `Bonjour (_buttonheist._tcp)` | Build: `Tuist + SPM`
- Version: `0.0.1` | License: `Apache 2.0`

## 2) System Context

Button Heist operates as a client-server system where the iOS app hosts a TCP server discovered via Bonjour, and macOS tooling (CLI or MCP server) connects to send commands and receive UI state. AI agents interact through the MCP server's 14 tools, while humans use the CLI's 29 commands -- both dispatch through a single command facade (`TheFence`).

```mermaid
flowchart LR
    Agent["AI Agent\n(Claude Code)"]
    Human["Developer\n(Terminal)"]
    MCP["ButtonHeistMCP\n14 MCP Tools"]
    CLI["buttonheist CLI\n29 Commands"]
    Fence["TheFence\nCommand Dispatch"]
    App["iOS App\nTheInsideJob Server"]

    Agent -->|MCP tool calls| MCP
    Human -->|shell commands| CLI
    MCP --> Fence
    CLI --> Fence
    Fence <-->|"TCP / NDJSON\nWiFi or USB"| App
```

## 3) Architecture Overview (components and layers)

The system is layered into six tiers: a shared protocol layer (TheScore), a transport layer (TheGetaway), an iOS server layer (TheInsideJob and crew), a macOS client layer (TheMastermind), a command dispatch layer (TheFence), and consumer interfaces (CLI/MCP). All component names follow a heist crew metaphor where each member has a single, well-defined responsibility.

```mermaid
flowchart TB
    subgraph ConsumerLayer["Consumer Interfaces"]
        MCP["ButtonHeistMCP"]
        CLI["ButtonHeistCLI"]
    end

    subgraph DispatchLayer["Command Dispatch"]
        Fence["TheFence\n29 commands"]
    end

    subgraph ClientLayer["macOS Client"]
        Mastermind["TheMastermind\n@Observable"]
        Handoff["TheHandoff\nDiscovery + Connection"]
    end

    subgraph TransportLayer["Transport"]
        Discovery["DeviceDiscovery\nNWBrowser"]
        Connection["DeviceConnection\nNWConnection"]
        SocketServer["SimpleSocketServer\nNWListener"]
    end

    subgraph ServerLayer["iOS Server"]
        InsideJob["TheInsideJob\n@MainActor"]
        Bagman["TheBagman\nElement Cache"]
        Safecracker["TheSafecracker\nTouch Injection"]
        Muscle["TheMuscle\nAuth + Sessions"]
        Stakeout["TheStakeout\nRecording"]
        Fingerprints["TheFingerprints\nOverlay"]
    end

    subgraph SharedLayer["Shared Protocol"]
        Score["TheScore\nWire Types"]
        Getaway["TheGetaway\nServer Transport"]
    end

    MCP --> Fence
    CLI --> Fence
    Fence --> Mastermind
    Mastermind --> Handoff
    Handoff --> Discovery
    Handoff --> Connection
    Connection <-->|TCP| SocketServer
    SocketServer --> InsideJob
    InsideJob --> Bagman
    InsideJob --> Safecracker
    InsideJob --> Muscle
    InsideJob --> Stakeout
    InsideJob --> Fingerprints
    Score -.->|used by| InsideJob
    Score -.->|used by| Mastermind
    Getaway -.->|used by| SocketServer
```

## 4) Module and Package Relationships

The project comprises 8 modules with a strict, acyclic dependency graph. TheScore sits at the foundation with zero dependencies, TheGetaway adds transport on top of it, and the iOS and macOS sides branch from there. CLI and MCP are thin wrappers that depend only on TheButtonHeist (which re-exports TheScore).

- `TheScore` (4 files, 1107 LOC) -- shared wire protocol, no dependencies
- `TheGetaway` (2 files, 565 LOC) -- TCP server + Bonjour, imports TheScore
- `TheInsideJob` (16 files, 4324 LOC) -- iOS server, imports TheScore + TheGetaway + AccessibilitySnapshotParser
- `TheButtonHeist` (10 files, 2609 LOC) -- macOS client, @_exported import TheScore
- `ButtonHeistCLI` (21 files, 1925 LOC) -- CLI, imports TheButtonHeist + ArgumentParser
- `ButtonHeistMCP` (2 files, 454 LOC) -- MCP server, imports TheButtonHeist + MCP SDK

```mermaid
flowchart BT
    Score["TheScore\nShared Protocol"]
    Getaway["TheGetaway\nTransport"]
    InsideJob["TheInsideJob\niOS Server"]
    ButtonHeist["TheButtonHeist\nmacOS Client"]
    CLI["ButtonHeistCLI"]
    MCP["ButtonHeistMCP"]
    TestApp["TestApp\nDemo Apps"]
    ASP["AccessibilitySnapshot\nSubmodule"]
    ArgParser["ArgumentParser\n1.3.0+"]
    MCPSDK["MCP SDK\n0.11.0+"]

    Getaway --> Score
    InsideJob --> Score
    InsideJob --> Getaway
    InsideJob --> ASP
    ButtonHeist --> Score
    CLI --> ButtonHeist
    CLI --> ArgParser
    MCP --> ButtonHeist
    MCP --> MCPSDK
    TestApp --> InsideJob
    TestApp --> Score
```

## 5) Data Model (key entities)

The wire protocol centers on `HeistElement` as the atomic UI element representation, grouped into an `Interface` snapshot with optional tree structure. Actions produce `ActionResult` with an `InterfaceDelta` diff, and recordings bundle an `InteractionEvent` log with the video payload. All types are `Codable + Sendable`.

```mermaid
erDiagram
    Interface {
        Date timestamp
        HeistElement[] elements
        ElementNode[] tree
    }
    HeistElement {
        Int order
        String label
        String value
        String identifier
        String[] traits
        CGRect frame
        CGPoint activationPoint
        ElementAction[] actions
    }
    ActionResult {
        Bool success
        ActionMethod method
        String message
        InterfaceDelta interfaceDelta
        Bool animating
    }
    InterfaceDelta {
        DeltaKind kind
        Int elementCount
        HeistElement[] added
        Int[] removedOrders
        ValueChange[] valueChanges
    }
    RecordingPayload {
        String videoData
        Int width
        Int height
        Double duration
        StopReason stopReason
        InteractionEvent[] interactionLog
    }
    InteractionEvent {
        Double timestamp
        ClientMessage command
        ActionResult result
    }
    ServerInfo {
        String protocolVersion
        String appName
        String bundleIdentifier
        String deviceName
        String simulatorUDID
    }

    Interface ||--|{ HeistElement : contains
    HeistElement ||--o{ ElementAction : supports
    ActionResult ||--o| InterfaceDelta : includes
    InterfaceDelta ||--o{ ValueChange : details
    RecordingPayload ||--o{ InteractionEvent : logs
    InteractionEvent ||--|| ActionResult : records
```

## 6) API Surface (public endpoints to owning components)

The system exposes two consumer interfaces: a CLI with 29 commands and an MCP server with 14 tools. Both dispatch through `TheFence.execute(request:)` which routes to the appropriate handler. The wire protocol defines 29 `ClientMessage` cases (client-to-server) and 15 `ServerMessage` cases (server-to-client).

- `activate --identifier ID` | `activate` MCP tool --> TheFence --> `ClientMessage.activate(ActionTarget)`
- `type --text "hello"` | `type_text` MCP tool --> TheFence --> `ClientMessage.typeText(TypeTextTarget)`
- `screenshot` | `get_screen` MCP tool --> TheFence --> `ClientMessage.requestScreen`
- `list` | `get_interface` MCP tool --> TheFence --> `ClientMessage.requestInterface`
- `session` (CLI only) --> TheFence --> auto-connect + REPL loop

```mermaid
sequenceDiagram
    participant Client as CLI or MCP
    participant Fence as TheFence
    participant Mastermind as TheMastermind
    participant TCP as TCP Transport
    participant Server as TheInsideJob

    Client->>Fence: execute(request)
    Fence->>Mastermind: send(ClientMessage)
    Mastermind->>TCP: RequestEnvelope + requestId
    TCP->>Server: NDJSON over TCP
    Server->>Server: performInteraction()
    Server->>TCP: ResponseEnvelope
    TCP->>Mastermind: dispatch ServerMessage
    Mastermind->>Fence: waitForResponse callback
    Fence->>Client: FenceResponse
```

## 7) End-to-End Data Flow (hot path)

The hot path is the "activate element" flow: the client sends an activation command, TheInsideJob refreshes the accessibility hierarchy, resolves the target element, takes a before snapshot, executes the action (trying `accessibilityActivate()` first, falling back to synthetic tap), waits briefly for animations, takes an after snapshot, computes an `InterfaceDelta`, and returns the `ActionResult`. This performInteraction pipeline is shared by all action commands.

```mermaid
sequenceDiagram
    participant CLI as CLI
    participant Fence as TheFence
    participant IJ as TheInsideJob
    participant Bag as TheBagman
    participant SC as TheSafecracker
    participant FP as TheFingerprints

    CLI->>Fence: activate --identifier "Submit"
    Fence->>IJ: ClientMessage.activate
    IJ->>Bag: refreshElements()
    Bag->>Bag: parse hierarchy + hash
    IJ->>Bag: snapshot before
    IJ->>SC: activate(element)
    SC->>SC: accessibilityActivate()
    alt fallback
        SC->>SC: synthetic tap at activationPoint
        SC->>FP: show touch indicator
    end
    IJ->>Bag: snapshot after
    Bag->>Bag: compute InterfaceDelta
    IJ->>Fence: ActionResult + delta
    Fence->>CLI: FenceResponse
```

## 8) State Model (session lifecycle)

Each TCP connection progresses through authentication, session locking, active interaction, and eventual disconnection. The session lock enforces single-driver exclusivity -- only one driver identity controls the app at a time. Observers bypass the session lock and receive read-only broadcasts. Sessions auto-release after 30 seconds of inactivity post-disconnect.

```mermaid
stateDiagram-v2
    [*] --> TcpConnected
    TcpConnected --> AuthChallenge: server sends authRequired
    AuthChallenge --> Authenticated: token matches
    AuthChallenge --> UiApproval: empty token
    AuthChallenge --> Rejected: wrong token
    UiApproval --> Authenticated: user taps Allow
    UiApproval --> Rejected: user taps Deny
    Authenticated --> SessionActive: claim session lock
    Authenticated --> SessionLocked: another driver active
    SessionActive --> Interacting: send commands
    Interacting --> SessionActive: receive results
    SessionActive --> Disconnected: connection lost
    Disconnected --> SessionHeld: 30s grace timer
    SessionHeld --> SessionReleased: timer expires
    SessionHeld --> SessionActive: reconnect same driver
    SessionReleased --> [*]
    Rejected --> [*]

    AuthChallenge --> ObserverMode: watch message
    ObserverMode --> [*]: disconnect
```

## 9) User Flows (top 2 tasks)

The two most common workflows are (1) an AI agent using MCP tools to explore and interact with an iOS app, and (2) a developer using the CLI for rapid iteration during development. Both follow the same pattern: discover device via Bonjour, authenticate, get the UI hierarchy, perform actions, and inspect results through deltas.

```mermaid
flowchart TD
    Start["Start: Agent or Developer"]
    Discover["Discover device\nvia Bonjour"]
    Connect["TCP connect + authenticate"]
    GetUI["Get interface hierarchy"]
    Decide{Inspect or Act?}
    Inspect["Read element list\nscreenshot"]
    Act["Activate / tap / type / swipe"]
    Delta["Receive ActionResult + delta"]
    Done{Continue?}
    End["Disconnect"]

    Start --> Discover
    Discover --> Connect
    Connect --> GetUI
    GetUI --> Decide
    Decide -->|inspect| Inspect
    Decide -->|act| Act
    Inspect --> Decide
    Act --> Delta
    Delta --> Done
    Done -->|yes| Decide
    Done -->|no| End
```

## 10) Key Components and Responsibilities

The system has 12 named components ("crew members"), each with a single focused responsibility. The heist metaphor maps naturally to the domain: TheInsideJob is the operative embedded inside the app, TheFence is the dealer who routes stolen goods (commands), TheMastermind plans the operation from outside.

- `TheScore` -- wire protocol types: 29 client messages, 15 server messages, `HeistElement`, `Interface`, `InterfaceDelta`, `ActionResult`
- `TheInsideJob` -- iOS server singleton (@MainActor): TCP server, Bonjour, command routing, performInteraction pipeline, app lifecycle
- `TheSafecracker` -- synthetic touch engine: IOKit HID events for tap, swipe, drag, pinch, rotate, draw-path; text input via UIKeyboardImpl
- `TheBagman` -- element cache and UI observer: accessibility hierarchy parsing, weak NSObject refs, delta computation, screenshot capture
- `TheMuscle` -- auth and session management: token validation, UI approval dialog, session lock (one driver, 30s timeout), observer tracking
- `TheStakeout` -- screen recording: H.264/MP4 via AVAssetWriter, configurable FPS/scale, inactivity timeout, interaction event log
- `TheFingerprints` -- visual touch overlay: translucent circles on a passthrough window for debugging touch locations
- `ThePlant` -- ObjC +load hook that auto-starts TheInsideJob in DEBUG builds before Swift code runs
- `TheMastermind` -- macOS observable coordinator: @Observable state, async `waitForResponse<T>`, requestId correlation
- `TheFence` -- command dispatch facade: routes 29 commands, auto-discovery/connection/reconnect, `sendAndAwait<T>` pattern
- `TheHandoff` -- connection lifecycle: Bonjour discovery, TCP connect, keepalive (ping 3s), auto-reconnect (60 attempts at 1s)
- `TheGetaway` -- TCP transport: `SimpleSocketServer` (NWListener, max 5 connections, 30 msg/s rate limit, 10MB buffer, NDJSON framing)

## 11) Integrations and External Systems

Button Heist integrates with Apple system frameworks for networking, touch synthesis, and media capture, plus two SPM dependencies for CLI parsing and MCP protocol support. The AccessibilitySnapshot submodule (forked from cashapp) provides the core hierarchy parsing capability. All external integrations are system-level or build-time; there are no cloud services or external APIs.

- `Network.framework` -- NWListener (TCP server), NWConnection (TCP client), NWBrowser (Bonjour discovery)
- `IOKit` (private) -- HID event synthesis via dlsym for multi-finger touch injection
- `AVFoundation` -- AVAssetWriter for H.264/MP4 screen recording
- `AccessibilitySnapshot` -- forked submodule (RoyalPineapple/AccessibilitySnapshot, buttonheist branch) for accessibility hierarchy parsing
- `swift-argument-parser 1.3.0+` -- CLI command and option parsing
- `MCP swift-sdk 0.11.0+` -- Model Context Protocol server for AI agent tool integration

```mermaid
flowchart LR
    BH["Button Heist"]
    Network["Network.framework\nTCP + Bonjour"]
    IOKit["IOKit\nHID Touch Events"]
    AVF["AVFoundation\nScreen Recording"]
    ASP["AccessibilitySnapshot\nHierarchy Parser"]
    ArgParser["ArgumentParser\nCLI Parsing"]
    MCPSDK["MCP SDK\nAI Agent Protocol"]
    UIKit["UIKit\nAccessibility + UI"]

    BH --> Network
    BH --> IOKit
    BH --> AVF
    BH --> ASP
    BH --> ArgParser
    BH --> MCPSDK
    BH --> UIKit
```

## 12) Assumptions and Gaps

This overview is generated from the project knowledge base, source code, and documentation. The core architecture, data model, and interaction flows are well-documented. A few areas remain underspecified or would benefit from deeper investigation.

- TBD: `Exact error recovery behavior when IOKit dlsym fails on physical devices vs. simulator`
- TBD: `Full list of Info.plist configuration keys and their interaction with environment variable overrides`
- TBD: `Performance characteristics under load (max elements in hierarchy, recording memory pressure)`
- Next reads: `ButtonHeist/Sources/TheInsideJob/TheInsideJob.swift` (command routing), `ButtonHeist/Sources/TheButtonHeist/TheFence.swift` (dispatch logic)
- Next reads: `docs/AUTH.md` (full auth flow details), `docs/dossiers/` (per-component design rationale)
- Risks to verify: `Session lock race conditions with multiple rapid connect/disconnect cycles`
- Risks to verify: `AccessibilitySnapshot submodule compatibility when upstream cashapp/AccessibilitySnapshot updates`
