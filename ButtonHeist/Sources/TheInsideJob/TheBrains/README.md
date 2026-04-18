# TheBrains

Command execution engine. Takes a `ClientMessage`, works it through refresh → action → settle → delta, and returns an `ActionResult`.

## Reading order

1. **`TheBrains+Dispatch.swift`** — Start here. `executeCommand(_:)` is the single entry point from TheGetaway. A switch routes every `ClientMessage` case to one of four pipelines:

   - **`performInteraction`** (most commands) — refresh → captureBeforeState → action closure → actionResultWithDelta. Used by all accessibility actions and touch gestures.
   - **`performElementSearch`** — same shape but the scroll loop manages its own refresh/settle internally. Patches `ScrollSearchResult` onto the result.
   - **`performWaitFor`** — polls `stash.hasTarget(elementTarget)` in a settle loop until found/absent or timeout.
   - **`performExplore`** — scrolls all containers, assembles result inline (doesn't use `actionResultWithDelta`; needs full wire elements in `ExploreResult`).

   Two private helpers `executeAccessibilityAction` and `executeTouchGesture` are second-level switches that unpack the associated value and call `performInteraction` with the specific `executeXxx` closure.

2. **`TheBrains.swift`** — Core class. Key types:

   - `BeforeState` — frozen snapshot (sorted elements, raw parsed elements, hierarchy, VC identity) taken before every action.
   - **`refresh()`** — delegates to `stash.refresh()`, then calls `recordDuringExplore(_:)` which accumulates viewport heistIds into `explorePhase` when it is `.active`.
   - **`actionResultWithDelta(before:)`** — the convergence point. On failure: immediate return from before-snapshot. On success: settle via `tripwire.waitForAllClear(1s)` → `stash.parse()` → screen-change detection (VC identity OR topology) → `stash.apply()` → `exploreAndPrune()` → snapshot → `stash.computeDelta()` → re-resolve target for post-action element metadata → `ActionResultBuilder.success()`.

   **Response state** — `SentState` struct (treeHash, beforeState, screenId) tracks the last response sent to the driver. `recordSentState()` snapshots current state; `computeBackgroundDelta()` compares against it. TheGetaway calls `recordSentState()` after every send.

   **Wait handlers** — `executeWaitForIdle(timeout:)` and `executeWaitForChange(timeout:expectation:)` live here (not in TheGetaway) because they're accessibility-level work: refresh, settle, delta, expectation evaluation. The wait-for-change handler has a fast path (tree already changed since last response) and a slow path (poll loop with `tripwire.waitForAllClear`).

   **TheGetaway-facing methods** — `currentInterface()`, `broadcastInterfaceIfChanged()`, `computeBackgroundDelta()`, `captureScreen()`, `captureScreenForRecording()`, `screenName`, `screenId`, `stakeout`. These exist so TheGetaway and TheInsideJob never reach through to TheStash.

3. **`TheBrains+Actions.swift`** — Two generic pipelines and all `executeXxx` methods:
   - `performElementAction(target:method:action:)` — ensureOnScreen → resolveTarget → checkInteractivity → action closure. Used by activate, increment, decrement, customAction.
   - `performPointAction(elementTarget:pointX:pointY:action:)` — resolvePoint → action closure → showFingerprint. Used by tap, longPress, drag, pinch, rotate, twoFingerTap.
   - `executeSwipe` has two paths: unit-point (element-relative 0-1 coordinates resolved against frame) and absolute-point.
   - `executeTypeText` is the longest: optional tap-to-focus → poll for active text input → optional clear/delete → type string → refresh → re-resolve for value readback.

4. **`TheBrains+Scroll.swift`** — `ScrollableTarget` enum (`.uiScrollView` for direct setContentOffset, `.swipeable` for synthetic swipe fallback). `executeScroll` does one page. `executeScrollToVisible` tries three strategies: already visible → content-space one-shot jump → failure. `executeElementSearch` tries four: visible → one-shot → page-by-page loop (up to 200 scrolls) → not found. `ensureOnScreen` pre-scrolls off-viewport elements and nudges into the comfort zone (frame inset by 1/6).

5. **`TheBrains+Exploration.swift`** — `exploreAndPrune()` calls `beginExploreCycle()`, runs `exploreScreen()`, then `endExploreCycle()` and `registry.prune(keeping:)`. Per container: checks fingerprint cache (skip if unchanged) → scrolls to leading edge → pages through accumulating elements via `stitchPage` → restores visual origin for `UIScrollView` targets → caches state. Exploration uses `ScrollableTarget` so non-`UIScrollView` containers use swipe fallback.

6. **`TheBrains+Exploration+Manifest.swift`** — `ScreenManifest` bookkeeping struct. Tracks pending/explored containers, scroll count, skip counts, timing. `maxScrollsPerContainer = 200`.

7. **`ActionResultBuilder.swift`** — Assembles `ActionResult` from method + snapshot. Two init paths (from `[ScreenElement]` or explicit screenName/Id). Two terminal methods: `success(elementLabel:elementValue:elementTraits:exploreResult:)` and `failure(errorKind:)`.

> Full dossier: [`docs/dossiers/13-THEBRAINS.md`](../../../../docs/dossiers/13-THEBRAINS.md)

## Audit Acceptance Criteria

- Unsupported commands include stable command identity and current screen context.
- Explore pruning relies on explicit `explorePhase` (`.idle`/`.active`) and always resets to `.idle`.
- `exploreAndPrune()` explores scrollable containers through both direct `UIScrollView` and swipe fallback paths before pruning.
