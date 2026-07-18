# Observation Pipeline

Button Heist has one current semantic graph owned by TheVault, one private
retained ordered history owned by `SemanticObservationLog`, and one delivery
path owned by `SemanticObservationStream`. Raw parser samples remain live or
diagnostic evidence. Only a clean settlement proof can enter the ordered commit
path. Presence reads the committed tree; temporal predicates and receipts read
replayable retained entries. The tripwire drives one serialized producer from
dirty state to a sealed clean publication. Consumers join that refresh or reuse
its clean commit.

**Illustrates:** [ARCHITECTURE.md](../ARCHITECTURE.md),
[API.md](../API.md), [WIRE-PROTOCOL.md](../WIRE-PROTOCOL.md)

**Source of truth:**
`ButtonHeist/Sources/TheInsideJob/TheVault/TheVault+InterfaceState.swift`,
`ButtonHeist/Sources/TheInsideJob/TheVault/SemanticObservationValues.swift`,
`ButtonHeist/Sources/TheInsideJob/TheVault/SemanticObservationLog.swift`,
`ButtonHeist/Sources/TheInsideJob/TheVault/SemanticObservationPublication.swift`,
`ButtonHeist/Sources/TheInsideJob/TheVault/SemanticObservationStream.swift`,
`ButtonHeist/Sources/TheInsideJob/TheBrains/SettleSession.swift`,
`ButtonHeist/Sources/TheInsideJob/TheBrains/Navigation+ScrollSettleProof.swift`,
`ButtonHeist/Sources/TheInsideJob/TheBrains/Navigation+Explore.swift`,
`ButtonHeist/Sources/TheInsideJob/TheBrains/Navigation+ExplorationScanning.swift`,
`ButtonHeist/Sources/TheInsideJob/TheBrains/Navigation+SemanticExploration.swift`,
`ButtonHeist/Sources/TheInsideJob/TheBrains/InteractionObservation.swift`,
`ButtonHeist/Sources/TheInsideJob/TheBrains/PredicateWait.swift`,
`ButtonHeist/Sources/TheInsideJob/TheBrains/PredicateWait+Evaluation.swift`,
`ButtonHeist/Sources/TheInsideJob/TheBrains/PredicateWait+ObservationStream.swift`,
`ButtonHeist/Sources/TheInsideJob/TheTripwire/AccessibilityNotificationBus.swift`

## Authority And Publication

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
    Settle --> Clean{"clean settlement?"}
    Clean -->|no| Diagnostic["failed-settle diagnostic<br/>no graph or log mutation"]
    Clean -->|yes| Outcome["SettleSession.Result<br/>exact final InterfaceObservation"]
    Outcome --> Admission{"stream admission<br/>tripwire + exact capture still current?"}
    Admission -->|no| Diagnostic
    Admission -->|yes| Proof["InterfaceObservationProof"]

    Proof --> Committer["SemanticObservationStream<br/>ordered admission + publication"]
    Committer --> Graph["TheVault.commitInterfaceGraph<br/>classify + commit current graph"]
    Graph --> Publication["construct settled publication<br/>from committed graph"]
    Publication --> Scope["project tree + trace evidence<br/>once per fulfilled scope"]
    Scope --> Log["private SemanticObservationLog<br/>publish retained entry"]
    Log --> Runtime["advance runtime generation<br/>and settled sequence"]
    Runtime --> Delivery["SemanticObservationStream<br/>complete waiters"]
    Runtime --> Cursor["ObservationCursor<br/>generation + sequence order<br/>capture-derived timestamp metadata"]
    Cursor --> Seal["clean publication<br/>admitting tripwire signal"]
    Seal --> Delivery
    Delivery --> Consumers
    Seal --> Armed["re-arm and wait for next trip"]
    Armed --> Tripwire
    Cursor --> Entries["SemanticObservationLog.read<br/>scope plus cursor replay"]

    Current["committed InterfaceTree"] --> Presence["presence and target resolution"]
    Graph --> Current
    Entries --> Window["ObservationWindow<br/>immutable baseline through current"]
    Window --> Temporal["temporal predicate and receipt facts"]
    Window --> Trace["AccessibilityTrace"]
    Trace --> Delta["one-way public delta fold"]
    Delta -. "never evaluator input" .-> Output["public output only"]
```

The ordering is structural: stream admission precedes TheVault's graph commit,
which computes the candidate tree, classifies continuity, admits the replacement
observation, and only then mutates canonical state. The graph commit completes
before private log publication; runtime state advances before stream waiters
are completed. This is an ordered, non-interleaving `@MainActor` sequence, not
an atomic transaction across Vault, log, runtime, and delivery owners. The
admitted result carries the exact parser observation which settled; the stream
rejects it if a later parse or tripwire signal superseded that capture. Each
fulfilled scope projects its tree and trace evidence from the same committed
observation. Consumers cannot observe an entry for graph state that has not
already committed, and consuming an entry cannot mutate the graph. Cursor
`observedAt` is derived from the capture's interface timestamp and is metadata;
generation and settled sequence provide correctness ordering.

Visible settlement is serialized. A trip invalidates the clean seal before a
read can be admitted. The first consumer starts the refresh and concurrent
consumers join it; once graph reduction, log publication, and runtime commit
complete, all consumers receive the same ordered event. Quiet action chains
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

```mermaid
sequenceDiagram
    participant Caller as Explorer / scroll / inflation
    participant Transition as performViewportTransition
    participant UIKit as UIKit viewport
    participant Settle as SettleSession
    participant Stream as SemanticObservationStream
    participant Graph as TheVault current graph
    participant Log as Private ordered log
    participant Callback as Observation callback

    Caller->>Transition: movement intent
    Transition->>UIKit: dispatch movement
    UIKit-->>Transition: moved
    Transition->>Settle: minimal settle: parse + one run-loop turn + repeat parse
    Settle-->>Transition: clean outcome with exact final observation
    Transition->>Stream: admit and commit outcome
    Stream->>Stream: verify tripwire and capture identity<br/>construct InterfaceObservationProof
    Stream->>Graph: reduce graph
    Graph-->>Stream: committed tree
    Stream->>Log: publish retained entry
    Log-->>Stream: published
    Stream->>Stream: advance runtime state<br/>complete waiters
    Stream-->>Transition: settled event
    Transition-->>Caller: committed event
    Caller->>Callback: evaluate committed observation
    Callback-->>Caller: continue or finish
    Note over Transition,Callback: No next movement before commit<br/>Explorer waits for callback
```

```mermaid
flowchart TD
    Target{"known target with<br/>scroll-content point?"} -->|yes| Direct["jump directly to 2D content point"]
    Direct --> DirectCommit["minimal settle → parse proof<br/>→ graph reduce → stream commit"]
    DirectCommit --> RetainKnown["retain revealed viewport"]
    Target -->|no| Save["save visual origin"]
    Save --> Order{"caller-selected search order"}
    Order -->|forwardFirst| FirstForward["scan forward ray first"]
    Order -->|backwardFirst| FirstBack["scan back ray first"]
    FirstForward --> Move["move exactly one viewport"]
    FirstBack --> Move
    Move --> Legal{"legal content offset changed?"}
    Legal -->|yes| Commit["minimal settle → parse proof<br/>→ graph reduce → stream commit"]
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
cannot return before its settle, proof, graph reduction, and publication finish.
When the callback already returned `finish`, final restoration does not invoke
that goal callback again. There is no alternate traversal or commit path.

## Wait Lifecycle

```mermaid
flowchart TD
    Start["PredicateWait.Execution<br/>one direct wait pipeline"] --> Visible["bounded visible check"]
    Visible -->|matched| Match["return matched"]
    Visible -->|unmatched| Route{"one eligible, already-resolvable<br/>terminal element target?"}
    Route -->|yes| Reveal["inflate exact HeistId<br/>reveal + retain .current"]
    Route -->|appearance, unresolved,<br/>container, or multiple targets| Discovery["canonical directional discovery<br/>restore .origin"]
    Reveal --> Prepare["standalone temporal: establish baseline once<br/>action expectation: preserve supplied baseline"]
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
