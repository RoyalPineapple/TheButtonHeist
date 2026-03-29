# Scrolling Deep Dive

> **Source:** `ButtonHeist/Sources/TheInsideJob/TheBagman+Scroll.swift` (orchestration), `TheSafecracker+Actions.swift` (scroll primitives)
> **Parent dossiers:** [13-THEBAGMAN.md](13-THEBAGMAN.md), [04-THESAFECRACKER.md](04-THESAFECRACKER.md)

TheBagman owns all scroll orchestration — three explicit scroll commands for agents, and an automatic pre-interaction scroll that ensures every action is visible on screen. TheSafecracker provides the scroll primitives (`scrollByPage`, `scrollToEdge`, `scrollToMakeVisible`) but never decides what to scroll or when.

## Auto-Scroll to Visible

### Why it exists

Humans watching an agent interact with a simulator need to see every action happen on screen. Without auto-scroll, an agent can tap, type into, or swipe an element that's scrolled out of the viewport — the action succeeds but the observer sees nothing happen.

The check runs inside TheBagman before every interaction (via `ensureOnScreen(for:)`). The agent has no knowledge of it, sends no extra parameters, and receives no indication it happened. From the agent's perspective the command just works. From the human's perspective the screen scrolls to the element and then the action occurs.

### What it checks

The check compares the element's `accessibilityFrame` (screen coordinates, read from the live `NSObject`) against `UIScreen.main.bounds`. If the frame is fully contained within the screen bounds, no scroll is needed.

**This is a bounds check, not a visibility check.** It does not care about:
- Keyboard overlapping the element
- Modal sheets or overlays obscuring the element
- Other views drawn on top of the element
- The element being transparent or hidden

It only cares whether the element's frame is geometrically within the screen rectangle. An element behind a keyboard is "on screen" — an element scrolled 500 points below the viewport is not.

### What it does when an element is off-screen

1. Walks the accessibility/view hierarchy upward from the element via `nextAncestor(of:)` to find the nearest `UIScrollView` with `isScrollEnabled == true`
2. Calls `scrollToMakeVisible(_:in:)` which converts the element's frame into the scroll view's coordinate space and adjusts `contentOffset` by the minimum amount needed to bring the element fully within the scroll view's visible rect
3. Waits for the scroll animation to settle via `tripwire.waitForAllClear(timeout: 1.0)` — this uses presentation-layer diffing, not a fixed sleep
4. Refreshes the element cache via `bagman.refreshAccessibilityData()` so subsequent reads (activation points, frames) reflect post-scroll positions

```mermaid
flowchart TD
    Cmd["Any interaction command"]
    Cmd --> HasTarget{element target<br/>or first responder?}
    HasTarget -->|no| Execute["Execute interaction"]
    HasTarget -->|yes| Resolve["Resolve live NSObject"]

    Resolve --> Frame["Read object.accessibilityFrame"]
    Frame --> Valid{non-null,<br/>non-empty?}
    Valid -->|no| Execute
    Valid -->|yes| OnScreen{frame within<br/>UIScreen.main.bounds?}
    OnScreen -->|yes| Execute

    OnScreen -->|no| Walk["Walk ancestor chain<br/>nextAncestor(of:)"]
    Walk --> ScrollView{found UIScrollView<br/>with isScrollEnabled?}
    ScrollView -->|no| Execute
    ScrollView -->|yes| Scroll["scrollToMakeVisible()<br/>minimum contentOffset adjustment"]
    Scroll --> Settle["tripwire.waitForAllClear(1.0s)<br/>presentation-layer diffing"]
    Settle --> Refresh["bagman.refreshAccessibilityData()<br/>rebuild element cache"]
    Refresh --> Execute
```

### Entry points

Two public methods resolve their target, then delegate to a shared private implementation:

| Method | Resolves object from | Used by |
|--------|---------------------|---------|
| `ensureOnScreen(for: ElementTarget)` | TheBagman screenElements registry | activate, increment, decrement, customAction, tap, longPress, swipe, drag, pinch, rotate, twoFingerTap, typeText |
| `ensureFirstResponderOnScreen()` | `tripwire.currentFirstResponder()` responder chain walk | editAction, setPasteboard, getPasteboard, resignFirstResponder |

Both resolve to a live `NSObject` and check its `accessibilityFrame` against `UIScreen.main.bounds`. `NSObject` is the right abstraction because `accessibilityFrame` lives on NSObject via the UIAccessibility informal protocol, and the ancestor walk needs the live object to climb `superview` / `accessibilityContainer`. A bare `CGRect` can't tell you which scroll view to scroll.

### Requirements

- **UIScrollView ancestor.** The element must be inside a `UIScrollView` (or subclass — `UITableView`, `UICollectionView`, `UITextView`, etc.) with `isScrollEnabled == true`. If no scrollable ancestor exists, the check is a no-op.
- **Valid accessibilityFrame.** The live `NSObject` must return a non-null, non-empty `accessibilityFrame`. Elements with `.isNull` or `.isEmpty` frames are skipped.
- **Reachable via ancestor walk.** `nextAncestor(of:)` traverses `UIView.superview`, `UIAccessibilityElement.accessibilityContainer`, and KVO `accessibilityContainer`. If the hierarchy is broken or uses a non-standard container pattern the walk won't find the scroll view.
- **TheTripwire injected.** If `tripwire` is nil the scroll still happens but there's no settle wait — the interaction proceeds immediately after adjusting the content offset.

### Limitations

- **Single scroll view.** The ancestor walk stops at the first `UIScrollView` it finds. Nested scroll views (e.g. a horizontal carousel inside a vertical table) will only scroll the innermost one. If the element is off-screen in the outer scroll view, the inner scroll adjustment alone won't bring it into the viewport.
- **No retry.** If the scroll doesn't fully bring the element on screen (e.g. the element is larger than the viewport, or the scroll view has constraints that prevent reaching the target offset), there is no second attempt.
- **No synthetic touch scrolling.** All scrolling uses `UIScrollView.setContentOffset(animated: true)` directly. This bypasses gesture recognizers, scroll view delegates, and any custom scrolling behavior that only responds to touch events. Paging scroll views, scroll views with `scrollViewWillEndDragging` snapping, and custom pull-to-refresh headers may not behave as expected.
- **Frame-based only.** The check uses `accessibilityFrame` which is a rectangle in screen coordinates. It does not account for scroll view content insets reducing the actual visible area — though `scrollToMakeVisible` does account for `adjustedContentInset` when computing the visible rect and clamping the offset.
- **Raw coordinate gestures bypass the check.** Gestures specified by explicit `pointX`/`pointY` coordinates (no element target) skip auto-scroll entirely. If an agent sends a tap at coordinates that happen to be off-screen, there's no element to scroll to.

### Best-effort guarantee

The auto-scroll never blocks or fails the command. If anything goes wrong — element can't be resolved, no scrollable ancestor, frame is null, tripwire is nil — the interaction proceeds at the current position, exactly as it did before this feature existed.

## Explicit Scroll Commands

Three commands expose scrolling directly to agents. These are not auto-scroll — they are standalone commands the agent sends intentionally.

| Command | Method | Behavior |
|---------|--------|----------|
| `scroll` | `TheBagman.executeScroll` → `scrollByPage` | Moves contentOffset by `frame.height - 44pt` overlap in the given direction |
| `scroll_to_visible` | `TheBagman.executeScrollToVisible` | Bidirectional scroll search with lazy container support |
| `scroll_to_edge` | `TheBagman.executeScrollToEdge` → `scrollToEdge` | Jumps to content extreme, iterates for lazy containers |

TheBagman orchestrates all three; TheSafecracker provides the scroll primitives (`scrollByPage`, `scrollToEdge`). `scroll_to_visible` uses `scrollByPage` in a multi-phase search loop.

### scroll (page step)

Scrolls the nearest `UIScrollView` ancestor by one page in the given direction. "One page" is the scroll view's frame dimension minus a 44pt overlap, so the user retains context across pages.

```
newOffset.y = offset.y + (frame.height - 44)   // down/next
newOffset.y = offset.y - (frame.height - 44)   // up/previous
newOffset.x = offset.x + (frame.width - 44)    // right
newOffset.x = offset.x - (frame.width - 44)    // left
```

Offsets are clamped to `[-insets.top, contentSize.height + insets.bottom - frame.height]` (vertical) and the equivalent horizontal range by default. When `clampToContentSize: false`, forward directions (down, right, next) skip the upper clamp — needed for SwiftUI lazy containers where `contentSize` grows as content is rendered. Returns `false` if the computed offset equals the current offset (already at the edge).

Directions: `.up`, `.down`, `.left`, `.right`, `.next` (alias for down), `.previous` (alias for up).

### scroll_to_visible (bidirectional search)

Searches for an element matching an `ElementMatcher` predicate by scrolling through the nearest scroll view. Unlike `scroll` (one page) or `scrollToMakeVisible` (minimal adjustment for a known element), this is a search operation — it finds elements that may not be on screen yet.

**Input:** `ScrollToVisibleTarget` containing an `ElementTarget` predicate, optional `maxScrolls` (default 20, clamped to >= 1), and optional `direction` (default `.down`).

**Matching:** Uses `resolveFirstMatch` with first-match semantics — any match is success, no uniqueness check. This is different from `resolveTarget` (which requires exactly one match). Matching runs on the canonical `AccessibilityHierarchy` tree, not on wire types.

**Two-phase algorithm:**

1. **Phase 0 — Check current tree.** Before scrolling, `refreshAccessibilityData()` and check if the element is already visible via `resolveFirstMatch`. If found, return immediately with `scrollCount: 0`.

2. **Phase 1 — Scroll in primary direction.** Uses `scanLoop()` — scrolls one page at a time (via `scrollByPage(animated: false, clampToContentSize: false)`), yields 2 display frames via `yieldFrames(2)` (`CATransaction.flush()` + `Task.yield()`), refreshes the element cache, then checks for a match. Tracks unique heistIds via `onScreen` set to detect when new content stops appearing (content exhausted). The content-size clamp is always disabled so lazy containers can scroll past the currently-materialized region.

3. **Phase 2 — Reverse search.** If Phase 1 didn't find the element and budget remains, jump to the opposite edge via `scrollToOppositeEdge`, yield frames, and run `scanLoop()` again in the primary direction to cover content before the original starting position. Skipped entirely if Phase 1 exhausted the budget.

**Non-blocking scroll:** The scroll loop uses `yieldFrames(2)` — just `CATransaction.flush()` + `Task.yield()` per frame — instead of the heavier `waitForSettle`. This is enough for layout to run and lazy containers to materialize content, without waiting for animations to finish. Combined with `animated: false`, multi-page searches are very fast.

**Response:** Every `scrollToVisible` result includes a `scrollSearchResult` with `scrollCount`, `uniqueElementsSeen`, `totalItems`, `exhaustive`, and `foundElement`.

```mermaid
flowchart TD
    S["executeScrollToVisible(target)"] --> REF["refreshAccessibilityData()"]
    REF --> CHK{"resolveFirstMatch(target)<br/>Already visible?"}
    CHK -->|Yes| DONE["Return success<br/>(scrollCount: 0)"]
    CHK -->|No| FSV["findFirstScrollView()<br/>(walk onScreen elements<br/>→ scrollableAncestor)"]
    FSV --> SVOK{Found<br/>scroll view?}
    SVOK -->|No| FAIL0["Return failure:<br/>'No scroll view found'"]
    SVOK -->|Yes| PH1["Phase 1: scanLoop()<br/>Primary direction"]

    PH1 --> SLOOP["scrollByPage(animated: false,<br/>clampToContentSize: false)"]
    SLOOP --> SETTLE["yieldFrames(2)"]
    SETTLE --> REFR["refreshAccessibilityData()"]
    REFR --> FM{"resolveFirstMatch(target)"}
    FM -->|Found| END["Return success<br/>+ ScrollSearchResult"]
    FM -->|Not found| NEW{New heistIds<br/>appeared?}
    NEW -->|No new IDs| STALL["Break — content exhausted"]
    NEW -->|Yes| BUDGET{scrollCount<br/>< maxScrolls?}
    BUDGET -->|Yes| SLOOP
    BUDGET -->|No| STALL

    STALL --> PH2["Phase 2: scrollToOppositeEdge()<br/>+ yieldFrames(2)"]
    PH2 --> SCAN2["scanLoop() again<br/>(same direction, remaining budget)"]
    SCAN2 --> RESULT{Found?}
    RESULT -->|Yes| END
    RESULT -->|No| FAILN["Return failure:<br/>'not found after N scrolls'"]
```

### scroll_to_edge (jump to extreme)

Jumps the content offset to the absolute edge of the content:

| Edge | Offset |
|------|--------|
| `.top` | `y = -insets.top` |
| `.bottom` | `y = contentSize.height + insets.bottom - frame.height` |
| `.left` | `x = -insets.left` |
| `.right` | `x = contentSize.width + insets.right - frame.width` |

Returns `true` without scrolling if already at the target edge.

**Re-jump iteration:** Content may grow after the initial jump (lazy containers materialize on scroll). After a successful edge jump, `executeScrollToEdge` yields frames and re-jumps in a loop (up to 20 iterations), exiting when both `contentSize` stabilizes and `scrollToEdge` reports no movement. Uses `yieldFrames(2)` between iterations — lightweight frame yielding, not full settle polling.

## Ancestor Walk

All scroll operations share `nextAncestor(of:)` to find the nearest scrollable container. It handles three cases:

1. **UIView** → `view.superview` — standard UIKit view hierarchy
2. **UIAccessibilityElement** → `element.accessibilityContainer` cast to `NSObject` — VoiceOver container elements that aren't UIViews
3. **Other NSObject** → KVO `value(forKey: "accessibilityContainer")` — covers custom accessibility containers that implement the informal protocol

The walk stops at the first `UIScrollView` (or subclass) with `isScrollEnabled == true`. This means:
- `UITableView`, `UICollectionView`, `UITextView` are all found (they're UIScrollView subclasses)
- Disabled scroll views (`isScrollEnabled = false`) are skipped — the walk continues upward
- SwiftUI `ScrollView` works because it's backed by a `UIScrollView` in the underlying UIKit hierarchy

### What the walk cannot find

- Scroll views behind a broken container chain (e.g. a custom `UIAccessibilityElement` whose `accessibilityContainer` is nil)
- Non-UIScrollView custom scrolling containers (e.g. a custom `UIView` that implements its own pan-gesture-driven scrolling)
- SwiftUI `LazyVStack` without a `ScrollView` parent — there's no UIScrollView in the hierarchy to find

## Settle After Scroll

After any `setContentOffset(animated: true)` call, the scroll view runs a Core Animation animation (~300ms). The auto-scroll path waits for this to complete using `tripwire.waitForAllClear(timeout: 1.0)`.

TheTripwire's settle detection works by repeatedly snapshotting CALayer presentation trees and comparing them. When all presentation layers match their model layers (no in-flight animations), it returns. This covers both UIKit animations and SwiftUI transitions that might be triggered by the scroll.

After settle, `bagman.refreshAccessibilityData()` rebuilds the element cache. This is necessary because:
- `accessibilityFrame` values change after scrolling (the views moved)
- `activationPoint` values change (derived from frames)
- The agent's next action needs to tap/interact at the new position

The `scroll` command does **not** settle or refresh internally — it returns immediately after `setContentOffset`. The settle and delta computation happens in the outer `performInteraction` pipeline after the command returns.

`scroll_to_visible` and `scroll_to_edge` are now `async` and handle their own frame yielding internally — both use `yieldFrames(2)` (`CATransaction.flush()` + `Task.yield()` per frame) between steps. This is lighter than `waitForSettle` — just enough for layout to run and lazy content to materialize, without waiting for animations to finish. The outer pipeline still runs `actionResultWithDelta` after they return.

## Implementation Notes

### Why setContentOffset, not synthetic touch

Synthetic touch scrolling would require simulating a multi-step pan gesture:
1. Touch down
2. Multiple touch-moved events with appropriate velocity
3. Touch up with deceleration

This is fragile — scroll view physics, deceleration curves, and content inset handling are complex. `setContentOffset(animated: true)` gives us exact positioning with UIKit handling all the animation. The trade-off is that we bypass `UIScrollViewDelegate` methods like `scrollViewWillEndDragging(_:withVelocity:targetContentOffset:)`, which means paging snap behavior won't trigger.

### Why the 44pt overlap in page scroll

The 44pt overlap when paging ensures continuity — the last few lines of the previous page remain visible at the top of the next page. This matches the standard iOS VoiceOver three-finger-swipe page scrolling behavior. 44pt is also the minimum recommended touch target size in the HIG.

### Why NSObject for ensureOnScreen

The auto-scroll has two callers: element-targeted commands (resolve through TheBagman) and first-responder commands (resolve through the UIView responder chain). Both produce a live `NSObject` that has `accessibilityFrame` and participates in the view hierarchy. Accepting `NSObject` lets both paths share one implementation without forcing either to convert to the other's resolution type.

A `CGRect` parameter was considered and rejected because the ancestor walk needs the live object reference — you can't climb `superview` from a rectangle.
