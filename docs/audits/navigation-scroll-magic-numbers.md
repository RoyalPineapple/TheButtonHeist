# `Navigation+Scroll.swift` — magic-number audit

Scope: every numeric literal in `ButtonHeist/Sources/TheInsideJob/TheBrains/Navigation+Scroll.swift` (740 LOC). Catalog, classify, propose a name and a home where the value earns one.
Date: 2026-05-12.
Audit-only — no source changes.

## Summary

Twenty-three numeric literals appear in the file. Most are loop indices (`0`, `2`, `1`), arithmetic constants (`-1`, `* 2`), or values whose meaning is obvious from a single call site (`maxScrolls = 200` is already locally named). The genuinely magical numbers cluster in two places: **frame-yield counts** after a scroll/jump (`yieldFrames(3)`, `yieldRealFrames(20)`), and a one-shot **timeout** for `waitForAllClear`. Both have multiple call sites with identical values and zero local context explaining why the number is what it is.

| Outcome | Count | Notes |
|---|---|---|
| Propose named constant | 4 | Two frame-yield budgets, one settle timeout, one max-page-walk cap |
| Leave inline | 19 | Loop indices, structural arithmetic, obvious bounds, single-use locals already named |
| Delete | 0 | No unused literals found |

The right home for the named values is **`Navigation`** (not `AccessibilityPolicy`, not a new global namespace). They are scroll-pipeline timing parameters, peer to the existing `swipeGestureDuration: TimeInterval = 0.12` and `SettleSwipeProfile` constants already declared on `Navigation` in `Navigation.swift`. `AccessibilityPolicy` is for trait-semantic rules ("which traits are transient"), not for pacing.

## Methodology

`Grep -n '[0-9]+\.?[0-9]*'` over the file, then triage each hit:

1. Cite file:line.
2. Identify the enclosing function and what the value drives.
3. Decide: name / leave / delete.
4. If naming, propose a name and a home.

Strings and identifiers that contain digits (`2015` in the `AXRuntime attribute 2015` docstring, `0.2.25` in a version reference, the array-builder digit on line 263 for `0..<50`) are noted where relevant but the docstring digits are not counted.

## Per-literal catalog

### Frame yields after scroll

| Line | Site | Call | Means | Frequency | Action |
|---|---|---|---|---|---|
| 69 | `scrollOnePageAndSettle` (non-animated UIScrollView path) | `tripwire.yieldFrames(3)` | "Three layout frames after a non-animated `setContentOffset` so new elements appear before refresh" | 3× in this file (69, 495, 510), plus matching uses in `TheBrains+Actions` / dossier docs | **Name.** `Navigation.postScrollLayoutFrames: Int = 3` |
| 495 | `ensureOnScreen` (post `scrollToMakeVisible`) | `tripwire.yieldFrames(3)` | Same: settle one short layout window before re-reading geometry | same family | **Name.** Same constant. |
| 510 | `ensureFirstResponderOnScreen` (post `scrollToMakeVisible`) | `tripwire.yieldFrames(3)` | Same | same family | **Name.** Same constant. |
| 121 | `settleSwipeMotion` inner loop | `tripwire.yieldFrames(1)` | "One frame between settle-state evaluations" | 1×, but the value pairs with `SettleSwipeProfile.minFrames`/`maxFrames` | **Leave inline.** Single call site, value is intrinsic to the loop body (yield one frame, step, repeat). Naming it adds noise without changing meaning. |
| 69 | (animated branch — `animateScrollFingerprint` instead, no literal) | — | — | — | — |

`yieldFrames(3)` is the canonical "post-scroll, pre-refresh layout window." Three sites use it with the same value. That's the textbook case for a named constant — and the value is opaque without context (why 3, not 2 or 5?).

### Heavier frame yields after recorded-position jumps

| Line | Site | Call | Means | Frequency | Action |
|---|---|---|---|---|---|
| 313 | `executeScrollToVisible` (after `jumpToRecordedPosition`) | `tripwire.yieldRealFrames(20)` | "Twenty real (CADisplayLink-paced) frames so the SPI's animated scroll has time to land" | 5× in this file (313, 317, 352, 359, 399) | **Name.** `Navigation.postJumpRealFrames: Int = 20` |
| 317 | `executeScrollToVisible` (after `ensureOnScreenSync` follow-up) | `tripwire.yieldRealFrames(20)` | Same | same family | **Name.** Same constant. |
| 352 | `executeElementSearch` (after recorded-position jump) | `tripwire.yieldRealFrames(20)` | Same | same family | **Name.** Same constant. |
| 359 | `executeElementSearch` (after `restoreScrollPosition` fallback) | `tripwire.yieldRealFrames(20)` | Same | same family | **Name.** Same constant. |
| 399 | `searchFineTuneAndResolve` (after `ensureOnScreenSync`) | `tripwire.yieldRealFrames(20)` | Same | same family | **Name.** Same constant. |

Five sites, same value, same purpose. This is the most-repeated literal in the file and the one most likely to drift if a future change tunes only one site. `yieldRealFrames` (Task.sleep at 16ms intervals) is distinct from `yieldFrames` (Task.yield), so the constant must be named with `Real` in the identifier to keep them distinguishable — these are two different budgets, not one. Per the TheTripwire dossier the heavier variant exists specifically for animated SPI scrolls; `20` is the empirical budget for that animation to land.

### Page-walk caps

| Line | Site | Call | Means | Frequency | Action |
|---|---|---|---|---|---|
| 263 | `executeScrollToEdge` swipeable path | `for _ in 0..<50` | "Walk at most 50 pages before declaring the edge unreachable" | 1× | **Name.** `Navigation.scrollToEdgeMaxPages: Int = 50`. Cap is opaque inline; a name documents the semantic ("50 pages is our budget, anything more probably loops"). Single-use, but the value is a policy decision, not a loop bound that's intrinsic to the algorithm. |
| 366 | `executeElementSearch` page-by-page loop | `let maxScrolls = 200` | "Iterative search walks at most 200 pages" | 1× | **Leave inline.** Already locally named via `let maxScrolls = 200`; the binding sits two lines from the loop and is self-documenting. Promoting to a type-level constant is gold-plating; it neither dedupes nor improves discoverability for the only call site. |

The asymmetry is worth noting in passing — `scroll_to_edge` budgets 50 pages and `element_search` budgets 200 — but they're different operations and different budgets are defensible. The audit recommends **not** consolidating them; just name the one that's currently inline.

### Settle timeout

| Line | Site | Call | Means | Frequency | Action |
|---|---|---|---|---|---|
| 484 | `ensureOnScreen` (after `jumpToRecordedPosition`) | `tripwire.waitForAllClear(timeout: 1.0)` | "Wait up to 1s for layout to quiesce after an SPI jump before reading geometry" | 1× in this file, but the same `1.0` appears as a default elsewhere in TheTripwire | **Name.** `Navigation.postJumpSettleTimeout: TimeInterval = 1.0` |

The literal `1.0` for a `TimeInterval` is a bit-rot magnet — readers can't tell whether the value is "one second" by intent or by typo for `10` or `0.1`. A named constant on `Navigation` makes the unit and the intent explicit at the call site. This is a single-call-site value but the cost of naming is one line and the readability win is large.

### Comfort-zone fractions (already named — confirming)

| Line | Site | Value | Status |
|---|---|---|---|
| 471 | `Navigation.comfortMarginFraction` | `1.0 / 6.0` | **Already named** as a `private static let CGFloat`. Used at 476, 477, 493, 508, 521 and consumed by `TheSafecracker` tests (`TheSafecrackerScrollTests.swift` lines 186/202/221/243). |
| 476 | `interactionComfortZone` width inset | `bounds.width * comfortMarginFraction` | Already symbolic. **Leave.** |
| 477 | `interactionComfortZone` height inset | `bounds.height * comfortMarginFraction` | Already symbolic. **Leave.** |

The repeated `1.0 / 6.0` in `TheSafecrackerScrollTests` is a separate concern (test/prod duplication of the fraction). That's a test-hygiene fix, not in scope for this audit. Flagging only.

### Structural / arithmetic literals (leave inline)

| Line | Site | Literal | Why leave |
|---|---|---|---|
| 195 | `currentSwipeSafeBounds` | `?? 0` | Default for a missing `directionalLayoutMargins.leading`. Idiomatic optional default; naming hurts. |
| 198 | `currentSwipeSafeBounds` | `screen.height - insets.bottom` | Pure arithmetic, no magic. |
| 201 | `currentSwipeSafeBounds` | `screen.minX + horizontalInset` | Arithmetic. |
| 203 | `currentSwipeSafeBounds` | `max(0, screen.width - horizontalInset * 2)` | `0` is "clamp to non-negative width." The `* 2` is structurally "inset both sides." Both are read clearly inline; naming either would obscure the geometry. |
| 204 | `currentSwipeSafeBounds` | `max(0, bottom - top)` | Same — clamp to non-negative height. |
| 345 | `executeElementSearch` | `scrollCount: 0` | "Zero scrolls performed" — argument label fully documents it. |
| 355 | `executeElementSearch` | `scrollCount: 1` | "One scroll performed (the recorded-position jump)." Argument label documents it. |
| 365 | `executeElementSearch` | `var scrollCount = 0` | Standard counter init. |
| 378 | `executeElementSearch` | `scrollCount += 1` | Standard counter increment. |

### Docstring digits (not literals — context only)

- Line 165: `AXRuntime attribute 2015` — SPI attribute ID. The number is the SPI identifier; it's the name. Already in a comment, no action.
- Line 532: `Post-0.2.25` — release version reference in a docstring. Not a literal in code.

## Grouped findings

### Group A: Frame-yield budgets (3 named constants)

Two `yieldFrames` budgets and one `yieldRealFrames` budget appear with the same value across multiple call sites. These are the textbook drift-risk cases.

```swift
extension Navigation {
    /// Layout frames to yield after a non-animated UIScrollView scroll
    /// or `scrollToMakeVisible` before re-reading the accessibility tree.
    /// Empirical: 3 frames covers a CATransaction flush plus a UIKit
    /// layout pass without waiting for animations.
    static let postScrollLayoutFrames: Int = 3

    /// Real (CADisplayLink-paced) frames to yield after an accessibility-SPI
    /// scroll jump (`jumpToRecordedPosition`, `restoreScrollPosition`,
    /// `scrollToMakeVisible`-animated). The SPI queues an animated scroll;
    /// `Task.yield` alone won't advance it, so this uses `yieldRealFrames`
    /// (Task.sleep at 16ms intervals).
    static let postJumpRealFrames: Int = 20
}
```

- `postScrollLayoutFrames`: replaces `yieldFrames(3)` at lines 69, 495, 510.
- `postJumpRealFrames`: replaces `yieldRealFrames(20)` at lines 313, 317, 352, 359, 399.

### Group B: Page-walk cap (1 named constant)

```swift
extension Navigation {
    /// Maximum pages `scroll_to_edge` will walk before declaring the edge
    /// unreachable. Paired with `element_search`'s 200-page cap declared
    /// locally; the asymmetry is intentional (search is broader than edge-seek).
    static let scrollToEdgeMaxPages: Int = 50
}
```

- Replaces the inline `0..<50` at line 263.
- The `element_search` cap at line 366 stays as a local `let maxScrolls = 200` — one call site, already named.

### Group C: Settle timeout (1 named constant)

```swift
extension Navigation {
    /// Settle window after `jumpToRecordedPosition` before reading geometry
    /// for the comfort-zone check. Paired with `postJumpRealFrames` — the
    /// SPI jump animates, this is the upper bound on waiting for it to land.
    static let postJumpSettleTimeout: TimeInterval = 1.0
}
```

- Replaces `waitForAllClear(timeout: 1.0)` at line 484.

### Group D: Already named — no action

- `Navigation.swipeGestureDuration: TimeInterval = 0.12` (`Navigation.swift:49`).
- `Navigation.SettleSwipeProfile.directionChange` / `.sameDirection` carrying `minFrames`/`maxFrames`/`requiredIdleFrames`/`requiredStableViewportFrames` (`Navigation.swift:64-71`). All five of those literals (6, 24, 2, 3, 1, 3, 1, 1) are already inside named struct fields with docstrings.
- `Navigation.comfortMarginFraction: CGFloat = 1.0 / 6.0` (`Navigation+Scroll.swift:471`).

These are the precedent for where the proposed Group A/B/C constants belong: peer `static let` declarations on `Navigation` itself, not a new namespace.

## Why `Navigation`, not a new `ScrollTiming` namespace

The four proposed constants are all consumed by methods on `Navigation` (and tests of `Navigation`). They aren't policy in the `AccessibilityPolicy` sense — they don't describe rules-of-the-world about how UIKit traits map to wire types; they're pacing parameters tuned against TheTripwire's frame model and the iOS scroll-animation duration. Making a new `ScrollTiming` enum to hold four constants would add a layer and a file for no callable surface. The existing pattern (peer `static let` next to `swipeGestureDuration` and `SettleSwipeProfile`) is the right shape.

If a future change pulls scroll orchestration out of `Navigation` into a `Spelunker`/`TheCartographer` type (as `resolution-layer-shape.md` proposes), these constants move with it. They don't have an independent reason to exist.

## What this audit does not propose

- **No new file.** Four `static let`s are not a module.
- **No consolidation of `maxScrolls=200` with `scrollToEdgeMaxPages=50`.** They're different budgets for different operations; consolidating would force a wrong call.
- **No promotion of `yieldFrames(1)` on line 121.** It's a one-call-site loop-body cadence, not a policy.
- **No touching of `comfortMarginFraction`.** Already named; the test-side duplication of `1.0 / 6.0` in `TheSafecrackerScrollTests` is a separate hygiene item.
- **No source changes.** This is the audit; implementation is a follow-up PR.

## Implementation sketch (for a follow-up PR)

A follow-up PR would:

1. Add the four `static let` declarations to `Navigation` (in `Navigation.swift`, next to `swipeGestureDuration`).
2. Replace eight call sites in `Navigation+Scroll.swift` (lines 69, 263, 313, 317, 352, 359, 399, 484, 495, 510 — eight if you count Group A/B/C as eight literal occurrences across the five families).
3. No test changes — the values don't change, only the names.
4. Update `docs/dossiers/14a-SCROLLING.md` if it cites specific numeric values (e.g. "waits for settle via `yieldFrames(3)`" would become "via `postScrollLayoutFrames`").

Total proposed source diff: ~12 lines added, ~10 lines changed. No behavior change.
