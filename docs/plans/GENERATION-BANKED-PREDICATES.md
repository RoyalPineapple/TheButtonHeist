# Generation-Banked Predicate Lists

Status: design. Successor to `UNIFIED-SETTLEMENT.md`, which collapsed the four
timing systems into one clock and one comparison. That work made the change
event trustworthy. This work fixes what consumes it.

## The rule this restores

AGENTS.md, Button Heist House Style:

> Maintain one pipeline per concept: action, result, logging, error, evidence,
> observation, and settlement should each have one owner and one shape.

`WaitFor` and `expect` are the same concept with two shapes. They differ in
exactly one thing — where the baseline comes from — and are otherwise the same
machine: an ordered list of predicates drained across a growing window bounded
by a timeout.

## The model

**A step carries an ordered list of predicates, evaluated across one growing
window bounded by one timeout.**

Evaluation is triggered by a generation that proved a change, not by every tick.
A tick that changed nothing proves nothing and is not an evaluation point.

At each such generation:

1. Walk the remaining predicates **in order**.
2. Evaluate each against that generation's trace.
3. Remove the ones now satisfied — *bank* them.
4. Carry the rest to the next generation.

The step succeeds when the list empties. It fails when the timeout expires with
predicates still pending.

### What a generation is

A generation is **any semantic diff in the known tree**. Every tick takes a
snapshot and classifies it, in the same three-way language the predicates use:

| Tick classification | Meaning | Evaluation point |
|---|---|---|
| `.noChange()` | nothing semantically moved | no |
| `.elements(...)` | the tree changed within the same baseline | yes |
| `.screen(...)` | new baseline | yes |

The tick vocabulary and the predicate vocabulary are the same vocabulary. That
parallel is the point: a predicate asks about the kind of thing a tick reports.

A screen change is **not** a special checkpoint. It is one of the two change
classifications, and it advances the cursor exactly as an element change does.

`.noChange` ticks are **ignored for everything except keep-alive bookkeeping**.
They prove the pipeline is still running; they do not reach predicates, do not
advance the cursor, and are not inspected. The classification exists so a tick
can be dismissed cheaply.

The one exception is terminal: **`.noChange` is a legitimate end state for an
action.** An action that provably changed nothing settled successfully. That is
the `noChange` predicate being satisfied, and it is what converts case 3 of the
settlement four-case table (indefinite animation, no AX change) from failure to
success. Note this is a *window-level* question — "the window contained no
change" — not the per-tick classification of the same name.

**The existing `generation` counter is not this.** `SemanticObservationStore.swift:202-204`
advances it only on `continuity.isReplacement`, so it counts baselines, not
semantic diffs — it is a baseline counter carrying the name "generation".
`AccessibilityObservationChange` is closer, but it is a two-case enum
(`.elementChanged` / `.screenChanged`) with no `.noChange`: today "nothing
changed" is the *absence of a fact* rather than a classification. Making it the
third case is what lets a tick be classified rather than inspected.

### Why banking, not simultaneity

Today a multi-assertion predicate must hold *all at once*:

```swift
.changed(.elements([
    .appeared(.label("Processing")),
    .disappeared(.label("Submit")),
]))
```

If "Processing" appears at one tick and "Submit" is confirmed gone at a later
one, and "Processing" is gone by then, this never holds — even though both
events demonstrably occurred inside the window. That is the transient case the
system exists to catch: a toast is more than a tick, and it does not coexist
with the state that follows it.

Banking makes the conjunction accumulate. Simultaneity makes the most important
case inexpressible.

### One list, no cursors

The timeline is **single and sequential**. Everything that happens — a tree
diff, a spoken string — happens in one order, on one clock, and the evidence
records it that way. "This happened, then that happened" is always answerable.

The predicates are **one list**, authored in whatever order, freely interleaving
kinds. There is no split, no partition, and no cursor to maintain.

### The tick

**A tick carries one thing**: the next snapshot, or the next announcement. Not a
snapshot with announcements attached — a single event. That is what makes
announcements peers of snapshots rather than a side channel.

A `.noChange` tick carries nothing and is keep-alive only; it has nothing to
offer anyone.

### The baseline

There is **one global baseline** for the delta predicates — held by the run,
replaced when a screen change says so. Not a baseline per fact, not one per
predicate.

A delta predicate measures against *that*. It does not go hunting for which two
captures it is about, which is what `ChangeFactMetadata.captureEdge` exists to
answer today. With one baseline, that lookup disappears, and a predicate needs
the baseline and the tick rather than the whole window.

### The rule

> A tick walks the remaining list in order, asking only the predicates that
> answer its type. Each one it satisfies drops out. **The first one that answers
> its type and is *not* satisfied blocks the rest** — the walk stops there.

Two things follow, and both matter:

- A predicate of another type is **not asked** and does **not block**. A
  snapshot tick passes an unsatisfied announcement predicate as if it were not
  there.
- A tick is **not spent on one predicate**. It keeps satisfying consecutive
  predicates of its type until one refuses. `[appeared(A), appeared(B)]` against
  one settled snapshot showing both arrivals satisfies both.

The second is deliberate. A tick is one *settled* snapshot, and a settled
snapshot can evidence several arrivals at once. Spending the tick per predicate
would make the verdict depend on how finely the tripwire happened to sample —
the same UI with different frame timing would pass or fail — which contradicts
the display-linked rule this system is built on.

Blocking is what makes the list a sequence rather than a bag with
order-flavoured tie-breaking. It is the consumption step that makes the greedy
match exact: a later predicate cannot be satisfied by an earlier event, because
the unsatisfied predicate in front of it held the walk.

### The generic, as a fold

The kind-specific part collapses to one question — *does this predicate answer
this tick type* — and the walk is written once, **non-mutating**: list plus
tick in, new list out.

```swift
func remaining<T: Tick>(after tick: T, from pending: [Pending]) -> [Pending] {
    let blocked = pending.firstIndex { $0.answers(T.self) && !$0.isSatisfied(by: tick) }
        ?? pending.endIndex
    return pending.enumerated()
        .filter { $0.offset >= blocked || !$0.element.answers(T.self) }
        .map(\.element)
}
```

Find where the walk stops; keep everything from there on, plus the other-type
predicates interleaved before it.

**"Satisfied" is not state.** There is no flag on a predicate and no lifecycle —
satisfied means *absent from the returned list*. A predicate cannot be asked a
question at the wrong time because there is no wrong time to be in.

The whole step state is then the remaining list plus the baseline, and the
session is a fold over ticks:

```swift
ticks.reduce(authored) { remaining(after: $1, from: $0) }
```

Success is reaching empty; failure is the timeout firing with anything left.
Replayable by construction — same ticks, same result — which the report gets
for free.

`answers(_:)` is a type relationship, not a switch: `SnapshotPredicate` answers
snapshot ticks, `DeltaPredicate` answers snapshot ticks against the baseline,
`AnnouncementPredicate` answers announcement ticks. That is what the type split
buys — the four hand-maintained switches over the same distinction
(`isSnapshotPredicate`, `latchesPositiveEvaluation`, `Semantics.init(resolved:)`,
and the evaluator's own) all reduce to it.

This makes ordering between announcements expressible, which it is not today:

```swift
[.announcement("Saving…"), .announcement("Saved.")]
```

means those two, in that order, against the spoken stream — while any graph
predicates in the same step drain independently against generations.

Cross-lane order is **observable but not assertable**. The timeline records that
the toast appeared before "Saved." was spoken, and a report can show it. The
list cannot *require* it: because each cursor skips the other kind, authoring a
graph predicate before an announcement predicate constrains neither against the
other.

That is a deliberate limit, not an oversight. Requiring cross-lane order would
mean blocking one lane's cursor on the other's progress, which turns two exact
greedy matches into one that can deadlock on evidence that arrives in a valid
but unanticipated order.

This is also the boundary between the two predicate families, and it is already
enforced. Graph predicates target nodes; announcements match strings via the
shared `StringMatch` (`StringExpressions.swift:73-76`), so `.contains`,
`.prefix`, `.suffix` and `.exact` come from the same matcher the rest of the
language uses. The trace evaluator's refusal of announcement predicates
(`AccessibilityPredicate+Evaluation.swift:41-46`) is correct and stays: spoken
text is not in the graph, so the graph evaluator should refuse it.

### Why ordered, and why greedy is exact

The list is a cursor. Each predicate is banked at most once, at the first
generation that satisfies it, and is then removed from the check set. That is
greedy first-match, and it is exact for subsequence matching with
position-independent predicates by the standard exchange argument: if a match
exists at generations `j₁ < … < jₖ` and greedy banks at `g₁ ≤ j₁`, then by
induction `gᵢ ≤ jᵢ`, so greedy never blocks a feasible completion.

The precondition matters: predicates must be position-independent, and banking
must consume. Both hold here.

Order is meaningful *between* generations. Within one generation there is no
order — the generation is the unit of simultaneity.

## Snapshot and delta under banking

The two predicate kinds bank differently, and this is the rule that makes the
distinction load-bearing rather than decorative.

| | banks | re-evaluated |
|---|---|---|
| delta (`appeared` / `disappeared` / `updated`) | yes — permanent once proven | no |
| snapshot (`exists` / `missing`) | no | every evaluation point |

A delta asserts *an event occurred*. Events do not stop having occurred, so a
proven delta stays proven. A snapshot asserts *the tree is currently thus*, and
that can stop being true — so it must re-prove itself in each generation, and a
step whose `exists(X)` was true and is now false must fail.

This is already implemented one level up, and correctly:

```swift
// Settlement.swift:463-470
var latchesPositiveEvaluation: Bool {
    case .positiveTransition, .announcement:  true
    case .currentState, .completeHistory:     false
}
```

`.positiveTransition` is `changed(...)`; `.currentState` is `exists`/`missing`
(`Settlement.swift:174-185`). The same partition appears a third time as
`ResolvedElementAssertion.isSnapshotPredicate`. **Three hand-maintained switches
over one distinction, in two modules, with nothing making them agree.**

## What is wrong today

### Two layers disagree about whether matching consumes

- `Settlement.Requirement` latches: a delta is permanent once true.
- `evaluateElements` re-scans all facts for every assertion with no memory: a
  delta must be true *now*.

A delta predicate is permanent at the outer layer and instantaneous at the
inner one. Banking resolves this in favour of the outer layer, which is the one
that matches the model.

### The list does not exist at any layer

| Layer | Today | Needed |
|---|---|---|
| `WaitFor.init` | `_ predicate: AccessibilityPredicate` | `[AccessibilityPredicate]` |
| `WaitStep.predicate` | singular | ordered list |
| `.expect(...)` | singular | ordered list |
| `Settlement.Predicate.Requirement.predicate` | `Settlement.Predicate?` | list + per-item banked state |

`Requirement` holding one optional predicate is why there is no "next
unsatisfied predicate" to pull off.

### There is no tick classification to react to

Three counters are called "generation" and none of them is the one this needs:

| Name | Location | What it counts |
|---|---|---|
| `Readiness.Generation` | `Settlement.swift:497` | capture readiness |
| store `generation` | `SemanticObservationStore.swift:202` | baselines (replacements only) |
| `ClientDelivery.Generation` | `ClientDelivery.swift:10` | delivery epochs |

The classification this needs — `.noChange` / `.elements` / `.screen` per tick —
is closest to `AccessibilityObservationChange`, which is missing the `.noChange`
case. Settlement then has to drain the list on ticks classified as either change
kind.

### Nothing distinguishes "carried forward" from "failed"

An unsatisfied predicate at a generation boundary is `.unmet`. Under banking it
means "still pending, try next generation" — a different state with a different
terminal consequence.

## The collapse: `WaitFor` and `expect` are one machine

The difference is the baseline, and the code already isolates it to one
expression (`Settlement.swift:938-941`):

```swift
self.triggerEvidence = switch command {
case .action(let action): .actionPending(action.command)
case .currentState, .observation: .observation
}
```

`expect` takes the action's pre-dispatch capture as baseline. `WaitFor` takes
the current state. Everything after — ordered list, growing window,
generation-triggered draining, one timeout — is identical.

But they then diverge into separate `Command` cases and separate phases
(`.awaitingActionDispatch` vs `.observation(deadline)`) as though they were
different machines. They are not.

**After:** one session type with an ordered predicate list, a window, and a
timeout. Baseline is a parameter, not a case. `WaitStep` and the action
expectation stop being separate shapes.

This is why the change is smaller than it first appears: making `.expect()` and
`WaitFor` list-valued is *one* edit once they are one type, not two.

## Blast radius

### Changed

| Target | Location | Change |
|---|---|---|
| `WaitFor.init` | `HeistControl.swift:5-11` | predicate → ordered list |
| `WaitStep.predicate` | `WaitStep.swift:11` | singular → list |
| `.expect(...)` | `HeistActions.swift:27`, `HeistContent.swift:309` | singular → list |
| `Predicate.Requirement` | `Settlement.swift:451-459` | one predicate → list + banked state |
| `Session` | `Settlement.swift:919-955` | one shape, baseline as parameter |
| `Settlement.Executor` | `Settlement+Execution.swift` | drain on generation bump |

Wire format, parser, renderer and validator follow the DSL change. Per the
standing position on public API — same version required for server and client —
the wire contract breaks with no adapters and no backward compatibility.

### Deleted

| Target | Why |
|---|---|
| `ResolvedElementAssertion.isSnapshotPredicate` | third copy of the arity split; subsumed by the type split below |
| separate `.awaitingActionDispatch` / `.observation` phases | one machine, one phase set |

### Type-level

The arity distinction should be a type, not three Bools. `ScreenAssertion`
already **is** the snapshot type — it is used standalone as the condition type
for `if` / `case` / `while` (`ControlSteps.swift:38,41,50`, `HeistControl.swift:77,94,117`,
`HeistPlan.swift:444,454`) and has `rootPredicate` projecting back to a
standalone predicate. `ElementAssertion` is the one duplicating `exists` /
`missing`.

```swift
public enum SnapshotPredicate {          // renamed from ScreenAssertion
    case exists(AccessibilityTarget)
    case missing(AccessibilityTarget)
}

public enum DeltaPredicate {
    case appeared(AccessibilityTarget)
    case disappeared(AccessibilityTarget)
    case updated(AccessibilityTarget, ElementPropertyChange)
}

public enum ElementAssertion {
    case snapshot(SnapshotPredicate)
    case delta(DeltaPredicate)
}
```

The prize is not the enum shape. It is that the two evaluators lose access to
evidence they have no business reading: the delta evaluator stops taking
`current`, and the snapshot evaluator stops taking `facts`. Banking then falls
out of the type — deltas bank, snapshots do not — instead of being a fourth
hand-maintained switch.

The wire codec already branches on `PresencePredicateWireType` vs
`ElementAssertionWireType` (`AccessibilityPredicate.swift:327-363`). The split
exists in the format; only the Swift type is flat. That is strong evidence this
is the right cut.

## Sequencing

Commits are for review legibility; this squashes on merge.

0. Land the boundary-projection work (PR #1402 follow-on). A screen change
   projects one `screenChanged` fact and no element facts. **Prerequisite:**
   before it, every navigation manufactured a full screen of spurious
   appeared/disappeared, so no correct banking rule is derivable.
1. Split `ElementAssertion` into snapshot/delta; rename `ScreenAssertion` →
   `SnapshotPredicate`. Delete `isSnapshotPredicate`. No behavior change.
2. Unify `WaitFor` and `expect` into one session shape with baseline as a
   parameter. No list yet, no behavior change.
3. Make the predicate list-valued through DSL, wire, parser, renderer,
   validator. Single-element lists preserve current behavior.
4. Add `.noChange` to the tick classification so a tick is classified rather
   than inspected; drain the list on any tick classified as a change. This is
   the behavior change.
5. Docs: `ARCHITECTURE.md`, `docs/diagrams/settle-loop.md`, `HEIST-LANGUAGE-SPEC.md`.

## Open questions

1. **A step whose predicates are already true.** A wait on `exists(X)` where X is
   already present must not sit until timeout waiting for a tick that changes
   something. Snapshot predicates are total — they answer on any capture — so
   the first evaluation presumably happens against the baseline regardless of
   classification. Needs stating precisely.

2. **Snapshot predicates and banking order.** A snapshot never banks, so it is
   re-checked at every point. Does an unbanked snapshot block the cursor from
   advancing past it to later deltas, or does the cursor skip it? Skipping makes
   the list a partial order rather than a sequence.

3. **`updated` across a generation.** `updated` reads two graphs via
   `metadata.captureEdge`. Within a generation that edge is well defined. A
   predicate carried forward is evaluated against the *next* generation's
   trace — so its baseline moved. Whether that is intended needs deciding.

## Test posture

Per AGENTS.md the workflow is API → tests → implementation. The contract to lock
first:

1. **Accumulation.** Two delta assertions satisfied in different generations —
   the conjunction holds. This is the case that fails today.
2. **Transient.** An element that appears and is gone before the next
   generation is still catchable by `appeared`.
3. **Snapshot non-banking.** `exists(X)` true at one generation and false at the
   next fails the step.
4. **Order.** Two predicates that could each match two different generations
   bank greedily — first predicate to the first matching generation.
5. **Timeout.** The list not draining before the deadline fails, and the failure
   names which predicates were still pending.

Case 1 is the one with no current coverage and is the reason this work exists.
