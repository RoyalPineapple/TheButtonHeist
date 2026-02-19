# Strategy: Invariant Testing

## Contents
- [Goal](#goal) — self-consistency verification
- [Prerequisites](#prerequisites) — needs prior exploration data
- [Passes](#passes) — stability, idempotency, reversibility, persistence, completeness, consistency
- [Element Selection](#element-selection) — per-invariant element targeting
- [Termination](#termination) — completion and partial results
- [What to Look For](#what-to-look-for) — state leaks, ghost state, dead elements

---

Systematically verifies the 6 observable invariants defined in SKILL.md. Instead of testing invariants opportunistically during exploration, this strategy makes invariant verification the primary goal.

## Goal

Verify that the app's behavior is **self-consistent**. You don't need to know what the "correct" behavior is — you only need to verify that the app doesn't contradict itself.

## Prerequisites

This strategy works best **after** the app has been explored at least once (via `systematic-traversal` or `map-screens`). It needs a known set of screens and transitions to test against. If no prior session exists, do a quick initial exploration first: visit each reachable screen, catalog elements, and record transitions. Then begin invariant testing.

## Passes

Run these passes in order. Each pass tests one invariant across all known screens and elements.

### Pass 1: Stability

**Invariant**: The element set on a screen should not change between observations when no action is taken.

For each known screen:
1. Navigate to the screen
2. Call `get_interface` — record the element set (identifiers, labels, values)
3. Wait (do nothing)
4. Call `get_interface` again — record the element set
5. Compare the two snapshots

**Expected**: Identical element sets (excluding expected dynamic content like timestamps, clocks, or animation states).

**Finding if violated**: ANOMALY — "Screen [name] element set changed spontaneously between observations"

This pass runs first because it establishes whether the screen is stable enough to test other invariants on.

### Pass 2: Idempotency

**Invariant**: Activating a static element twice in a row should produce the same state both times.

For each screen, for each element that is NOT a toggle, counter, or navigation:
1. Record the current interface state
2. `activate` the element
3. Record the interface state → call this State A
4. `activate` the same element again
5. Record the interface state → call this State B
6. Compare State A and State B

**Expected**: State A equals State B.

**Finding if violated**: ANOMALY — "Element [id] produces different state on second activation"

Skip elements that are expected to change on each activation (toggles, counters, navigation buttons).

### Pass 3: Reversibility

**Invariant**: Actions that have an inverse should return to the original state when the inverse is applied.

#### Navigation reversibility
For each known transition (screen A → screen B):
1. Start on screen A, record the interface state → call this Original A
2. Navigate to screen B (via the known action)
3. Navigate back to screen A (via back button, swipe-back, or known reverse transition)
4. Record the interface state → call this Restored A
5. Compare Original A and Restored A

**Expected**: Original A and Restored A have the same element set and values.

#### Value reversibility
For each adjustable element (sliders, steppers):
1. Record the current value
2. `increment` 5 times, record the value after each
3. `decrement` 5 times, record the value after each
4. Compare final value with original

**Expected**: Final value equals original value.

#### Gesture reversibility
For elements on screens that support pinch/rotate:
1. Record the interface state
2. `pinch(scale: 2.0)` then `pinch(scale: 0.5)`
3. Record the interface state
4. Compare with original

**Expected**: State restored after inverse gesture.

**Finding if violated**: ANOMALY — "Reversibility broken: [forward action] then [reverse action] did not restore original state"

### Pass 4: Persistence

**Invariant**: Values you set should persist when you navigate away and come back.

For each screen with stateful elements (toggles, text fields, sliders):
1. Record the current values of all stateful elements
2. Change each value:
   - Toggle: `activate` to flip it
   - Slider/stepper: `increment` 3 times
   - Text field: `type_text` with a distinctive string like "PERSIST_TEST"
3. Record the new values
4. Navigate to a different screen
5. Navigate back to the original screen
6. Record the values again
7. Compare with the values from step 3

**Expected**: Values from step 6 match values from step 3.

**Finding if violated**: ANOMALY — "Persistence broken: [element] value changed from [expected] to [actual] after navigation roundtrip"

### Pass 5: Completeness

**Invariant**: Every element that advertises accessibility actions should produce an observable effect when activated.

For each screen, for each element with actions in its actions array:
1. Record the interface state
2. `activate` the element
3. Record the interface state
4. Compare: Did anything change? (value, element set, screen navigation)

**Expected**: At least one observable change (value update, screen transition, element appearance change).

**Finding if violated**: INFO — "Element [id] has actions [list] but activation produced no observable effect"

Note: This is INFO, not ANOMALY — some elements legitimately do nothing visible (e.g., analytics triggers, audio playback). But it's worth flagging because it may indicate a broken element.

### Pass 6: Consistency

**Invariant**: The same screen should present the same elements regardless of how you navigated there.

For each screen reachable via 2+ different navigation paths:
1. Navigate to the screen via path A, record the interface → State via A
2. Navigate back to a common ancestor
3. Navigate to the screen via path B, record the interface → State via B
4. Compare State via A and State via B

**Expected**: Same element set and same interactive element states (values of toggles, sliders, etc. may differ if they depend on prior actions, but the element structure should match).

**Finding if violated**: ANOMALY — "Screen [name] has different element sets depending on navigation path"

This pass requires 2+ known paths to the same screen. Check `## Transitions` in session notes. If a screen has only one known entry point, skip it for this pass and record as INFO — "Screen [name] has only one known entry point, consistency not testable."

## Element Selection

Unlike other strategies, element selection is driven by invariant requirements:
- **Stability**: All screens, no elements needed
- **Idempotency**: Non-toggle, non-counter, non-navigation elements with actions
- **Reversibility**: Navigation elements, adjustable elements, pinchable/rotatable areas
- **Persistence**: Toggles, text fields, sliders — anything with mutable state
- **Completeness**: All elements with actions
- **Consistency**: Only screens with 2+ navigation paths

## Termination

Complete all 6 passes, then stop. If iteration limit is reached mid-pass, complete the current pass and report partial results for remaining passes.

## What to Look For

- **State leaks**: Navigation away and back changes values (Persistence, Reversibility)
- **Ghost state**: Screen depends on navigation path (Consistency)
- **Spontaneous changes**: Elements change without interaction (Stability)
- **Dead elements**: Actions advertised but nothing happens (Completeness)
- **Cumulative drift**: Increment+decrement doesn't return to original (Reversibility)
- **Double-activation bugs**: Second activation produces different result (Idempotency)
