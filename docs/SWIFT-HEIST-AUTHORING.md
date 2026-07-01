# Swift Heist Authoring Boundary

`HeistPlan` is The Button Heist durable DSL artifact boundary. Canonical heist
source is the runtime text form of that language; it is parsed by ThePlans and
never by `swiftc`. Swift files are a trusted local authoring frontend that MAY
generate a validated `HeistPlan`, but arbitrary Swift structure is not itself
durable heist language.

Treat checked-in Swift files like product code, but keep the boundary explicit:
Swift may wrap, select, name, organize, and call heists outside the DSL. If a
behavior must survive `.heist`, catalog discovery, MCP composition, replay, or
canonical rendering, it MUST lower to a durable `HeistPlan` expressed as
`HeistDef`, `RunHeist`, `If`, `WaitFor`, `ForEach`, `Warn`, `Fail`, actions,
targets, and expectations. Durable loops must use The Button Heist's explicit
`ForEach` primitive, not native Swift `for`.

`HeistPlan` is the execution model. Humans may author rich Swift DSL files that
build a `HeistPlan`. Agents SHOULD prefer canonical heist source strings when
sending compact heists through MCP. Generated `.heist` package directories are
durable artifacts that store `manifest.json` and canonical `plan.json`.
Standalone `.json` files are generated runtime wire IR for diagnostics and
tooling; they are not the authoring language. Public MCP tools advertise only
durable `plan` source strings and `.heist` artifact `path`s, not raw wire IR
fields or direct viewport/debug/session commands.

Decoding `.json` IR or a `.heist` package reconstructs an executable
`HeistPlan` with the body, targets, arguments, and expectations required for
runtime execution. `ThePlans` can render that AST back to canonical Swift DSL.
Canonical rendering preserves semantic meaning, not arbitrary authorship
details. In particular, JSON does not recover:

- helper functions or builder structure
- comments
- local variables, constants, or their names
- source grouping, whitespace, formatting, or review intent

At runtime, The Button Heist executes only `HeistPlan`. Swift result builders are
convenience for building AST values; they are not the language contract and do
not preserve Swift source structure. Canonical heist source is the constrained
runtime authoring language accepted by `run_heist(plan:)` when it parses to a
durable plan; `.json` is internal/generated raw IR; `.heist` is a durable
generated package artifact. Swift DSL, canonical source, and canonical plan JSON
are projections of the same AST. That AST
belongs to the broader [Accessibility Contract](ACCESSIBILITY-CONTRACT.md):
semantic intent enters the runtime and settled semantic evidence comes back.

Reusable heist helpers that should survive JSON must be written as heist
definitions, not arbitrary Swift functions:

```swift
let heist = try HeistPlan("purchaseFlow") {
    HeistDef<String>("LibraryScreen.addToCart", parameter: "item") { item in
        Activate(.label(item))

        Activate(.label("Add to Cart"))
            .expect(.exists(.label("Cart")))
    }

    RunHeist("LibraryScreen.addToCart", "Milk")
    RunHeist("LibraryScreen.addToCart", "Bread")
}
```

Swift wrappers can still factor source outside the DSL. If you want Swift, wrap
the heist in Swift:

```swift
func checkoutPlan() throws -> HeistPlan {
    try HeistPlan("purchaseFlow") {
        HeistDef<String>("LibraryScreen.addToCart", parameter: "item") { item in
            Activate(.label(item))
            Activate(.label("Add to Cart"))
        }

        RunHeist("LibraryScreen.addToCart", "Milk")
    }
}
```

`HeistDef` bodies carry their definition dependency and invocation path into
`HeistPlan`. Canonical rendering can reproduce equivalent definitions and
invocations, but it does not preserve arbitrary helper function names, source
grouping, comments, local constants, or native Swift calls.

## Swift test runner boundary

In app and UI tests, Swift calls the job and The Button Heist describes the job. The
host-language runner boundary is:

```swift
import ButtonHeistTesting

try await runHeist("addToCart", argument: "Milk") { item in
    Activate(.label(item))
    Activate(.label("Add to Cart"))
        .expect(.exists(.label("Cart")))
}
```

Outside `runHeist(...) { ... }` is Swift: tests may choose data, await the
receipt, and assert on failures. Inside the closure is heist source that
lowers to `HeistPlan`, validates through the normal plan contract, executes
through the in-app heist runtime, and returns the normal receipt.

For app-hosted XCTest/KIF-style targets, `runHeistSync(...) { ... }` provides
the same in-process execution without making
the test method `async`. They run the heist on the main actor, pump the main run
loop, and report failures with `XCTFail` at the call site. Use this path when
your test host shares teardown machinery with KIF/RKT-style app tests; async
XCTest teardown can race app cleanup in those targets.

Passing runs can record receipts without relying on inherited environment
variables:

```swift
func testCheckoutCompletes() {
    runHeistSync("Checkout.pay", recordReceipt: .always, to: receiptsURL) {
        Activate(.label("Pay"))
            .expect(.appeared(.label("Payment Complete")))
    }
}
```

If no URL is supplied, explicit sync-test receipts are written under the process
temporary directory at `buttonheist-receipts/`.

`RunHeist(...)` composes inside durable plans. `runHeist(...)` executes a heist
now from Swift tests. `run_heist` crosses the CLI/MCP tool boundary.

To stop at a screen, open a ButtonHeist session, and let a human or agent
connect through MCP or the CLI, halt a synchronous XCTest after ordinary app
navigation:

```swift
func test_PARACHUTE_driveCheckout() {
    logIn()
    navigateToCheckout()
    joinHeist(token: "probe", port: 1456)
}
```

`joinHeist` defaults to simulator loopback only. Pass `allowedScopes:
ConnectionScope.default` to accept simulator and USB clients, or
`allowedScopes: ConnectionScope.all` when LAN clients are intentional.

The helper starts a fresh InsideJob server, prints a ready line after the
listener reports its bound port, then halts test progression while pumping the
run loop so the client can interact with the live app. Bazel-launched simulators
may still need external port forwarding from the host; the app process can
report the bound simulator-side port but cannot create that host bridge itself.

Inside a durable plan, `RunHeist("Name", argument)` is the composition step
that invokes a named reusable heist. It is not a Swift helper call:

```swift
HeistPlan("purchaseFlow") {
    RunHeist("LibraryScreen.addToCart", "Milk")
}
```

Semantic actions should describe user intent and expected semantic outcome:

```swift
HeistPlan {
    TypeText("milk", into: .label("Search"))
        .expect(.exists(.element(.label("Search"), .value("milk"))))

    Activate(.label("Delete"))
        .expect(.missing(.label("Delete")))
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
  viewport/debug/session action steps, and empty branches as
  test quality failures.

Mechanical commands are explicit escape hatches. Use the namespace to make that
intent visible:

```swift
Mechanical.Tap(x: 120, y: 400)
```

Viewport/debug/session commands such as `scroll`, `scroll_to_edge`, and
`scroll_to_visible` are direct client commands, not durable Swift Heist
primitives. Normal semantic actions do not need pre-action viewport movement.
`Activate`, `TypeText`, `Increment`, `Decrement`, custom actions, and rotors own
reveal, element inflation, and live geometry through the runtime pipeline.

```swift
CustomAction("Archive", on: .label("Message"))
    .expect(.change(.elements()))

TypeText("Bruschetta", into: .label("Search Items"))
    .expect(.exists(.element(.label("Search Items"), .value("Bruschetta"))))

Increment(.label("Quantity"))
    .expect(.updated(.label("Quantity"), .value(before: "2", after: "3")))

Increment(.label("Volume"))
    .until(.exists(.element(label: "Volume", value: "100")), timeout: .seconds(5))

Rotor("Headings", on: .label("Article"), direction: .next)
    .withoutExpectation("Navigation cursor only")
```

String predicates are exact by default. `Activate(.label("Search"))` matches
the label `Search` with case and typography folding; it does not match
`Search results`. This applies to every element string predicate field:
`label`, `identifier`, and `value`. Prefer exact labels, identifiers, values,
and traits when they name the intended control clearly.

When converting a loose text selector, use an explicit broad match so the
looseness stays visible in review:

```swift
Activate(.label(.contains("Search")))

WaitFor(.element(
    label: .contains("No results"),
    identifier: .contains("empty_state"),
    value: .contains("0 items")
), timeout: .seconds(2))
```

`StringMatch` cases `.contains`, `.prefix`, and `.suffix` work on all element string predicate fields
and require non-empty strings. They are opt-in matching modes, not a fallback
for failed exact predicates.

To require multiple ordered checks, use repeated checks in `.element(...)`:

```swift
Activate(.element(
    .label(.prefix("foo")),
    .label(.contains("bar")),
    .label(.suffix("baz")),
    .traits([.button]),
    .excludeTraits([.notEnabled])
))
```

All checks must pass in order. Contradictory checks are valid source but cannot
match any element in practice.

Use `.updated(...)` for explicit same-screen property-delta assertions in
action expectations. The first argument may be an element matcher and the second
argument is the property change matcher. Use `before:` and `after:` when the
previous value matters; use the unlabeled form for a destination-only value. For
example, `.value("3")` is exact and `.value(.contains("items"))` is explicitly broad.
This remains an observed-change predicate for `.expect(...)` and does not infer
the action's target from hidden context.

When text entry or validation can reflow the interface, prefer a settled-state
assertion such as `.exists(.element(..., .value(...)))` or a `WaitFor(...)`
over `.updated(...)`. Keep `.updated(...)` for changes that should remain
same-screen element deltas.

`.expect(.updated(...))` lowers to an element-change predicate. Include an
explicit element matcher when the assertion must be tied to a durable element:
`.updated(.label("Quantity"), .value(before: "2", after: "3"))`.

Standalone `WaitFor(...)` is final-state oriented. Transition predicates still
communicate intent, but `WaitFor(.appeared(...))`,
`WaitFor(.disappeared(...))`, and `WaitFor(.updated(...))` can pass with a
warning when their implied final state is already true or becomes true without
an observed transition. Use snapshot predicates for destination state after an
action when the transition itself does not matter.

Use `.screenChanged(...)` for navigation. Assertions inside `screenChanged` are
destination snapshot assertions, not element-delta predicates:
`.screenChanged(.exists(.label("Receipt")))`. Do not put `.appeared(...)`,
`.disappeared(...)`, or `.updated(...)` inside `.screenChanged(...)`.

`ForEach` has two durable authoring forms:

```swift
ForEach(.label("Delete"), limit: 20) { target in
    Activate(target)
        .expect(.missing(target), timeout: .seconds(2))
}

ForEach("Milk", "Eggs") { item in
    TypeText(item, into: .label("Add item"))
        .expect(.exists(.label(item)), timeout: .seconds(2))
}
```

Do not use native Swift `for` inside `HeistPlan {}` or any nested DSL body. The
heist source compiler does not lower native loops because native loops flatten
at authoring time and lose loop intent. If a loop should survive JSON, write
`ForEach`.

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

## Compilation boundary

Swift compilation is an **author-time** step, not a runtime capability. It lives
only in the authoring tools:

- `buttonheist run_heist Flow.swift --entry makeHeist` compiles the Swift source
  to a `HeistPlan`, validates that plan for runtime behavior, then sends it down
  the ordinary `run_heist` path — identical to passing a durable `.heist`
  package or canonical ButtonHeist `HeistPlan` source.
- `heist-plan compile Flow.swift --entry makeHeist --output Flow.heist` compiles
  and persists a `.heist` package (or `.json` IR) without running it.

The runtime never compiles arbitrary Swift. Local `.swift` files remain authoring
tool inputs only: compile them with the CLI or `heist-plan`, then run the
resulting plan or artifact.

For MCP, `run_heist` accepts durable ButtonHeist source via the `plan` field.
The top-level source MUST parse to a `HeistPlan`. That string is not sent to
`swiftc` and is not executed as Swift. It is parsed by ThePlans as constrained
ButtonHeist source, lowered to a `HeistPlan`, and validated through the same
runtime plan pipeline as `.heist` artifacts and compiled Swift authoring output.
The MCP tool still does not expose local Swift authoring inputs such as
`source_file` or `entry`, and it MUST NOT accept direct viewport/debug/session
commands or raw wire IR as heist source.

This runtime compiler accepts only ButtonHeist DSL constructs: semantic and
durable mechanical actions, expectations and expectation waivers, `If`,
`WaitFor`, `Case`, `Else`, `ForEach`, `RunHeist`, `Warn`, `Fail`, canonical
`HeistDef` definitions, and the `HeistPlan { ... }` root wrapper emitted by
canonical rendering. It rejects arbitrary Swift such as imports, variables,
functions, native `if`/`for`/`while`/`switch`, interpolation, custom calls,
body-local `try`, `await`, package imports, and unbounded loops. Agents should
send the full canonical source returned by `canonicalSwiftDSL()`. Body-only
statement snippets are not a supported authored surface.

Canonical sugar may elide an implied wrapper when the remaining spelling is the
same DSL concept: `Activate(.label("Pay"))` is shorthand for a target built from
the `.label("Pay")` predicate, `WaitFor(.label("Pay"))` is shorthand for an
element existence predicate, and `.expect(.appeared(.label("Toast")))` is
shorthand for an element-change assertion. Sugar must stay local and
unambiguous; write `.screenChanged` or
`.screenChanged(.exists(.label("Receipt")))` for navigation, and use
`.appeared(...)`, `.disappeared(...)`, or `.updated(...)` only for same-screen
element deltas.

There is no runtime Swift execution and no hidden fallback: a local Swift file
either compiles to an admissible `HeistPlan` ahead of time or the command fails.

### Resolving built ThePlans artifacts

Compiling Swift source links the user file against a **built** `ThePlans`
module. Resolution runs in this order:

1. **`HEIST_THEPLANS_BUILD_DIR`** — the deterministic override. Set it to a
   SwiftPM build directory containing `Modules/ThePlans.swiftmodule` or
   `Modules/ThePlans.swiftinterface`, plus `ThePlans.build/*.swift.o`; or set it
   to an Xcode products directory containing `ThePlans.framework`. This is what
   CI uses for SwiftPM command-line compilation:

   ```bash
   swift build --package-path ButtonHeist --product heist-plan
   HEIST_THEPLANS_BUILD_DIR=ButtonHeist/.build/debug \
     heist-plan compile Flow.swift --entry makeHeist --output Flow.heist
   ```

2. **Installed compiler artifacts** — The Homebrew distribution supports Apple
   Silicon macOS only. It installs `heist-plan` next to `buttonheist` and
   installs the arm64 `ThePlans` build artifacts under `lib/ThePlans`. The
   installed artifact uses `ThePlans.swiftinterface`, not a binary
   `ThePlans.swiftmodule`, so the user's active Swift compiler rebuilds the
   importable module for its own toolchain. The artifact also includes
   `description.json` so the compiler can link the active ThePlans object list
   after installation. From that install shape, `.swift` heists compile without a
   ButtonHeist checkout or environment variable:

   ```bash
   buttonheist run_heist --path Flow.swift --entry makeHeist
   heist-plan compile Flow.swift --entry makeHeist --output Flow.heist
   ```

3. **Local package discovery** — absent the override, the local ButtonHeist
   checkout's `.build` directories are searched for the same artifacts.

4. **Xcode products discovery** — Xcode/Tuist test runs can also compile
   against a products directory containing `ThePlans.framework`. The compiler
   checks standard Xcode build environment variables and the running test
   executable's ancestor directories.

The compiler never builds `ThePlans` from source on demand. If no built
artifacts are found, compilation fails with a diagnostic that lists every path
that was searched and tells you to install The Button Heist with compiler artifacts,
run `swift build --package-path ButtonHeist --product heist-plan`, or set
`HEIST_THEPLANS_BUILD_DIR`. In Xcode/Tuist tests, the diagnostic also lists
candidate products directories. Set `HEIST_SOURCE_COMPILER_TRACE=1` to trace
which resolution branch was taken.

## Explicit non-goals

Swift Heist does not preserve:

- native Swift loop intent unless the source used The Button Heist `ForEach`
- arbitrary helper functions or closure structure
- comments, whitespace, imports, or local constants
- hidden pre-action viewport movement for semantic actions
- viewport/debug/session commands as durable action steps
- arbitrary dynamic code over the wire
- raw JSON wire IR as the agent-facing authoring format
- generic variables beyond scoped `target_ref` and string refs

The durable language intentionally excludes unbounded loops, sleeps, retries,
catch/recover flow, and unknown JSON keys. Runtime admission rejects unsafe or
unexecutable plans; lint reports quality issues such as missing expectations or
mechanical commands in strict semantic tests.
