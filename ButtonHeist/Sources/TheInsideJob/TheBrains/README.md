# TheBrains

Command execution engine. Takes a `ClientMessage`, works it through refresh → action → settle → delta, and returns an `ActionResult`.

TheBrains is the orchestrator. Two internal components handle the heavy lifting:

- **`Navigation`** — scroll orchestration and screen exploration. Owns `ScrollableTarget`, `SettleSwipeLoopState`, `ScreenManifest`, and `lastSwipeDirectionByTarget`. Public entry points are `executeScroll`, `executeScrollToVisible`, `executeScrollToEdge`, `executeElementSearch`, `exploreAndPrune`, `makeSemanticallyVisible`, `makeActionable`, `ensureFirstResponderOnScreen`.
- **`Actions`** — the 21 `executeXxx` action handlers (activate, increment, decrement, customAction, editAction, setPasteboard, getPasteboard, resignFirstResponder, tap, longPress, swipe, drag, pinch, rotate, twoFingerTap, drawPath, drawBezier, typeText, plus the `performElementAction` / `performPointAction` generic pipelines and duration helpers).

Navigation's invariant: visible pages are physical evidence; known state is semantic memory; reconciliation is the only place evidence becomes memory.

Both components are owned by TheBrains (`let navigation: Navigation`, `let actions: Actions`) and share the same TheStash / TheSafecracker / TheTripwire references. They are *internal components of TheBrains*, not crew members in their own right — neutral noun-style names. Actions holds a reference to Navigation so targeted element/point flows can call `makeActionable(for:)`, and edit, pasteboard, and resign-first-responder commands can call `ensureFirstResponderOnScreen()`.

TheBrains keeps the post-action delta cycle, dispatch, wait handlers, response state, and recording state. It also re-exposes the most-touched Navigation/Actions members via typealiases and forwarding properties so callers can spell them `brains.X` when the original location was less ergonomic; new code should call `brains.navigation.X` / `brains.actions.X` directly.

## Reading order

1. **`TheBrains+Dispatch.swift`** — Start here. `executeCommand(_:)` is the single entry point from TheGetaway. A switch routes every `ClientMessage` case to one of four pipelines:

   - **`performInteraction`** (most commands) — refresh → captureBeforeState → action closure → actionResultWithDelta. Used by all accessibility actions and touch gestures. The action closure calls `actions.executeXxx(target)` or `navigation.executeScroll(target)` etc.
   - **`performElementSearch`** — same shape but the scroll loop in `navigation.executeElementSearch` manages its own refresh/settle internally. Patches `ScrollSearchResult` onto the result.
   - **`performWaitFor`** — polls the fresh semantic hierarchy in a settle loop until found/absent or timeout.
   - **`performExplore`** — calls `navigation.exploreAndPrune()`, assembles the result inline (doesn't use `actionResultWithDelta`; needs full wire elements in `ExploreResult`).

   Action and gesture cases unpack their associated values in `executeCommand` and call `performInteraction` with the specific `actions.executeXxx` closure.

2. **`TheBrains.swift`** — Core class. Key types:

   - `BeforeState` — frozen accessibility capture plus the local parser state needed for matching, screen classification, and diagnostics.
   - **`refresh()`** — delegates to `stash.refresh()`.
   - **`ScreenClassifier.swift`** — parsed accessibility signatures classify no-change, element-change, and screen-change. Tripwire triggers parsing; parsed signatures decide.
   - **`actionResultWithDelta(before:)`** — the convergence point. On failure: immediate return from before-capture. On success: settle until stable or Tripwire-triggered → `stash.parse()` → `ScreenClassifier.classify(before:after:)` → `stash.apply()` → `navigation.exploreAndPrune()` → `AccessibilityTrace` → derived `AccessibilityTrace.Delta` → `ActionResultBuilder.success()`.

   **Response state** — `SentState` stores the captured semantic state from the last response sent to the driver. Metadata such as interface hash, capture hash, and screen id is derived from that capture; viewport movement stays inside the interaction layer and does not become response memory. `recordSentState()` snapshots current state; `computeBackgroundAccessibilityTrace()` refreshes local state and derives any public trace from capture hashes. Broadcast de-duplication memory also lives here because it describes outbound delivery, not TheStash's accessibility belief. TheGetaway calls `recordSentState()` after every send.

   **Wait handlers** — `executeWaitForIdle(timeout:)` and `executeWaitForChange(timeout:expectation:)` live here (not in TheGetaway) because they're accessibility-level work: refresh, settle, delta, expectation evaluation. Wait-for-change installs one server-side predicate, checks current state first, then watches settled changes until the expectation is true or the timeout clears it. In that wait-specific path, `element_disappeared` is current absence, not proof of a prior removal event.

   **TheGetaway-facing methods** — `observeInterface(_:)`, `currentInterface()`, `computeBackgroundAccessibilityTrace()`, `captureScreen()`, `captureScreenForRecording()`, `screenName`, `screenId`, `stakeout`. These exist so TheGetaway and TheInsideJob never reach through to TheStash. Observation policy lives here: `get_interface` requests can trigger exploration and selection, while `get_screen` performs a fresh visible parse and returns geometry with the screenshot.

3. **`Actions.swift`** — Type declaration and shared dependencies for the action execution component.

4. **`ActionExecutionInputs.swift`** — Protocol conformances and small input adapters that let batch and single-command execution call the same action methods.

5. **`Actions+ElementActions.swift`** — Element-targeted accessibility actions and the `performElementAction(target:method:action:)` pipeline: semantic selector → `navigation.makeActionable` → interactivity check → action closure with `LiveActionTarget`. Used by activate, increment, decrement, customAction, and rotor.

6. **`Actions+PointGestureActions.swift`** and **`Actions+GestureGeometryResolution.swift`** — Point and gesture actions plus the geometry helpers that resolve element-relative or absolute points immediately before dispatch. Used by tap, longPress, swipe, drag, pinch, rotate, twoFingerTap, drawPath, and drawBezier.

7. **`Actions+TextInputActions.swift`** — Text, edit, pasteboard, and first-responder commands. `executeTypeText` handles optional `navigation.makeActionable` + tap-to-focus → poll for active text input → type a non-empty string → refresh → re-resolve for value readback.

8. **`Actions+RecoveryPolicies.swift`** — Named recovery policies for stale or refused live targets.

9. **`Navigation.swift`** — Type declaration, init, state (`lastSwipeDirectionByTarget`), and the nested types `SettleSwipeProfile`, `SettleSwipeStep`, `SettleSwipeLoopState`, `ScrollableTarget`, `ScrollAxis`, `ScreenManifest`. Plus `refresh()` and `clearCache()` helpers.

10. **`Navigation+Scroll.swift`** — `executeScroll` does one page. `executeScrollToVisible` uses the semantic reveal path: already visible → reveal plan → fresh visible resolution → classified failure. `executeElementSearch` searches only containers matching the requested axis, page-by-page up to 200 scrolls. `makeActionable` is the central semantic actionability path for targeted actions. Direction mapping, axis detection, and `safeSwipeFrame` (tab-bar-aware clip) also live here.

11. **`Navigation+Explore.swift`** — `exploreAndPrune()` builds a local `var union: Screen`, runs `exploreScreen()`, then writes `stash.currentScreen = union`. Per container: scrolls to leading edge → pages through accumulating elements via `reconcilePage` → restores visual origin for `UIScrollView` targets. Exploration uses `ScrollableTarget` so non-`UIScrollView` containers use swipe fallback. `ScreenManifest` bookkeeping lives in `Navigation.swift`.

12. **`ActionResultBuilder.swift`** — Assembles `ActionResult` from method + snapshot/capture. Three init paths (from `[ScreenElement]`, `AccessibilityTrace.Capture`, or explicit screenName/Id). Two terminal methods: `success(payload:)` and `failure(errorKind:payload:)`.

> Full dossier: [`docs/dossiers/13-THEBRAINS.md`](../../../../docs/dossiers/13-THEBRAINS.md)

## Audit Acceptance Criteria

- Unsupported commands include stable command identity and current screen context.
- `exploreAndPrune()` explores scrollable containers through both direct `UIScrollView` and swipe fallback paths.
- `Navigation` and `Actions` are internal components of TheBrains, not crew members. Production code can call either `brains.navigation.X` / `brains.actions.X` (preferred) or `brains.X` (forwarders, kept for test compatibility).
