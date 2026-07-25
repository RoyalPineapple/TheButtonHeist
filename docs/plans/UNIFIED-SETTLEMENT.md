# Unified Timing and Settlement

Status: implemented in #1402.

This is the design as approved, kept as the record of why the collapse
happened. Code references and the "what exists today" survey below describe
the state *before* the change — that survey is the motivation, not a
description of the tree. For how settlement works now, read
`docs/diagrams/settle-loop.md`.

**One part of this plan did not survive implementation: the four-case
animation-delta rule.** It shipped, failed, and was removed in the same PR.
A process-wide animation count has no attribution — it cannot say *whose*
animations are running, so a keyboard sliding into place over an already-quiet
tree was indistinguishable from a spinner that never stops, and the rule turned
successful actions into timeouts. `AnimationObserver`, the `UIViewAnimationState`
swizzle, the bounded-`CAAnimation` layer census, and `SettleStability` are all
gone. Settlement now compares accessibility trees and nothing else. Everything
below about counting animations is history; the rest of the plan stands.

## The rule this restores

AGENTS.md, Button Heist House Style:

> Maintain one pipeline per concept: action, result, logging, error, evidence,
> observation, and settlement should each have one owner and one shape.

Settlement currently has four owners and three shapes. This plan is not a new
architecture; it is enforcement of the rule already written down.

The invariant on top: **the tripwire is the only source of time. Everything
that is not a timeout is display-linked.** One clock (tick), one comparison
(the AX observation diff), one event (the change).

## What exists today

Four systems, stacked rather than redundant, connected by lossy seams.

| # | System | Clock | Evidence | Terminal |
|---|--------|-------|----------|----------|
| 1 | `Settlement.Reducer` | none — event-sourced on `ExecutionSink` | readiness + handoff + predicate | `TerminalIntent` |
| 2 | `SettleSession` / `SettleLoopRunner` | tick (`waitForNextTick`) | AX-tree fingerprint | `SettleOutcome` |
| 3 | `UIKitIdleTracker` | run-loop `.beforeWaiting` + animation swizzle | `waitUntilIdle` bool | bool |
| 4 | Liveness | wall-clock age of last pulse reading | `pulseIsFresh` | bool |

Plus the pulse itself, which computes a **second, independent geometry
fingerprint** (`PresentationFingerprint`, `scanLayers()`) via a full CALayer DFS
on **every tick at 10Hz**, consumed by exactly two callers.

### The three seams where information dies

1. **SettleSession → Settlement.Reducer.** `SettleSession` computes a
   fingerprint, discards the diff, and hands the reducer an opaque
   `Readiness.Path` tag (`Settlement+Execution.swift:1049-1056`). Raw animation
   and geometry data cannot cross. This is why the animation-delta rule has no
   home today.

2. **Two fingerprints for one question.** The pulse's `PresentationFingerprint`
   (summed CALayer presentation geometry, 0.5pt tolerance) and SettleSession's
   AX-tree fingerprint (`SettleTimeline.swift:52-77`) both answer "did the
   interface move." The AX fingerprint **already includes coarse-bucketed frame
   geometry** — masked only for `updatesFrequently` elements
   (`SettleTimeline.swift:98-105`). The layer scan is a strictly weaker
   re-derivation, computed 10× per second whether or not anyone asks.

3. **`.unavailable` collapses into `.timedOut`.** `SettleLoopRunner.swift:169-178`
   maps a pulse-not-running tick and an ordinary timeout to the same
   `SettleOutcome`. A stopped clock and a slow app are indistinguishable
   downstream.

### The doc comment that defends the split

`TheTripwire+Pulse.swift:175-183` argues the boundary is intentional:

> The boundary is intentional — layer quiet and AX-tree quiet disagree on every
> spinner.

That is correct and it is the reason to collapse, not to keep both. A spinner is
precisely "animation active, AX tree unchanged." Two fingerprints that disagree
cannot classify it. One comparison that also reads the animation count can — see
the four cases below.

## The unified pipeline

```
tick ──→ parse AX tree ──→ diff vs previous ──→ emit change event
           (+ animation count read)                   │
                          ┌──────────────────┬────────┴─────────┐
                          ▼                  ▼                  ▼
                    settle verdict     predicate eval     liveness (absence)
```

One clock. One comparison. One event. Three readers.

`Settlement.Reducer` stays event-sourced — it is not a polling loop and must not
become one. It correctly waits on facts that have no per-tick answer. What
changes is that its inputs arrive from one pipeline instead of three.

## The four cases

Activating a control, with `pre` = animation count sampled before dispatch:

| # | Animations | AX change | Verdict |
|---|-----------|-----------|---------|
| 1 | none spawned | none | **settled** — a no-change action |
| 2 | spawned, completed | none | **settled** — a little animating button |
| 3 | spawned, outlasts the action timeout | none | **fail** — falsified stability |
| 4 | any | predicate matched | **settled** — predicate is the authority |

Case 3 is the only failure. Any predicate with no change fails.

The `noChange` predicate used to convert case 3 to case 4 and was deleted: it
was the only predicate whose evidence is absence, so it could never drain early
and only ever resolved at the deadline. Asserting "this action correctly did
nothing" is currently inexpressible. If it is wanted again it belongs in the
timeout verdict — a question about the window — not in the predicate list.

### What the animation count can and cannot see

`AnimationObserver` counts `UIViewAnimationState` start/stop edges — that is,
`UIView.animate` and friends. A raw `CAAnimation` added straight to a layer
(`layer.add(_:forKey:)`) never touches that class, so it does **not** move
`activeCount`.

This is load-bearing, not a gap. `TestApp/Sources/AnalogClockDemo.swift` runs
three infinite `CABasicAnimation`s on `CAShapeLayer`s with a deliberately static
AX tree, and its contract is that taps still settle. Structurally that is case 3
— indefinite animation, no AX change — and it passes only because the count
never rises above baseline.

So the rule fires on *view* animations that outlive the action, which is the
case where the app is genuinely mid-transition. Decorative Core Animation is
correctly ignored, exactly as the analog-clock fixture already asserts.

Stated as one rule:

> A cycle whose diff is `unchanged` **and** whose animation count exceeds the
> pre-action baseline is not settlement evidence. It is falsified stability.

Case 2 passes because the animation completes and the count returns to baseline
before the timeout. Case 3 fails because it never does.

## Blast radius

### Deleted

| Target | Location | Why |
|--------|----------|-----|
| `PresentationFingerprint` | `TheTripwire+PulseReading.swift:31-70` | weaker duplicate of the AX diff |
| `scanLayers()` per-tick DFS | `TheTripwire+Pulse.swift:219` | 10Hz full CALayer walk, ~2 consumers |
| `waitForAllClear` / `allClear` | `TheTripwire+Pulse.swift:184,305` | both callers are pacing, not correctness |
| `resolveSettleWaiters` + `settleWaiters` | `TheTripwire+Pulse.swift:284-299` | the layer-quiet waiter queue |
| `SettlePolicy` (3 cases) | `SettleSession.swift:56-62` | one settle rule, not a policy enum |
| `SettleEvidence` (3 cases) | `SettleSession.swift:65-69` | the diff is the evidence |
| `presentationSettleGraceMs` (500ms) | `SettleSession.swift:303` | exists only to reconcile the two fingerprints |
| `presentationAdmitsSettlement` | `SettleLoopRunner.swift:130-138` | same |
| `UIKitIdleTracker.waitUntilIdle` | `UIKitIdleTracker.swift:148-171` | settlement reads the count, never waits on it |
| `RunLoopIdleObserver` (whole file) | `RunLoopIdleObserver.swift` | sole consumer was `waitUntilIdle`; see below |
| `startIdleTask` / `.uikitIdle` event | `SettleLoopRunner.swift:94-123,194-205` | no second clock racing the tick |
| `operationDepth` gating | `UIKitIdleTracker.swift:24-47,132-146` | gated only the wait; the count read needs no permission |
| `confirmMainThreadResponsive` | `TheBrains+Dispatch.swift:146-154` | self-referential; see Liveness |

### Why `RunLoopIdleObserver` goes

The observer callback is main-thread code, and the display link is serviced by
the same run loop. There is no state where `.beforeWaiting` reports something a
tick could not: if the loop is draining, it is also servicing the link.

The one case where they differ — sustained main-queue backlog, loop services
frames but never drains — points the wrong way. Under backlog `.beforeWaiting`
never fires, so `waitUntilIdle` blocks to timeout. That is not stronger
evidence, it is a hang, and it is the documented XCUITest spinner failure
(`App failed to quiesce within 30.0s`) reproduced in our own tree.

Deleting the sole consumer also deletes a silent-failure mode: `waitUntilIdle`
is double-gated on `operationDepth > 0`, and `installIfAvailable`
(`UIKitIdleTracker.swift:102-110`) swallows swizzle failure into a warning — so
today the idle evidence can vanish permanently with nothing but a log line.

`UIKitIdleTracker` survives as what it actually is: the install/teardown owner
for the animation counter. It gets renamed — see below.

### Renaming after the collapse

"Idle" is the word for the concept being deleted, so both types carrying it are
misnamed once nothing waits on idleness.

| Today | After | Why |
|-------|-------|-----|
| `UIKitIdleTracker` | `AnimationObserver` | owns swizzle install/restore + the count; `observe` is the canonical verb for "receives an event or snapshot", and it sits beside the existing `AccessibilityNotificationObserver` |
| `AnimationIdleCounter` | folded in, or `AnimationCount` | see below |
| `tripwire.uikitIdleTracker` | `tripwire.animationObserver` | property name at every call site |

`Tracker` is not in the AGENTS.md vocabulary table; `Observer` matches both the
verb list and the neighbouring type in the same directory.

**The counter should fold into the observer.** More than half of
`AnimationIdleCounter` (133 lines) exists only to serve waiters —
`waitUntilIdle`, `cancelAll`, `resolve`, `remove`, the `WaiterStore`, the
`TimedOneShot`. With nothing waiting, roughly 55 lines delete outright and what
remains is a lock around four `Int`s plus two `observe` methods, with exactly one
owner. That is small enough to live in `AnimationObserver` directly.

Folding is optional and separable — the rename stands on its own if the fold is
deferred. `AnimationIdleCounterTests.swift` and
`UIKitIdleTrackerIntegrationTests.swift` rename either way; the waiter-focused
cases in both delete with the waiter code.

### Kept, demoted

- **`AnimationIdleCounter`** — survives as a per-tick **read** via the existing
  `animationSnapshot` (`UIKitIdleTracker.swift:49-52`), which is already
  synchronous and already ungated by `operationDepth`. No new API.
- **`MainThreadProbe`** — unchanged, stays at the wire layer. It is the only
  honest wedge detector because it is the only one not running on the thing it
  measures.

### Kept as-is

`Settlement.Reducer`, `Settlement.Session`, `AccessibilityNotificationBus`,
the tick/pulse mechanism itself, `yieldFrames`.

## Liveness

In-process main-actor code cannot detect its own wedge. `confirmMainThreadResponsive`
runs `@MainActor`, so it can only execute in the cases where dispatch would have
succeeded anyway — a check guaranteed to pass whenever it runs at all. Scheduling
work on the run loop *is* the liveness test; `MainThreadProbe` is built correctly
around exactly that (schedule, then observe from a background queue).

Post-dispatch, a wedge freezes `Settlement.Executor` **and** its own
`ContinuousClock` deadline task, because `armDeadline` is `@MainActor`
(`Settlement+Execution.swift:1064-1075`). Nothing fires. There is no in-process fix.

So: liveness stops being a check and becomes an **absence**. The pipeline stops
emitting; the external observer (client, over the socket) notices and probes.
That architecture already exists.

The one thing `confirmMainThreadResponsive` genuinely bought — a one-tick wait at
`.immediate` when `pulseIsFresh()` is false — is a settle concern, and the
pipeline covers it directly.

## Sequencing

Commits are for review legibility; this squashes on merge.

0. Fix `updatesFrequently` over-masking (value only, keep geometry). Standalone
   correctness fix; lands first because everything downstream trusts the diff.
1. Delete the layer fingerprint. Move `waitForAllClear`'s two callers
   (`Heist.swift:271`, `Navigation.swift:23`) to the observation stream.
   Independently verifiable, no behavior change intended.
2. Emit the diff. `SettleSession` returns the change, not just a fingerprint
   equality bool. Reducer gains the delta as a fact.
3. Collapse the policies. `SettlePolicy` and `SettleEvidence` out; consecutive-cycles
   survives as a parameter, not a case.
4. Sample the animation count per tick; implement the four-case rule.
5. Delete `confirmMainThreadResponsive` and the idle-wait plumbing
   (`waitUntilIdle`, `RunLoopIdleObserver`, `operationDepth`).
6. Rename `UIKitIdleTracker` → `AnimationObserver`; fold the counter in.
7. Docs: `ARCHITECTURE.md`, `docs/diagrams/`, affected dossiers.

## Open questions

1. **Viewport transition at `required: 2`.** `SettleSession.viewportTransition`
   (`SettleSession.swift:445-461`) is the one consecutive-cycles caller whose
   behavior under the unified rule I would verify by running rather than by
   reasoning.

## Bug found while scoping: `updatesFrequently` over-masks

`updatesFrequently` declares that **the value** churns — a timer label, a
progress percentage. It says nothing about position. But one guard masks three
things (`SettleTimeline.swift:98-110`):

```swift
guard !element.traits.contains(.updatesFrequently) else { return }
hasher.combine(element.value)      // correct to mask
// ...shape / frame                // WRONG — geometry is not the value
// ...activation point             // WRONG — same
```

An element carrying that trait can therefore slide across the screen and the
fingerprint still reads `unchanged`. That is a live false-settle, independent of
this plan.

Fix: mask the value only; always hash geometry and activation point.

```swift
if !element.traits.contains(.updatesFrequently) {
    hasher.combine(element.value)
}
// geometry and activation point hashed unconditionally
```

This also resolves the animation interaction cleanly, with no special case in
the four-case table: a *moving* spinner falsifies stability through its geometry
delta; a stationary one with a churning value does not. The trait stops being a
blanket stability exemption and becomes what it says it is.

Landing this early is worthwhile — it is a small, independently testable
correctness fix that the rest of the plan then builds on.

## Test posture

Per AGENTS.md the workflow is API → tests → implementation. The behavioral
contract to lock first is the four-case table: four hosted tests against a demo
screen with (1) an inert button, (2) a button with a short completing animation,
(3) a button that starts an indefinite animation with no AX change, (4) the same
with a matching predicate.

Case 3 is the one with no current coverage and is the reason this work exists.

Step 0 needs its own check independent of the four cases: an element carrying
`updatesFrequently` that moves must produce a fingerprint change, while the same
element churning only its value must not.
