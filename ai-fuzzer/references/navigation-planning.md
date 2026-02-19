# Navigation Planning

## Contents
- [Building the Graph](#building-the-graph) — how the transition table works
- [Finding a Route](#finding-a-route) — BFS route planning
- [Executing a Route](#executing-a-route) — step-by-step route execution
- [Navigation Stack](#navigation-stack) — tracking depth and backtracking
- [Persistent Navigation Map](#persistent-navigation-map) — cross-session nav-graph.md I/O
- [When to Plan Routes](#when-to-plan-routes) — when to use route planning vs. wandering

---

You accumulate a navigation graph as you explore. **Use it.** When you need to reach a specific screen, don't wander — plan a route.

### Building the Graph

Your `## Transitions` table IS the graph. Each row is a directed edge:

| From | Action | To |
|------|--------|----|
| Main Menu | activate "Settings" | Settings |
| Settings | activate "Back" | Main Menu |

This gives you two edges: Main Menu → Settings and Settings → Main Menu. As you explore, this graph grows. By mid-session you know how most screens connect.

### Finding a Route

When you need to navigate from screen A to screen B:

1. Check `## Transitions` for a direct edge A → B. If found, use it.
2. If no direct edge, trace through known transitions:
   - Start from A
   - Find all screens reachable in 1 step from A
   - For each, find all screens reachable in 1 step from those
   - Continue until you find B (breadth-first search)
   - The path with fewest steps is your route
3. If B is not reachable via known transitions, navigate to the screen closest to B (fewest hops from B's known entry points) and explore from there.

### Executing a Route

For each step in the planned route:
1. Look up the action from `## Transitions` (e.g., `activate "Settings"`)
2. Find the element on the current screen matching that action (by identifier or label)
3. Execute the action
4. Read the delta: `screenChanged` should show the expected destination
5. Verify the fingerprint matches the expected screen
6. If verification fails: you're on an unexpected screen. Record the unexpected transition and re-plan from your current position.

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

### Persistent Navigation Map

A shared navigation map at `references/nav-graph.md` accumulates knowledge across sessions.

**At session start:**
1. Read `references/nav-graph.md` if it exists
2. Pre-populate your mental navigation graph with all known transitions and back-routes
3. You now know how to reach every previously discovered screen without re-exploring

**At session end:**
1. Merge any new transitions into `references/nav-graph.md`
2. Update the Back Routes table with any new back-navigation discoveries
3. Mark transitions as "reliable" if they've been verified in 2+ sessions
4. Add any navigation anomalies to the Notes section

**If no nav graph exists:** First session creates it after exploration.

### When to Plan Routes

- **Fuzzing loop**: When `## Next Actions` says to visit a different screen, plan a route instead of wandering
- **Refinement**: Navigate to each finding's screen via the graph
- **Reproduction**: Use the graph to reach the finding's screen without replaying the full trace
- **Returning after interruption**: After a `screenChanged` interrupts your batch, plan a route back
