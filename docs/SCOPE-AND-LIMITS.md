# Scope and limits

The Button Heist proves structural accessibility: that elements are declared,
reachable, and activatable through the accessibility contract. This page states
what it cannot see, defines the terms its evidence depends on, and gives the
triage discipline for turning failures into good bug reports. A tool that
claims observed evidence owes you a precise definition of what was observed.

## Platform scope

The Button Heist automates iOS apps. The CLI and MCP server run on macOS as
clients of the in-app server; there is no macOS app automation, no Android,
and no web support.

## Out-of-process blindness

Running inside the app is the source of every capability on the
[Why in-process](WHY-IN-PROCESS.md) page, and it has one hard limit: the
server sees only its own process's accessibility tree. Anything owned by
another process is invisible:

- **SpringBoard-owned permission alerts** — location, notifications, camera,
  tracking, and the rest of the system alert family.
- **Share sheets and other remote view controllers** — content hosted from
  another process inside your app's window.
- **`SFSafariViewController`** — the browser view is another process's
  content.
- **`WKWebView` page content** — web pages render in a separate WebContent
  process; the web page's accessibility tree is not part of the app's tree.

This is an architectural boundary, not a backlog item. For flows that must
cross it, pair the tools: The Button Heist drives and audits the in-app
interface; an out-of-process shell such as XCUITest handles system dialogs and
other-process surfaces around it.

The handoff should be explicit in tests. XCUITest should tap SpringBoard or
other system UI, then Button Heist should assert the app-owned accessibility
contract once the app is back on an in-process screen. Do not send Button Heist
commands while a SpringBoard alert is visible; that surface is outside the app
tree by design. See the paired example in
[Adoption examples](../examples/adoption-examples.md#pairing-with-xcuitest-for-system-dialogs).

## What observed evidence means

The runtime does not own a polling-based settle loop or a hidden stability
timeout. Evidence is derived from the Vault's current admitted snapshot and its
ordered `Observation.Event` history (drawn in the
[heist execution diagram](diagrams/heist-execution.md)):

- A MainActor boundary parses one complete accessibility reading into an
  immutable `Observation.Snapshot`.
- The Vault compares that reading with current truth, commits the new current
  snapshot, then records and publishes the corresponding ordered events.
- `elementsChanged` carries the new snapshot. A screen replacement records
  old-tree departures, one `screenChanged` marker, then new-tree arrivals.
- `noChange` is emitted only after a fresh complete reading proves that all
  observed semantics, screen- and view-space geometry, activation points, focus,
  keyboard, screen, and window context are unchanged under the one geometry
  tolerance.
- Accessibility notifications and viewport movement can trigger another
  reading, but notification kind never substitutes for the resulting parsed
  state.
- Current-state predicates read the current snapshot. Temporal predicates fold
  the exact event order after their private history boundary.

Authored leaf and whole-heist timeouts are the only execution deadlines. The
MainActor host owns both as absolute policies and schedules one task for the
earlier deadline. On expiry it cancels in-flight work, admits final evidence,
and gives the deterministic machine one final crank. There is no separate
five-second cap or diagnostic-only observation path.

## Realized content

Semantic targeting abstracts the viewport: an activation can act on an
offscreen accessible target without a caller-authored scroll step. The bound
is realization. Lazily instantiated content — `UICollectionView`
virtualization, `LazyVStack`, and friends — has no accessibility elements
until the framework creates them. The Button Heist's scroll exploration can
realize such content by scrolling, but an element that has never been realized
is not in the tree and cannot be targeted by a pure tree read. "Offscreen"
means realized but out of the viewport, not hypothetical. The resolution and
reveal flow is drawn in the
[element inflation diagram](diagrams/element-inflation.md).

## Accessibility classes The Button Heist does not catch

Passing heists are the floor, not the ceiling. A green run proves elements are
declared, reachable, and activatable. It does not validate:

- **Visual accessibility** — contrast ratios, Dynamic Type layout, color-only
  information, Reduce Motion behavior. Those are rendering properties;
  screenshot and snapshot tests validate them.
- **VoiceOver focus placement** — where focus lands after a transition, and
  whether it is preserved sensibly across updates.
- **Posted announcements** — `UIAccessibility` notification announcements are
  not part of the parsed tree.
- **Label and hint quality** — the tool proves a label exists and matches; it
  cannot judge whether the label is a good one.
- **Navigation effort** — semantic targeting auto-reveals offscreen targets,
  so a passing heist says nothing about how many swipes a VoiceOver user needs
  to reach the same control. A screen where every element is labeled but Pay
  takes forty swipes passes every heist.
- **Voice Control and Switch Control specifics** — each has interaction
  patterns this tool does not model.

Reading order is in the parsed tree, so an agent can assess a whole screen's
sequence in one pass — heist data can inform these judgments, but it does not
automate them.

## Findings are leads, not verdicts

When The Button Heist cannot operate an element, the first hypothesis is that
the app's accessibility is incomplete — and a VoiceOver user would hit the
same wall. It must not be the only hypothesis. Before filing a product bug,
rule out the alternatives:

1. **A parser gap.** The parser may have missed an element VoiceOver does
   reach, or computed the wrong activation point. Treating every failed
   activation as accessibility debt without ruling this out files bugs against
   the app for the tool's own blind spots.
2. **Incomplete observation evidence.** A transition may not have produced the
   capture or ordered events the expectation required before its authored
   deadline.
3. **A stale test.** The contract may have legitimately changed.

The match is not exact in either direction: a gesture-driven control can fail
the tool yet work under VoiceOver, and an element the tool can activate may
still sit behind a focus trap a real user never escapes. Verify with an
independent witness — Accessibility Inspector, or an audit tool such as axe —
before filing, and file what the witness confirms. Run down a failure this way
and it is usually a fact about the product, not noise to retry past.
