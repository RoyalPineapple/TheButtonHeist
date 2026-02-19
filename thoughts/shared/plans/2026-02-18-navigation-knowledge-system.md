# Navigation Knowledge System

## Overview

Teach the fuzzer agent to leverage accumulated navigation knowledge — transitions, screen fingerprints, back-routes — for efficient, goal-oriented navigation. Currently the fuzzer discovers transitions reactively but doesn't use them to plan routes. This plan adds pathfinding, smart back-navigation, navigation stack tracking, and cross-session knowledge persistence.

## Current State Analysis

**What exists:**
- `## Transitions` table in session notes: From/Action/To entries
- `## Screens Discovered` table: names, fingerprints, element counts
- InterfaceDelta with `screenChanged` + full `newInterface`
- Screen fingerprinting via element identifier sets
- Multiple session files from prior exploration with rich transition data
- State-exploration strategy with depth-first traversal
- Heuristic back-navigation: label search → position search → swipe gesture

**What's missing:**
- No pathfinding between screens (can't compute "how do I get from A to D?")
- No navigation stack (can't backtrack efficiently)
- Heuristic back-navigation ignores known reverse transitions
- Each session starts from zero navigation knowledge
- No persistent navigation map across sessions

### Key Discoveries:
- Real session data shows the app has a shallow hierarchy (depth 2) with ~10 screens
- Back-navigation already fails in real sessions (Touch Canvas → wrong screen)
- Transitions table already captures bidirectional edges (forward + back)
- The fuzzer already reads prior session notes at startup for compaction recovery — same mechanism works for navigation knowledge

## Desired End State

The fuzzer agent can:
1. **Plan a route** from any screen to any other screen using known transitions
2. **Navigate back** using recorded reverse transitions, not just heuristics
3. **Track its position** in the navigation graph with a stack for efficient backtracking
4. **Inherit knowledge** from prior sessions so subsequent runs start with a complete navigation map
5. **Update the map** as new transitions are discovered

### Verification:
- Run `/fuzz` on the test app. After exploring 3-4 screens, the fuzzer should navigate directly to a specific screen via planned route (visible in session notes `## Navigation Stack`).
- Run `/fuzz` again in a new session. It should read the persistent nav graph and know all transitions without re-discovering them.
- `/reproduce` should use the nav graph to reach a finding's screen efficiently instead of replaying the full trace.

## What We're NOT Doing

- No code changes to InsideMan, TheGoods, or the MCP server — this is purely agent instruction updates
- No new MCP tools — the existing tools provide everything needed
- No probabilistic routing or ML — simple BFS on known transitions
- No handling of dynamic screens (screens with changing element sets) — that's a separate problem

## Implementation Approach

All changes are to the AI fuzzer's documentation and instructions (SKILL.md, command files, reference files). The "navigation graph" is a mental model the LLM agent builds from its session notes, not a code data structure.

---

## Phase 1: Navigation Planning (SKILL.md)

### Overview
Add a "Navigation Planning" section to SKILL.md that teaches the agent how to build a navigation graph from `## Transitions`, find shortest paths, execute planned routes, and verify each step.

### Changes Required:

#### 1. SKILL.md — Add "Navigation Planning" section

**File**: `ai-fuzzer/SKILL.md`

Add after the "Using Deltas to Guide Exploration" section (before "Session Notes"):

```markdown
## Navigation Planning

You accumulate a navigation graph as you explore. **Use it.** When you need to reach a specific screen, don't wander — plan a route.

### Building the Graph

Your `## Transitions` table IS the graph. Each row is a directed edge:

| From | Action | To |
|------|--------|----|
| Main Menu | activate "Settings" | Settings |
| Settings | activate "Back" | Main Menu |

This gives you two edges: Main Menu → Settings and Settings → Main Menu.

### Finding a Route

When you need to navigate from screen A to screen B:

1. Check `## Transitions` for a direct edge A → B. If found, use it.
2. If no direct edge, trace through known transitions:
   - Start from A
   - Find all screens reachable in 1 step from A
   - For each, find all screens reachable in 1 step from those
   - Continue until you find B (BFS — breadth-first search)
   - The path with fewest steps is your route
3. If B is not reachable via known transitions, navigate to the screen closest to B (fewest hops away from B's known entry points) and explore from there.

### Executing a Route

For each step in the planned route:
1. Look up the action from `## Transitions` (e.g., `activate "Settings"`)
2. Find the element on the current screen matching that action (by identifier or label)
3. Execute the action
4. Read the delta: `screenChanged` should show the expected destination
5. Verify the fingerprint matches the expected screen
6. If verification fails: you're on an unexpected screen. Re-plan from current position.

### When to Plan Routes

- **Fuzzing loop**: When `## Next Actions` says to visit a different screen, plan a route there instead of wandering
- **Refinement**: Navigate to each finding's screen via the graph
- **Reproduction**: Use the graph to reach the finding's screen without replaying the full trace
- **Returning to exploration**: After a screen change interrupts your batch, plan a route back
```

### Success Criteria:
- [ ] SKILL.md contains "Navigation Planning" section with graph building, pathfinding, route execution, and usage triggers

---

## Phase 2: Smart Back-Navigation (SKILL.md)

### Overview
Update the "Back Navigation" section to prefer known reverse transitions over heuristics. The fuzzer already records back-transitions in `## Transitions` — it should use them first.

### Changes Required:

#### 1. SKILL.md — Replace "Back Navigation" section

**File**: `ai-fuzzer/SKILL.md`

Replace the current back-navigation section (~line 333) with:

```markdown
## Back Navigation

When you need to return to a previous screen, **check your knowledge first**:

### 1. Known reverse transition (preferred)
Check `## Transitions` for a recorded edge from the current screen back to your target. Example:
- You're on "Settings" and want to go back to "Main Menu"
- `## Transitions` has: `Settings | activate "Back" | Main Menu`
- Use that exact action — it's proven to work

### 2. Navigation stack (if tracked)
Check `## Navigation Stack` for the action that brought you here. The reverse of that transition is your best bet for going back.

### 3. Heuristic search (fallback)
Only if no known transition exists:
1. Look for elements with labels containing "Back", "Cancel", "Close", "Done", or a back arrow
2. Try elements in the top-left of the screen (x < 100, y < 100) — typical iOS back button position
3. Swipe right from left edge: `swipe(startX: 0, startY: 400, direction: "right", distance: 200)`
4. If none work, record as INFO finding: "No back navigation from [screen]"

### 4. After navigating back
Verify you reached the expected screen:
- Read the delta — `screenChanged` should show the expected destination fingerprint
- If you ended up on the wrong screen, record the actual destination in `## Transitions` (it's a new edge) and re-plan from there
```

### Success Criteria:
- [ ] Back-navigation section prioritizes known transitions over heuristics
- [ ] Navigation stack is referenced as second option
- [ ] Heuristic fallback clearly marked as last resort

---

## Phase 3: Navigation Stack in Session Notes

### Overview
Add a `## Navigation Stack` section to the session notes format. This tracks the fuzzer's current path through the app, enabling efficient backtracking by popping the stack instead of planning new routes.

### Changes Required:

#### 1. SKILL.md — Update session notes format

**File**: `ai-fuzzer/SKILL.md`

Add `## Navigation Stack` to the session notes format template (after `## Transitions`):

```markdown
## Navigation Stack
Current path from root to current screen. Push when navigating forward, pop when going back.

| Depth | Screen | Arrived Via |
|-------|--------|-------------|
| 0 | Main Menu | (root) |
| 1 | Controls Demo | activate "Controls Demo" |
| 2 | Text Input | activate "Text Input" |

**Current screen**: Text Input (depth 2)
**Back action**: activate "Controls Demo" (known transition to Controls Demo)
```

#### 2. SKILL.md — Update session notes lifecycle

**File**: `ai-fuzzer/SKILL.md`

In the "How it works" subsection, add navigation stack updates:

Add to the list of "After every significant event" updates:
- `## Navigation Stack` — push on forward navigation, pop on back navigation

In the "Resuming after compaction" steps, add:
- Check `## Navigation Stack` to know your current position in the app and how to backtrack

#### 3. SKILL.md — Navigation Stack operations

**File**: `ai-fuzzer/SKILL.md`

Add to the "Navigation Planning" section (from Phase 1):

```markdown
### Navigation Stack

Maintain a `## Navigation Stack` in your session notes to track your current path through the app.

**Push** when any action produces a `screenChanged` delta (forward navigation):
- Add a row: depth, screen name, action that got you there

**Pop** when you navigate back:
- Remove the top row
- The new top is your current screen

**Use the stack to**:
- Know your current depth in the app (useful for deciding whether to go deeper or back out)
- Backtrack efficiently: the "Arrived Via" column for the current row tells you what transition to reverse
- Detect navigation anomalies: if a "back" action doesn't pop to the expected screen, it's a finding
- Resume after compaction: read the stack to know exactly where you are
```

### Success Criteria:
- [ ] Session notes format includes `## Navigation Stack` template
- [ ] Navigation stack push/pop rules defined
- [ ] Compaction recovery references the navigation stack
- [ ] Navigation stack used for backtracking guidance

---

## Phase 4: Persistent Navigation Map

### Overview
Create a persistent navigation map file that accumulates transition knowledge across sessions. New sessions read this at startup to inherit all previously discovered transitions, screen fingerprints, and back-routes.

### Changes Required:

#### 1. New reference file: `ai-fuzzer/references/nav-graph.md`

**File**: `ai-fuzzer/references/nav-graph.md`

Template (initially empty, populated by sessions):

```markdown
# Navigation Graph

Persistent navigation knowledge accumulated across fuzzing sessions. Read this at session start. Update it at session end.

**Last updated**: [timestamp]
**App**: [app name]
**Sessions contributing**: [count]

## Screens

| # | Name | Fingerprint | Elements | Entry Points |
|---|------|-------------|----------|--------------|

## Transitions

| From | Action (element) | To | Reverse Action | Reliable |
|------|------------------|----|----------------|----------|

## Back Routes

Known reliable back-navigation from each screen:

| Screen | Back Action | Destination | Method |
|--------|-------------|-------------|--------|

## Notes
- [Any navigation anomalies, dead ends, or quirks discovered across sessions]
```

Key additions over session-level `## Transitions`:
- **Reverse Action** column: the action to go back (if known)
- **Reliable** column: whether this transition has been verified across multiple sessions
- **Back Routes** table: dedicated quick-lookup for back-navigation from each screen
- **Entry Points**: how many ways to reach each screen

#### 2. SKILL.md — Add nav graph lifecycle

**File**: `ai-fuzzer/SKILL.md`

Add to the "Navigation Planning" section:

```markdown
### Persistent Navigation Map

A shared navigation map at `references/nav-graph.md` accumulates knowledge across sessions.

**At session start:**
1. Read `references/nav-graph.md` if it exists
2. Pre-populate your mental navigation graph with all known transitions
3. Pre-populate your back-routes with the Back Routes table
4. You now know how to reach every screen without re-discovering transitions

**At session end:**
1. Merge any new transitions into `references/nav-graph.md`
2. Update the Back Routes table with any new back-navigation discoveries
3. Mark transitions as "reliable" if they've been verified in 2+ sessions
4. Add any navigation anomalies to the Notes section

**If no nav graph exists:**
- First session creates it from scratch after exploration
- Write the initial graph at session end
```

### Success Criteria:
- [ ] `references/nav-graph.md` template exists with all table structures
- [ ] SKILL.md documents read-at-start, write-at-end lifecycle
- [ ] Back Routes table provides quick lookup for back-navigation
- [ ] Reliability tracking across sessions

---

## Phase 5: Command Updates

### Overview
Update all command files to use navigation planning, the navigation stack, and the persistent nav graph.

### Changes Required:

#### 1. fuzz.md — Use navigation planning

**File**: `ai-fuzzer/.claude/commands/fuzz.md`

**Step 0** (Verify Connection): Add after checking for existing session:
```markdown
5. **Load navigation knowledge**: Read `references/nav-graph.md` if it exists. This gives you all known transitions, back-routes, and screen fingerprints from prior sessions.
```

**Step 3** (Initialize Session Notes): Add:
```markdown
8. Write the `## Navigation Stack` section with the initial screen at depth 0
```

**Step 4a** (Observe + Plan Batch): Update screen navigation logic:
```markdown
- If everything on this screen has been tried, **plan a route** to the highest-priority unexplored screen using known transitions (see "Navigation Planning" in SKILL.md). Don't wander — navigate directly.
```

**Step 4b** (Execute Batch): Update `screenChanged` handling:
```markdown
- **`screenChanged`**: Navigated to a new screen. **Push** onto navigation stack. The delta includes the full `newInterface`. Record transition in `## Transitions`. Stop batch, explore or navigate back (use known back-route if available), then re-plan.
```

**Step 4c** (Record): Add:
```markdown
4. **Update navigation stack**: Push for forward navigation, pop for back navigation
```

**Step 5** (Refinement): Update:
```markdown
1. **Navigate to finding's screen**: Use the navigation graph to plan a route to each finding's screen. Check `## Transitions` for the shortest path from your current position.
```

**Step 6** (Generate Report): Add:
```markdown
4. **Update persistent nav graph**: Merge all new transitions into `references/nav-graph.md`
```

#### 2. explore.md — Use navigation planning

**File**: `ai-fuzzer/.claude/commands/explore.md`

**Step 0**: Add nav graph loading and navigation stack initialization.

**Step 3** (Elements with actions): Update `screenChanged` handling:
```markdown
- **`screenChanged`**: Stop batch, **push** onto navigation stack, use the `newInterface` from delta to record new screen and transition. Navigate back using **known back-route** from nav graph if available, otherwise use heuristic back-nav. **Pop** navigation stack on return.
```

#### 3. reproduce.md — Use nav graph for reaching finding's screen

**File**: `ai-fuzzer/.claude/commands/reproduce.md`

**Step 2** (Build Reproduction Sequence): Update:
```markdown
2. **Plan navigation using nav graph**: Instead of walking backward through the trace, check `references/nav-graph.md` for the shortest route from the current screen to the finding's screen. This is faster and doesn't require the exact trace path.
3. If nav graph doesn't have a route to the finding's screen, fall back to trace-walking.
```

**Step 3** (Verify Connection): Update:
```markdown
4. **Load nav graph**: Read `references/nav-graph.md` for shortest path planning
5. If already on the finding's screen, skip navigation
6. If not, **plan route** from current screen to finding's screen using nav graph transitions
```

#### 4. map-screens.md — Output to persistent nav graph

**File**: `ai-fuzzer/.claude/commands/map-screens.md`

**Step 0**: Add nav graph loading to pre-populate known screens.

**Step 4** (Save Report): Add:
```markdown
2. **Update persistent nav graph**: Write all discovered transitions, back-routes, and screen data to `references/nav-graph.md`. This is the primary output — future sessions will use it for navigation planning.
```

#### 5. stress-test.md — Use nav graph for element targeting

**File**: `ai-fuzzer/.claude/commands/stress-test.md`

**Step 0**: Add nav graph loading.

**Step 1** (Identify Targets): If targeting a specific element on a different screen, use nav graph to reach that screen first.

### Success Criteria:
- [ ] All commands load nav graph at startup
- [ ] fuzz.md uses pathfinding for screen selection
- [ ] explore.md uses known back-routes for returning after transitions
- [ ] reproduce.md uses nav graph instead of trace-walking for reaching finding's screen
- [ ] map-screens.md writes to persistent nav graph
- [ ] Navigation stack is maintained in fuzz.md and explore.md

---

## Implementation Order

Phase 1 → Phase 2 → Phase 3 → Phase 4 → Phase 5

Phases 1-2 update SKILL.md core instructions. Phase 3 updates session notes format. Phase 4 creates the persistent nav graph. Phase 5 wires everything into the commands.

## Testing Strategy

### Integration Testing:
1. Run `/map-screens` on the test app → verify `references/nav-graph.md` is created with all transitions
2. Run `/fuzz` → verify the fuzzer reads the nav graph and uses planned routes (check session notes for `## Navigation Stack`)
3. Run `/fuzz` in a new session → verify it loads prior nav graph and navigates efficiently from the start
4. Run `/reproduce` against a finding → verify it uses nav graph instead of replaying full trace

## Files Modified/Created

| File | Action |
|------|--------|
| `ai-fuzzer/SKILL.md` | **EDIT** — Add Navigation Planning, update Back Navigation, add Navigation Stack, add nav graph lifecycle |
| `ai-fuzzer/references/nav-graph.md` | **CREATE** — Persistent navigation map template |
| `ai-fuzzer/.claude/commands/fuzz.md` | **EDIT** — Nav graph loading, pathfinding, navigation stack, back-route usage |
| `ai-fuzzer/.claude/commands/explore.md` | **EDIT** — Nav graph loading, back-route usage, navigation stack |
| `ai-fuzzer/.claude/commands/reproduce.md` | **EDIT** — Nav graph for reaching finding's screen |
| `ai-fuzzer/.claude/commands/map-screens.md` | **EDIT** — Output to persistent nav graph |
| `ai-fuzzer/.claude/commands/stress-test.md` | **EDIT** — Nav graph loading for element targeting |
