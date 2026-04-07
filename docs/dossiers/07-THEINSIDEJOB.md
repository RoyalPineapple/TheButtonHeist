# TheInsideJob — The Inside Operative

> **Module:** `ButtonHeist/Sources/TheInsideJob/`
> **Platform:** iOS 17.0+ (UIKit, DEBUG builds only)
> **Role:** Master coordinator of the entire iOS-side operation

## Responsibilities

TheInsideJob is the central hub running inside the target iOS app. It:

1. **Runs a TLS/TCP server** (`SimpleSocketServer`) listening for remote commands
2. **Manages TLS identity** (`TLSIdentity`) — runtime-generated self-signed ECDSA certificates with SHA-256 fingerprint pinning
3. **Provides server transport** (`ServerTransport`) — protocol abstraction for server-side networking
4. **Broadcasts presence** via Bonjour mDNS (`_buttonheist._tcp`)
5. **Drives hierarchy updates** via TheTripwire's pulse-based settle detection (no debounce timer)
6. **Detects background changes** — `computeBackgroundDelta()` compares `lastSentTreeHash` against the live tree to detect changes that occurred while the agent was thinking; the delta is attached to the next `ResponseEnvelope`
7. **Wait for change** — `handleWaitForChange` polls the settle gate in a loop, checking each settled state against an optional `ActionExpectation`, returning when the expectation is met or timeout expires
8. **Polls for UI changes** at configurable intervals (default 2.0s, min 0.5s) as a supplementary mechanism
9. **Dispatches all commands** to crew members via a two-level dispatch structure
10. **Manages client subscriptions** and broadcasts hierarchy/screen updates
11. **Filters connections by scope** (`ConnectionScope`) — classifies incoming connections at `.ready` using typed `NWEndpoint.Host` and interface detection

## Architecture Diagram

```mermaid
graph TD
    subgraph TheInsideJob["TheInsideJob (Singleton, @MainActor)"]
        Core["TheInsideJob.swift — Server lifecycle, message dispatch, performInteraction"]
        Dispatch["TheInsideJob+Dispatch.swift — Grouped interaction dispatch"]
        Pulse["Extensions/Pulse.swift — Invalidation, pulse transitions, settle-driven polling"]
        Anim["Extensions/Animation.swift — waitForIdle handler"]
        Screen["Extensions/Screen.swift — Screenshot capture, recording mgmt"]
        Auto["Extensions/AutoStart.swift — @_cdecl entry point for ThePlant"]
    end

    subgraph Crew["Crew Members (Owned)"]
        Tripwire["TheTripwire — UI pulse, settle detection"]
        Brains["TheBrains — Action dispatch, delta cycle"]
        Stash["TheStash — Element registry, resolution"]
        Burglar["TheBurglar — Parse pipeline"]
        Muscle["TheMuscle — Auth & sessions"]
        Safecracker["TheSafecracker — Touch & text"]
        Stakeout["TheStakeout — Recording"]
    end

    subgraph Transport["Transport"]
        Server["SimpleSocketServer — TLS/TCP listener"]
        STransport["ServerTransport — Protocol abstraction"]
        TLS["TLSIdentity — ECDSA cert + SHA-256 fingerprint"]
    end

    TLS --> Server
    STransport --> Server
    Core --> Muscle
    Core --> Stakeout
    Core --> Tripwire
    Core --> Brains
    Brains --> Stash
    Brains --> Safecracker
    Stash --> Burglar
    Core --> STransport
    Dispatch --> Brains
    Pulse --> Brains
    Pulse --> Tripwire
    Screen --> Stakeout
```

## Key Files

| File | Purpose |
|------|---------|
| `TheInsideJob.swift` | Core lifecycle, server wiring, message dispatch |
| `TheBrains.swift` | Action dispatch, delta cycle, exploration orchestration |
| `TheBurglar.swift` | Hierarchy parsing, parse/apply pipeline, topology detection |
| `TheStash.swift` | Element registry, target resolution, wire conversion, screen capture |
| `ScreenManifest.swift` | Full-screen element census bookkeeping |
| `Extensions/Pulse.swift` | `scheduleHierarchyUpdate`, `handlePulseTransition`, `startPollingLoop`, `broadcastIfChanged`, `sendInterface` |
| `Extensions/Animation.swift` | `handleWaitForIdle`, `handleWaitForChange` — wait handlers with settle detection and expectation-driven polling |
| `Extensions/Screen.swift` | Screen capture broadcast, recording start/stop handlers |
| `Extensions/AutoStart.swift` | `@_cdecl` bridge for ObjC auto-start |
| `SimpleSocketServer.swift` | NWListener TLS/TCP server, connection management |
| `ServerTransport.swift` | Server-side networking protocol abstraction |
| `TLSIdentity.swift` | ECDSA cert generation, SHA-256 fingerprint, Keychain persistence |

## Singleton Pattern and `configure()`

`TheInsideJob` uses a manually managed `private static var _shared`. The `public static var shared` property lazily creates a default instance if `_shared` is nil.

`configure(token:instanceId:allowedScopes:port:)` is a **one-shot factory**:
- If `_shared` is already set: logs a warning and returns immediately (no-op)
- If `_shared` is nil: creates a new instance with the provided parameters

Calling `shared` before `configure()` creates a default instance that ignores any subsequent `configure()` call.

## Message Dispatch Flow

```mermaid
flowchart TD
    Receive["handleClientMessage"]
    Receive --> Decode["Decode RequestEnvelope"]
    Decode --> ObsCheck["isObserver = muscle.observerClients.contains(clientId)"]

    ObsCheck --> Level1["Level 1: Protocol + Observation (all clients)"]
    Level1 --> L1Cases["subscribe / unsubscribe / ping / status / requestInterface / requestScreen / waitForIdle"]

    ObsCheck --> ObsGate{"is observer?"}
    ObsGate -->|yes| ReadOnly["Return: Watch mode is read-only"]
    ObsGate -->|no| Level2["Level 2: Recording + Interactions"]

    Level2 --> RecCases["startRecording / stopRecording"]
    Level2 --> DispatchInt["dispatchInteraction → 3 sub-dispatchers"]

    DispatchInt --> AccDisp["dispatchAccessibilityAction"]
    DispatchInt --> TouchDisp["dispatchTouchGesture"]
    DispatchInt --> Inline["Inline: typeText, scroll, scrollToVisible,<br/>scrollToEdge, waitFor, explore"]
    DispatchInt --> Search["performElementSearch() (dedicated path)"]

    AccDisp --> Perform["performInteraction()"]
    TouchDisp --> Perform
    Inline --> Perform
```

### `dispatchAccessibilityAction`
`activate`, `increment`, `decrement`, `performCustomAction`, `editAction`, `setPasteboard`, `getPasteboard`, `resignFirstResponder`

### `dispatchTouchGesture`
`touchTap`, `touchLongPress`, `touchSwipe`, `touchDrag`, `touchPinch`, `touchRotate`, `touchTwoFingerTap`, `touchDrawPath` (≤10,000 points), `touchDrawBezier` (≤1,000 segments)

### Inline in `dispatchInteraction`
`typeText`, `scroll`, `scrollToVisible` (one-shot), `scrollToEdge`, `waitFor`, `explore`

### `performElementSearch` (dedicated path)
`elementSearch` — iterative page-by-page scroll search. Bypasses `performInteraction` because the scroll loop manages its own refresh/settle cycles.

## `performInteraction` Pipeline

Every interaction except `elementSearch` flows through this method:

```mermaid
flowchart TD
    Start["performInteraction(message, interaction)"]
    Start --> S1["1. stakeout?.noteActivity()"]
    S1 --> S2["2. brains.refresh()"]
    S2 --> S3["3. brains.captureBeforeState() — before"]
    S3 --> S3b["4. tripwire.topmostViewController() — beforeVC"]
    S3b --> S4["5. await interaction() — TheSafecracker.*"]
    S4 --> S5{"success?"}
    S5 -->|yes| S5a["6. await brains.actionResultWithDelta()"]
    S5 -->|no| S5b["6. Build failure ActionResult"]
    S5a --> S6{"recording active?"}
    S5b --> S6
    S6 -->|yes| S6a["7. Record InteractionEvent to Stakeout"]
    S6 -->|no| S7["8. send(.actionResult)"]
    S6a --> S7
    S7 --> S8["9. If hasSubscribers: broadcast InteractionEvent"]
```

`performElementSearch` is structurally identical but calls `brains.executeElementSearch` directly (handles repeated scroll+settle cycles internally) and preserves `scrollSearchResult` in the response. `scrollToVisible` is now a one-shot jump that flows through the standard `performInteraction` pipeline.

## Status Message Handling

`status` is handled specially:
- Allowed **pre-auth**: any client that has completed `clientHello` → `serverHello` (is in `helloValidatedClients`) can send `status` before providing a token
- Allowed **post-auth**: routed through the Level 1 dispatch for all authenticated clients including observers
- Builds `StatusPayload` via `makeStatusPayload()` from `Bundle.main`, `UIDevice.current`, and `TheMuscle` state

## Update Mechanisms

Two paths trigger hierarchy broadcasts:

### 1. Pulse-driven invalidation (primary)

```mermaid
flowchart LR
    AX["Accessibility notification / notifyChange()"] --> Schedule["scheduleHierarchyUpdate()"]
    Schedule --> SetFlag["hierarchyInvalidated = true"]
    SetFlag --> Wait["Wait for next .settled transition"]
    Wait --> Pulse["handlePulseTransition(.settled)"]
    Pulse --> Broadcast["broadcastIfChanged()"]
```

There is **no debounce timer**. The mechanism is entirely pulse-driven:
- `scheduleHierarchyUpdate()` sets `hierarchyInvalidated = true`
- the next `.settled` transition fires `handlePulseTransition`
- `broadcastIfChanged()` refreshes via TheBrains, compares the snapshot hash, and broadcasts the same shared interface payload path

### 2. Settle-driven polling (supplementary)

`startPolling(interval:)` enables an optional loop that waits on `tripwire.waitForAllClear(timeout:)`, then calls the same `broadcastIfChanged()` path. The timeout defaults to 2s and is clamped to a 0.5s minimum. **Disabled by default** (`isPollingEnabled = false`); auto-started instances can enable it.

## Lifecycle State Machine

```mermaid
stateDiagram-v2
    [*] --> Stopped: TheInsideJob.shared (lazy)
    Stopped --> Running: start() [async throws]
    Running --> Suspended: didEnterBackground
    Suspended --> Resuming: willEnterForeground
    Resuming --> Running: resume task completes
    Running --> Stopped: stop()
    Stopped --> [*]

    state Running {
        [*] --> ServerUp: TLSIdentity + ServerTransport.start()
        ServerUp --> Advertising: NetService.publish()
        Advertising --> Observing: startAccessibilityObservation + startLifecycleObservation
        Observing --> Pulsing: tripwire.startPulse()
        Pulsing --> OptionalPolling: startPolling(interval) [optional]
    }

    state Suspended {
        [*] --> TearDown: stopPulse + stop transport + tearDown muscle
        TearDown --> Waiting: wait for foreground
    }
```

`ServerState` is an enum with four cases: `.stopped`, `.running(transport: ServerTransport)`, `.suspended`, `.resuming(task: Task<Void, Never>)`. There is no `Configured` state -- `configure()` sets the singleton but does not change `ServerState`.

`suspend()` tears down the entire TCP server, Bonjour, pulse, and observation. `resume()` recreates everything from scratch on a potentially new port — any connected clients are silently disconnected.

## Transport Wiring

Five closure assignments wire `TheMuscle` ↔ `ServerTransport`:
- `muscle.sendToClient` → `transport.send(_:to:)`
- `muscle.markClientAuthenticated` → `transport.markAuthenticated(_:)`
- `muscle.disconnectClient` → `transport.disconnect(clientId:)`
- `muscle.onClientAuthenticated` → `sendServerInfo`
- `muscle.onSessionActiveChanged` → update Bonjour TXT record (`sessionactive` key)

Inbound data paths:
- **Authenticated path**: `transport.onDataReceived` → `handleClientMessage`
- **Pre-auth path**: `transport.onUnauthenticatedData` → checks for `status` probe from hello-validated clients → otherwise routes to `muscle.handleUnauthenticatedMessage`

## Items Flagged for Review

### MEDIUM PRIORITY

**No unit tests for TheInsideJob itself**
- Delta computation logic in TheStash is pure data transformation and could be tested without UIKit
- Server-side dispatch logic is untested

### LOW PRIORITY

**Background/foreground lifecycle**
- `suspend()` tears down the entire TCP server and Bonjour
- `resume()` recreates on a potentially new port
- Any connected clients are silently disconnected with no notification
- Expected iOS behavior but worth understanding
