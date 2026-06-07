# Button Heist MCP Agent Guide

Button Heist drives iOS apps through the accessibility layer — the same interface VoiceOver uses. You interact with live UI elements by their identity and traits, not screen coordinates. A coordinate that works on one device breaks on another; an element's label and traits work everywhere.

## Core Loop

1. **Read** — `get_interface` returns the app accessibility state with labels, values, traits, actions, and capture-local diagnostic annotations.
2. **Act** — use `perform(step:)` with one ButtonHeist DSL step for ordinary app controls. Always attach `.expect(...)` when you know what should change.
3. **Read the response** — action responses carry trace-backed result evidence. If the delta answers your question, skip `get_interface`.
4. **Wait if needed** — when the delta shows a transient state, call `perform(step:)` with one simple `WaitFor(...)` statement. The server checks the current settled state first, then watches settled accessibility state until the predicate is true.
5. **Repeat** — only re-fetch when you need elements you haven't seen.

## Choosing Tools

**Observing**: `get_interface` for element data, `get_screen` for visual context plus fresh visible geometry. Start with `get_interface`; it returns the app accessibility state for the current screen, including content Button Heist can discover in scroll views. Pass `subtree.element` to project from a leaf, or `subtree.container` with a current `containerName` to inspect a container. `containerName` is ButtonHeist's generated name for a container in the current interface capture. It is useful for inspection. It is not a semantic target or durable heist selector. Reach for `get_screen` when layout, pixels, or the current viewport geometry matters.

**Acting**: `perform(step:)` is the single-step control surface. It wraps your `step` as `HeistPlan { <step> }`, compiles it through ThePlans, requires the compiled body to contain exactly one eligible step, then executes that plan through the normal heist runtime.

Allowed `perform(step:)` statements are one primitive action or one simple wait:

```swift
Activate(.label("Pay")).expect(.changed(.screen()))
TypeText("milk", into: .label("Search")).expect(.changed(.elements))
Increment(.label("Quantity"))
Decrement(.label("Quantity"))
CustomAction("Archive", on: .label("Message"))
Rotor("Headings", on: .label("Article"))
SetPasteboard("hello")
Edit(.paste)
DismissKeyboard()

Mechanical.Tap(.label("Map"))
Mechanical.LongPress(.label("Message"))
Mechanical.Swipe(.label("Carousel"), .left)
Mechanical.Drag(.label("Slider"), to: .point(x: 200, y: 40))

WaitFor(.present(.label("Checkout")), timeout: 5)
```

`perform(step:)` rejects program-shaped source: multiple statements, `HeistPlan`, `HeistDef`, `RunHeist`, `If`, `WaitFor { ... } Else { ... }`, `ForEach`, `Warn`, and `Fail`. Use `run_heist(plan:)` for those.

**Targets**: element actions share one target grammar:

```swift
.label("Pay")
.identifier("pay_button")
.value("Milk")
.element(label: "Pay", traits: [.button])
.target(.element(label: "Delete"), ordinal: 1)
```

Ordinal belongs inside the target:

```swift
Activate(.target(.label("Pay"), ordinal: 0))
```

Do not write action-level ordinals:

```swift
Activate(.label("Pay"), ordinal: 0)
```

**Waiting**: use `perform(step:)` with simple `WaitFor(...)` when the UI is updating asynchronously — network requests, timers, animations completing. The predicate should name the specific outcome:

```swift
WaitFor(.changed(.screen()), timeout: 10)
WaitFor(.present(.label("Receipt")), timeout: 5)
WaitFor(.absent(.label("Loading")), timeout: 10)
```

For `.absent(...)`, the predicate means the element is absent from the current settled hierarchy. It does not require Button Heist to prove the element existed and then vanished.

**Composing**: `run_heist` for typed multi-step plans in a single call. Prefer the `plan` field with canonical ButtonHeist source when authoring compact heists as an agent:

```swift
HeistPlan {
    Activate(.label("Pay"))
        .expect(.changed(.screen()))

    TypeText("milk", into: .label("Search"))
        .expect(.present(.element(label: "Search", value: "milk")))
}
```

Use `run_heist(plan:)` for definitions, composition, branching, waits with bodies, loops, warnings, failures, or multiple steps:

```swift
HeistPlan("shop") {
    HeistDef<String>("Cart.addItem", parameter: "item") { item in
        TypeText(item, into: .label("Search"))
            .expect(.changed(.elements))
        Activate(.label("Add"))
            .expect(.present(.label("Added")))
    }

    RunHeist("Cart.addItem", "Milk")

    If(.present(.label("Pay"))) {
        Activate(.label("Pay"))
            .expect(.changed(.screen()))
    } Else {
        Warn("Pay button unavailable")
    }
}
```

The `plan` string is ButtonHeist source, not arbitrary Swift. It accepts the canonical DSL constructs rendered by Button Heist and rejects imports, variables, functions, native Swift control flow, interpolation, custom calls, body-local `try`, `await`, and unbounded loops. JSON plan IR is internal/generated; use source for compact authoring unless you are passing a generated `.heist` artifact path.

Use the same source string for discovery before execution. `list_heists(plan:)` shows the root entry and reusable `HeistDef` capabilities; `describe_heist(plan:)` describes one of those entries. These examples are copyable into `run_heist(plan:)` by removing the discovery-specific fields:

```text
list_heists detail="detailed" plan: """
HeistPlan("shop") {
    HeistDef<String>("Cart.addItem", parameter: "item") { item in
        Activate(.label(item))
    }

    RunHeist("Cart.addItem", "Milk")
}
"""
```

```text
describe_heist heist="Cart.addItem" plan: """
HeistPlan("shop") {
    HeistDef<String>("Cart.addItem", parameter: "item") { item in
        Activate(.label(item))
    }

    RunHeist("Cart.addItem", "Milk")
}
"""
```

Do not author heists as raw `version`/`name`/`parameter`/`definitions`/`body` JSON. That shape is internal IR for generated artifacts, storage, wire transport, and debugging.

## Trace Semantics

Screen changes create full baselines. Same-screen changes are patches on top of the current baseline.

Actions can refresh off-screen state by exploring scroll views before or after the interaction, but that exploration is not a screen boundary by itself. It only broadens Button Heist's current-screen knowledge. If the app stays on the same screen, the action result is still an elements-changed patch; if Button Heist detects a real screen change, the trace starts a new full baseline.

`get_interface` returns app state. A default call may refresh discoverable off-screen content so the returned hierarchy is current. Passing `subtree` scopes that projection to the part of the hierarchy you asked for. `get_screen` is diagnostic: it returns pixels plus fresh visible geometry for the current viewport, not a replacement for the app-state hierarchy.

## Local MCP Development

Use this workflow when testing a worktree-local `ButtonHeistMCP` change through an MCP host.

**Build the worktree binary:**

```bash
cd ButtonHeistMCP
swift build -c release
```

The release binary is written to `ButtonHeistMCP/.build/release/buttonheist-mcp` in the current worktree.

**Know what `.mcp.json` loads.** The repo config starts `buttonheist` with `./scripts/buttonheist-mcp.sh`. That wrapper resolves its own directory, treats the parent as the repo root, and `exec`s that worktree's release binary. It does not build the server, choose a device, or rewrite environment variables; the MCP host's environment is inherited by the server process.

Start the MCP host or agent from the worktree you are testing. If a host loaded `.mcp.json` from another checkout, its relative `./scripts/buttonheist-mcp.sh` may still point at that checkout until the MCP session is restarted.

**Set target environment before starting the MCP host:**

- `BUTTONHEIST_DEVICE`: discovered device name, named target, or direct `host:port`. Use `127.0.0.1:<port>` for simulator direct-connect sessions that bypass Bonjour.
- `BUTTONHEIST_TOKEN`: auth token from `TheInsideJob`.
- `BUTTONHEIST_DRIVER_ID`: stable driver identity for session locking. Use a unique value per agent/session when multiple clients share a token.

Exporting these variables after the host has already launched does not update an already-running MCP server process. Start a fresh MCP session or agent after changing the target environment.

**Reload after rebuilds.** MCP hosts usually keep the server process alive for the lifetime of the loaded MCP session. Rebuilding `ButtonHeistMCP` updates the binary on disk, but an already-loaded server keeps running the old code. End the MCP session or start a fresh agent/host from this worktree after each rebuild. If tool behavior still matches the previous build after restarting, verify the host resolved `.mcp.json` from the correct worktree.

**Run against a simulator endpoint:**

```bash
TASK_SLUG="mcp-reload-debug"
SIM_UDID=$(xcrun simctl create "$TASK_SLUG" "iPhone 16 Pro")
xcrun simctl boot "$SIM_UDID"
xcrun simctl bootstatus "$SIM_UDID" -b

xcodebuild -workspace ButtonHeist.xcworkspace -scheme "BH Demo" \
  -destination "platform=iOS Simulator,id=$SIM_UDID" build
APP=$(ls -td ~/Library/Developer/Xcode/DerivedData/ButtonHeist*/Build/Products/Debug-iphonesimulator/BHDemo.app | head -1)
xcrun simctl install "$SIM_UDID" "$APP"

INSIDEJOB_PORT=$((RANDOM % 10000 + 20000))

SIMCTL_CHILD_INSIDEJOB_PORT="$INSIDEJOB_PORT" \
SIMCTL_CHILD_INSIDEJOB_TOKEN="$TASK_SLUG" \
SIMCTL_CHILD_INSIDEJOB_ID="$TASK_SLUG" \
xcrun simctl launch "$SIM_UDID" com.buttonheist.testapp

export BUTTONHEIST_DEVICE="127.0.0.1:$INSIDEJOB_PORT"
export BUTTONHEIST_TOKEN="$TASK_SLUG"
export BUTTONHEIST_DRIVER_ID="$TASK_SLUG"
```

Then start the MCP host or agent from this worktree so `.mcp.json` resolves to the same build. For a one-off stdio smoke check outside a host:

```bash
BUTTONHEIST_DEVICE="127.0.0.1:$INSIDEJOB_PORT" \
BUTTONHEIST_TOKEN="$TASK_SLUG" \
BUTTONHEIST_DRIVER_ID="$TASK_SLUG" \
./scripts/buttonheist-mcp.sh
```

When the session is done, shut down and delete the dedicated simulator:

```bash
xcrun simctl shutdown "$SIM_UDID"
xcrun simctl delete "$SIM_UDID"
```

## Async Changes

For operations that take time (payments, network requests):
1. `activate target={"label":"Pay","traits":["button"]} expect={"type":"screen_changed"}` — perform accessibility activation and declare the expected outcome
2. Delta shows spinner, expectation not met → `wait predicate={"type":"screen_changed"}` — server waits until the real screen arrives

## Expectations

Every action is an opportunity to validate. Attaching `expect` costs nothing — the action runs the same way — but turns a command into a verified assertion. Agents that use expectations routinely catch regressions as a side effect of navigation. Agents that do not use expectations are throwing away evidence.

Before you act, ask: what should change? A toggle flips a value. A nav button changes the screen. A delete removes an element. Form that hypothesis, attach it, and let the result confirm or correct you. Unmet expectations are information, not errors — they tell you what actually happened so you can adapt.

Expectations are as specific as you need — say what you know, omit what you don't:
- `{"type": "elements_changed"}` — something should change (broadest).
- `{"type": "element_updated"}` — some element's property should change.
- `{"type": "element_updated", "element": {"label": "Counter"}}` — this specific element should change.
- `{"type": "element_updated", "element": {"label": "Counter"}, "property": "value"}` — its value specifically.
- `{"type": "element_updated", "element": {"label": "Counter"}, "property": "value", "to": "5"}` — and it should become "5".

Each level narrows what counts as success. The more specific, the more a failure tells you.

## Authoring Heists

Heists are authored reusable instructions, not logs inferred from live clicking. Use `run_heist(plan:)` for multi-step flows and keep expectations in the source whenever the app should prove a state change.

**Attach expectations to every meaningful action.** A heist without expectations is only a sequence of commands; a heist with expectations is a self-verifying test suite that validates on every replay.

**One action, one purpose.** Each step should do exactly one thing and verify it. Do not chain five interactions and check at the end — check after each one. This makes replay failures precise: step 7 failed means the 7th interaction broke.

**Read the delta before moving on.** If your expectation wasn't met, understand why before continuing. The receipt gives you the evidence to correct the next step or revise the authored plan.

## Efficiency

Read the delta first — skip `get_interface` when the delta already told you what changed. Use semantic matcher fields from the current screen; after navigation, build targets from the new delta or interface evidence. Pass `subtree` when you only need one subtree or one leaf from the current hierarchy.
