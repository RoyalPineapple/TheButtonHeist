# Action Pipeline

One action end to end: a command enters at TheFence, crosses the wire, resolves
an `AccessibilityTarget`, activates, settles, appends captures, evaluates the
ordered fact stream, and returns a receipt with a folded public delta.

**Illustrates:** [ARCHITECTURE.md](../ARCHITECTURE.md), [API.md](../API.md), [WIRE-PROTOCOL.md](../WIRE-PROTOCOL.md)
**Source of truth:** `ButtonHeist/Sources/TheInsideJob/TheBrains/TheBrains+HeistActionExecution.swift`, `ButtonHeist/Sources/TheInsideJob/TheBrains/PostActionObservation.swift`, `ButtonHeist/Sources/TheInsideJob/TheBrains/SettleSession.swift`, `ButtonHeist/Sources/TheScore/Evidence/AccessibilityTrace+ChangeFacts.swift`, `ButtonHeist/Sources/TheScore/Evidence/AccessibilityTraceDiff.swift`, `ButtonHeist/Sources/TheButtonHeist/TheFence/DeltaProjection.swift`

```mermaid
sequenceDiagram
    participant Client as CLI / MCP client
    participant Fence as TheFence
    participant Muscle as TheMuscle (server)
    participant Brains as TheBrains
    participant Stash as TheStash
    participant Safecracker as TheSafecracker

    Client->>Fence: command + arguments
    Note over Fence: parse to TheFence.Command —<br/>strings become typed values here
    Fence->>Muscle: ClientMessage<br/>(.heistPlan / .runtimeAction)<br/>via TheHandoff TLS-PSK
    Muscle->>Brains: dispatch command
    Brains->>Stash: capture BeforeState<br/>(settled screen, interface hash,<br/>tripwire baseline)
    Brains->>Stash: resolveTarget(AccessibilityTarget)
    Stash-->>Brains: TargetResolution (.resolved InterfaceTree.Element)
    Brains->>Safecracker: ActivationPolicy.apply / gesture dispatch
    Safecracker-->>Brains: InteractionResult (+ ActivationTrace)
    Brains->>Brains: SettleSession.run(start:baselineTripwireSignal:)
    Note over Brains,Stash: settle blocks here —<br/>poll parsed tree every 100 ms,<br/>3 identical fingerprints = settled,<br/>hard timeout 5000 ms →<br/>SettleOutcome (settled / timedOut / cancelled)
    Brains->>Brains: append settled captures + scoped notifications
    Note over Brains: derive ordered ChangeFact stream<br/>screen boundary = departures,<br/>screen marker, arrivals
    Brains->>Brains: evaluate expectation from<br/>current Interface tree + facts
    Brains-->>Muscle: ActionResult
    Muscle-->>Fence: actionResult message<br/>(same wire back)
    Note over Fence: fold facts one way into public delta<br/>screen marker dominates final kind
    Fence-->>Client: receipt (outcome, trace, expectation,<br/>folded delta, activationTrace)
```

Notes:

- The before-state is captured **before** the action is delivered. Settled
  captures are truth; facts are derived over the full observation window.
- Settle blocks the pipeline: the response does not leave the app until `SettleSession` reaches a terminal `SettleOutcome`. A `timedOut` outcome is reported as `settled: false` in the receipt, never passed off as stable.
- Scoped screen, layout, value, and announcement notifications are fact evidence
  and prevent `noChange`; screen notification begins a new generation.
- Public delta is a lossy formatting fold. Predicate evaluation never reads it.
