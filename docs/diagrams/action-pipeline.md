# Action Pipeline

One action end to end: resolve typed syntax, establish an evidence boundary,
arm settlement, dispatch exactly once, and return one projection of the
canonical `Settlement.Result`.
Reducer state, event ordering, phase deadlines, handoff, and cleanup are owned
by the [settlement loop](settle-loop.md).

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
    participant Evidence as Observation + notification + readiness
    participant Safecracker as TheSafecracker

    Client->>Fence: canonical command plus arguments
    Fence->>Fence: parse and admit typed syntax
    Fence->>Brains: heist plan or runtime action
    Brains->>Brains: resolve target, action, and optional predicate
    Brains->>Settlement: Settlement.Command.action
    Settlement->>Evidence: capture baseline and arm channels
    Settlement->>Safecracker: dispatch resolved action exactly once
    Safecracker-->>Settlement: ActionDispatchResult
    Evidence-->>Settlement: ordered settlement evidence
    Settlement->>Settlement: execute active reducer loop
    Settlement-->>Brains: one absorbing Settlement.Result
    Brains->>Brains: project canonical action response
    Brains-->>Fence: canonical projection
    Fence-->>Client: action result
```
