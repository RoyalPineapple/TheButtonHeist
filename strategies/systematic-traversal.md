# Strategy: Systematic Traversal

The default fuzzing strategy. Methodically visits every element on every reachable screen.

## Goal

Achieve complete coverage — every interactive element on every screen gets exercised at least once. Finds bugs that occur during normal usage paths.

## Element Selection

Process elements **in order** (by `order` field from snapshot), top to bottom:

1. Start with elements that have actions (activate, increment, decrement, custom)
2. Then elements without explicit actions (try tapping them — they may be buttons without accessibility actions)
3. Skip static labels and decorative elements (no identifier, no actions, no tap response)

## Action Selection

For each element, try actions in this order:

1. **`tap`** — The universal interaction. Try it on everything.
2. **`activate`** — If the element has actions, activate it via accessibility API.
3. **`long_press`** — Might reveal context menus or alternate behaviors.
4. **`swipe` (all 4 directions)** — Might scroll, dismiss, or reveal hidden content.
5. **`increment` / `decrement`** — Only if the element has these in its actions array.
6. **`perform_custom_action`** — Try each action in the element's actions list.

After each action:
- Get a new interface snapshot
- If the screen changed (new elements appeared), you've found a transition
- Record the transition and decide: explore the new screen, or go back and continue?

## Screen Traversal

Use **breadth-first** exploration:

1. Fully explore the starting screen (try every element)
2. Collect all screen transitions discovered
3. Visit each new screen in the order discovered
4. Fully explore each new screen
5. Continue until no new screens are found or depth limit reached

Depth limit: 10 levels of navigation. Beyond that, report as INFO that deeper paths exist.

## Termination

Stop exploring a screen when:
- Every element with actions has been tried
- Every tappable element has been tapped
- You've been on this screen for more than 30 actions without finding anything new

Stop the overall fuzz when:
- All reachable screens have been fully explored
- The user-specified iteration limit is reached
- A CRASH is detected (report it and stop — the connection is dead)

## What to Look For

- **Missing back navigation**: You navigated to a screen but can't get back
- **Broken transitions**: Tapping an element navigates somewhere unexpected
- **Disappearing elements**: An element was in the snapshot but gone after an unrelated action
- **Value inconsistencies**: A slider's value doesn't change after increment/decrement
- **Duplicate screens**: The same screen is reachable via multiple paths (INFO, not a bug)
- **Unresponsive elements**: Elements with actions that always return `elementNotFound`
- **Crashes**: Any action that kills the app
