# TheBrains

Command execution engine. Takes a `ClientMessage`, works it through refresh → action → settle → delta, and returns an `ActionResult`.

TheBrains is the orchestrator. Two internal components handle the heavy lifting:

- **`Navigation`** — scroll orchestration and screen exploration. Owns `ScrollableTarget`, `SettleSwipeLoopState`, `ScreenManifest`, and `lastSwipeDirectionByTarget`. Public entry points are `executeScroll`, `executeScrollToVisible`, `executeScrollToEdge`, `executeElementSearch`, `exploreAndPrune`, `ensureOnScreen`, `ensureFirstResponderOnScreen`.
- **`Actions`** — the 21 `executeXxx` action handlers (activate, increment, decrement, customAction, editAction, setPasteboard, getPasteboard, resignFirstResponder, tap, longPress, swipe, drag, pinch, rotate, twoFingerTap, drawPath, drawBezier, typeText, plus the `performElementAction` / `performPointAction` generic pipelines and duration helpers).

Navigation's invariant: visible pages are physical evidence; known state is semantic memory; reconciliation is the only place evidence becomes memory.

Both components are owned by TheBrains (`let navigation: Navigation`, `let actions: Actions`) and share the same TheStash / TheSafecracker / TheTripwire references. They are *internal components of TheBrains*, not crew members in their own right — neutral noun-style names. Actions holds a reference to Navigation so targeted element/point flows can call `ensureOnScreen(for:)`, and edit, pasteboard, and resign-first-responder commands can call `ensureFirstResponderOnScreen()`.

TheBrains keeps the post-action delta cycle, dispatch, wait handlers, response state, and recording state. It also re-exposes the most-touched Navigation/Actions members via typealiases and forwarding properties so callers can spell them `brains.X` when the original location was less ergonomic; new code should call `brains.navigation.X` / `brains.actions.X` directly.

## Reading order

1. **`TheBrains+Dispatch.swift`** — Start here. `executeCommand(_:)` is the single entry point from TheGetaway. A switch routes every `ClientMessage` case to one of four pipelines:

   - **`performInteraction`** (most commands) — refresh → captureBeforeState → action closure → actionResultWithDelta. Used by all accessibility actions and touch gestures. The action closure calls `actions.executeXxx(target)` or `navigation.executeScroll(target)` etc.
   - **`performElementSearch`** — same shape but the scroll loop in `navigation.executeElementSearch` manages its own refresh/settle internally. Patches `ScrollSearchResult` onto the result.
   - **`performWaitFor`** — polls the fresh semantic hierarchy in a settle loop until found/absent or timeout.
   - **`performExplore`** — calls `navigation.exploreAndPrune()`, assembles the result inline (doesn't use `actionResultWithDelta`; needs full wire elements in `ExploreResult`).

   Two private helpers `executeAccessibilityAction` and `executeTouchGesture` are second-level switches that unpack the associated value and call `performInteraction` with the specific `actions.executeXxx` closure.

2. **`TheBrains.swift`** — Core class. Key types:

   - `BeforeState` — frozen accessibility capture plus the local parser state needed for matching, screen classification, and diagnostics.
   - **`refresh()`** — delegates to `stash.refresh()`.
   - **`ScreenClassifier.swift`** — parsed accessibility signatures classify no-change, element-change, and screen-change. Tripwire triggers parsing; parsed signatures decide.
   - **`actionResultWithDelta(before:)`** — the convergence point. On failure: immediate return from before-capture. On success: settle until stable or Tripwire-triggered → `stash.parse()` → `ScreenClassifier.classify(before:after:)` → `stash.apply()` → `navigation.exploreAndPrune()` → `AccessibilityTrace` → derived `AccessibilityTrace.Delta` → `ActionResultBuilder.success()`.

   **Response state** — `SentState` struct (semantic `treeHash`, cheap `viewportHash`, `captureHash`, beforeState, screenId) tracks the last response sent to the driver. `recordSentState()` snapshots current state; `computeBackgroundAccessibilityTrace()` first checks the viewport hash plus capture context, then derives the public trace from capture hashes. Broadcast de-duplication memory also lives here because it describes outbound delivery, not TheStash's accessibility belief. TheGetaway calls `recordSentState()` after every send.

   **Wait handlers** — `executeWaitForIdle(timeout:)` and `executeWaitForChange(timeout:expectation:)` live here (not in TheGetaway) because they're accessibility-level work: refresh, settle, delta, expectation evaluation. Wait-for-change installs one server-side predicate, checks current state first, then watches settled changes until the expectation is true or the timeout clears it. In that wait-specific path, `element_disappeared` is current absence, not proof of a prior removal event.

   **TheGetaway-facing methods** — `observeInterface(_:)`, `currentVisibleInterface()`, `computeBackgroundAccessibilityTrace()`, `captureScreen()`, `captureScreenForRecording()`, `screenName`, `screenId`, `stakeout`. These exist so TheGetaway and TheInsideJob never reach through to TheStash. Observation policy lives here: `get_interface` requests can trigger exploration and projection, while `get_screen` performs a fresh visible parse and returns geometry with the screenshot.

3. **`Actions.swift`** — Two generic pipelines and all `executeXxx` methods:
   - `performElementAction(target:method:action:)` — `navigation.ensureOnScreen` → `stash.resolveTarget` → checkInteractivity → action closure. Used by activate, increment, decrement, customAction.
   - `performPointAction(elementTarget:pointX:pointY:action:)` — `navigation.ensureOnScreen` when element-targeted → live geometry resolution or raw coordinate passthrough → action closure → showFingerprint. Used by tap, longPress, drag, pinch, rotate, twoFingerTap.
   - `executeSwipe` has two paths: unit-point (element-relative 0-1 coordinates resolved against frame) and absolute-point.
   - `executeTypeText` handles optional `navigation.ensureOnScreen` + tap-to-focus → poll for active text input → type a non-empty string → refresh → re-resolve for value readback.

4. **`Navigation.swift`** — Type declaration, init, state (`lastSwipeDirectionByTarget`), and the nested types `SettleSwipeProfile`, `SettleSwipeStep`, `SettleSwipeLoopState`, `ScrollableTarget`, `ScrollAxis`, `ScreenManifest`. Plus `refresh()` and `clearCache()` helpers.

5. **`Navigation+Scroll.swift`** — `executeScroll` does one page. `executeScrollToVisible` tries three strategies: already visible → content-space one-shot jump → failure. `executeElementSearch` searches only containers matching the requested axis, page-by-page up to 200 scrolls. `ensureOnScreen` returns a named pre-action positioning result; targeted action callers must consume failures before dispatch. Direction mapping, axis detection, and `safeSwipeFrame` (tab-bar-aware clip) also live here.

6. **`Navigation+Explore.swift`** — `exploreAndPrune()` builds a local `var union: Screen`, runs `exploreScreen()`, then writes `stash.currentScreen = union`. Per container: scrolls to leading edge → pages through accumulating elements via `reconcilePage` → restores visual origin for `UIScrollView` targets. Exploration uses `ScrollableTarget` so non-`UIScrollView` containers use swipe fallback. `ScreenManifest` bookkeeping lives in `Navigation.swift`.

7. **`ActionResultBuilder.swift`** — Assembles `ActionResult` from method + snapshot/capture. Three init paths (from `[ScreenElement]`, `AccessibilityTrace.Capture`, or explicit screenName/Id). Two terminal methods: `success(payload:)` and `failure(errorKind:payload:)`.

> Full dossier: [`docs/dossiers/13-THEBRAINS.md`](../../../../docs/dossiers/13-THEBRAINS.md)

## Audit Acceptance Criteria

- Unsupported commands include stable command identity and current screen context.
- `exploreAndPrune()` explores scrollable containers through both direct `UIScrollView` and swipe fallback paths.
- `Navigation` and `Actions` are internal components of TheBrains, not crew members. Production code can call either `brains.navigation.X` / `brains.actions.X` (preferred) or `brains.X` (forwarders, kept for test compatibility).
