# Transport Control Plane

One off-main owner consumes transport events, admits per-client requests, and
keeps liveness diagnosis independent from the MainActor it measures. This
diagram answers "which work can still progress when the app main thread is
wedged?"

**Illustrates:** [ARCHITECTURE.md](../ARCHITECTURE.md), [WIRE-PROTOCOL.md](../WIRE-PROTOCOL.md)
**Source of truth:** `ButtonHeist/Sources/TheInsideJob/Server/ServerTransport.swift`, `ButtonHeist/Sources/TheInsideJob/Server/NetworkBoundary/SocketClientRegistry.swift`, `ButtonHeist/Sources/TheInsideJob/TheGetaway/TransportControlPlane.swift`, `ButtonHeist/Sources/TheInsideJob/TheGetaway/TheGetaway+Transport.swift`, `ButtonHeist/Sources/TheInsideJob/Runtime/MainThreadProbe.swift`

## Ownership and execution

```mermaid
flowchart LR
    CLIENT["Diagnostic client<br/>explicit main-thread probe"]
    SOCKET["ServerTransport<br/>transportEvents"]

    subgraph offmain["Off MainActor"]
        CONTROL["TransportControlPlane<br/>sole event consumer"]
        ADMISSION["Per-client ordered<br/>admission"]
        SIDEBAND["Transport-control sideband<br/>ping · mainThreadProbe"]
        PROBE["MainThreadProbe<br/>single terminal gate"]
    end

    subgraph main["MainActor"]
        STREAM["One bounded stream<br/>app work + coalesced control wake"]
        BRAINS["TheBrains<br/>single interaction executor"]
        HEIST["HeistExecution.Host<br/>effects and observation delivery"]
    end

    CLIENT -- "mainThreadProbe" --> SOCKET
    SOCKET --> CONTROL
    CONTROL --> ADMISSION
    ADMISSION --> SIDEBAND
    ADMISSION --> STREAM
    SIDEBAND -- "pong" --> CLIENT
    SIDEBAND --> PROBE
    PROBE -- "responsive · mainThreadUnresponsive · workTimedOut" --> CLIENT
    PROBE -. "CFRunLoopPerformBlock + wake" .-> main
    STREAM --> BRAINS
    BRAINS --> HEIST
```

`ping` and `mainThreadProbe` never enter the MainActor stream or TheBrains.
Admitted app work crosses one bounded, capacity-admitted stream. The control
plane retains client-lease invalidations and transport backlog facts off-main
and coalesces them behind one pending control wake-up, so connection churn
cannot grow the stream or lose cancellation facts. UI work still has one
interaction executor. The same lease gates admission and execution.
Response handlers reserve delivery against their originating socket
incarnation. Replacement wiring drains prior interaction work before its
generation is admitted.

## Failure taxonomy

```mermaid
flowchart TD
    PROBE["Explicit diagnostic probe"] --> BEGAN{"Did the main run loop<br/>begin scheduled work?"}
    BEGAN -- "No" --> UNRESPONSIVE["mainThreadUnresponsive"]
    BEGAN -- "Yes" --> COMPLETED{"Did admitted probe work<br/>complete in time?"}
    COMPLETED -- "No" --> WORK["workTimedOut"]
    COMPLETED -- "Yes" --> RESPONSIVE["responsive"]

    REQUEST["Independent app request"] --> TERMINAL{"Response before<br/>its one deadline?"}
    TERMINAL -- "Yes" --> RESULT["Request result"]
    TERMINAL -- "No" --> TIMEOUT["request.timeout"]
```

These outcomes locate different boundaries:

- Transport failure says the sideband itself cannot exchange messages.
- `mainThreadUnresponsive` says transport is alive but scheduled main-run-loop
  work did not begin.
- `workTimedOut` says the main run loop began the probe but its admitted work
  did not finish.
- Request execution owns one normal deadline. Explicit probe outcomes do not
  compete with or replace a request's terminal result.
