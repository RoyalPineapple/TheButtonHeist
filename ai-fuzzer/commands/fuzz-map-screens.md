---
description: Build a navigation graph of all reachable screens in the app
---

# /fuzz-map-screens — Screen Graph Builder

You are tasked with systematically mapping every reachable screen in the connected iOS app and building a navigation graph showing how screens connect.

## CRITICAL
- ALWAYS fingerprint screens by their element set, not by visual appearance or a single identifier
- ALWAYS record transitions even to already-known screens — they are new edges in the graph
- DO NOT re-explore screens that are already fully mapped — check your session notes first
- DO NOT spend more than 200 total actions — report a partial map if the limit is reached

## Step 0: Verify Connection + Check for Existing Session

1. **Ensure CLI is on PATH**: Build the CLI and add to PATH if `buttonheist` is not already available:
   ```bash
   cd ButtonHeistCLI && swift build -c release && cd ..
   export PATH="$PWD/ButtonHeistCLI/.build/release:$PATH"
   ```
2. Run `buttonheist list --format json` (via Bash) — confirm at least one device is connected
3. If no devices found: stop and tell the user to launch the app and try again
4. Print the connected device name and app name for confirmation
5. **Set up fast connections**: If `BUTTONHEIST_HOST` is not already set, export env vars for direct connection (skips ~2s Bonjour discovery per command):
   ```bash
   export BUTTONHEIST_HOST=127.0.0.1
   export BUTTONHEIST_PORT=1455
   ```
6. **Check for existing session**: List `.fuzzer-data/sessions/fuzzsession-*.md` files. If the most recent one has `Status: in_progress`, read it to pick up partial screen maps. Skip screens already fully mapped. If starting fresh, create a new notes file: `.fuzzer-data/sessions/fuzzsession-YYYY-MM-DD-HHMM-map-screens.md`
5. **Load navigation knowledge**: Read `references/nav-graph.md` if it exists. Pre-populate known screens and transitions — skip mapping what's already known.
6. **Load session notes format**: Read `references/session-notes-format.md` for notes file format, naming, and update protocol.
7. **Load navigation planning**: Read `references/navigation-planning.md` for route planning algorithm and navigation stack protocol.

During mapping, update your session notes file continuously:
- After each new screen: add to `## Screens Discovered`
- After each transition: add to `## Transitions`
- Every 5 actions: update `## Progress` and `## Next Actions`

## Step 1: Start Screen

1. Run `buttonheist screenshot --output /tmp/bh-screen.png` then Read it, and run `buttonheist watch --once --format json --quiet`
2. Fingerprint the current screen:
   - Extract all element identifiers (excluding nil)
   - Extract all element labels
   - Give the screen a human-readable name based on prominent elements (e.g., "Main Menu", "Settings", "Login Form")
3. Initialize the graph:
   - `screens`: dict mapping fingerprint → {name, element_count, elements_summary}
   - `transitions`: list of {from, action, to}
   - `exploration_stack`: stack of (screen_fingerprint, untried_elements)

Push the current screen onto the exploration stack.

## Step 2: Exploration Loop

While the exploration stack is not empty:

### 2a. Pick Next Element

**Consult your session notes** — read `## Screens Discovered` and `## Transitions` to know which screens and edges are already mapped. Skip navigation you've already recorded.

Pop the top of the stack. If all navigation-like elements have been tried on this screen, pop again.

Navigation-like elements (in priority order):
1. Elements in tab bars (container type `tabBar`)
2. Elements in lists (container type `list`) — likely table/collection view cells
3. Buttons with labels suggesting navigation ("Settings", "Profile", "More", "Details", ">" etc.)
4. Any other tappable elements not yet tried

### 2b. Try Navigation

1. Record the current screen fingerprint
2. Run `buttonheist action --identifier ID --format json` for the selected element (preferred — uses accessibility API). Fall back to `buttonheist touch tap` if the element has no actions.
3. Read the delta from the response:
   - **`noChange` or `valuesChanged`**: No navigation. Mark element as "stays on screen". Continue to next element.
   - **`screenChanged`**: The delta includes the full `newInterface` — use it to fingerprint the new screen (no separate `get_interface` needed).
     - **New screen (not in `screens` dict)**:
       - Name it based on prominent elements
       - Add to `screens` dict
       - Record transition: `{from: current_screen, action: "activate [element]", to: new_screen}`
       - Push new screen onto exploration stack
       - **Explore it** (push current screen's remaining elements back on stack first)
     - **Known screen (already in `screens` dict)**:
       - Record transition (it's a new edge in the graph, even if the screen is known)
       - Navigate back — don't re-explore
   - **`elementsChanged`**: Some elements appeared/disappeared but same screen. Mark as structural change, continue.

### 2c. Navigate Back

After recording a transition to a known screen, navigate back:
1. Look for back/close/cancel/done elements
2. Try swipe-right from left edge
3. If back navigation works, verify you returned to the expected screen (fingerprint check)
4. If back navigation fails, record as INFO finding and continue from wherever you are

## Step 3: Build the Graph

After exploration completes, generate the screen map:

```
## Screen Map

### Screens Discovered: [count]

| # | Screen Name | Elements | Fingerprint (abbreviated) |
|---|-------------|----------|--------------------------|
| 1 | Main Menu   | 8        | {home, settings, ...}    |
| 2 | Settings    | 12       | {back, theme, ...}       |
| ...

### Navigation Graph

Main Menu
  ├── [tap "Settings"] → Settings
  │   ├── [tap "Theme"] → Theme Picker
  │   │   └── [tap "Back"] → Settings
  │   └── [tap "Back"] → Main Menu
  ├── [tap "Profile"] → Profile
  │   └── [tap "Back"] → Main Menu
  └── [tab "Search"] → Search
      └── [tab "Home"] → Main Menu

### Transitions: [count]

| From | Action | To |
|------|--------|----|
| Main Menu | tap "Settings" | Settings |
| Settings | tap "Back" | Main Menu |
| ...

### Findings

#### Dead Ends (no back navigation)
- [screen name] — reached via [path], no way back

#### Orphan Screens (single entry point)
- [screen name] — only reachable from [screen] via [element]

#### Deep Paths
- [path description] — [depth] levels deep
```

## Step 4: Save Report

1. Write the full screen map to `.fuzzer-data/reports/YYYY-MM-DD-HHMM-screen-map.md`.
2. **Update persistent nav graph**: Write all discovered screens, transitions (with reverse actions), and back-routes to `references/nav-graph.md`. This is the primary output — future sessions will use it for navigation planning.

## Limits

- **Max screens**: 50. If more exist, report how many were found and stop.
- **Max depth**: 15 levels of navigation.
- **Max total actions**: 200. Report partial map if limit reached.

## Crash Handling

If the app crashes during mapping, record the CRASH with the action that caused it, save the partial map, and stop.
