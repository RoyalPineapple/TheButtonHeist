# Action Pipeline

One action end to end: resolve typed syntax, establish an evidence boundary,
arm settlement, dispatch exactly once, and return one projection of the
canonical `Settlement.Result`.

**Illustrates:** [ARCHITECTURE.md](../ARCHITECTURE.md), [API.md](../API.md),
[WIRE-PROTOCOL.md](../WIRE-PROTOCOL.md)

**Source of truth:**
`ButtonHeist/Sources/TheInsideJob/TheBrains/TheBrains+HeistActionExecution.swift`,
`ButtonHeist/Sources/TheInsideJob/TheBrains/Settlement.swift`,
`ButtonHeist/Sources/TheInsideJob/TheBrains/Settlement+Execution.swift`,
`ButtonHeist/Sources/TheInsideJob/TheBrains/Settlement+Reducer.swift`,
`ButtonHeist/Sources/TheInsideJob/TheBrains/Settlement+ResultProjection.swift`,
`ButtonHeist/Sources/TheInsideJob/TheSafecracker/ActionDispatchResult.swift`,
`ButtonHeist/Sources/TheInsideJob/TheTripwire/AccessibilityNotificationBus.swift`,
`ButtonHeist/Sources/TheScore/Reports/ActionResult.swift`

```mermaid
sequenceDiagram
    participant Client as CLI or MCP
    participant Fence as TheFence
    participant Brains as TheBrains
    participant Settlement as Settlement.Executor
    participant Observation as Observation Store / Log / Stream
    participant Notifications as AccessibilityNotificationBus
    participant Readiness as UIKitIdleTracker
    participant Safecracker as TheSafecracker

    Client->>Fence: canonical command plus arguments
    Fence->>Fence: parse and admit typed syntax
    Fence->>Brains: heist plan or runtime action
    Brains->>Brains: resolve target, action, and optional predicate
    Brains->>Settlement: action-triggered Settlement.Command
    Settlement->>Observation: capture and commit baseline
    Observation-->>Settlement: Observation.Moment
    Settlement->>Notifications: begin action window after announcement position
    Settlement->>Observation: subscribe after Moment
    Settlement->>Readiness: begin active observation demand
    Settlement->>Settlement: arm absolute deadline
    Settlement->>Safecracker: dispatch resolved action exactly once
    Safecracker-->>Settlement: ActionDispatchResult

    loop until terminal evidence
        Observation-->>Settlement: committed Observation.Event
        Notifications-->>Settlement: ordered announcement event
        Readiness-->>Settlement: readiness established or invalidated
        Settlement->>Settlement: reduce and evaluate typed predicate evidence
    end

    alt readiness lacks an eligible observation
        Settlement->>Observation: capture one handoff observation
        Observation-->>Settlement: admitted post-readiness Event
    end

    Settlement->>Settlement: quiesce children, then release owner leases
    Settlement-->>Brains: Settlement.Result
    Brains->>Brains: project ActionResult once
    Brains-->>Fence: outcome-bound action and expectation evidence
    Fence-->>Client: action result
```

Notes:

- The evidence channels are armed before dispatch, so synchronous hierarchy
  changes and announcements cannot be missed.
- `AccessibilityTarget` is the only target currency. Crossing a capture
  boundary requires semantic re-resolution before a capture-local `HeistId`
  can join to live UIKit evidence.
- An attached expectation is evaluated inside action settlement. There is no
  post-action `waitFor` and no second timeout.
- Current-state predicates must hold in the returned handoff. Positive
  transitions and announcements may latch qualifying post-baseline events.
- Completion requires successful dispatch, optional predicate satisfaction,
  trustworthy readiness, and a handoff admitted for that readiness generation.
- `Settlement.ResultProjector` is the only action-result assembly path. Public
  delta remains a lossy output fold and never becomes evaluator input.
