# Migrating off the git model onto ticks

Branch: `alex/nightly-watchdog-correctness` (PR #1402)

## The two models

**Git model (old).** Captures are immutable commits carrying `parentHash` +
`sequence`, validated for canonical lineage on construction and decode. What
happened is a *diff* computed between adjacent commits. The durable artifact is
an `AccessibilityTrace` — a commit chain you walk and diff. A reading is a
transaction: prepared, validated, atomically published, guarded by a delivery
token, and markable dirty by "invalidation."

**Tick model (new).** The vault mints a tick per moment, and the tick carries
the full snapshot. What happened was decided once, in the vault, when it chose
which tick to mint. Nothing downstream diffs anything, and nothing asks a
recording for a live fact.

## Invariants the new world holds to

1. The vault owns all determinations about state. Everyone else reacts to the
   ticks it emits. Nobody else reasons about this.
2. The vault is the only emitter of ticks.
3. Ticks are atomic *at the machine*: one tick, one pass, one settle check. The
   original bug was folding three ticks into a single `admit` — not the array
   itself. Carrying ticks around in an array is fine; ticks are sequential. The
   only rule is that they enter the pipe one at a time in the correct order.
   There is no timing component — *when* a tick arrives is not part of the
   contract, only its position in the sequence.
4. `.noChange` is the carrier that proves the stream is alive. Interesting ticks
   ride *between* carrier ticks, never on them.
5. The TickLog is a recording of the past and a source of no live truth. Nothing
   is inferred from it; it is appended to and never read until the run is over.
6. There is one lane. Predicates that do not care about a tick are indifferent
   to it, which is not routing.
7. Nothing latches. Predicates match and disappear; an empty list is the only
   record that they did.
8. There is no such thing as invalidation. Data that is stale is *gone* — the
   next reading mints the next tick. Nothing is marked dirty, because there is
   no working copy to mark.
9. A screen change is one event in the world and six steps in here, and the
   ticks go out *as those steps happen*, not derived afterwards from the
   collapsed result.
10. **The tick machine has no concept of time, only order.** Every snapshot or
    announcement in the vault is *now* until the next one arrives, so "the
    newest entry" is the present by definition. There is no freshness to
    consult and no such thing as a reading that exists but is stale.
11. **The only legitimate consumers of wall-clock time are the timeout and the
    Safecracker.** Anything else reading a clock is reasoning about time it has
    no business knowing.

    The Tripwire is the *boundary* where real time enters and becomes order —
    which is what makes its display link a half concept. `CADisplayLink` is
    genuinely wall clock: hardware refresh, 60/120Hz, and `updateDisplayLinkRate`
    tunes it. It has to be real, because only the hardware knows when a frame is
    ready to sample. But `onTick` does `tickCount += 1`, reads, and resolves
    waiters with `.observed` — a position, never a duration. Nothing downstream
    learns when it fired, how long since the last one, or at what rate.

    A clock on the inside, a counter on the outside. That is why it is the basis
    of the tick-based timing rather than an exception to it: everything after it
    inherits a sequence, and the sequence has a real cause. The display link is
    not a third consumer — it is the boundary.

    **Verified against the tree.** Every wall-clock use in the settlement runtime
    is arming a deadline: `SemanticObservationTiming:64`, `Settlement:33`,
    `Settlement+Reducer:187` (readiness allowance), `:357` (handoff allowance),
    plus `TheBrains:330` (cleanup on teardown). One mechanism, several phases.
    Nothing measures elapsed time to decide behaviour and nothing compares
    durations to conclude the UI settled.

12. **There is one of each of them.** One brains, one tripwire, one safecracker,
    one vault. Each could be a singleton if it were worth the ceremony. So any
    machinery whose job is to decide *which of the many* gets something, or to
    reconcile two of them racing, is modelling a plurality that does not exist.
    A dictionary keyed by subscriber, an ordering queue over competing readers,
    a token proving which reader won — each is the git model's
    many-working-copies assumption wearing a different hat.

    The exception to watch for is something plural *within* the one instance.
    Scope pressure is genuinely a max over several held scopes, because one run
    nests scopes inside itself. That is plural scopes, not plural consumers.

    **What this collapsed, in `Observation.Stream`:**

    | Was | Modelled | Is |
    |---|---|---|
    | `subscribers: [UInt64: Subscriber]` + broadcast filter | many listeners, route by scope | `receive:` — one closure |
    | `DeliveryState` (~50 lines: `nextOrder`, `pending`, contiguity drain) | many readers racing for order | gone; the vault emits in order |
    | `publicationWaiters: [DeliveryToken: …]` | many awaiting publication | gone |
    | `DeliveryToken` / `DeliveryGeneration` / `CommittedDelivery` | proving which reader won | gone |
    | `latestDelivered*` | a delivered copy distinct from the store | `latestRead*` — a main-actor mirror of the store |
    | 4 × `invalidate*` entry points | marking a working copy dirty | `discardCurrentObservation` + `discardIfScreenChangedSinceRead` |
    | `SemanticObservationScopePressure` | — | **kept.** Plural scopes, not plural consumers. |

    The comment that gave it away, on the old `beforeVisibleReading` seam:
    *"whether a second consumer starts its own or joins this one."* There is no
    second consumer.

    The ~9 `instant: ContinuousClock.Instant` fields on `Settlement` types are
    not a second time concept: the reducer is pure and cannot read a clock, so
    the instant rides in on the fact for a deadline to be armed from. That is the
    timeout's plumbing.

## The screen boundary, in full

Per `screen-change-timeline.md`:

1. Detect
2. **empty `elementsChanged` tick** — the departure. Identity does not survive a
   boundary, so a `missing` half needs a reading holding none of what left.
3. Throw away the tree, parse visible, classify
4. **`screenChanged` tick** — the identity moves. Lands *before* the arriving
   graph: naming a screen needs only what is on it.
5. Stitch edges (`fullGraph()`) — **NOT CALLED TODAY. Real hole.**
6. **graph `elementsChanged` tick** — the arrival

The order is what a boundary *means*. Deriving all three from one finished
commit gets the order right and the layering wrong: by commit time the moments
have already collapsed, step 2's "empty tree" is a device minted after the
arrival was already parsed, and step 5 has nowhere to live.

## Inventory: which systems are in which shape

| System | Shape |
|---|---|
| The one comparison (`SnapshotEvent.isChange`) | new — single decision point, vault-owned |
| Screen classification (`ScreenClassifier` → `ScreenContinuity.isReplacement`) | new — vault-owned |
| Tick vocabulary (`Tick`: 4 cases, full payloads) | new |
| Predicate evaluation (`Expectation`, `PendingStep`, `PendingPredicate`) | new (this PR) |
| `TickStep` + `TickLog.steps` | **git residue, DEAD — zero production consumers** |
| Vault publish path (commit transaction + delivery token) | **git** |
| `Capture.parentHash` + `hasCanonicalLineage` | **git** |
| `availability` + invalidation | **git — there is no invalidation** |
| `AccessibilityTrace` | git, but load-bearing as the report/wire artifact |
| `Evidence/` diff layer (~3400 lines) | git, wire-locked by JSON fixtures |
| `AccessibilityObservationChangeReducer` | transitional; dies when the live log is durable |

## Plan

Ordered so that each phase leaves the tree in a judgeable state, cheap deletions
come before decisions, and nothing blocks on an unanswered question.

**Checkpoint discipline:** the tree must *build* at the end of Phase B, even if
tests fail. Everything after that is judged on tests. A long red stretch with no
build is how the last one went wrong.

### Phase 0 — where the tree stands
- `Observation.Event.ticks` and `SnapshotEvent.ticks` are **deleted** (they were
  the collapse, one layer up from the first one).
- **The tree does not build. Expected. Do not "fix" it by restoring a ticks
  property at the vault boundary — that is the rejected layering.**
- Outstanding build breaks: `publishImmediately(.tick(...))` in
  `SemanticObservationStream+Settlement.swift` names a case that does not exist
  yet (see Phase 4 — the log holds ticks); the orphaned delivery plumbing from
  Phase 2; ~10 call sites still on the old `latestCommittedEvent()` name;
  9 errors from a `throws` added to `SettlementReducerTests.admission`.

### Phase 1 — the store emits ticks — **DONE**
- `Store.commitObservation` → `readObservation(_:emit:)`, emitting at its own
  steps: departure tick *before* the old tree is let go, `screenChanged` *after*
  the log records, arrival tick after the new tree is installed. Non-boundary
  readings emit the one tick `isChange` produces.
- `CommittedObservation` → `ReadObservation`.
- **Still to do:** the missing `fullGraph()` call at step 5, between ticks 4 and
  6. It lives on `Navigation` (`TheBrains`), is `async`, and commits readings of
  its own — so it cannot be called from inside the store's synchronous mutation.
  It is work the *stream* schedules between emitting tick 4 and tick 6.
- Keep a separate query API for the tree-and-sequence consumers
  (`ElementInflation`, `Navigation`, `InteractionCoordinator` — ~12 sites on
  `latestReadEvent()` / `settledEvent(after:)`). They ask a different question
  and must not be forced through ticks.

### Phase 2 — delete the transaction — **MOSTLY DONE**
- Deleted: `StoreOwner.commitAdmission`, `resolveDelivery`, `DeliveryToken`,
  `DeliveryGeneration`, `CommittedDelivery`, `DeliveryAdmission`,
  `DeliveryResolution`, and the readmit/supersede loop in
  `publishCommittedObservation` — replaced by: read, then push each tick into
  the pipe in order.
- **Still orphaned, delete next:** `deliveryState`, `PendingDelivery`,
  `waitForPublication`, `completePublication`, `synchronizeDeliveryGeneration`,
  `latestDeliveredSnapshotEvent`, `beforeCommittedDelivery`,
  `beforeResolvedDeliveryEnqueue`, `enqueueValidatedDelivery`.
- `CommittableInterfaceObservation` still exists; it is the pre-transaction
  "not yet committed" value and should go with the rest.

### Phase 3 — delete invalidation — **DONE**
- `Availability` (3 states) deleted. `.invalidated(.some)` was serving a reading
  it called invalid — incoherent once every reading is *now* until the next.
- `latestCommittedEvent`/`Snapshot`/`Moment` → `latestReadEvent`/`Snapshot`/
  `Moment`, reading straight off the log.
- Four discard entry points (`invalidateCurrentObservation`,
  `invalidateIfSignalChanged`, `requireReplacement`, `clearCurrentInterface`)
  collapsed to `discardCurrentObservation` + `discardIfSignalChanged`.
- Old names for reference: `availability`, `.invalidated`,
  `invalidateCurrentObservation`, `invalidateIfSignalChanged`,
  `latestSettledObservationInvalidated`,
  `invalidateLatestSettledObservation`, `invalidateDeliveryIfSignalChanged`
- Confined to `SemanticObservationStream*.swift` + `Store`/`StoreOwner`. The
  other 30-odd `invalidate` hits in the tree are unrelated (CADisplayLink,
  transport, readiness) — leave them.

### Phase 4 — the log holds ticks, and derivable state comes off the event

`Observation.Event` and `Tick` are the two sides of the one comparison, not two
views of one thing. `SnapshotEvent` is the **input** to the decision (how the
reading was obtained); `Tick` is the **output** (what happened, in the vocabulary
predicates evaluate). Once the tick is minted the event's job is done — which is
exactly what "the vault owns all determinations" means.

The bug this phase fixes: `SnapshotEvent` caches four answers the log can already
give, and caching them is what invited re-deriving the boundary at four separate
layers.

**Derivable from the log — cut from the event:**

| Field | The log answers it by |
|---|---|
| `previous: Snapshot?` | stepping back one snapshot entry. `Log.record` *already* computes this as `latestSnapshotEvent`, then stores a copy on the event. Pure duplication. **This is the field that invited the four re-derivations.** |
| `transition` | `(previous, moment, generation)` — all in the log. Two consumers, both in `AccessibilityObservationChange`, the stored-trace rebuild already slated to die. |
| `generation` | **counting `.screenChanged` entries.** A `.screenChanged` tick *is* the generation boundary, so `ScreenGeneration` — a bare `rawValue + 1` counter — carries nothing the log lacks. Structural, not a walk over values. |
| `sequence` | position. But see the ordering note below. |

**Not derivable — genuinely belongs on the event:**
- `continuity` — the *decision*, not a record of one. `ScreenClassifier.classify`
  consumes trees, notifications and lineage, none of which survive on the entry.
  9 live consumers in `Navigation`/`ElementInflation`. It is the input that picks
  which tick gets minted.
- `logIndex` — the position itself. Cannot derive position from position.
- `sourceScope`, `captureID`, `notificationSequence`, `semanticSignal` — facts
  about *how* the reading was taken. Recorded, not recomputable.
- `viewportFrames` / `placementTolerance` — inputs to `isChange`'s stillness
  half; the tolerance is a runtime value (`CoarseFrameComparison.currentTolerance`).

**Dependencies, checked against the code — not what I first assumed:**
- `SnapshotEvent.transition` has **zero consumers**. It is computed in
  `Log.record` and never read. Free deletion, no coupling.
- `AccessibilityObservationChangeReducer` reads `Capture.transition` — the *wire*
  type, a different field with the same name. So this phase and Phase F are
  **independent**; I earlier thought they were entangled.
- `generation` escapes to the wire as `Capture.context.observationGeneration`,
  read by the stored-trace rebuild. Cutting it is **not vault-local** and touches
  the encoding.

This phase is broken into A–D below because "the log holds ticks" was one line
carrying four separate decisions.

---

## The reordered sequence

Phases 1–3 and 7 are done (above). What remains, in dependency order:

### A — pure deletion, nothing to decide
No design questions, no behaviour change, largest remaining chunk of straight
removal. Do this first because it shrinks everything after it.
- The orphaned delivery plumbing: `deliveryState`, `PendingDelivery`,
  `waitForPublication`, `completePublication`, `synchronizeDeliveryGeneration`,
  `latestDeliveredSnapshotEvent`, `beforeCommittedDelivery`,
  `beforeResolvedDeliveryEnqueue`, `enqueueValidatedDelivery`,
  `CommittableInterfaceObservation`.
- `SnapshotEvent.transition` — zero consumers.
- `SnapshotEvent.previous` — the retained comparison operand. `Log.record`
  already computes it as `latestSnapshotEvent`; only `isChange` reads it, and
  only during the comparison. **This is the field that invited four
  re-derivations of the boundary**, so removing it removes the temptation
  structurally.
- `PulseReading.timestamp` — wall clock past the boundary, zero readers.
- `TickLogFoldTests` leftovers if any remain.

### B — make the tree build  ← **CHECKPOINT**

**The `.noChange` routing question was fake — RESOLVED.** There is only one
consumer of the stream. Every `subscribe(scope:)` call site:
- `SemanticObservationStream+Settlement.swift:13`, `:40` — `receive: { _ in }`,
  the no-op default. These register **scope pressure**, not delivery.
- `SemanticObservationStream+Waiters.swift:98`, `:119` — one-shot "tell me when
  the next reading lands", not an ongoing consumer.
- `Settlement+Execution.swift:985` — **the run. The only tick consumer.**

So `canFulfill` is not dividing a stream between competing listeners; the run
subscribes at its own scope and filters its own input. A bare `.noChange` needs
no scope, because there is no other subscriber it could wrongly reach.

*How this went wrong:* the code says `subscribers` (plural), has a subscription
type and a broadcast filter, and I took that machinery as evidence of the
situation it was designed for instead of checking who actually listens.

**`subscribe` is two jobs under one name.** `SemanticObservationScopePressure`
does no delivery at all — `subscribedObservationScope()` is
`subscriptions.values.max()`, i.e. "what is the widest scope anyone wants", which
is how the vault decides how hard to look; `activeObservationDemands` is a count
driving cadence. Split them: pressure keeps `addSubscription`/`removeSubscription`,
delivery becomes a single receiver rather than a dictionary.

Then: fix the ~10 `latestCommittedEvent()` call sites, and the `throws` on
`SettlementReducerTests.admission`.

**Tree builds at the end of B.** Tests may fail.

**DONE.** What B turned out to include beyond what was written above:

- **`Observation.Event` was redesigned**, which was not in B's scope and is what
  generated most of its churn. `.snapshot(SnapshotEvent)` became
  `.read(SnapshotEvent, Tick)` + `.replayed(SnapshotEvent)`. A live reading
  carries the tick the vault minted; a log reading carries none. Two cases rather
  than a `Tick?`, so a consumer must say which it handles.
- **`SemanticObservationPublicationTests.swift` deleted whole** (~680 lines). It
  tested the delivery model itself — tokens, ordering, supersession, readmission
  — so there was nothing to port it to. See F2 for what its intent becomes.
- **`derivedTick`** on `SnapshotEvent`, one named site for the two stopgap paths
  rather than four inline copies. Deleted in F.
- **`generate-project.sh` must be re-run after deleting a test file**, or the
  build fails on a missing input that is no longer referenced by any source.
- Renames: `latestCommitted*` → `latestRead*`, `requireScreenReplacement`/
  `clearCurrentInterface`/`invalidateLatestSettledObservation` → one
  `discardCurrentObservation`, `commitObservation` → `readObservation(_:emit:)`.
- Assertions on `latestSettledObservationInvalidated` were **removed rather than
  renamed** — there is no staleness flag to assert on, and one of them
  (`TheVaultResolutionTests:422`) asserted a settle failure marks the reading
  invalid, which now contradicts the assertion two lines above it that the tree
  survived.

### C — `fullGraph()` at step 5
Currently never called, so edges are never stitched after a boundary. A real
hole, independent of everything above.

**The design hole, stated honestly:** `fullGraph()` lives on `Navigation`
(`TheBrains`), is `async`, and commits readings of its own. It cannot be called
from inside the store's synchronous mutation, and it must not recurse. "The
stream schedules it between tick 4 and tick 6" is a direction, not a design —
where it actually lives needs deciding before this can be executed.

### D — `generation` off the event
Derived from `.screenChanged` boundaries in the log rather than a `rawValue + 1`
counter.

**Not vault-local:** `generation` escapes to the wire as
`Capture.context.observationGeneration` and is read by
`AccessibilityObservationChangeReducer`. Also `TheVault+Rotor` uses it as a
traversal cursor, which becomes "has a boundary landed since I started."
Deferred until after the wire boundary is understood (Phase F).

### E — extract `TheTimeout`
Contained, does not block the vault work, but mixing it into the migration diff
makes both harder to judge. Detail below.

### F — the `Evidence/` layer reads ticks
`AccessibilityObservationChangeReducer` dies here. Wire-locked, largest piece.
`sequence` → `logIndex` (87 sites) lands after this, once the log holds ticks and
the two counters are genuinely one.

**Also here: the log must hold the ticks it minted.** B left two stopgaps that
violate invariant 1, both in `Settlement+Execution.swift`'s `fact(for:)`.

1. **`.replayed`.** The run subscribes `replayingAfter: arming.boundary.moment`
   so a reading landing between the boundary capture and the subscription still
   reaches it. Those arrive off the log — and the log records *readings*, not the
   ticks the vault minted for them.
2. **`.captureCompleted(.handoff(…))`.** `boundary.admit` (line ~969) wraps a
   `SnapshotEvent` it was handed and returns `.admitted(event)`. The capture went
   through the vault upstream, but only the reading survives the trip.

Both rebuild a tick from `event.isChange`:

```swift
tick: event.isChange ? .elementsChanged(event.moment.capture) : .noChange
```

`isChange` is the vault's own answer, read rather than recomputed, so the
non-boundary case is right. **A screen boundary is not:** the vault minted three
ticks for it and this yields one. The reconstruction also happens outside the
vault, which invariant 1 forbids regardless of whether the answer comes out
right.

Fix: the log entry carries its tick, replay and `admit` hand it back, and both
cases stop deriving anything. Then `Event.read`/`.replayed` differ only in
provenance, not in what they carry.

### F2 — test coverage of the whole system

The old suite tested the git model's mechanics. Deleting that machinery deleted
its tests with it, so coverage has to be rebuilt — **preserving the invariants
and the intent of the old suite, but validating the new system rather than the
old one.** A ported test is a test of the thing that is gone.

**Deleted in A/B, with what each was really protecting:**

| Deleted test | Tested | The intent, restated for ticks |
|---|---|---|
| `testCommitDeliveryPublishesContiguousStoreOrder` | the ordering queue drains contiguously | **ticks reach the run in the order the vault minted them** — invariant 3 |
| `testLifecycleResetDropsSuspendedDeliveryFromPriorGeneration` | generation-stamped delivery is dropped after reset | a reading taken before a discard does not reach the run |
| `testResetAfterActorResolutionSupersedesStaleMainActorEnqueue` | enqueue supersession across the actor hop | same, at the hop |
| `testOlderDeliveryDoesNotOverwriteNewerLiveCapture` | two readers racing over the live capture | **the mirror holds what the store holds** — no separate delivered copy to go stale |
| `testInvalidatedDeliveryReadmitsCurrentSourceOnce` | the readmit loop readmits exactly once | there is no readmission: a discard means the next reading opens a new screen — invariant 8 |
| `testRepeatedInvalidationSupersedesBoundedReadmission` | readmission is bounded | same |
| `testInvalidationPreservesLogButBlocksAdmittedRead` | a reading in the log refused as stale | replaced by `testDiscardKeepsTheLogAndTakesTheTree`: the log keeps what was read, the tree goes — invariants 5 and 10 |
| `testDeadlineOnAMetAndQuietRunSettlesRatherThanTimesOut` (SettlementReducerTests) | one folded admission ends the run | each tick is reduced on its own and asked whether it ended the run |

**What the new suite has to cover, none of which the old one could:**

1. **One tick, one pass.** A screen boundary is three ticks; each is a separate
   reduction, each asked whether it settled the run. The original bug was
   folding them — a test has to fail if they refold.
2. **Boundary order.** Departure (empty `elementsChanged`), then `screenChanged`,
   then arrival (graph `elementsChanged`). The departure must be emitted while
   the old tree is still what the vault holds.
3. **`.noChange` as a real gate.** Stillness is a tick that drains a predicate,
   not a latched Bool and not an empty array.
4. **Nothing latches.** Predicates match and disappear; an empty list is the
   only record — invariant 7.
5. **The vault is the only emitter.** Nothing downstream mints or derives a
   tick. The two `derivedTick` stopgaps are the current exception and their
   removal is Phase F; a test should pin that once they are gone.
6. **Order without timing.** No test may assert *when* a tick arrived, only its
   position — invariants 3 and 10.
7. **One consumer.** The stream has one receiver; scope pressure is a max over
   held scopes and is a separate question from delivery — invariant 12.

**Sequencing:** this lands after F, because F removes the `derivedTick` stopgaps
and moves the ticks into the log. Writing the tests before that pins the stopgap
as if it were the design.

### G — lineage, rename, docs, green
`parentHash`/`hasCanonicalLineage`; the `Settlement` → heist-step rename; the doc
rewrite; then the three CI failures.

#### G-docs — the README and `docs/` describe the git model as current

Not a refresh. The docs state the deleted machinery as the design, so they are
wrong rather than stale, and a reader following them today would build against a
model that no longer exists.

| File | Lines | Stale-model hits | Shape of the work |
|---|---|---|---|
| `docs/ARCHITECTURE.md` | 903 | **71** | the concentration; the observation section is a spec of the old pipeline |
| `docs/API.md` | 620 | 12 | surface names that moved (`latestCommitted*`, delivery outcomes) |
| `docs/ACCESSIBILITY-CONTRACT.md` | 182 | 8 | commit/invalidation as the contract's vocabulary |
| `docs/HEIST-LANGUAGE-SPEC.md` | 447 | 6 | mostly incidental, needs reading |
| `docs/DESIGN-RATIONALE.md` | 141 | 5 | argues *for* the git model in places |
| `README.md` | 501 | 2 | light. **Protected by AGENTS.md — do not edit without an explicit ask.** |

**Already done on this branch:** the DSL surface rename reached the docs —
`.changed(.elements([…]))` → `.elementsChanged([…])` across 13 files, so the
authored *examples* already speak ticks. What G-docs owes is the **prose**: the
paragraphs that describe how observation works are still the git model.

**The passages that are actively wrong**, all in `ARCHITECTURE.md` and all
describing what A and B deleted:

- `:102` "asks the Store to commit it" — the store reads; nothing commits.
- `:105` "publishes that same committed event only after the Store exposes it" —
  the store emits ticks as it reads; there is no publish-after-expose step.
- `:110-114` "a changed signal invalidates the admitted read […] reuse the
  committed event until the next trip, explicit invalidation, or screen
  replacement" — invariant 8: nothing is invalidated, the tree is discarded.
- `:112` **"Concurrent consumers join that cycle"** — invariant 12. This is the
  plurality written down as architecture, and it is the sentence that most needs
  to go.
- `:166` "Every capture follows capture → admit → commit" — the pipeline is
  capture → read → tick.
- `:73` "The committed `TheVault.interfaceTree` is the sole current semantic
  truth" — right in substance, wrong in name: it is the main-actor mirror of what
  the store holds.

**Sequenced last, after F2.** Docs written before the code settles describe an
intermediate state. The earlier doc purge in A cut comments and two `.notes`
files wholesale on the same reasoning — this is the rewrite that purge deferred.

---

## Phase detail

### Phase 5 — extract `TheTimeout`

The timeout is one of only two consumers of wall-clock logic, and it is currently
spread across four types with overlapping jobs:

| Today | Holds | Where |
|---|---|---|
| `SemanticObservationTiming` | the default budget (1s) + `viewportTransitionMinimumBudgetMs` | `SemanticObservationTiming.swift` |
| `SemanticObservationDeadline` | `start` + `timeout`, `hasTimeRemaining`, `remainingSeconds`/`remainingDuration`, `elapsedMilliseconds`, `reserving` | same file |
| `Settlement.PhaseDeadline` | `phase` + target `instant`, `remainingDuration` | `Settlement.swift:91` |
| `Settlement.ActionAllowances` | readiness / expectation sub-budgets | `Settlement.swift:103` |
| `RuntimeElapsed` | the clock read (`now`) + elapsed measurement | `RuntimeElapsed.swift` |

Two deadline types with near-identical methods, the budget constant in a third
place, the clock in a fourth.

**`TheTimeout`** — named to match `TheVault` / `TheBrains` / `TheTripwire` /
`TheSafecracker` / `TheFence` — owns all of it:
- the budget and its defaults
- the clock read (`RuntimeElapsed` folds in; it is used for nothing but deadlines
  and elapsed reporting)
- deadline arming, including phase and allowance carve-ups
- `hasTimeRemaining` / `remaining` / `elapsed`
- `reserving` — budget subdivision

**Why it is worth a type and not just a rename:** it makes invariant 11
structural. `TheTimeout` becomes *the only thing in the system that reads a
clock* (the Safecracker aside, and the Tripwire's display link is the boundary,
not a consumer). Today that rule lives only in this file; as a type it is
greppable — any `ContinuousClock` / `CFAbsoluteTimeGetCurrent` / `Date()` outside
`TheTimeout` and `TheSafecracker` is a violation.

**Open shape question:** `SemanticObservationDeadline` carries `start` (so it can
report elapsed and subdivide via `reserving`); `PhaseDeadline` carries only the
target `instant` plus a phase tag. Either
- **one type with a phase**, simpler if phases do not nest, or
- **`TheTimeout` owns the budget and hands out phase deadlines** — closer to what
  the code does now (one budget carved into readiness / expectation / observation).

Sequencing: after the tree builds. It is a contained extraction and does not
block the vault work, but doing it mid-migration mixes two large diffs.

### Phase 6 — delete lineage
- `Capture.parentHash`, `AccessibilityTrace.hasCanonicalLineage` and the decode
  guard. A tick carries the full snapshot; lineage validation protects a commit
  chain that no longer exists. 14 sites.
- Wire contract: `parentHash` is encoded. Check the encoding-stability tests
  before removing it from the payload.

### Phase 7 — delete the dead diff API — **DONE**
- `TickStep`, `TickLog.steps`, `.interfaces`, `.elementEdits`,
  `.elementSetChanged`, `.crossesScreenBoundary` — deleted (150 → 62 lines).
- `TickLogFoldTests` coverage of them deleted, plus `testStillnessIsTheNewestTick`
  which asked the recording for a live fact.
- `TickStep` is **not** `PendingStep`. `PendingStep` is the predicate holder (the
  1D 3-case enum) and is untouched.

### Phase 8 — `Evidence/` reads ticks instead of re-diffing
- Change facts stop being computed by diffing two captures and start being read
  off the ticks the vault already minted.
- **Wire-locked**: `elementSetChanged` and friends appear in JSON fixtures and
  encoding-stability tests. The encoding stays; only the producer changes.
- Largest piece. Last.
- `AccessibilityObservationChangeReducer` dies here — this is the "becomes a
  read instead of a rebuild" its own doc promises.

### Phase 9 — the rename
`Settlement` is misnamed: it is the whole runtime, not settlement. `Run` is
taken (that is the whole heist). Rename to heist-step vocabulary.
- Rename: the `Settlement` namespace, `SettlementExecutionBoundary`,
  `AdmittedSettlementFact`, `LiveSettlementExecutionBoundary`,
  `LiveSettlementLifecycle`, `executeSettlementCommand`, `beginSettlement`,
  `finalizeSettlement`, `SettlementResultScript`, `SettlementCompletionProbe`,
  `ScriptedSettlementBoundary`, `scriptedSettlement`, 4 test classes.
- **Leave**: `ObservationSettlement`, `produceVisibleSettlement`,
  `activeSettlementBoundaries` (vault-side, genuinely settling) and
  `HeistSettlementEvidence` / `ActionSettlementEvidence` (wire types under an
  encoding-stability contract — `testExistingSettlementEncodingsRemainStable`).
- ~713 occurrences, 66 files, 5 files named `Settlement*`.

### Phase 10 — docs, rewritten from the tick model
Comments and notes describing the old model were **cut wholesale** (see below);
the repo docs were deliberately left for a rewrite because they describe the
commit model as *the architecture*, not in passing:
- `docs/ARCHITECTURE.md` — 903 lines, ~25 commit-model references. "Every capture
  follows capture → admit → commit", "installs the graph, log, lineage and
  admitted-read state atomically", "consecutive unchanged observation diffs".
- `docs/ACCESSIBILITY-CONTRACT.md` — the capture/admit/commit/publish pipeline.
- `docs/DESIGN-RATIONALE.md` — "Ordered facts preserve what endpoint diffs
  erase" (this one is arguably already tick-shaped).
- The six-step screen boundary needs re-documenting somewhere; it lived in the
  now-deleted `screen-change-timeline.md` and survives only in this file.

### Phase 11 — green
Three known CI failures, all in territory the migration rewrites — which is why
they are fixed *after*, once, in the new world:
1. `MenuOrderDogfoodHeistTests` — settlement timeout. The atomic-tick +
   drained-gate work addresses this.
2. `TheBrainsActionTests.testExecuteCommandFailedActivateCarriesPostActionTraceLikeSuccessfulAction`
   — `XCTUnwrap` nil `Capture` at `TheBrainsActionDirectActionTests.swift:344`.
3. `TheTripwireHostedBehaviorTests.testAnnouncementExpectationLatchesUntilReadyHandoff`
   and `DogfoodFeatureFlowTests.testActionExpectationUsesTransientLifecycleEvidenceOnlyFromItsOwnAction`
   — both wait on the "Transient Flow" header then hit `no traversable app
   windows`.

## Already done on this branch (settlement side)

- `Tick.Kind` / `tick.kind` deleted; `Tick` is the enum
- lanes gone: `lane`, `reads()`, `admits()`, `matches()`, `matching()`, the
  cross-lane `preconditionFailure`
- predicate queue is a 1D array of a 3-case enum: `.single(p)`, `.pair(p, p)`,
  `.owed(after: Int, p)` — all data on the cases
- one verb, `evaluate`, returning `.indifferent` / `.matched` / `.unmatched`
- `draining` → `remaining(of:after:)`
- `TickLog.isStill` deleted; `TickLog.replacement` deleted
- `completedOutcome` no longer reads the TickLog
- `.noChange` is a real predicate, appended last as the gate
- `admit()` folds exactly one tick
- `consume` reduces per tick, so each gets its own settle check
- `Tick.observation(_:isChange:isReplacement:screenHeading:)` deleted
- `crossesScreenBoundary` pattern-matches instead of comparing kinds

## Doc and comment purge — done

Cut wholesale, no replacements (docs get redone in Phase 9):
- `TickStep` and every doc on it — "a change needs two", "the only place a tree
  is compared to another tree"
- `TickLog` struct doc — the paragraph arguing against the old model
- `AccessibilityTrace` — "Captures are the durable source of truth"
- `AccessibilityTrace+Diff` — "Captures remain trace truth"
- `Capture.parentHash` / `sequence` / `transition` field docs
- `CommittableInterfaceObservation` — "admitted for commit"
- Vault: `latestSettledObservationInvalidated`,
  `committedScopedScreenChangedSequence`,
  `invalidateSettledObservationIfScreenChangedSinceCommit`,
  `admitCurrentObservation`, `produceVisibleSettlement` doc blocks
- `Settlement+Execution.armReadiness` — "read the same commit outcome"
- `Navigation+Explore` — "answered on commit"
- `.notes/settlement-flow.md` — deleted (rejected "lane" language)
- `.notes/screen-change-timeline.md` — deleted (stale tick names, code pointers
  to deleted APIs). Its six-step boundary spec is preserved in this file.

Left alone deliberately: `discoveryCommitPolicy` (46 uses) and
`CommittedElementTarget` (13) are name collisions, not the commit concept.
`CATransaction.flush()`'s "commits before we sample" is a real CoreAnimation
commit.

## Wall-clock audit

**`PulseReading.timestamp: CFAbsoluteTime` — delete it.** Wall clock captured at
the display-link boundary and carried past it, with **zero readers** in sources
or tests. `tick: UInt64` is the position and is the only thing anything reads.
Deleting it makes the boundary honest: time enters, order leaves, nothing else
survives.

`Date()` survives in `SemanticObservationStream+Settlement.swift:154` (the
admission timestamp) and `WireConversion`/`TheVault+InterfaceState` defaults.
These flow into `Capture.interface.timestamp` — report metadata that nothing
branches on. Not part of the machine's reasoning, but worth a look during
Phase 7 when the report boundary is rewritten.

## Rules that keep biting

- Never restore a `ticks: [Tick]` property anywhere. Arrays of ticks are the
  bug. The vault emits them one at a time.
- Never derive the boundary sequence from a finished commit. Emit as the steps
  happen.
- Comments state what the code does — never what it isn't, used to be, or what
  was rejected.
- Never drive Swift edits via python string-replace. Use Edit; let the compiler
  enumerate call sites.
- `xcodebuild` via `scripts/test-runner.py`, never `swift build`. Never two
  runner invocations at once — it kills the simulator.
- Never `sleep` to wait for background work; use the completion notification.
