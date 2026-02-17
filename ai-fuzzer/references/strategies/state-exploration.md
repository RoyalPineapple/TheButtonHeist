# Strategy: State Exploration

Focuses on navigation depth, screen reachability, and state machine coverage. Maps the app as a directed graph and finds navigation dead ends, unreachable states, and inconsistent transitions.

## Goal

Build a complete map of the app's screen states and transitions. Find screens that can't be reached, screens you can't leave, and transitions that behave differently depending on how you arrived.

## Element Selection

Prioritize **navigation elements** — things that change the screen:

1. Elements that look like navigation: labels containing "back", "next", "done", "cancel", "close", "menu", "settings", "more"
2. Elements in tab bars (container type `tabBar` in the tree)
3. Elements in navigation bars (typically at top of screen, y < 100)
4. List/table cells (often navigate to detail screens)
5. Buttons with arrow-like labels or ">" indicators

## Screen Fingerprinting

To identify unique screens, compute a fingerprint from:
1. The set of element identifiers (excluding nil)
2. The set of element labels
3. The container structure from the tree (group types and nesting)

Two interface results represent the same screen if their fingerprints match, even if values or positions differ slightly.

## Exploration Algorithm

Use **depth-first** exploration with backtracking:

```
1. Fingerprint the current screen → call it S0
2. Record S0 in visited set
3. For each navigation-like element on S0:
   a. Activate the element (use `activate` for elements with actions, `tap` as fallback)
   b. Get new interface, fingerprint it → Snew
   c. If Snew == S0: no transition, try next element
   d. If Snew is new (not in visited):
      - Record transition: S0 --[element]--> Snew
      - Recursively explore Snew (go to step 3 with Snew)
      - Navigate back to S0
   e. If Snew is already visited:
      - Record transition: S0 --[element]--> Snew (but don't re-explore)
      - Navigate back to S0
4. When all elements on S0 explored, return (backtrack)
```

## Back Navigation

Critical for this strategy. Try these in order:
1. Look for an element with identifier or label containing "back", "Back", "close", "Close", "cancel", "Cancel", "dismiss"
2. Look for an element in the top-left area (x < 100, y < 100) — typical back button position
3. Swipe right from left edge: `swipe(startX: 0, startY: 400, direction: "right", distance: 200)`
4. If none work, record a finding: "Cannot navigate back from screen [fingerprint]"

## State Consistency Checks

After navigating A → B → back to A:
1. Get interface of A again
2. Compare with the original interface of A
3. If elements differ (beyond expected value changes like timestamps): ANOMALY — state leaked

After navigating A → B → C → back → back to A:
1. Verify we actually returned to A (fingerprint match)
2. If we ended up somewhere else: ANOMALY — back navigation is inconsistent

## Termination

- **Depth limit**: 15 levels of navigation. Report deeper paths as INFO.
- **Screen limit**: 50 unique screens. Report that more exist as INFO.
- **Stuck detection**: If you've been on the same screen for 10 actions without finding a new transition, move on.

## What to Look For

- **Navigation dead ends**: Screens with no back navigation (you can get in but not out)
- **Orphan screens**: Screens that are only reachable via one specific path (single point of failure)
- **Asymmetric transitions**: A → B exists but B → A doesn't (and there's no alternative back path)
- **State leaks**: Navigating away and back changes the original screen's state
- **Inconsistent paths**: Reaching the same screen via different paths produces different element states
- **Deep nesting**: Screens that are 10+ levels deep — potential for stack overflow or memory issues
- **Tab bar state**: Switching tabs and switching back should preserve the state of each tab
- **Modal conflicts**: Opening multiple modals or action sheets simultaneously
