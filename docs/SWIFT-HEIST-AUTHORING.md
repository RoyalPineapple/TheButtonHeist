# Swift Heist Authoring Boundary

Swift Heist is the editable source form for authoring heists. Treat the Swift
DSL like product code: it can use helper functions, local variables, comments,
and formatting to make a heist easy to read and maintain. Durable loops must
use Button Heist's explicit `ForEach` primitives, not native Swift `for`.

`HeistPlan` is the execution model. A Swift DSL file builds a `HeistPlan`; a
`.heist` JSON file stores and transports a `HeistPlan`. JSON is the wire and
storage artifact, not the source authoring surface.

Decoding `.heist` JSON reconstructs an executable `HeistPlan` with the steps,
targets, arguments, and expectations required for playback. `ButtonHeistDSL`
can render that AST back to canonical Swift DSL. Canonical rendering preserves
semantic meaning, not arbitrary authorship details. In particular, JSON does
not recover:

- helper functions or builder structure
- comments
- local variables, constants, or their names
- source grouping, whitespace, formatting, or review intent

At runtime, Button Heist executes only `HeistPlan`. The Swift DSL is an
authoring convenience that produces a plan; JSON is a durable representation of
that plan. Swift DSL and JSON are two projections of the same AST.

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

Runtime admission and lint are separate:

- Runtime admission rejects plans that cannot safely execute.
- `.recordingQuality` lint flags recordings that read like transcripts instead of
  compact semantic tests.
- `.strictTest` lint treats missing expectations, mechanical commands, viewport
  setup before semantic actions, and empty branches as test quality failures.

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

`ForEach` has two durable authoring forms:

```swift
try ForEach(.matching(.label("Delete")), limit: 20) { target in
    Activate(target)
        .expect(.absent(target), timeout: .seconds(2))
}

try ForEach(["Milk", "Eggs"]) { item in
    TypeText(item, into: .label("Add item"))
        .expect(.present(.label(item)), timeout: .seconds(2))
}
```

Do not use native Swift `for` inside `Heist {}`. The heist result builder does
not lower native loops because native loops flatten at authoring time and lose
loop intent. If a loop should survive JSON, write `ForEach`.

Semantic `ForEach` serializes as `for_each_element`. String-array `ForEach`
serializes as `for_each_string`. Runtime `ForEach` repeats semantic intent;
commands re-resolve targets. The loop owns match counting, ordinal scheduling,
and limit enforcement only. Semantic `ForEach` takes an initial settled
observation, counts the predicate matches, and never executes more bodies than
that initial count. After each successful body it observes settled state once
and re-evaluates the matched collection. If the policy-backed identity/order
of the matched collection is unchanged, the next body uses the next ordinal. If
identity/order changed, the next body resets to ordinal `0`. State-only
mutations do not reset ordinal scheduling. Each body action still resolves the
live `ElementTarget` through the normal command/actionability pipeline, so
out-of-range or non-actionable targets fail with normal command diagnostics.
