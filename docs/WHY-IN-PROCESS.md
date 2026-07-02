# Why in-process

The first question an iOS engineer asks about The Button Heist is "why not
XCUITest?" This page answers it from Apple-documented behavior, then places the
other public approaches on the same map.

The short version: The Button Heist runs inside the app so it can hold the live
accessibility tree — real `UIAccessibilityElement`s, not serialized copies —
and act through the same declared activations VoiceOver invokes. No
out-of-process driver can do either, because iOS does not let one process
traverse another app's live accessibility tree. This argument as one picture
is the [process boundaries diagram](diagrams/process-boundaries.md).

## The surface under test

The Button Heist operates on the resolved runtime accessibility tree: the
structure where automatic inference, developer annotations, and framework
resolution combine into what VoiceOver actually reads — labels, values, traits,
identifiers, actions, containers. A defect in any of those layers is visible
only in the resolved tree, and the resolved tree is what a test should assert
against.

The ideal would be to register as an assistive technology and consume the
interface through the exact OS path VoiceOver uses. Apple exposes no public API
for that. In-process is the closest reachable vantage: parse the app's own
resolved hierarchy, hold the real elements, and invoke their real methods.

## Where XCUITest stops

XCUITest is genuinely built on accessibility, and it is close to the right
thing. The gap is narrow and specific:

- **A test holds a proxy, not an element.** `XCUIElement` is a query in the
  test runner's process, not a live `UIAccessibilityElement`. Touching a
  property makes an IPC round-trip into the app and returns an
  `XCUIElementSnapshot` — a serialized copy of the accessibility attributes.
  The thing the test inspects is a snapshot, never the live tree.
- **The action is a synthesized touch, not a declared activation.** `tap()`,
  in Apple's own words, "sends a tap event to a hittable point computed for
  the element." Accessibility is the lookup key for where to tap; the pixel at
  the computed coordinate is what gets exercised. The element's declared
  `accessibilityActivate()` — the activation VoiceOver invokes — is never
  called.
- **The activation point is consumed, never exposed.** Every element may
  declare an activation point, the spot VoiceOver dispatches to. XCUITest uses
  it internally inside `tap()` but never hands it to the test: you cannot read
  it, assert on it, or know it was used. Coordinate-computing drivers below
  XCUITest never see it at all. The Button Heist exposes the declared
  activation point on every element and dispatches to it only as the
  VoiceOver-order fallback after `accessibilityActivate()`.

The same shape rules out Appium, WebDriverAgent, and idb-based tools:
WebDriverAgent wraps XCUITest, Appium drives WebDriverAgent, and all of them
are out of process — resolving a serialized accessibility query and acting
through synthesized events. A different driver changes the element vocabulary
and leaves you inspecting a copy and acting on pixels.

The deeper reason this cannot be fixed from outside: iOS exposes no public API
for one process to traverse another app's live accessibility tree the way
VoiceOver does (unlike macOS, where cross-process `AXUIElement` exists).
VoiceOver reaches it through private, entitled frameworks. To read the live
tree rather than a snapshot, you have to run inside the app. The Button Heist
does.

## What in-process buys

**The whole vocabulary, not the tappable slice.** The accessibility interface
is not a label and a tap. It is every trait, the hint, the value, custom
content, and — to act — not just activate but increment, decrement, custom
actions, and the rotor. There is no pixel for a custom action, no coordinate
that reads a hint. A tool that taps screen coordinates can exercise the slice
of accessibility that happens to have a tappable frame; The Button Heist holds
the real element and calls the real methods.

**Settled evidence instead of delivered events.** Because it lives inside the
app, The Button Heist can wait for the interface to genuinely settle — quiet
accessibility-tree fingerprints, not sleeps — then re-parse and assert what the
action changed. The unit of proof shifts from "the event was delivered" to
"the interface contract was fulfilled." [Scope and limits](SCOPE-AND-LIMITS.md)
defines "settled" precisely.

**A control plane wherever the app runs.** The server starts inside the
process, so it opens in places an external driver cannot reach: an app-hosted
test can navigate to a hard-to-reach state, start a session, and hold the run
loop while an agent or human connects and works the live state in place. See
`joinHeist` in the [README](../README.md).

To be precise about the claim: driving UI through accessibility trees is not
new — Android `AccessibilityService` agents, macOS `AXUIElement` agents, and
tree-scraping MCP tools all predate this project. What is distinct here is
doing it in-process on iOS, with live elements, real `accessibilityActivate()`,
and settled evidence after every action.

## The public landscape

**EarlGrey** is the public prior art for in-process iOS testing, and its
synchronization-first thesis — act only when the app is idle — is prior art
for the settle model. The difference is the surface: EarlGrey matches views
and synthesizes touches; The Button Heist parses the declared accessibility
tree and invokes declared activations. Both run inside the app; they read
different layers of it.

**Maestro** is the closest artifact-shaped comparison: small declarative flow
files, `assertVisible`, bounded `repeat`, `runFlow` subflows. It is
out-of-process, so it inherits the snapshot-and-synthesized-touch shape above.
The differentiation is settled evidence, real `accessibilityActivate()`,
per-step expectations, and change predicates in the receipt.

**Vision and computer-use agents** operate screenshot-to-coordinates: read
pixels, infer intent, tap a point. That works on anything visible and proves
nothing about the accessibility contract. The Button Heist gives an agent
structured text state instead of pixels, real accessibility actions instead of
computed coordinates, and a receipt of what changed instead of a screenshot to
re-read. The two compose: pixels remain the right proof when the subject is
visual.

**Coordinate MCP wrappers** (for example, tools built on idb) hand agents the
accessibility tree as geometry: read frames, compute a center, tap the point.
They demonstrate the demand for agent-driven iOS automation and inherit every
limit above.

## The dual payoff

One property falls out of the architecture and is worth stating on its own:
the same run that automates the app audits it. The interface The Button Heist
depends on to do its work is the accessibility interface, so when an
interaction fails, it usually means an assistive technology user hits the same
wall in the same place for the same reason. A failed interaction is a lead,
not noise to retry past — and a passing flow is evidence the contract those
users depend on actually holds. A coordinate driver finishes the flow whether
the accessibility works or not, so a broken element rides along behind a green
check; The Button Heist goes through the accessibility, so the broken element
is the red.

The failure is a strong lead, not a verdict. The triage discipline — including
ruling out parser gaps before filing app bugs — is in
[Scope and limits](SCOPE-AND-LIMITS.md).

## The cost

In-process has one hard limit: the server sees only its own process. System
dialogs, other-process content, and out-of-app surfaces are invisible.
[Scope and limits](SCOPE-AND-LIMITS.md) names them and recommends the pairing
that covers them.
