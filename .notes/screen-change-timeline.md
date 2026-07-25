# Ticks

Every change we notice goes through the ticks. That is the whole rule.

The tree updating *is* a tick. There is no exploration tick, no search tick, no
screen tick — one system, and a tick is what we saw. That is why the three ticks
of a screen change are not three kinds of thing: they are three moments the tree
was in a different state, and the boundary between them is the only one that is
not a tree at all.

Nothing is held back and nothing is suppressed. A tick is a true statement about
what we saw, so there is no lane for who caused it: the app moved on its own, we
scrolled looking for a button, exploration walked a container — all the same. If
the tree changed and we noticed, it ticks.

The scroll case is the one worth saying out loud. Searching for an element moves
a scroll view, which reveals elements that were always there. Those are changes
we noticed along the way, and they tick like anything else. The search returns a
resolution; the tree updating is incidental to having moved the viewport.

## The four ticks

| Tick | Carries | Answered by |
|---|---|---|
| `snapshot` | `Interface` | element predicates |
| `screenChange` | `ScreenFacts` | `ScreenPredicate` |
| `announcement` | `String` | `AnnouncementPredicate` |
| `noChange` | nothing | the settlement gate only |

An empty screen is not a fifth kind. It is a `snapshot` with an empty tree, and
the ordinary snapshot math already says the right thing about one: nothing is
found, so every `missing` half drains and every `exists` half refuses. That is
the removals, and nobody enumerated them.

## What a screen change is

The app navigates. That is one event in the world and six in here:

1. **Detect** — heuristics or a `screenChanged` notification.
2. **Empty snapshot tick** — the old screen stopped answering.
3. **Throw away the tree, parse what is visible, classify it.** This is the new
   baseline. `SemanticObservationStore:201` already does exactly this:
   `isReplacement ? admission.tree : candidateTree`.
4. **Screen info tick** — what the new screen *is*, carrying no tree.
5. **Stitch the edges**, governed by the traversal knobs. Each page commits, and
   each commit ticks, because each is a change we noticed.
6. **Graph tick** — the accumulated tree, however far it got.

Steps 2, 4 and 6 are ordered because that is what a boundary means, not because
anything is being held. The screen info tick lands before the stitching: naming a
screen needs only what is on it, and a caller waiting on
`changed(.screen("Settings"))` should not also wait for every container to be
walked.

## Where the pieces are

| Step | Code | State |
|---|---|---|
| 1 detect | `ScreenClassifier.classify` ← `SemanticObservationStore:192` | exists |
| 3 throw away + parse | `SemanticObservationStore:201` | exists |
| 3 name it | `ScreenClassifier.screenName(of:)` → `Snapshot.screenName` | wired |
| 5 stitch | `Navigation.fullGraph` | exists, not called on a screen change |
| 2/4/6 | `Expectation.vacated(at:)` / `.screenChange(_:)` / `.snapshot(_:)` | exist |

`ScreenFacts` is named by the classifier's own primary header — the same reading
it uses to decide whether two captures are the same screen. Not a slug of
whatever text was projected first.

## What is left

`Settlement.Reducer.admit` fires all three screen-change ticks back to back from
one admission, and `fullGraph()` is never called on a screen change, so step 5
does not happen and the graph tick carries the visible hierarchy.

The one guard to watch: `Navigation+ExplorationScanning.swift:113` aborts
exploration when its first page classifies as a replacement. Reading
`ScreenClassifier.classify`, it should not fire on this path — detection commits
the new screen first, so exploration compares new-to-new and gets
`.sameGeneration`. The `.screenChanged` notification short-circuits before any
comparison, though, so whether detection consumed it needs a run to confirm.

## Two jobs, one function

`exploreScreen` serves callers that want opposite things:

| Callers | Job | Returns |
|---|---|---|
| `observeInterface`, `exploreForWait` | build a graph | the graph |
| `discoverTarget`, `scanForSemanticTarget` | find one element | a resolution |

The second pair scrolls until it finds what it wants and stops. It does not
build a graph — it moves the viewport, and the tree updating is incidental.
`scanForSemanticTarget` already returns `SemanticTargetScanResult`, which is the
honest shape; `discoverTarget` still returns an `InterfaceExplorationResult` it
does not mean.

`fullGraph` names the first job.
