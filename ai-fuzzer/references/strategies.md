# Fuzzing Strategies

Strategies define how the fuzzer selects elements and actions. Each strategy focuses on a different dimension of testing. When specified via `/fuzz`, the fuzzer reads this file and follows the matching strategy's rules.

## Shared Rules

**Screen intent first**: Before element-by-element testing on any strategy, identify the screen's intent using `references/screen-intent.md`. Run workflow tests for the recognized intent, then proceed to strategy-specific element selection.

**Model before testing**: After identifying intent, build a behavioral model (see `## Behavioral Modeling` in SKILL.md). The model generates predictions that make testing targeted instead of random.

**Per-screen termination**: Stop exploring a screen when every relevant element has been tested for the strategy's goals, OR after 30 actions without new findings.

**Overall termination**: Stop when all reachable screens are explored, the iteration limit is reached, or a CRASH is detected.

---

## Systematic Traversal (default)

**Goal**: Complete coverage — every interactive element on every screen gets exercised at least once.

**Element selection** (randomized within tiers):
1. Elements with actions (activate, increment, decrement, custom)
2. Elements without explicit actions (try tapping — may be unlabeled buttons)
3. Skip static labels and decorative elements

**Action order per element**: activate → tap → long_press → swipe (all 4 directions) → increment/decrement (if adjustable) → custom actions.

**Screen traversal**: Breadth-first. Fully explore the starting screen, collect transitions, visit each new screen in discovery order. Depth limit: 10 levels.

**What to look for**: Missing back navigation, broken transitions, disappearing elements, value inconsistencies after increment/decrement, unresponsive elements with actions, crashes.

---

## Boundary Testing

**Goal**: Test edges and extremes — element frames, screen borders, value limits, gesture parameters.

**Element selection**: Prioritize elements with large frames (more boundary surface), elements near screen edges, adjustable elements (value boundaries), and overlapping elements.

**Action selection**:

*Coordinate boundary taps* — For each element, extract its frame and tap at all 4 corners plus 1pt outside each edge (8 taps total). Detects hit-testing failures and ghost taps.

*Screen edge interactions* — Tap all 4 screen corners. Swipe from all 4 edges. Tests system gesture conflicts.

*Value boundaries* — For adjustable elements: increment 20x (track progression, check for wrapping), decrement 20x, then rapid alternation (10 cycles).

*Extreme gesture parameters* — `pinch(scale: 0.01)`, `pinch(scale: 100.0)`, `rotate(angle: 628.0)` (100 rotations), `swipe(distance: 2000)`, `long_press(duration: 10.0)`, full-diagonal drag.

**What to look for**: Hit-testing failures (tap inside frame doesn't register), ghost taps (tap outside triggers element), value overflow/wrapping, layout breakage after extreme gestures, crashes from extreme numeric values.

---

## Gesture Fuzzing

**Goal**: Apply unexpected gestures to elements that weren't designed for them. Finds crash bugs, gesture recognizer conflicts, and state corruption.

**Element selection**: Target elements least likely to expect complex gestures — buttons, labels, toggles, navigation elements, table cells.

**Action selection** (randomized order per element):

*Single-finger*: tap, long_press(0.5s), long_press(3.0s), swipe (all 4 directions), drag (200pt each direction).

*Multi-touch*: two_finger_tap, pinch(2.0), pinch(0.5), rotate(1.57), rotate(-1.57).

*Rapid sequences* (same element): 5x rapid tap, swipe up then immediately down, pinch in then out, tap then immediately long_press.

*Random coordinates*: 5-10 random screen positions with random gestures.

**What to look for**: Crashes from unexpected gestures (especially multi-touch on simple elements), gesture recognizer conflicts, unintended action triggers, state corruption, UI freezes.

---

## State Exploration

**Goal**: Map the app as a directed graph. Find navigation dead ends, unreachable states, and inconsistent transitions.

**Element selection**: Prioritize navigation elements — labels containing "back"/"next"/"done"/"menu"/"settings", tab bar elements, nav bar elements (y < 100), list cells, buttons with arrows.

**Exploration algorithm**: Depth-first with backtracking:
1. Fingerprint current screen → S0
2. For each navigation-like element on S0: activate → if screenChanged to new Snew, push nav stack, recursively explore, then navigate back
3. If screen already visited, record the edge and navigate back
4. When all elements explored, backtrack

**State consistency checks**: After A → B → back-to-A, compare interface with original. Use behavioral model for specific predictions (not just generic diff). Detect state leaks and inconsistent back-navigation.

**Termination overrides**: Depth limit 15. Screen limit 50. Stuck detection: 10 actions without new transition → move on.

**What to look for**: Navigation dead ends (can get in but not out), orphan screens (single entry point), asymmetric transitions, state leaks across navigation, path-dependent screen state, tab bar state preservation, modal conflicts.

---

## Swarm Testing

**Goal**: Randomly restrict available action types to force unusual interaction patterns. Research shows swarm testing finds 42% more distinct crashes than full-palette testing.

**Swarm configuration** (session start):
1. Pick random 3-5 action types from: activate/tap, long_press, swipe, pinch, rotate, two_finger_tap, drag/draw_path, increment/decrement
2. Always include activate/tap (needed for navigation)
3. Always include increment/decrement if screen has adjustable elements
4. Fill remaining slots randomly. Excluded types are off-limits for this session.
5. Exceptions (always allowed): activate on nav elements, swipe-right from left edge (iOS back), type_text

**Element selection**: Same as systematic-traversal but randomized within tiers.

**Action selection**: Only included types, in order: activate → tap → remaining included types.

**Session diversity**: Check prior swarm session files to avoid repeating the same subset. Log included/excluded actions in `## Config`.

**What to look for**: Everything from systematic-traversal, plus gesture-dependent behavior (works with tap but crashes with long_press), action ordering bugs, under-tested code paths forced by restricted palette.

---

## Invariant Testing

Systematically verifies the 6 observable invariants from SKILL.md. Works best after prior exploration (needs known screens and transitions).

**Prerequisites**: At least one prior session with screen catalog and transitions. If none exists, do a quick initial exploration first.

### Pass 1: Stability
For each known screen: get_interface twice with no actions between. Element sets should be identical (excluding dynamic content like timestamps). Run first — establishes whether screens are stable enough for other passes.

### Pass 2: Idempotency
For each non-toggle, non-counter, non-navigation element with actions: activate twice consecutively. State after first activation should equal state after second.

### Pass 3: Reversibility
*Navigation*: For each known A → B transition, navigate forward and back. Original A state should be restored.
*Values*: For adjustable elements, increment 5x then decrement 5x. Final value should equal original.
*Gestures*: pinch(2.0) then pinch(0.5). State should restore.

### Pass 4: Persistence
For each screen with stateful elements: change values (toggle, increment 3x, type "PERSIST_TEST"), navigate away, navigate back. Changed values should persist.

### Pass 5: Completeness
For each element with accessibility actions: activate and check for any observable effect (value change, screen transition, element appearance change). INFO if no effect — may indicate broken element.

### Pass 6: Consistency
For screens reachable via 2+ paths: navigate via path A, record state. Navigate via path B, record state. Element sets should match (values may differ if path-dependent).

**Termination**: Complete all 6 passes. If iteration limit hit mid-pass, finish current pass and report partial results.

**What to look for**: State leaks (persistence/reversibility), ghost state (consistency), spontaneous changes (stability), dead elements (completeness), cumulative drift (reversibility), double-activation bugs (idempotency).
