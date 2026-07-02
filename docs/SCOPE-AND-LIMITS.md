# Scope and limits

The Button Heist proves structural accessibility: that elements are declared,
reachable, and activatable through the accessibility contract. This page states
what it cannot see, defines the terms its evidence depends on, and gives the
triage discipline for turning failures into good bug reports. A tool whose
pitch is settled evidence owes you a precise definition of both words.

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

## What "settled" means

Evidence is captured against a settled interface, and "settled" has an exact
definition:

- The settle loop re-parses the accessibility tree about every 100 ms and
  computes a content fingerprint over each element's label, identifier, value,
  traits, and geometry.
- The interface is settled after **3 consecutive quiet cycles** with an
  identical fingerprint — a roughly 300 ms floor. Because the fingerprint
  includes position and size, an element still sliding or resizing cannot pass
  for settled.
- Elements carrying the `updatesFrequently` trait are masked out of the
  fingerprint, so spinners and tickers do not block settlement forever.
- A separate lightweight tripwire pulses at roughly 10 Hz over the
  presentation layer (in-flight animations, navigation, window identity) and
  resets the baseline when it sees a visible transition. It never reads the
  accessibility tree.
- If the interface has not settled after **5 seconds** (the default hard
  timeout), the runtime stops waiting and reports the capture as explicitly
  unsettled rather than silently treating it as settled. Diagnostic evidence
  from a non-clean settle is kept separate from settled semantic truth.

Two premises make waiting for stability the right default rather than an
arbitrary delay: an iOS interface spends most of its life at rest, so settle
converges quickly; and an element in transition should not be interacted with
anyway — the window in which The Button Heist declines to act is the window in
which acting would be wrong.

## Realized content

Semantic targeting abstracts the viewport: an activation can act on an
offscreen accessible target without a caller-authored scroll step. The bound
is realization. Lazily instantiated content — `UICollectionView`
virtualization, `LazyVStack`, and friends — has no accessibility elements
until the framework creates them. The Button Heist's scroll exploration can
realize such content by scrolling, but an element that has never been realized
is not in the tree and cannot be targeted by a pure tree read. "Offscreen"
means realized but out of the viewport, not hypothetical.

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
2. **A false settle.** The capture may have committed against a state that
   was still becoming itself, or timed out unsettled.
3. **A stale test.** The contract may have legitimately changed.

The match is not exact in either direction: a gesture-driven control can fail
the tool yet work under VoiceOver, and an element the tool can activate may
still sit behind a focus trap a real user never escapes. Verify with an
independent witness — Accessibility Inspector, or an audit tool such as axe —
before filing, and file what the witness confirms. Run down a failure this way
and it is usually a fact about the product, not noise to retry past.
