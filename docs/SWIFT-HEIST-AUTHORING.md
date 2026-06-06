# Swift Heist Authoring Boundary

Swift Heist is the editable source form for authoring heists. Treat the Swift
DSL like product code: it can use helper functions, local variables, comments,
and formatting to make a heist easy to read and maintain. Durable loops must
use Button Heist's explicit `ForEach` primitives, not native Swift `for`.

`HeistPlan` is the execution model. A Swift DSL file builds a `HeistPlan`;
standalone `.json` files are explicit raw HeistPlan IR for debug, import, and
export; generated `.heist` package directories store `manifest.json` and
canonical `plan.json`.

Decoding `.json` IR or a `.heist` package reconstructs an executable
`HeistPlan` with the body, targets, arguments, and expectations required for
runtime execution. `ThePlans` can render that AST back to canonical Swift DSL.
Canonical rendering preserves semantic meaning, not arbitrary authorship
details. In particular, JSON does not recover:

- helper functions or builder structure
- comments
- local variables, constants, or their names
- source grouping, whitespace, formatting, or review intent

At runtime, Button Heist executes only `HeistPlan`. The Swift DSL is the source
authoring language; `.json` is raw IR; `.heist` is a generated package artifact.
Swift DSL and canonical plan JSON are two projections of the same AST. That
AST belongs to the broader [Accessibility Contract](ACCESSIBILITY-CONTRACT.md):
semantic intent enters the runtime and settled semantic evidence comes back.

Reusable heist helpers that should survive JSON must be written as heist
definitions, not arbitrary Swift functions:

```swift
enum LibraryScreen {
    static let addToCart = HeistDef<String>("addToCart") { input in
        Activate(.label(input))

        Activate(.label("Add to Cart"))
            .expect(.present(.label("Cart")))
    }
}

try HeistPlan("purchaseFlow") {
    LibraryScreen.addToCart("Milk")
    LibraryScreen.addToCart("Bread")
}
```

`HeistDef` values carry their definition dependency and invocation path into
`HeistPlan`. Canonical Swift rendering can reproduce equivalent definitions
and invocations, but it does not preserve arbitrary helper function names,
source grouping, comments, or local constants.

Semantic actions should describe user intent and expected semantic outcome:

```swift
try HeistPlan {
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
- `.compositionQuality` lint flags composed plans that read like transcripts
  instead of compact semantic tests.
- `.strictTest` lint treats missing expectations, mechanical commands,
  viewport/debug action steps, and empty branches as
  test quality failures.

Mechanical commands are explicit escape hatches. Use the namespace to make that
intent visible:

```swift
Mechanical.Tap(x: 120, y: 400)
```

Viewport/debug commands such as `scroll`, `scroll_to_edge`, and
`scroll_to_visible` are direct inspection commands, not durable Swift Heist
primitives. Normal semantic actions do not need pre-action viewport movement.
`Activate`, `TypeText`, `Increment`, `Decrement`, custom actions, and rotors own
reveal, element inflation, and live geometry through the runtime pipeline.

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

Semantic `ForEach` serializes as `for_each_element`. Finite string `ForEach`
serializes as `for_each_string`. Runtime `ForEach` repeats semantic intent;
commands re-resolve targets. The loop owns match counting, ordinal scheduling,
and limit enforcement only. Semantic `ForEach` takes an initial settled
observation, counts the predicate matches, and never executes more bodies than
that initial count. After each successful body it observes settled state once
and re-evaluates the matched collection. If the policy-backed identity/order
of the matched collection is unchanged, the next body uses the next ordinal. If
identity/order changed, the next body resets to ordinal `0`. State-only
mutations do not reset ordinal scheduling. Each body action still resolves the
live `ElementTarget` through the normal command and element inflation pipeline, so
out-of-range or non-inflated targets fail with normal command diagnostics.

## Compilation Boundary

Swift compilation is an **author-time** step, not a runtime capability. It lives
only in the authoring tools:

- `buttonheist run_heist Flow.swift --entry makeHeist` compiles the Swift source
  to a `HeistPlan`, validates that plan for runtime behavior, then sends it down
  the ordinary `run_heist` path — identical to passing a `.heist` package or
  `.json` IR.
- `heist-plan compile Flow.swift --entry makeHeist --output Flow.heist` compiles
  and persists a `.heist` package (or `.json` IR) without running it.

The runtime never compiles Swift. `TheFence`, the MCP server, and `TheInsideJob`
have no knowledge of Swift source — they accept only canonical plan IR. The MCP
`run_heist` tool therefore exposes only the plan schema; there is no `source_file`
input. Compile with the CLI or `heist-plan`, then run the resulting plan.

There is no runtime Swift execution and no hidden fallback: a Swift source either
compiles to an admissible `HeistPlan` ahead of time or the command fails.

### Resolving built ThePlans artifacts

Compiling Swift source links the user file against a **built** `ThePlans`
module. Resolution runs in this order:

1. **`HEIST_THEPLANS_BUILD_DIR`** — the deterministic override. Set it to a
   SwiftPM build directory containing `Modules/ThePlans.swiftmodule` and
   `ThePlans.build/*.swift.o`, or an Xcode products directory containing
   `ThePlans.framework`. This is what CI uses for SwiftPM command-line
   compilation:

   ```bash
   swift build --package-path ButtonHeist --product heist-plan
   HEIST_THEPLANS_BUILD_DIR=ButtonHeist/.build/debug \
     heist-plan compile Flow.swift --entry makeHeist --output Flow.heist
   ```

2. **Local package discovery** — absent the override, the local ButtonHeist
   checkout's `.build` directories are searched for the same artifacts.

3. **Xcode products discovery** — Xcode/Tuist test runs can also compile
   against a products directory containing `ThePlans.framework`. The compiler
   checks standard Xcode build environment variables and the running test
   executable's ancestor directories.

The compiler never builds `ThePlans` from source on demand. If no built
artifacts are found, compilation fails with a diagnostic that lists every path
that was searched and tells you to run
`swift build --package-path ButtonHeist --product heist-plan` (or set
`HEIST_THEPLANS_BUILD_DIR`). In Xcode/Tuist tests, the diagnostic also lists
candidate products directories. Set `HEIST_SOURCE_COMPILER_TRACE=1` to trace
which resolution branch was taken.

## Explicit Non-Goals

Swift Heist does not preserve:

- native Swift loop intent unless the source used Button Heist `ForEach`
- arbitrary helper functions or closure structure
- comments, whitespace, imports, or local constants
- hidden pre-action viewport movement for semantic actions
- viewport/debug commands as durable action steps
- arbitrary dynamic code over the wire
- generic variables beyond scoped `target_ref` and string refs

The durable language intentionally excludes unbounded loops, sleeps, retries,
catch/recover flow, and unknown JSON keys. Runtime admission rejects unsafe or
unexecutable plans; lint reports quality issues such as missing expectations or
mechanical commands in strict semantic tests.
