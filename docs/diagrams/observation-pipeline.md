# Observation Pipeline

Button Heist has one `SemanticObservationStore`. It owns the current semantic
graph, retained ordered history, sequence and screen lineage, notification
cursor, and admitted-read state. `SemanticObservationStream` owns settlement
scheduling and delivery, but no second semantic state. Raw parser samples
remain live or diagnostic evidence. Only an admitted settled observation can enter the
Store. Presence reads its current tree; temporal predicates and results read
its replayable retained entries. The tripwire drives one serialized producer
from invalidated state to an admitted commit. Consumers join that refresh or
reuse its admitted result.

**Illustrates:** [ARCHITECTURE.md](../ARCHITECTURE.md),
[API.md](../API.md), [WIRE-PROTOCOL.md](../WIRE-PROTOCOL.md)

**Source of truth:**
`ButtonHeist/Sources/TheInsideJob/TheVault/TheVault+InterfaceState.swift`,
`ButtonHeist/Sources/TheInsideJob/TheVault/SemanticObservationValues.swift`,
`ButtonHeist/Sources/TheInsideJob/TheVault/SemanticObservationHistory.swift`,
`ButtonHeist/Sources/TheInsideJob/TheVault/SemanticObservationStore.swift`,
`ButtonHeist/Sources/TheInsideJob/TheVault/SemanticObservationStream.swift`,
`ButtonHeist/Sources/TheInsideJob/TheVault/SemanticObservationStream+Settlement.swift`,
`ButtonHeist/Sources/TheInsideJob/TheBrains/SettleSession.swift`,
`ButtonHeist/Sources/TheInsideJob/TheBrains/Navigation+ViewportTransition.swift`,
`ButtonHeist/Sources/TheInsideJob/TheBrains/Navigation+Explore.swift`,
`ButtonHeist/Sources/TheInsideJob/TheBrains/Navigation+ExplorationScanning.swift`,
`ButtonHeist/Sources/TheInsideJob/TheBrains/Navigation+SemanticExploration.swift`,
`ButtonHeist/Sources/TheInsideJob/TheBrains/InteractionCoordinator.swift`,
`ButtonHeist/Sources/TheInsideJob/TheBrains/PredicateWait.swift`,
`ButtonHeist/Sources/TheInsideJob/TheBrains/PredicateWait+Evaluation.swift`,
`ButtonHeist/Sources/TheInsideJob/TheBrains/PredicateWait+ObservationStream.swift`,
`ButtonHeist/Sources/TheInsideJob/TheTripwire/AccessibilityNotificationBus.swift`

## Authority And Commit

```mermaid
flowchart TD
    Tripwire["TheTripwire<br/>serialized refresh trigger"] --> Dirty["dirty observation state<br/>settled reads pause"]
    Dirty --> Producer["SemanticObservationStream<br/>one visible refresh producer"]
    Consumers["waits + action before-state"] --> Producer
    Producer --> Settle
    Parser["Accessibility parser read"] --> Raw["InterfaceObservation<br/>live capture or diagnostic evidence"]
    Raw --> Settle["SettleSession<br/>reduce parser samples"]
    Raw -. "never publishes directly" .-> NoAuthority["not semantic authority"]
    Signals["UIKit accessibility notifications"] --> Bus["AccessibilityNotificationBus<br/>retained ingress evidence"]
    Bus --> Checkpoint["non-destructive notification checkpoint"]
    Checkpoint --> Admission
    Settle --> Settled{"settled?"}
    Settled -->|no| Diagnostic["failed-settle diagnostic<br/>no semantic commit"]
    Settled -->|yes| Outcome["SettleSession.Result<br/>exact final InterfaceObservation"]
    Outcome --> Admission{"stream admission<br/>tripwire + exact capture still current?"}
    Admission -->|no| Diagnostic
    Admission -->|yes| Committable["CommittableInterfaceObservation"]

    Committable --> Committer["SemanticObservationStream<br/>ordered commit caller"]
    Committer --> Store["SemanticObservationStore.commitObservation<br/>derive candidate graph + continuity + events"]
    Store --> Atomic["one Store assignment<br/>tree + history + lineage + cursors + admitted-read state"]
    Atomic --> Delivery["SemanticObservationStream<br/>complete waiters"]
    Atomic --> Cursor["ObservationCursor<br/>generation + sequence order<br/>capture-derived timestamp metadata"]
    Cursor --> Admitted["admitted Store state<br/>admitting tripwire signal"]
    Admitted --> Delivery
    Delivery --> Consumers
    Admitted --> Armed["re-arm and wait for next trip"]
    Armed --> Tripwire
    Cursor --> Entries["SemanticObservationStore.read<br/>scope plus cursor replay"]

    Current["committed InterfaceTree"] --> Presence["presence and target resolution"]
    Atomic --> Current
    Entries --> Window["ObservationWindow<br/>immutable baseline through current"]
    Window --> Temporal["temporal predicate and result facts"]
    Window --> Trace["AccessibilityTrace"]
    Trace --> Delta["one-way public delta fold"]
    Delta -. "never evaluator input" .-> Output["public output only"]
```

The ordering is structural. The stream first admits the exact parser capture
which settled. `SemanticObservationStore.commitObservation` then derives the
candidate graph, classifies continuity, constructs every fulfilled-scope event,
validates retained lineage in a copied Store, and installs that Store with one
assignment. Only then does the stream update disposable live evidence and wake
waiters. A failed derivation leaves the complete prior Store intact. Consumers
therefore cannot observe history, lineage, or cursor state for a graph that did
not commit. Cursor `observedAt` is derived from the capture's interface
timestamp and is metadata; generation and settled sequence provide correctness
ordering.

Visible settlement is serialized. A trip invalidates admitted-read state before a
read can be admitted. The first consumer starts the refresh and concurrent
consumers join it; once the Store commit completes, all consumers receive the
same ordered event. Quiet action chains
reuse that event. After-action settlement always starts a fresh capture through
the same producer and publishes through the same commit path.

## Viewport Movement

`Navigation.performViewportTransition` is the only product-owned movement
operation. `ViewportExplorer`, page scroll, inflation placement, and rollback
all submit movement intent to it. No next movement can dispatch until the
previous viewport has committed; exploration additionally waits for its
predicate callback.

Known semantic targets do not page through blank space. If `InterfaceTree`
already carries a target's scroll membership and parser-derived two-dimensional
content point, inflation submits that point directly to the same transition.
Directional page discovery is the fallback for unknown targets or missing
reveal evidence.

After a physical page move, the first settled capture whose semantic viewport
differs from the pre-movement viewport commits immediately. An identical settled
capture remains provisional within the shared one-second semantic observation
budget so delayed SwiftUI accessibility updates can arrive. If the viewport is
legitimately blank or semantically identical, its latest settled capture commits
when there is no budget for another two-frame settle.

```mermaid
sequenceDiagram
    participant Caller as Explorer / scroll / inflation
    participant Transition as performViewportTransition
    participant UIKit as UIKit viewport
    participant Settle as SettleSession
    participant Stream as SemanticObservationStream
    participant Store as SemanticObservationStore
    participant Callback as Observation callback

    Caller->>Transition: movement intent
    Transition->>UIKit: dispatch movement
    UIKit-->>Transition: moved
    Transition->>Settle: minimal settle: parse + two run-loop turns + stable repeat
    Settle-->>Transition: successful outcome with exact final observation
    Transition->>Stream: admit and commit outcome
    Stream->>Stream: verify tripwire and capture identity<br/>construct CommittableInterfaceObservation
    Stream->>Store: commit admitted observation + notification checkpoint
    Store->>Store: derive graph, events, lineage, and cursors<br/>install one complete Store value
    Store-->>Stream: committed event
    Stream->>Stream: complete waiters
    Stream-->>Transition: settled event
    Transition-->>Caller: committed event
    Caller->>Callback: evaluate committed observation
    Callback-->>Caller: continue or finish
    Note over Transition,Callback: No next movement before commit<br/>Explorer waits for callback
```

```mermaid
flowchart TD
    Target{"known target with<br/>scroll-content point?"} -->|yes| Direct["jump directly to 2D content point"]
    Direct --> DirectCommit["minimal settle → parse + admit<br/>→ Store commit"]
    DirectCommit --> RetainKnown["retain revealed viewport"]
    Target -->|no| Save["save visual origin"]
    Save --> Order{"caller-selected search order"}
    Order -->|forwardFirst| FirstForward["scan forward ray first"]
    Order -->|backwardFirst| FirstBack["scan back ray first"]
    FirstForward --> Move["move exactly one viewport"]
    FirstBack --> Move
    Move --> Legal{"legal content offset changed?"}
    Legal -->|yes| Commit["minimal settle → parse + admit<br/>→ Store commit"]
    Legal -->|no: true edge<br/>or clamped overdrag| Deplete["deplete this directional ray"]
    Commit --> Callback["observation callback"]
    Callback -->|finish| Finalize{"caller-selected exit position"}
    Callback -->|continue, including empty page| Move
    Deplete --> Opposite{"opposite ray remains?"}
    Opposite -->|yes| RestoreBetween["restore saved origin<br/>settle + parse + commit"]
    RestoreBetween --> OtherRay["scan opposite ray"]
    OtherRay --> Move
    Opposite -->|no| Finalize
    Finalize -->|origin| RestoreAll["restore touched scroll views<br/>settle + parse + commit"]
    Finalize -->|current| Retain["retain current viewport"]
```

The two rays are independent because the explorer commits the saved origin
between them. Empty pages do not imply an edge. A direction depletes only when
the next page cannot change the clamped legal content offset; UIKit bounce and
stretch are outside that legal interval. The exit position is known before
traversal and is applied whenever traversal ends: command and wait discovery
restore `.origin`, while inflation retains `.current`. Restoration is itself a movement, so `.origin`
cannot return before its settle, observation admission, and Store commit finish.
When the callback already returned `finish`, final restoration does not invoke
that goal callback again. There is no alternate traversal or commit path.

## Wait Lifecycle

```mermaid
flowchart TD
    Start["PredicateWait.Execution<br/>one direct wait pipeline"] --> Visible["bounded visible check"]
    Visible -->|matched| Match["return matched"]
    Visible -->|unmatched| Route{"one eligible, already-resolvable<br/>terminal element target?"}
    Route -->|yes| Admit{"ordinal-free semantic target<br/>uniquely selects chosen element?"}
    Admit -->|yes| Reveal["reveal semantic target<br/>retain .current"]
    Admit -->|no: ordinal-dependent,<br/>missing, or ambiguous| TargetFailure["target-resolution failure<br/>no stale-id fallback"]
    Reveal --> RevealCommit["settle and commit<br/>each viewport capture"]
    RevealCommit --> ResolveCurrent{"re-resolve semantic target<br/>in committed InterfaceTree"}
    ResolveCurrent -->|one match| CurrentHandoff["adopt this capture's HeistId<br/>for live handoff"]
    ResolveCurrent -->|missing or ambiguous| TargetFailure
    CurrentHandoff -->|more movement| Reveal
    CurrentHandoff -->|positioned| Prepare
    Route -->|appearance, unresolved,<br/>container, or multiple targets| Discovery["canonical directional discovery<br/>restore .origin"]
    Prepare["standalone temporal: establish baseline once<br/>action expectation: preserve supplied baseline"]
    Discovery --> Prepare
    ActionBaseline["supplied pre-action SettledCapture"] -.-> Prepare
    Prepare --> Evaluate["evaluate current tree or accumulated<br/>baseline-through-current window"]
    Evaluate -->|matched| Match
    Evaluate -->|unmatched| Idle["idle on retained log<br/>stream waiters"]
    Idle -->|retained entry| Window["build every accumulated<br/>baseline-through-entry window"]
    Window --> EntryEvaluation{"matched?"}
    EntryEvaluation -->|yes| Match
    EntryEvaluation -->|no, time remains| Route
    Idle -->|terminal reserve reached| FinalVisible["final visible settle<br/>same operation deadline"]
    FinalVisible -->|matched| Match
    FinalVisible -->|unmatched, time remains| FinalSearch["final reveal or canonical discovery<br/>same operation deadline"]
    FinalSearch -->|matched| Match
    FinalSearch -->|unmatched| Timeout["return timed out"]
```

The wait does not poll while idle. Retained entries are the wake-up mechanism;
an unmatched entry re-runs the same reveal or discovery route. A standalone
temporal baseline is established only after initial positioning; every later
evaluation uses the full accumulated window from that immutable baseline.
Action expectations keep the supplied pre-action baseline. The terminal visible
check, reveal, discovery, and waiter phases inherit one authored operation
deadline. Already-settled truth remains immediately evaluable; new settlement
or discovery starts only when the remaining budget contains the settle reducer's
declared quiet-window floor. After each reveal or discovery, the wait records its route cost and
reserves the longest observed duration so terminal verification starts before
that deadline. Terminal work receives no fresh 250 ms budget and no discovery
continues after the operation deadline. Every stage returns immediately when
the predicate is fulfilled, and no compatibility wait orchestration exists.
An eligible exact-target reveal admits semantic identity before its first
capture boundary, re-resolves that identity after every reveal commit, and uses
only the resulting capture's current `HeistId` for live handoff. A missing or
ambiguous match ends that inflation attempt safely instead of retaining an old
id or substituting a sibling.
`PredicateWait.Execution` directly coordinates the visible, reveal/discovery,
retained-log waiter, and terminal verification stages.
`PredicateObservationStreamState` only reduces one settled observation against
the immutable baseline and owns no lifecycle or history.

## Screen Boundaries

A screen boundary is one typed transition with this fact order:

```mermaid
sequenceDiagram
    participant Old as Old generation
    participant Facts as Ordered facts
    participant New as New generation

    Old->>Facts: every old node disappeared
    Facts->>Facts: screenChanged marker
    New->>Facts: every new node appeared
```

Consequences:

- `changed(.screen(...))` requires the screen marker, then evaluates its
  `exists` and `missing` assertions against the current tree.
- `changed(.elements(...))` can match same-screen lifecycle changes or the
  disappearance and appearance facts produced by a screen boundary.
- `updated` is constructible only from two captures in the same generation.
- Notification checkpoints retain their source events. Overflow is explicit
  `AccessibilityNotificationGap` evidence rather than silent history loss.
- Presence uses the same `AccessibilityTarget` resolver as actions and
  `get_interface`, including container and descendant-scoped targets.
- Only a complete, fact-free window can satisfy `noChange`.
- Public delta is output only. When a window contains a screen marker,
  `screenChanged` dominates the final public delta kind.
