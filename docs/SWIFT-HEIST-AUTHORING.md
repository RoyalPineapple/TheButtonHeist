# Swift Heist Authoring Boundary

Swift Heist is the editable source form for authoring heists. Treat the Swift
DSL like product code: it can use helper functions, local variables, comments,
formatting, and static expansion helpers such as `ForEach` to make a heist easy
to read and maintain.

`HeistPlan` is the execution model. A Swift DSL file builds a `HeistPlan`; a
`.heist` JSON file stores and transports a `HeistPlan`. JSON is the wire and
storage artifact, not the source authoring surface.

Decoding `.heist` JSON reconstructs an executable `HeistPlan` with the steps,
targets, arguments, and expectations required for playback. It does not
reconstruct the Swift source that produced it. In particular, JSON cannot
recover:

- helper functions or builder structure
- static `ForEach` source before expansion
- comments
- local variables, constants, or their names
- source grouping, whitespace, formatting, or review intent

At runtime, Button Heist executes only `HeistPlan`. The Swift DSL is an
authoring convenience that produces a plan; JSON is a durable representation of
that plan. Keep Swift DSL files when the heist needs to remain editable as
source, and keep `.heist` JSON when the heist needs to move across the wire or
be stored for deterministic playback.

Semantic actions should describe user intent and expected semantic outcome:

```swift
Heist {
    TypeText("milk", into: .label("Search"))
        .expect(.present(.element(label: "Search", value: "milk")))

    Activate(.label("Delete"))
        .expect(.absent(.label("Delete")))
}
```

When a semantic action intentionally has no durable outcome, make that waiver
explicit in source:

```swift
Activate(.label("Optional"))
    .withoutExpectation("No durable semantic outcome")
```

Validation can then distinguish an intentional waiver from a missing assertion:

- `.runtime` checks only execution contract concerns.
- `.recordingQuality` flags recordings that read like transcripts instead of
  compact semantic tests.
- `.strictTest` treats missing expectations, mechanical commands, viewport setup
  before semantic actions, empty branches, and oversized runtime loops as test
  quality failures.

Mechanical and viewport commands are explicit escape hatches. Use the namespace
to make that intent visible:

```swift
Mechanical.Tap(x: 120, y: 400)
Viewport.Scroll(.down)
Viewport.ScrollToVisible(.label("Checkout"))
```

Normal semantic actions do not need viewport setup. `Activate`, `TypeText`,
`Increment`, `Decrement`, custom actions, and rotors own reveal, actionability,
and live geometry through the runtime pipeline.

```swift
CustomAction("Archive", on: .label("Message"))
    .expect(.changed(.elements))

Rotor("Headings", on: .label("Article"), direction: .next)
    .withoutExpectation("Navigation cursor only")
```

`ForEach` has two authoring forms. `ForEach(collection)` is static Swift
expansion and emits only the linear child steps. `ForEach(.matching(predicate),
limit:)` emits one runtime `for_each` step; the closure receives
an `ElementTarget` data value recorded on the step as the body element. At
runtime each iteration instantiates that element as
`ElementTarget.predicate(predicate, ordinal: index)`, so the body repeats the
same semantic promise and command execution re-resolves it normally.
Runtime `ForEach` repeats semantic intent; commands re-resolve targets. The
loop owns match counting, ordinal scheduling, and limit enforcement only.
Runtime `ForEach` takes an initial settled observation, counts the predicate
matches, and never executes more bodies than that initial count. After each
successful body it observes settled state once and re-evaluates the matched
collection. If the policy-backed identity/order of the matched collection is
unchanged, the next body uses the next ordinal. If identity/order changed, the
next body resets to ordinal `0`. State-only mutations do not reset ordinal
scheduling. Each body action still resolves the live `ElementTarget` through
the normal command/actionability pipeline, so out-of-range or non-actionable
targets fail with normal command diagnostics.
