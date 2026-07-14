# Observation Pipeline

Button Heist has one current semantic tree and one retained temporal log.
Presence reads the current tree. Change evaluation reads a cursor-backed window
from the retained log. Receipts materialize trace evidence from that same
lineage, and public `delta` remains a final lossy fold.

**Illustrates:** [ARCHITECTURE.md](../ARCHITECTURE.md),
[API.md](../API.md), [WIRE-PROTOCOL.md](../WIRE-PROTOCOL.md)

**Source of truth:**
`ButtonHeist/Sources/TheInsideJob/TheStash/TheStash+InterfaceState.swift`,
`ButtonHeist/Sources/TheInsideJob/TheStash/SemanticObservationValues.swift`,
`ButtonHeist/Sources/TheInsideJob/TheStash/SemanticObservationLog.swift`,
`ButtonHeist/Sources/TheInsideJob/TheStash/ObservationEntrySequence.swift`,
`ButtonHeist/Sources/TheInsideJob/TheStash/SemanticObservationPublication.swift`,
`ButtonHeist/Sources/TheInsideJob/TheStash/SemanticObservationStream.swift`,
`ButtonHeist/Sources/TheInsideJob/TheBrains/InteractionObservation.swift`,
`ButtonHeist/Sources/TheInsideJob/TheBrains/ObservationWindow.swift`,
`ButtonHeist/Sources/TheInsideJob/TheBrains/PredicateWait+ObservationStream.swift`,
`ButtonHeist/Sources/TheInsideJob/TheTripwire/AccessibilityNotificationBus.swift`,
`ButtonHeist/Sources/TheScore/Core/AccessibilityPredicate+Evaluation.swift`,
`ButtonHeist/Sources/TheButtonHeist/TheFence/DeltaProjection.swift`

```mermaid
flowchart TD
    Parser["Parser read<br/>InterfaceObservation plus LiveCapture"] --> Settle["Settle and classify"]
    Signals["UIKit accessibility notifications"] --> Bus["AccessibilityNotificationBus<br/>one retained ingress log"]
    Cursor["Heist global sequence cut"] --> Checkpoint["Non-destructive checkpoint"]
    Action["Temporal action expectation"] --> Exact["Exact discovery SettledCapture<br/>captured before action dispatch"]
    Bus --> Checkpoint
    Checkpoint --> Settle

    Settle -->|clean proof| Tree["TheStash InterfaceTree<br/>sole current semantic truth"]
    Settle -->|timeout or unavailable| Diagnostic["Diagnostic observation<br/>not targetable truth"]
    Settle -->|typed lineage| Entry["ObservationEntry<br/>SettledCapture plus transition"]
    Entry --> Log["SemanticObservationLog<br/>bounded retained history"]

    Log --> Baseline["Resolve exact requested-scope capture<br/>at sequence cut"]
    Baseline --> Sequence["ObservationEntrySequence<br/>replayable after exact cursor"]
    Exact --> Sequence
    Request["Wait or expectation"] --> Kind{"Predicate kind"}

    Kind -->|exists or missing| Current["Current InterfaceTree or InterfaceGraph"]
    Current --> Target["Resolve AccessibilityTarget"]
    Target --> Element["element predicate"]
    Target --> Container["container predicate"]
    Target --> Within["within container"]
    Element --> Verdict["Predicate verdict"]
    Container --> Verdict
    Within --> Verdict

    Kind -->|changed or noChange| Sequence
    Sequence --> Window["ObservationWindow<br/>baseline through current"]
    Window --> Complete{"Complete history?"}
    Complete -->|no| Unmet["Unmet<br/>never noChange"]
    Complete -->|yes| Facts["Ordered ChangeFact values"]
    Facts --> Verdict

    Window --> Trace["AccessibilityTrace<br/>durable receipt evidence"]
    Trace --> Fold["One-way public delta fold"]
    Fold --> Public["noChange, elementsChanged, or screenChanged"]
    Public -. "never evaluator input" .-> Sink["Output only"]
```

Publication assigns generations through one scope-aware classifier:

```mermaid
flowchart TD
    Candidate["Settled candidate"] --> Notification{"Fresh screen-change notification?"}
    Notification -->|yes| Advance["Advance generation"]
    Notification -->|no| Scoped{"Previous capture in this scope?"}
    Scoped -->|no| Global["Compare with latest global source capture"]
    Scoped -->|yes, same global generation| Compare["Compare same-scope snapshots"]
    Scoped -->|yes, older generation| Global
    Global --> Decision{"Screen replacement?"}
    Compare --> Decision
    Decision -->|yes| Advance
    Decision -->|no| Keep["Keep or catch up to current generation"]
```

A screen boundary is one typed transition with this fact order:

```mermaid
sequenceDiagram
    participant Old as Old generation
    participant Facts as Ordered facts
    participant New as New generation

    Old->>Facts: elementsChanged with every old node disappeared
    Facts->>Facts: screenChanged marker
    New->>Facts: elementsChanged with every new node appeared
```

Consequences:

- `changed(.screen(...))` requires the screen marker, then evaluates its
  `exists` and `missing` assertions against the current tree.
- `changed(.elements(...))` can match same-screen lifecycle changes or the
  disappearance/appearance facts produced by a screen boundary.
- `updated` is constructible only from two captures in the same generation.
  Identically described nodes across a screen boundary disappear and reappear.
- Notification checkpoints retain their source events. Overflow is explicit
  `AccessibilityNotificationGap` evidence rather than silent history loss.
- Presence uses the same `AccessibilityTarget` resolver as actions and
  `get_interface`, including container and descendant-scoped targets.
- Only a complete, fact-free window can satisfy `noChange`.
- Public delta cannot recover the retained transition order it folds and never
  participates in predicate evaluation. If the window contains a screen marker,
  `screenChanged` dominates the final public delta kind.
