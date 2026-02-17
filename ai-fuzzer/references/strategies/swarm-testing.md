# Strategy: Swarm Testing

Randomly restricts the set of available action types for this session. By omitting some actions, the fuzzer is forced into unusual interaction patterns that wouldn't occur with the full action palette.

Research shows swarm testing finds 42% more distinct crashes than always using every action type.

## Goal

Discover bugs that only surface under unusual interaction constraints. When the fuzzer can't use its "easy" default actions, it exercises code paths that are rarely tested.

## Swarm Configuration

At the start of the session, randomly select a **subset** of action types from the full palette:

### Full Action Palette (8 types)
1. `activate` / `tap` (always counted together — basic element interaction)
2. `long_press`
3. `swipe`
4. `pinch`
5. `rotate`
6. `two_finger_tap`
7. `drag` / `draw_path`
8. `increment` / `decrement` (always counted together — adjustable elements)

### Selection Rules

1. Pick a random number between 3 and 5 — this is how many action types to include
2. **Always include** `activate`/`tap` — you can't navigate without basic interaction
3. **Always include** `increment`/`decrement` if the screen has adjustable elements — they're the only way to test value boundaries
4. Fill the remaining slots randomly from the other types
5. The excluded types are **off-limits** for this session (with exceptions below)

### Exceptions (always allowed regardless of swarm)

- `activate` on navigation elements — you need this to explore the app
- `swipe(direction: "right")` from left edge — iOS back gesture for navigation
- `type_text` — text input is a separate category, not a gesture

### Log the Swarm

Record the swarm configuration in session notes under `## Config`:

```
- **Swarm actions (included)**: activate/tap, long_press, pinch
- **Swarm actions (excluded)**: swipe, rotate, two_finger_tap, drag
```

## Element Selection

Same as `systematic-traversal` — process elements in order, top to bottom:

1. Elements with actions first
2. Elements without explicit actions (try tapping)
3. Skip static/decorative elements

## Action Selection

For each element, try only the **included** action types, in this order:

1. `activate` — always first (if element has actions)
2. `tap` — fallback for elements without actions
3. Remaining included types in any order

If an element would normally be tested with an excluded action type, skip that action. Record in Coverage that the action was "excluded by swarm" (not "untried").

## Screen Traversal

Same as `systematic-traversal` — breadth-first exploration across screens.

## Termination

Stop exploring a screen when:
- Every element has been tried with all **included** action types
- You've been on this screen for 30 actions without finding anything new

Stop overall when:
- All reachable screens fully explored (with included actions)
- Iteration limit reached
- CRASH detected

## What to Look For

Everything from `systematic-traversal`, plus:
- **Gesture-dependent behavior**: An element works with `tap` but crashes with `long_press` — the omitted gestures in one session become the focus of the next
- **Action ordering bugs**: With a restricted palette, you interact with elements in a different order than usual, potentially triggering sequence-dependent bugs
- **Under-tested code paths**: When the fuzzer can't swipe, it's forced to find alternative navigation, exercising less-traveled UI paths

## Session Diversity

Run multiple swarm sessions on the same app. Each session's random subset covers different ground. After 3+ sessions, the combined coverage exceeds what any single full-palette session would achieve.

Check prior `session/fuzzsession-*-swarm-testing*.md` files to see which action subsets were used before. Ideally, each session uses a different subset.
