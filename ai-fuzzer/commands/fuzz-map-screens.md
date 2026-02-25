---
description: Build a navigation graph of all reachable screens in the app
---

# /fuzz-map-screens — Screen Graph Builder

You are tasked with systematically mapping every reachable screen in the connected iOS app and building a navigation graph showing how screens connect.

## CRITICAL
- ALWAYS fingerprint screens by their element set, not by visual appearance or a single identifier
- ALWAYS record transitions even to already-known screens — they are new edges in the graph
- ALWAYS reuse `BUTTONHEIST_TOKEN` after first auth approval — repeated auth prompts mean the token was not carried forward
- DO NOT re-explore screens that are already fully mapped — check your session notes first
- DO NOT spend more than 200 total actions — report a partial map if the limit is reached

## Step 0: Verify Connection + Check for Existing Session

1. **Ensure CLI is on PATH**: Build the CLI and add to PATH if `buttonheist` is not already available:
   ```bash
   cd ButtonHeistCLI && swift build -c release && cd ..
   export PATH="$PWD/ButtonHeistCLI/.build/release:$PATH"
   ```
2. Run `buttonheist list --format json` (via Bash) — confirm at least one device is connected
3. Bootstrap auth token once: run `buttonheist watch --once --format json --quiet`, capture `BUTTONHEIST_TOKEN=...` from output, and store as `AUTH_TOKEN` for the session
4. Reuse token on every later command: `buttonheist ... --token "$AUTH_TOKEN"` (or `BUTTONHEIST_TOKEN="$AUTH_TOKEN" buttonheist ...`)
5. If no devices found: stop and tell the user to launch the app and try again
6. Print the connected device name and app name for confirmation
7. **Check for existing session**: List `.fuzzer-data/sessions/fuzzsession-*.md` files. If the most recent one has `Status: in_progress`, read it to pick up partial screen maps. Skip screens already fully mapped. If starting fresh, create a new notes file: `.fuzzer-data/sessions/fuzzsession-YYYY-MM-DD-HHMM-map-screens.md`
8. **Load navigation knowledge**: Read `references/nav-graph.md` if it exists. Pre-populate known screens and transitions — skip mapping what's already known.
9. **Load session notes format**: Read `references/session-notes-format.md` for notes file format, naming, and update protocol.
10. **Load navigation planning**: Read `references/navigation-planning.md` for route planning algorithm and navigation stack protocol.

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

## Step 2: Exploration Loop (Delegated to Haiku)

Read `references/execution-protocol.md` for the full execution plan format, delta handling rules, and return protocol.

While the exploration stack is not empty:

### 2a. Opus Plans the Batch

**Consult your session notes** — read `## Screens Discovered` and `## Transitions` to know which screens and edges are already mapped. Skip navigation you've already recorded.

Pop the top of the stack. If all navigation-like elements have been tried on this screen, pop again.

Identify navigation-like elements on this screen (in priority order):
1. Elements in tab bars (container type `tabBar`)
2. Elements in lists (container type `list`) — likely table/collection view cells
3. Buttons with labels suggesting navigation ("Settings", "Profile", "More", "Details", ">" etc.)
4. Any other tappable elements not yet tried

For each navigation-like element, plan a try-and-return action pair:
- Action: `buttonheist action --identifier ID --format json` (or `touch tap` if no actions)
- Expected delta: `screenChanged` for likely navigation, `noChange` for uncertain
- If `screenChanged`: include a back-navigation action (use known back-route from nav-graph if available, otherwise instruct Haiku to look for Back/Cancel/Close/Done)

### 2b. Dispatch to Haiku

Build an execution plan containing all try-and-return pairs for this screen:

**Context block**: Include CLI path, auth token, session notes path, trace file path, next trace seq, next finding ID, current screen + fingerprint, nav stack.

**Action list**: For each navigation-like element:
1. Activate the element (expected: `screenChanged` or `noChange`)
2. If `screenChanged`: record the new screen fingerprint and transition, then navigate back
3. If `noChange`/`valuesChanged`: mark as "stays on screen", continue

**Additional instructions for Haiku**:
- On `screenChanged` to a **new** screen: Record the transition, take a screenshot, navigate back using back-route or heuristic (Back/Cancel/Close/Done)
- On `screenChanged` to a **known** screen: Record the transition edge, navigate back
- On `noChange`/`valuesChanged`: Mark element as non-navigational, continue
- Record all transitions in session notes `## Transitions`
- Record new screens in session notes `## Screens Discovered`

**Purpose**: `navigation`
**Stop conditions**: Max actions for this screen (~5-10 per screen, 2 actions per element). Stop on crash. Stop on stuck-on-wrong-screen.

Dispatch:
```
Task(
  description: "[the execution plan]",
  model: "haiku",
  subagent_type: "Bash"
)
```

### 2c. Opus Processes Results

Read Haiku's Execution Result:
1. Parse new screens discovered from Coverage and Notes
2. For each new screen: name it based on prominent elements (Opus does the naming), add to `screens` dict, push onto exploration stack
3. Parse transitions from session notes updates
4. If Haiku reported stuck-on-wrong-screen: Opus navigates back using nav-graph knowledge, then continues
5. If Haiku reported crash: stop exploration, proceed to report

Loop back to 2a with the next screen on the stack.

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

If Haiku reports a crash (status: `stopped`, reason: `crash`): Record the CRASH finding with the action that caused it, save the partial map with all screens and transitions discovered so far, and stop. Tell the user the app crashed and they need to relaunch it.
