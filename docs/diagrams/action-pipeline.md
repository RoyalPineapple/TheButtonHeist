# Action Pipeline

One action end to end: a command enters at TheFence, crosses the wire, resolves
an `AccessibilityTarget`, activates, settles, appends captures, evaluates the
ordered fact stream, and returns a receipt with a folded public delta.

**Illustrates:** [ARCHITECTURE.md](../ARCHITECTURE.md), [API.md](../API.md), [WIRE-PROTOCOL.md](../WIRE-PROTOCOL.md)
**Source of truth:** `ButtonHeist/Sources/TheButtonHeist/TheFence/TheFence+RequestPayload.swift`, `ButtonHeist/Sources/TheInsideJob/TheBrains/TheBrains+HeistActionExecution.swift`, `ButtonHeist/Sources/TheInsideJob/TheBrains/ElementInflation.swift`, `ButtonHeist/Sources/TheInsideJob/TheBrains/PostActionObservation.swift`, `ButtonHeist/Sources/TheInsideJob/TheStash/SemanticObservationStream.swift`, `ButtonHeist/Sources/TheInsideJob/TheBrains/SettleSession.swift`, `ButtonHeist/Sources/TheInsideJob/TheTripwire/AccessibilityNotificationBus.swift`, `ButtonHeist/Sources/TheScore/Reports/ActionResultPayloads.swift`, `ButtonHeist/Sources/TheScore/Receipts/HeistExecutionStepResult.swift`, `ButtonHeist/Sources/TheScore/Evidence/AccessibilityTrace+ChangeFacts.swift`, `ButtonHeist/Sources/TheScore/Evidence/AccessibilityTraceDiff.swift`, `ButtonHeist/Sources/TheButtonHeist/TheFence/DeltaProjection.swift`

```mermaid
sequenceDiagram
    participant Client as CLI / MCP client
    participant Fence as TheFence
    participant Muscle as TheMuscle (server)
    participant Brains as TheBrains
    participant Inflation as ElementInflation
    participant Stash as TheStash
    participant Notifications as AccessibilityNotificationBus
    participant Safecracker as TheSafecracker

    Client->>Fence: command + arguments
    Note over Fence: descriptor owns command shape;<br/>route to FenceCommandInput;<br/>CommandAdmission produces FenceOperationRequest
    Fence->>Muscle: ClientMessage<br/>(.heistPlan / .runtimeAction)<br/>via TheHandoff TLS-PSK
    Muscle->>Brains: dispatch command
    Brains->>Stash: capture BeforeState<br/>(settled InterfaceTree, trace capture,<br/>tripwire baseline)
    Brains->>Notifications: beginActionWindow()
    Notifications-->>Brains: opening cursor
    Brains->>Inflation: inflate(AccessibilityTarget)
    Inflation->>Stash: resolve once against settled InterfaceTree
    Stash-->>Inflation: InterfaceTree.Element<br/>(pin HeistId + graph-derived deadline)
    Note over Inflation,Stash: nested reveal is outermost-first;<br/>refresh and stable geometry retain exact HeistId
    Inflation-->>Brains: LiveActionTarget for pinned HeistId
    Brains->>Safecracker: ActivationPolicy.apply / gesture dispatch
    Safecracker-->>Brains: InteractionResult (+ ActivationTrace)
    Brains->>Brains: SettleSession.run(start:baselineTripwireSignal:)
    Note over Brains,Stash: settle blocks here —<br/>poll parsed tree every 100 ms,<br/>3 identical fingerprints = settled,<br/>hard timeout 5000 ms →<br/>SettleOutcome (settled / timedOut / cancelled)
    alt clean settle proof
        Brains->>Notifications: capture() once
        Notifications-->>Brains: AccessibilityNotificationBatch<br/>(events, exact through-cursor, optional gap)
        Brains->>Stash: commit InterfaceObservationProof + batch
        Brains->>Brains: append committed capture + batch evidence
    else timed out / unavailable
        Brains->>Notifications: cancel action window
        Brains->>Stash: retain diagnostic observation only
        Note over Brains,Stash: receipt may carry diagnostic trace;<br/>parsed result is not admitted as settled truth
    end
    Note over Brains: derive ordered ChangeFact stream<br/>screen boundary = departures,<br/>screen marker, arrivals
    Brains->>Brains: evaluate expectation from<br/>current Interface tree + facts
    Brains-->>Muscle: ActionResult<br/>(outcome-bound observation evidence)
    Muscle-->>Fence: actionResult message<br/>(same wire back)
    Note over Fence: fold facts one way into public delta<br/>screen marker dominates final kind
    Fence-->>Client: receipt (outcome, evidence observation,<br/>expectation, folded delta)
```

Notes:

- The before-state is captured **before** the action is delivered. Proof-backed
  captures are settled truth; a timed-out receipt trace is diagnostic only.
- Semantic resolution pins one committed `HeistId` and one graph-derived
  deadline. Reveal, stale refresh, geometry stabilization, and multi-stage
  action handoff cannot switch to another semantic match.
- Settle blocks the pipeline: the response does not leave the app until `SettleSession` reaches a terminal `SettleOutcome`. A `timedOut` outcome is reported as `settled: false` and its parser result remains diagnostic rather than committed truth.
- Scoped screen, layout, value, and announcement notifications are fact evidence
  and prevent `noChange`; a scoped screen notification or snapshot-inferred
  replacement carrying `transition.fallbackReason` begins a new generation.
- First-responder state is capture-local `HeistId` value evidence. Trace context
  projects that id once to an `AccessibilityTarget`; no UIKit responder identity
  is retained or sent over the wire. First-responder actions also require the
  current and inflated ids to equal the captured id after inflation.
- Action observation evidence is exactly one of `none`, `announcement`, `trace`,
  or `settledTrace`; only `settledTrace` carries settlement evidence.
- A clean action window is captured once. Its exact through-cursor becomes the
  observation cursor, any bounded-history loss is explicit gap evidence, and
  its scoped-screen watermark is the invalidation baseline. A failed settle
  cancels the window without attaching its events to settled trace evidence.
- Public delta is a lossy formatting fold. Predicate evaluation never reads it.
