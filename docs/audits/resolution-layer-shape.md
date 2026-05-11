# Accessibility resolution layer — shape audit

Scope: structural critique of TheBurglar, TheStash, TheBrains, TheSafecracker.
Date: 2026-05-11.
Audit-only — no source changes.

## Summary

The current shape is **mediocre and on a trajectory to actively painful**. Most of the crew/file boundaries are correct: TheBurglar genuinely owns parsing, TheSafecracker genuinely owns touch synthesis, and TheStash genuinely owns the persistent registry. The orchestrator's instinct that "TheBrains is bloated" lands — it is the single biggest joint drawn at the wrong place. TheBrains conflates three responsibilities that do not co-vary: (a) `executeCommand` dispatch, (b) the converge-and-snapshot pipeline (`actionResultWithDelta`, `wait_for_change`, `wait_for_idle`, broadcast/background delta), and (c) a scroll/explore engine that is its own pipeline with its own state machine, its own paging primitives, and a 200-line settle-loop sub-state-machine. The pipeline as a whole is implicit but is not unrecoverable — the dispatch layer almost names the phases (`performInteraction`, `performElementSearch`, `performWaitFor`, `performExplore`) and the structural fix is to give those phases an explicit type with named methods, not to renumber the crew. Hypothesis H1 (pipeline implicit), H2 (TheBrains bloated), and H4 (cross-cutting policy scattered) are confirmed; H3 (TheStash has too many files) is refuted — TheStash is mostly well-decomposed and the file count is appropriate to its responsibilities; H5 (TheBurglar underspec'd) is refuted — it is the cleanest crew member in the audit. The single highest-leverage refactor: extract scroll + explore from TheBrains into a new `Spelunker` (or `TheCartographer`) type owning the scroll pipeline + ScrollableTarget + ScreenManifest + ContainerExploreState + exploration state machine — that alone removes ~1,200 LOC and three lifecycle types from TheBrains.

## Hypothesis verification

### H1: Pipeline is implicit
**Verdict:** confirmed
**Evidence:**
- The phases *capture → match → synthesize input → dispatch → observe settle → diff* are named nowhere as a type. They appear as a switch statement in `TheBrains+Dispatch.executeCommand` (lines 13-43) that routes to four implicit "pipeline shapes": `performInteraction`, `performElementSearch`, `performWaitFor`, `performExplore`.
- `actionResultWithDelta` (TheBrains.swift:116-203) is the real backbone — 88 lines that hard-code the post-action sequence: settle → re-parse → screen-change check → repopulate → apply → explore+prune → snapshot → delta → transient enrichment → captureActionFrame → build result. None of these are named methods on a named pipeline type; they are inline statements.
- `executeWaitForChange` (TheBrains.swift:386-449) and `executeWaitForIdle` (368-381) re-implement subsets of the same pipeline, with `computeDelta(before:afterSnapshot:)` (487-505) being a private duplicate of the screen-change detection logic from `actionResultWithDelta`.
- The fact that `TheBrains+Dispatch` exists as an extension file at all is a tell: it's the entry-point switch but lives off the main class because the main class is already too big.
**Implication:** A reader cannot navigate the resolution layer without first reverse-engineering the dispatch → pipeline → convergence sequence. Naming the phases (or at least the pipelines) as types would make `executeCommand` a one-line dispatcher and make the post-action cycle inspectable.

### H2: TheBrains is bloated
**Verdict:** confirmed, strongly
**Evidence:**
- 2,860 LOC across 7 files (`TheBrains.swift` 533, `+Actions` 451, `+Dispatch` 282, `+Exploration` 413, `+Exploration+Manifest` 46, `+Scroll` 735, plus `SettleSession` 300, `ActionResultBuilder` 89, `ActivateFailureDiagnostic` 104).
- Concretely separable responsibilities living in TheBrains today:
  1. **Command dispatch** — `executeCommand`, `executeAccessibilityAction`, `executeTouchGesture`, `unsupportedCommandResult`, `diagnosticMethod(for:)` (TheBrains+Dispatch.swift:13-277).
  2. **Action pipeline** — `performInteraction`, `performElementSearch`, `performWaitFor`, `performExplore` (Dispatch.swift:46-182).
  3. **The 22 `executeXxx` action methods** (Actions.swift) — `executeActivate`, `executeIncrement`, `executeDecrement`, `executeCustomAction`, `executeEditAction`, `executeSetPasteboard`, `executeGetPasteboard`, `executeResignFirstResponder`, `executeTap`, `executeLongPress`, `executeSwipe`, `executeDrag`, `executePinch`, `executeRotate`, `executeTwoFingerTap`, `executeDrawPath`, `executeDrawBezier`, `executeTypeText`, `executeScroll`, `executeScrollToVisible`, `executeScrollToEdge`, `executeElementSearch`.
  4. **Scroll engine** — `ScrollableTarget` enum, `ScrollAxis` OptionSet, `SettleSwipeProfile`, `SettleSwipeLoopState`, `scrollOnePageAndSettle`, `settleSwipeMotion`, `viewportAnchorSignature`, `safeSwipeFrame`, `currentSwipeSafeBounds`, `findScrollTarget`, `scrollableTarget(for:contentSize:)`, `resolveScrollTarget`, three direction-mapping statics, `ensureOnScreen`, `ensureFirstResponderOnScreen`, `ensureOnScreenSync`, `offViewportRegistryEntry`. (TheBrains+Scroll.swift, 735 LOC.)
  5. **Explore engine** — `ContainerExploreState`, `ContainerPage`, `exploreAndPrune`, `exploreScreen`, `exploreContainer`, `restoreAndCache`, `visibleElementsInContainer`, `buildOriginIndex`, `resolveHeistIds`, `stitchPage`, `restoreVisualOrigin`, `updateContainerExploreCache`, `totalOverflow`, `hasContentBeyondFrame`, `isObscuredByPresentation`, `topmostPresentedViewController`, plus `nearestViewController` and `isDescendant(of:)` extensions, plus the `ScreenManifest` struct in `+Exploration+Manifest`. (~460 LOC.)
  6. **Explore lifecycle state machine** — `ExplorePhase` enum, `recordDuringExplore`, `beginExploreCycle`, `endExploreCycle`, `containerExploreStates` dictionary, `lastSwipeDirectionByTarget` dictionary. (TheBrains.swift:36-62.)
  7. **Settle/wait pipelines** — `actionResultWithDelta` (88 lines), `repopulateAfterScreenChange`, `enriching(_:transient:)`, `executeWaitForIdle`, `executeWaitForChange`, `evaluateWaitForChange`, `refreshAndSnapshot`, `computeDelta(before:afterSnapshot:)`, `logSettleOutcome`.
  8. **Broadcast / sent-state tracking** — `SentState`, `recordSentState` (×2 overloads), `lastSentState`, `broadcastInterfaceIfChanged`, `currentInterface`, `computeBackgroundDelta`, `screenChangedSinceLastSent`, `lastSentScreenId`.
  9. **Pass-through facades for TheStash** — `captureScreen`, `captureScreenForRecording`, `screenName`, `screenId`, `stakeout`, `startKeyboardObservation`, `stopKeyboardObservation`, `clearCache`. (These are thin and arguably justified, but they add to the surface.)
- The `+Exploration+Manifest.swift` double-suffix file is exactly the smell the orchestrator named: an extension of an extension because `TheBrains+Exploration.swift` outgrew its parent.
**Implication:** 5 of those 9 responsibilities have nothing to do with the others except that they share access to `stash` and `tripwire`. Splitting along (4+5+6), (7+8), and (3) lines would yield three ~600-LOC types each with one job.

### H3: TheStash has too many files
**Verdict:** refuted
**Evidence:**
- 11 files totaling 2,675 LOC, but the responsibilities-per-file ratio is high and the boundaries are clean:
  - `TheStash.swift` (512) — class + `ScreenElement`, `ResolvedTarget`, `TargetResolution` + resolution entry points + action dispatch (`activate`/`increment`/`decrement`/`performCustomAction`/`jumpToRecordedPosition`/`liveGeometry`) + facades.
  - `ElementRegistry.swift` (229) + `ElementRegistry+Merge.swift` (537) — `RegistryNode`, `ElementRegistry` struct, the persistent-tree merge algorithm. The +Merge split is justified: it isolates a 500-line pure-functional algorithm (`collectOrphans`/`buildNodes`/`attachOrphans`/`sortContainerChildren`/`pruneEmptyContainers`/`buildIndex`) into a file where it can be read end-to-end.
  - `WireConversion.swift` (662) — pure transform: AccessibilityElement → HeistElement → InterfaceNode + the delta computation (`computeDelta`, `computeElementEdits`, `computeTreeEdits`, `suppressFunctionalMoveElementChurn`, `inferFunctionalPairs`, signature types). This is the single largest file in the audit but the cohesion is genuine — every line is "internal type → wire type" or "compare two wire forms".
  - `IdAssignment.swift` (108), `Interactivity.swift` (64), `Diagnostics.swift` (176) — each is a pure-static namespace enum with one named job and a constants table.
  - `TheStash+Matching.swift` (265) — `MatchMode` enum + `firstMatch`/`hasMatch`/`matches` extensions on AccessibilityHierarchy and AccessibilityElement + `matchScreenElements` + typography fold.
  - `ArrayHelpers.swift` (47), `RegistryNode+Walks.swift` (69), `TheStash+Capture.swift` (58) — small, single-purpose.
- The orchestrator hypothesis lumps WireConversion, ElementRegistry+Merge, and TheStash+Matching together as if they were a single "the registry" concept. They aren't. They are three different things that all happen to operate on registry data:
  - Merge is *how the persistent tree updates*.
  - Matching is *how queries find elements*.
  - WireConversion is *how internal types become wire types*.
- Changing one rarely requires touching the others. The one real cross-file coupling — `transientTraits` — is a policy duplication problem, not a file-count problem (see Finding 1).
**Implication:** TheStash's file shape is fine. The hypothesis was reading file count without reading file contents. Reorganization here would produce more files with smaller responsibilities-per-file but the same total complexity — net negative.

### H4: Cross-cutting concerns are scattered
**Verdict:** confirmed
**Evidence:**
- **Trait policy is in four places**, none of them the canonical source of truth:
  1. `Interactivity.swift:25-31` — `interactiveHeistTraits` (which traits make an element actionable).
  2. `IdAssignment.swift:19-30` — `traitPriority` (which traits drive heistId synthesis, with ranking).
  3. `ElementRegistry.swift:167-174` — `transientTraitNames: Set<String>` (which traits are excluded from `hasSameMinimumMatcher` identity stability).
  4. `WireConversion.swift:515-522` — `transientTraits: Set<HeistTrait>` (which traits are excluded from `ElementIdentitySignature` for functional-move pairing).
  Items 3 and 4 are *the same policy* — the set of traits that should not contribute to element identity — represented in two types in two files. Adding a new transient trait (e.g. `.flickrable`, `.frequentUpdate`, `.beingDragged`) requires editing both.
- **Screen-change policy** lives in `TheBurglar.isTopologyChanged` (lines 180-204) — back-button trait detection, header label set comparison, and tab bar persistence threshold (`tabSwitchPersistThreshold = 0.4`). That policy is consumed by `TheBrains.actionResultWithDelta` (line 156) and `TheBrains.computeDelta` (line 491). The threshold value is a magic number inside an otherwise mechanism-heavy class.
- **Heist-id synthesis policy** lives partly in `IdAssignment` (trait priority, label slugging, value-excluded rule) and partly in `ElementRegistry.resolveHeistId` + `hasSameMinimumMatcher` + `stableTraitNames` (the "minimum matcher" rule that decides when two heistIds collide for content-space disambiguation). The policy "value is excluded for stability" is asserted in both places — by `IdAssignment.synthesizeBaseId` excluding value from the slug, and by `ElementRegistry.hasSameMinimumMatcher` excluding value when label/id is present.
- **`updatesFrequently` is special-cased** in two algorithmic places: `SettleSession.fingerprint` (line 248-258) masks the rect, and `SettleSession.TimelineKey` (line 76-84) masks the key. Both correct, neither named "the updatesFrequently policy".
**Implication:** Each rule-of-the-world is correct in isolation but lives next to the mechanism that uses it. Changing the policy (e.g. promoting `flickrable` to interactive, or demoting `selected` from transient) requires hunting through the codebase. A single `AccessibilityPolicy.swift` (or a small set of policy constants in TheStash) consolidating these four trait lists into a single source of truth would fix this.

### H5: TheBurglar is the underspec'd outlier
**Verdict:** refuted — TheBurglar is the cleanest crew member in the audit
**Evidence:**
- One file, 428 LOC, three responsibilities, all of them parse-adjacent:
  1. `parse()` — read the AX tree.
  2. `apply(_:to:)` — populate TheStash's registry.
  3. `isTopologyChanged` — screen-change detection.
  4. `buildContainerIdentityContext` and `buildElementContexts` — context-propagating walks used by apply.
- The file is organized: clean MARK sections, no mutable instance state beyond two `let`s (parser, tripwire), value-typed `ParseResult` and `ContainerIdentityContext` outputs, and one cleanly bounded UIKit-poking helper (`revealHiddenSearchBars`).
- The only structural quibble is item 3 (screen-change policy) being co-located with parse mechanism (see H4). That's a policy/mechanism tangle, not an "under-loved corner".
**Implication:** TheBurglar should not be refactored as part of any reshape — its boundary is correct. The one thing to consider is lifting `isTopologyChanged` + `isTabBarContentChanged` + `partitionByTabBar` into the proposed `AccessibilityPolicy` module.

## Structural findings

### Finding 1: TheBrains is doing five jobs
**Severity:** rework
**Type:** god object
**Location:** `ButtonHeist/Sources/TheInsideJob/TheBrains/*.swift` (whole directory)
**Description:**
TheBrains' nine responsibilities (enumerated in H2) collapse to five distinct logical concerns:
- (A) **Command dispatch** — Dispatch.swift's switch + per-message routing.
- (B) **Action execution** — Actions.swift's 22 `executeXxx` methods that translate a typed target into a TheStash/TheSafecracker call.
- (C) **Scroll + ensure-on-screen engine** — Scroll.swift's 735 lines: ScrollableTarget, SettleSwipeLoopState, scrollOnePageAndSettle, findScrollTarget, ensureOnScreen, safeSwipeFrame.
- (D) **Explore engine** — Exploration.swift + Manifest.swift: ScreenManifest, ContainerExploreState, exploreAndPrune, exploreContainer, the ExplorePhase state machine.
- (E) **Pipeline convergence** — TheBrains.swift's `actionResultWithDelta`, settle/wait pipelines, sent-state tracking, broadcast.
These do not co-vary. Adding a new gesture changes (B). Changing how containers are explored changes (D). Changing settle policy changes (E). Adding a new container type (e.g. a chart that supports `.swipeable` but not `.uiScrollView`) changes (C). Each concern has its own lifecycle types (ExplorePhase / SettleSwipeLoopState / ContainerExploreState / SentState) that are siblings on TheBrains today.

**Sketch:**
Three new types, TheBrains retains (A) and (E):
- `ActionExecutor` — owns (B). Receives a `stash` and a `safecracker` ref. Holds the 22 `executeXxx` methods, the `performElementAction` / `performPointAction` generic pipelines, and the duration/velocity helpers. No state — pure functions of (target, stash, safecracker). ~600 LOC from `+Actions.swift`.
- `Spelunker` (or `TheCartographer`, `TheScout` — name TBD; the metaphor needs to stay) — owns (C) and (D). Holds `ScrollableTarget`, `ScrollAxis`, `SettleSwipeProfile`, `SettleSwipeLoopState`, `ScreenManifest`, `ContainerExploreState`, `ExplorePhase`, and `lastSwipeDirectionByTarget`. Public API is `scroll(_:direction:)`, `scrollToVisible(_:)`, `scrollToEdge(_:edge:)`, `elementSearch(_:)`, `exploreAndPrune()`, `ensureOnScreen(for:)`. Internal API hides the settle loop. ~1,200 LOC from `+Scroll.swift` + `+Exploration.swift` + `+Manifest.swift`.
- TheBrains slims to (A) + (E): `executeCommand`, the four pipeline-shape methods (`performInteraction`/`performElementSearch`/`performWaitFor`/`performExplore`), `actionResultWithDelta`, wait handlers, broadcast/sent-state. Calls `actionExecutor.executeActivate(...)` instead of `self.executeActivate(...)`. ~700 LOC.
The crew metaphor survives: a brain doesn't move the muscles itself, it tells the cartographer to scout and the executor to execute.

### Finding 2: Trait policy duplicated across files
**Severity:** rework
**Type:** policy/mechanism tangle
**Location:** `TheStash/Interactivity.swift:25-31`, `TheStash/IdAssignment.swift:19-30`, `TheStash/ElementRegistry.swift:167-174`, `TheStash/WireConversion.swift:515-522`
**Description:**
Four trait policy tables live next to the four pieces of mechanism that consume them. The most concrete drift risk is the *transient traits* set — represented as `Set<String>` in ElementRegistry and `Set<HeistTrait>` in WireConversion. They happen to be the same six values today; nothing in the type system or the build ensures they stay in sync. The drift mode is subtle: someone adds `.flickrable` to one place to fix a flaky test and leaves the other untouched, then a pairing-suppression test passes locally but registry-identity drifts in production.

**Sketch:**
Create `TheStash/AccessibilityPolicy.swift` (a caseless namespace enum or a struct of `static let` tables). Move:
- `interactiveHeistTraits` → `AccessibilityPolicy.interactiveTraits`
- `traitPriority` → `AccessibilityPolicy.synthesisRanking`
- both `transientTraits` sets → `AccessibilityPolicy.transientTraits` (one `Set<HeistTrait>`; the registry's `Set<String>` becomes a computed `transientTraitNames` derived from it)
- `TheBurglar.tabSwitchPersistThreshold` → `AccessibilityPolicy.tabSwitchPersistThreshold`
- The `staticText`/`image`/`header` set in `Interactivity.checkInteractivity` (line 52) → `AccessibilityPolicy.staticOnlyTraits`
This is not a renaming exercise — the existing constants are fine. The new file is a *policy index*: an agent (or human) editing the rules-of-the-world has one file to look at, and an inline doc comment in each policy declaration says where it's enforced.

### Finding 3: The pipeline phases are unnamed
**Severity:** improve
**Type:** missing concept
**Location:** `TheBrains/TheBrains+Dispatch.swift:13-43`, `TheBrains/TheBrains.swift:116-203`
**Description:**
The `executeCommand` switch routes 19 message cases to *four shapes*, but the shapes are named only by their entry point — `performInteraction`, `performElementSearch`, `performWaitFor`, `performExplore`. The "shape" of `performInteraction` (refresh → captureBeforeState → action closure → actionResultWithDelta) is encoded only by reading the body. `performElementSearch` differs by patching `ScrollSearchResult` onto the result post-hoc. `performWaitFor` differs by passing `errorKind: .timeout` conditionally. The differences are real — they are not "all the same pipeline with a different action closure" — but the code doesn't say so.

**Sketch:**
Either:
- (a) **`ActionPipeline` enum** with cases `.interaction(...)`, `.search(...)`, `.waitFor(...)`, `.explore`, and a single `run() async -> ActionResult` method per case. Cases carry their dispatch closure. The switch in `executeCommand` becomes `pipeline(for: message).run()`. Or
- (b) Less invasive: extract `actionResultWithDelta` into a struct `PostActionCycle` with named methods (`settle()`, `reparse()`, `detectScreenChange()`, `applyAndExplore()`, `computeDelta()`, `enrichTransients()`, `build()`). Internal flow stays imperative but each step has a name and a test surface.
(a) is the "name the pipeline" version; (b) is the "name the steps" version. (b) is the lower-cost option and is sufficient if the pipeline doesn't grow more shapes.

### Finding 4: Two separate "delta + screen-change" code paths in TheBrains
**Severity:** improve
**Type:** co-located concerns / functional duplication
**Location:** `TheBrains/TheBrains.swift:116-203` (`actionResultWithDelta`) vs `TheBrains/TheBrains.swift:486-505` (private `computeDelta(before:afterSnapshot:)`)
**Description:**
`actionResultWithDelta` and the private `computeDelta` both perform: derive `afterElements` from `stash.currentHierarchy.sortedElements`; call `tripwire.isScreenChange(before:after:)`; call `stash.isTopologyChanged(...)`; OR them; pass to `stash.computeDelta(...)`. The wait-for-change path reaches for `computeDelta` so it can produce a delta against a stale `BeforeState` without re-running the whole settle pipeline; the action path reaches for `actionResultWithDelta` so it can run the settle pipeline. Both encode the same screen-change-detection rule. If the rule changes (e.g. add a fourth signal beyond VC identity + topology), it changes in two places.

**Sketch:**
Extract a private method `detectScreenChange(before: BeforeState, afterElements: [AccessibilityElement], afterHierarchy: [AccessibilityHierarchy]) -> Bool` and call it from both sites. (Trivial fix once spotted; this is "improve" not "rework".)

### Finding 5: Pipeline state lives as siblings on TheBrains, not in a state machine
**Severity:** improve
**Type:** missing concept (per CLAUDE.md's "explicit state machines")
**Location:** `TheBrains/TheBrains.swift:27-62, 291-317`
**Description:**
TheBrains holds parallel state that is implicitly phased:
- `explorePhase: ExplorePhase = .idle` — explicitly modeled (good).
- `containerExploreStates: [AccessibilityContainer: ContainerExploreState]` — exists across cycles, cleared on screen change.
- `lastSwipeDirectionByTarget: [String: UIAccessibilityScrollDirection]` — per-swipe-target.
- `lastSentState: SentState?` — the response-tracking state, semantically "have we sent anything yet".
These don't co-vary into a single lifecycle, but they accumulate one-off "do we know X yet" booleans on the class. `clearCache()` (line 279-285) is the giveaway — five fields nil'd/cleared in one method, which the codebase's own CLAUDE.md guidance flags as a code smell.

**Sketch:**
This is borderline-okay; the only real win is bundling them by lifetime (per-screen vs across-screens vs per-swipe) into named structs. Worth flagging because the codebase has aggressive expectations around state-machine modeling, not because the code is broken.

### Finding 6: `WireConversion` is fine but the file is large
**Severity:** consider
**Type:** size-only
**Location:** `TheStash/WireConversion.swift` (662 LOC)
**Description:**
At 662 LOC it's the longest file in the audit. Three coherent sections:
- Element/tree wire conversion (~150 LOC).
- Delta computation (`computeDelta`, `computeElementEdits`, `computeTreeEdits`, `makeDelta`) (~250 LOC).
- Functional-move pairing inference (`suppressFunctionalMoveElementChurn`, `inferFunctionalHeistElementPairs`, `inferFunctionalTreePairs`, `inferFunctionalPairs`, signature types) (~200 LOC).
Each section is internally cohesive. Splitting into `WireConversion+Delta.swift` and `WireConversion+FunctionalMoves.swift` would help navigation. **Not urgent** — the file reads in order and each MARK section is a coherent chunk.

### Finding 7: TheStash facades for Burglar and WireConversion
**Severity:** consider
**Type:** anemic surface
**Location:** `TheStash/TheStash.swift:414-507`
**Description:**
TheStash has 11 pass-through methods that forward to TheBurglar (`refresh`, `parse`, `apply`, `isTopologyChanged`) or `WireConversion` (`toWire` × 2 overloads, `wireTree`, `wireTreeHash`, `computeDelta`, `traitNames`). The justification is in the dossier ("TheBurglar is module-internal; production callers go through TheStash"). That's coherent — it's a deliberate encapsulation boundary. The cost: any time a new wire-conversion method or parse method is added, the facade needs a new line. Acceptable trade-off; flagging only because it's a recurring noise during PRs.

## Proposed pipeline shape

The cleaner decomposition. Crew names retained except for the new member.

```
                  ┌─────────────────────────────┐
ClientMessage ───►│ TheBrains                   │
                  │  - executeCommand (dispatch)│
                  │  - performInteraction       │ ──► ActionExecutor.executeXxx(target, stash)
                  │  - performElementSearch     │      │
                  │  - performWaitFor           │      ▼
                  │  - performExplore           │     TheStash + TheSafecracker
                  │  - actionResultWithDelta    │      │
                  │  - SettleSession            │      │
                  │  - sent-state / broadcast   │      │
                  └─────────────┬───────────────┘      │
                                │ (post-action)        │
                                ▼                      │
                  ┌─────────────────────────────┐      │
                  │ Spelunker                   │◄─────┘ (scroll, ensureOnScreen)
                  │  - scroll / scrollToVisible │
                  │  - elementSearch            │
                  │  - exploreAndPrune          │
                  │  - ScrollableTarget         │
                  │  - SettleSwipeLoopState     │
                  │  - ScreenManifest           │
                  │  - ContainerExploreState    │
                  │  - ExplorePhase             │
                  └─────────────────────────────┘
                                │
                                ▼
                  ┌─────────────────────────────┐
                  │ TheStash                    │
                  │  - resolveTarget            │
                  │  - matchScreenElements      │
                  │  - ElementRegistry (Merge)  │
                  │  - WireConversion           │
                  │  - Diagnostics              │
                  │  - IdAssignment             │
                  │  - Interactivity            │
                  │  - liveGeometry / activate  │
                  └─────────────┬───────────────┘
                                │
                                ▼
                  ┌─────────────────────────────┐
                  │ TheBurglar                  │
                  │  - parse / apply            │
                  │  - isTopologyChanged        │
                  │  - buildElementContexts     │
                  └─────────────────────────────┘

       ┌─────────────────────────────────────────────────────┐
       │ AccessibilityPolicy (new, in TheStash)              │
       │  - interactiveTraits                                │
       │  - transientTraits                                  │
       │  - synthesisRanking                                 │
       │  - staticOnlyTraits                                 │
       │  - tabSwitchPersistThreshold                        │
       └─────────────────────────────────────────────────────┘
                  ▲       ▲      ▲      ▲
                  │       │      │      │
        Interactivity  IdAssignment  ElementRegistry  WireConversion  TheBurglar
        (read policy, don't own it)
```

**File-by-file migration:**

| Current file | Lines | New home |
|---|---|---|
| `TheBrains/TheBrains.swift` | 533 | TheBrains (slimmed to ~700 with pipeline calls) |
| `TheBrains/TheBrains+Dispatch.swift` | 282 | TheBrains (or `TheBrains+Dispatch.swift`) |
| `TheBrains/TheBrains+Actions.swift` | 451 | `TheBrains/ActionExecutor.swift` |
| `TheBrains/TheBrains+Scroll.swift` | 735 | `TheBrains/Spelunker/Spelunker+Scroll.swift` |
| `TheBrains/TheBrains+Exploration.swift` | 413 | `TheBrains/Spelunker/Spelunker+Explore.swift` |
| `TheBrains/TheBrains+Exploration+Manifest.swift` | 46 | `TheBrains/Spelunker/Spelunker.swift` (alongside `ScreenManifest`) |
| `TheBrains/SettleSession.swift` | 300 | stays |
| `TheBrains/ActionResultBuilder.swift` | 89 | stays |
| `TheBrains/ActivateFailureDiagnostic.swift` | 104 | stays |
| `TheStash/Interactivity.swift` | 64 | stays — reads `AccessibilityPolicy.interactiveTraits` |
| `TheStash/IdAssignment.swift` | 108 | stays — reads `AccessibilityPolicy.synthesisRanking` |
| `TheStash/WireConversion.swift` | 662 | stays — reads `AccessibilityPolicy.transientTraits` |
| `TheStash/ElementRegistry.swift` | 229 | stays — reads `AccessibilityPolicy.transientTraits` |
| `TheStash/AccessibilityPolicy.swift` | — | **new**, ~50 LOC of policy constants with cross-references |

The net file count goes up by one (AccessibilityPolicy) and goes down by zero (Spelunker absorbs three TheBrains extensions). The total LOC is unchanged. The win is **change locality**: a new gesture changes ActionExecutor only; a new container scroll strategy changes Spelunker only; a new transient trait changes AccessibilityPolicy only.

## What to keep

A surprising amount. TheBurglar's parse pipeline (parse → apply → refresh, with `ParseResult` as a value type and `ContainerIdentityContext` as a named output) is exemplary — model that pattern when other crew members get reshaped. TheStash's persistent-tree registry with its merge algorithm in `ElementRegistry+Merge.swift` is genuinely good design: the merge is a pure pipeline of total functions (`collectOrphans`, `buildNodes`, `attachOrphans`, `sortContainerChildren`, `pruneEmptyContainers`, `buildIndex`), each documented as such, and the `validateInvariants` method (line 489) earns its keep as a sanity check. `TargetResolution` and `ResolvedTarget` (TheStash.swift:96-121) are the right shape for the resolution contract — three named cases with diagnostic data. `MatchMode` (Matching.swift:61-66) and the exact-before-substring two-pass in `matchScreenElements` are the right shape for deterministic-but-forgiving lookup. `SettleSession`'s value-typed loop state, injectable closures, and explicit `SettleOutcome` enum are textbook for the pattern. `ActionResultBuilder` (89 LOC) is exactly the right size and exactly the right surface — do not "improve" it. The crew metaphor pays for itself in chat and in commits; don't rename anyone in pursuit of structural clarity.

## Sightings (not findings)

These are bugs/oddities noticed in passing — passing to the bug audit for triage, not investigated here.

- `TheBrains+Scroll.swift:560` — `bhIsUnsafeForProgrammaticScrolling` short-circuits to `return nil` in `scrollableTarget(for:contentSize:)`, but the caller in `findScrollTarget` (line 543) then falls through to `nil`, so the unsafe container is simply skipped. The container `markExplored` path in `exploreScreen` (line 97) does handle this, but `executeScroll` (line 351) returns "No scrollable ancestor found for element" — which is misleading if the ancestor exists but is unsafe. Worth confirming the diagnostic text is right when this fires.
- `TheBrains.swift:174-175` — `_ = await exploreAndPrune()` runs after every action regardless of outcome. The cycle cost is real (per-container fingerprint cache hits keep it cheap on no-op cases, but unconditional). If an action is purely UI state (e.g. a no-op `getPasteboard`), the post-action explore is wasted work. Could be gated on `!isScreenChange && delta != .noChange`.
- `TheBrains+Exploration.swift:107-110` — `if found { return manifest }` early-returns *during* the per-batch loop, but `manifest.pendingContainers` may still have entries. On the next `exploreAndPrune` call those entries are not seeded again because pendingContainers is freshly reset via `beginExploreCycle` — confirm that's the intent.
- `ElementRegistry.swift:122-141` — `resolveHeistId` has two return paths that look near-identical when `contentSpaceOrigin == nil`. The early `if let existing` branch returns the base ID without checking the second case's `existingOrigin` guard. Possibly correct but worth a closer look.
- `TheStash+Matching.swift:240-244` — the off-screen registry fallback is a full `flattenElements()` filter. On screens with thousands of off-screen elements (lists, picker columns) this is O(N) per matcher call. Cache invalidation considerations may be why no index exists — but worth profiling.
- `TheBrains.swift:344` — `guard let sent = lastSentState, sent.treeHash != 0 else { return nil }` — `treeHash == 0` as a sentinel is fragile; `0` is a legal hash value. `lastSentState: SentState?` already encodes "no prior send" via nil.
