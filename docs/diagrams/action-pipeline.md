# Action Pipeline

One action end to end: a typed command crosses the wire, resolves one
`AccessibilityTarget`, dispatches into one `ActionDispatchResult`, settles,
commits to the semantic observation Store, and returns state-shaped evidence.

**Illustrates:** [ARCHITECTURE.md](../ARCHITECTURE.md), [API.md](../API.md), [WIRE-PROTOCOL.md](../WIRE-PROTOCOL.md)
**Source of truth:** `ButtonHeist/Sources/TheButtonHeist/TheFence/TheFence+RequestPayload.swift`, `ButtonHeist/Sources/TheInsideJob/TheBrains/TheBrains+HeistActionExecution.swift`, `ButtonHeist/Sources/TheInsideJob/TheBrains/ElementInflation.swift`, `ButtonHeist/Sources/TheInsideJob/TheBrains/InteractionCoordinator.swift`, `ButtonHeist/Sources/TheInsideJob/TheBrains/ActionEvidenceProjector.swift`, `ButtonHeist/Sources/TheInsideJob/TheSafecracker/ActionDispatchResult.swift`, `ButtonHeist/Sources/TheInsideJob/TheVault/SemanticObservationStore.swift`, `ButtonHeist/Sources/TheInsideJob/TheTripwire/AccessibilityNotificationBus.swift`, `ButtonHeist/Sources/TheScore/Reports/ActionResult.swift`, `ButtonHeist/Sources/TheScore/Reports/ActionResultEvidence.swift`, `ButtonHeist/Sources/TheButtonHeist/TheFence/DeltaProjection.swift`

```mermaid
sequenceDiagram
    participant Client as CLI or MCP
    participant Fence as TheFence
    participant Brains as TheBrains
    participant Vault as TheVault
    participant Inflation as ElementInflation
    participant Notifications as AccessibilityNotificationBus
    participant Safecracker as TheSafecracker

    Client->>Fence: canonical command plus arguments
    Fence->>Fence: admit typed command, target, and expectation
    Fence->>Brains: heistPlan or runtimeAction via the server
    Brains->>Vault: current settled state and ObservationCursor
    Brains->>Notifications: beginActionWindow
    Notifications-->>Brains: opening notification cursor

    Brains->>Inflation: inflate AccessibilityTarget
    Inflation->>Vault: resolve against current InterfaceTree
    Vault-->>Inflation: selected InterfaceTree.Element after any container scope
    alt live handoff stays in the current capture
        Inflation->>Vault: join selected element's current HeistId to live evidence
        Vault-->>Inflation: current LiveActionTarget
    else reveal or refresh crosses a capture boundary
        Inflation->>Vault: admit ordinal-free semantic target for selected element
        Vault-->>Inflation: AdmittedSemanticTarget or typed admission failure
        loop after every committed capture
            Inflation->>Vault: resolve admitted target in committed InterfaceTree
            alt exactly one semantic match
                Vault-->>Inflation: matching element's current HeistId and live reference
            else missing or ambiguous
                Vault-->>Inflation: terminal target-resolution failure
            end
        end
    end
    Inflation-->>Brains: current LiveActionTarget or safe failure

    Brains->>Safecracker: dispatch resolved action
    Safecracker-->>Brains: ActionDispatchResult
    Brains->>Brains: settle post-action interface

    alt successful settlement
        Brains->>Notifications: checkpoint after opening cursor
        Notifications-->>Brains: retained events, through-cursor, gap
        Brains->>Vault: commit CommittableInterfaceObservation
        Vault->>Vault: install tree, history, lineage, and cursors together
    else timeout or unavailable
        Brains->>Notifications: close attribution window
        Brains->>Vault: retain diagnostic observation only
    end

    Brains->>Brains: ActionEvidenceProjector adds semantic evidence
    Brains->>Brains: evaluate expectation from current tree or ObservationWindow
    Brains-->>Fence: ActionResult.Payload plus outcome-bound evidence
    Fence->>Fence: custom Codable projects method plus optional tagged payload
    Fence->>Fence: fold ordered facts into output-only delta
    Fence-->>Client: action result
```

Notes:

- `AccessibilityTarget` is the only target currency. Element, container, and
  descendant-scoped targets resolve through the same current tree used by
  waits, expectations, and `get_interface` selection.
- When inflation crosses a capture boundary, it first admits the selected
  target without its terminal ordinal as `AdmittedSemanticTarget`. Every later
  committed capture re-resolves that identity; only the unique match's current
  `HeistId` may join to live UIKit evidence for geometry and dispatch. Missing
  or ambiguous resolution is terminal, with no stale-id or sibling fallback.
- `ActionDispatchResult` is the sole pre-observation dispatch result.
  `ActionEvidenceProjector` adds settlement and trace evidence directly to that
  outcome to produce `ActionResult`.
- `ActionResult.Payload` is the sole semantic payload. Its case determines the
  method and legal data; custom `Codable` owns the wire projection directly.
- Success and failure evidence share one body, but warning-bearing evidence is
  constructible only for success. Observation is exactly one of `none`,
  `announcement`, `trace`, or `settledTrace`.
- Notification checkpointing is non-destructive. A failed settle does not
  attach the selected events to settled evidence, but it does not erase ingress
  history for another cursor.
- An admitted commit appends one typed observation entry. Presence expectations read
  current state; temporal expectations consume a baseline-to-current window.
- Public delta is a lossy output fold. Predicate evaluation never reads it.
