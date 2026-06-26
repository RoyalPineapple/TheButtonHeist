# ButtonHeist MCP Tool Reference

_Generated from `TheFence.Command.descriptors`._

## Summary

| Tool | Family | Description |
|------|--------|-------------|
| `connect` | `session` | Establish or switch the active connection to a Button Heist app. |
| `describe_heist` | `heistRuntime` | Describe one root entry or reusable heist from a plan so an agent can call it safely. |
| `get_interface` | `observation` | Read the app accessibility hierarchy, optionally scoped to a subtree. |
| `get_pasteboard` | `observation` | Read text from the general pasteboard. |
| `get_screen` | `observation` | Capture a PNG screenshot with visible interface state. |
| `get_session_state` | `session` | Inspect connection, device, and last-action session state. |
| `list_heists` | `heistRuntime` | List the root entry and reusable heists in a plan. Use `detail: "detailed"` when composing against available capabilities. |
| `perform` | `heistRuntime` | Run one ButtonHeist DSL instruction from `step`: one action or one simple wait. |
| `run_heist` | `heistRuntime` | Run a full heist from ButtonHeist DSL source in `plan`, or from a generated `.heist` package at `path`. |

## StringMatch

`stringMatch` fields such as `label`, `identifier`, and `value` accept object form `{ "mode": "exact|contains|prefix|suffix", "value": "..." }`. Use `exact` for exact matching; broad modes require a non-empty value. Element matcher fields `label`, `identifier`, and `value` may also accept an array of StringMatch objects; every object in the array must match the same property. Prefer `checks` for ordered element predicate chains, including repeated string checks and trait checks. A string check item is `{ "kind": "label|identifier|value", "match": { "mode": "...", "value": "..." } }`; a trait check item is `{ "kind": "traits|excludeTraits", "values": ["button"] }`. Updated element predicates use full `before` and `after` element matcher objects.

## Details

### `connect`

Establish or switch the active connection to a Button Heist app.

- Family: `session`

Parameters:

| Parameter | Type | Required | Default | Values |
|-----------|------|----------|---------|--------|
| `target` | `string` | no | - | - |
| `device` | `string` | no | - | - |
| `token` | `string` | no | - | - |

### `describe_heist`

Describe one root entry or reusable heist from a plan so an agent can call it safely.

- Family: `heistRuntime`

Parameters:

| Parameter | Type | Required | Default | Values |
|-----------|------|----------|---------|--------|
| `heist` | `string` | yes | - | - |
| `path` | `string` | no | - | - |
| `plan` | `string` | no | - | - |

### `get_interface`

Read the app accessibility hierarchy, optionally scoped to a subtree.

Build DSL targets from returned accessibility language: `.label("Pay")`,
`.identifier("pay_button")`, `.value("Milk")`, `.element(.label("Pay"),
.traits([.button]))`, or `.target(..., ordinal: n)` for duplicates.
Direct matcher fields `label`, `identifier`, and `value` accept StringMatch
objects like `{ "mode": "exact|contains|prefix|suffix", "value": "..." }`,
or an array of those objects when one property needs multiple checks.
Prefer `checks` when order matters or traits belong in the same predicate
chain; each item is `{ "kind": "label|identifier|value|traits|excludeTraits",
"match": StringMatch }` or `{ "kind": "traits|excludeTraits", "values": [...] }`.
`containerName` is for inspection and viewport/debug commands only; it is
not a semantic target or durable heist selector.
`maxScrollsPerContainer` and `maxScrollsPerDiscovery` bound the command-owned
interface discovery pass; omit them to use Inside Job runtime defaults.

- Family: `observation`

Parameters:

| Parameter | Type | Required | Default | Values |
|-----------|------|----------|---------|--------|
| `checks` | `array` | no | - | - |
| `label` | `stringMatch` | no | - | - |
| `identifier` | `stringMatch` | no | - | - |
| `value` | `stringMatch` | no | - | - |
| `traits` | `stringArray` | no | - | - |
| `excludeTraits` | `stringArray` | no | - | - |
| `subtree` | `object` | no | - | - |
| `detail` | `string` | no | - | `summary`, `full` |
| `maxScrollsPerContainer` | `integer` | no | - | - |
| `maxScrollsPerDiscovery` | `integer` | no | - | - |

### `get_pasteboard`

Read text from the general pasteboard.

- Family: `observation`

Parameters:

_None._

### `get_screen`

Capture a PNG screenshot with visible interface state.

- Family: `observation`

Parameters:

| Parameter | Type | Required | Default | Values |
|-----------|------|----------|---------|--------|
| `output` | `string` | no | - | - |
| `inlineData` | `boolean` | no | - | - |

### `get_session_state`

Inspect connection, device, and last-action session state.

- Family: `session`

Parameters:

_None._

### `list_heists`

List the root entry and reusable heists in a plan. Use `detail: "detailed"` when composing against available capabilities.

- Family: `heistRuntime`

Parameters:

| Parameter | Type | Required | Default | Values |
|-----------|------|----------|---------|--------|
| `detail` | `string` | no | `"summary"` | `summary`, `detailed` |
| `path` | `string` | no | - | - |
| `plan` | `string` | no | - | - |

### `perform`

Run one ButtonHeist DSL instruction from `step`: one action or one simple wait.

Examples:
`Activate(.label("Pay")).expect(.change(.screen()))`
`TypeText("milk", into: .label("Search")).expect(.change(.elements()))`
`Increment(.label("Quantity"))`
`Decrement(.label("Quantity"))`
`CustomAction("Archive", on: .label("Message"))`
`Rotor("Headings", on: .label("Article"))`
`SetPasteboard("hello")`
`Edit(.paste)`
`DismissKeyboard()`
`Mechanical.Tap(.label("Map"))`
`Mechanical.Tap(ScreenPoint(x: 888, y: 372))`
`Mechanical.Tap(.label("Map"), at: UnitPoint(x: 0.5, y: 0.25))`
`Mechanical.LongPress(.label("Message"), at: UnitPoint(x: 0.5, y: 0.5))`
`Mechanical.Swipe(.label("Carousel"), .left)`
`Mechanical.Drag(.label("Slider"), to: ScreenPoint(x: 200, y: 40))`
`WaitFor(.exists(.label("Checkout")), timeout: .seconds(5))`

Use `perform` when one line is enough. Use `run_heist` when the job needs
multiple instructions, reusable heists, `RunHeist`, `If`,
`WaitFor(...).else { ... }`, `ForEach`, `Warn`, or `Fail`.

- Family: `heistRuntime`

Parameters:

| Parameter | Type | Required | Default | Values |
|-----------|------|----------|---------|--------|
| `step` | `string` | yes | - | - |

### `run_heist`

Run a full heist from ButtonHeist DSL source in `plan`, or from a generated `.heist` package at `path`.

Author plans as ButtonHeist source, not raw JSON IR:
`HeistPlan("shop") { ... }`
`HeistDef<String>("Cart.addItem", parameter: "item") { item in ... }`
`RunHeist("Cart.addItem", "Milk")`
`If(.exists(.label("Pay"))) { ... }.else { ... }`
`WaitFor(.change(.screen()), timeout: .seconds(10)).else { ... }`
`ForEach(["Milk", "Bread"]) { item in ... }`
`ForEach(.matching(.element(.label(.prefix("Delete")), .traits([.button]))), limit: 20) { target in ... }`
`Warn("message")`
`Fail("message")`

Provide exactly one source: `path` or `plan`. Use `argument` when the root
heist takes a string or element target. Runtime source is restricted
ButtonHeist DSL, not arbitrary Swift.

- Family: `heistRuntime`

Parameters:

| Parameter | Type | Required | Default | Values |
|-----------|------|----------|---------|--------|
| `argument` | `object` | no | - | - |
| `path` | `string` | no | - | - |
| `plan` | `string` | no | - | - |

