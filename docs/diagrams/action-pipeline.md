# Action Pipeline

One durable action is a leaf in the complete-heist machine. The machine opens
observation before dispatch, evaluates every admitted event in order, and
returns one typed result.

**Illustrates:** [ARCHITECTURE.md](../ARCHITECTURE.md), [API.md](../API.md),
[WIRE-PROTOCOL.md](../WIRE-PROTOCOL.md)

**Source of truth:**
`ButtonHeist/Sources/TheInsideJob/TheBrains/HeistExecution.swift`,
`ButtonHeist/Sources/TheInsideJob/TheBrains/HeistExecution+Leaf.swift`,
`ButtonHeist/Sources/TheInsideJob/TheBrains/HeistExecution+Host.swift`,
`ButtonHeist/Sources/TheInsideJob/TheSafecracker/ActionDispatchResult.swift`,
`ButtonHeist/Sources/TheScore/Reports/ActionResult.swift`

```mermaid
sequenceDiagram
    participant Machine as HeistExecution.Machine
    participant Host as MainActor Host
    participant Stream as Observation.Stream
    participant Tripwire as TheTripwire
    participant Vault as TheVault
    participant Safecracker as TheSafecracker

    Machine-->>Host: beginObservation(scope, leaf timeout)
    Host->>Vault: open protected history boundary
    Host->>Stream: begin scoped demand
    Stream->>Tripwire: resume display pulses
    Tripwire-->>Stream: pulse
    Stream->>Stream: claim notifications and parse UIKit
    Stream->>Vault: commit snapshot and ordered events
    Vault-->>Host: publication
    Host-->>Machine: observationBegan(baseline)
    Host-->>Machine: ordered events
    Machine-->>Host: currentSnapshot(scope)
    Host-->>Machine: currentSnapshot(snapshot)
    Machine-->>Host: dispatch(resolved command)
    Host->>Safecracker: dispatch exactly once
    Safecracker-->>Host: typed dispatch outcome
    Host-->>Machine: dispatchCompleted(outcome)
    loop until predicate and noChange
        Tripwire-->>Stream: pulse
        Stream->>Vault: commit snapshot and events
        Vault-->>Host: publication
        Host-->>Machine: ordered Observation.Event
    end
    Machine-->>Host: finishObservation(exit position)
    Host->>Stream: close causal cutoff and await Vault coverage
    Host->>Vault: project evidence and advance protected boundary
    Vault-->>Machine: observationFinished(evidence, outcome)
    Machine-->>Host: next heist State
```

The action leaf owns predicate progress but performs no effects. The host owns
dispatch, viewport work, cancellation, and the sole business deadline. The
stream owns pulse-driven capture and notification admission. The Vault owns
current truth and history. Successful steps release history before the next
leaf; their immutable evidence stays in the result. `ActionResult` is projected
once from dispatch truth plus that evidence.
