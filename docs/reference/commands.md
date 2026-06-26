# ButtonHeist Command Reference

_Generated from `TheFence.Command.descriptors`._

## Summary

| Command | Family | CLI | MCP | Description |
|---------|--------|-----|-----|-------------|
| `activate` | `semanticAction` | `activate` | - | Perform primary accessibility activation on a semantic UI element, or one of its named accessibility actions. |
| `connect` | `session` | `connect` | direct | Establish or switch the active connection to a Button Heist app. |
| `describe_heist` | `heistRuntime` | `describe_heist` | direct | Describe one root entry or reusable heist from a plan so an agent can call it safely. |
| `dismiss_keyboard` | `semanticAction` | `dismiss_keyboard` | - | Dismiss the on-screen keyboard through the current first responder or keyboard action path. |
| `drag` | `spatialAction` | `drag` | - | Explicit mechanical/spatial drag using exactly one typed intent: elementToPoint (activation point or unit start override) or pointToPoint. |
| `edit_action` | `semanticAction` | `edit_action` | - | Perform an edit action on the current first responder. |
| `get_interface` | `observation` | `get_interface` | direct | Read the app accessibility hierarchy, optionally scoped to a subtree. |
| `get_pasteboard` | `observation` | `get_pasteboard` | direct | Read text from the general pasteboard. |
| `get_screen` | `observation` | `get_screen` | direct | Capture a PNG screenshot with visible interface state. |
| `get_session_state` | `session` | `get_session_state` | direct | Inspect connection, device, and last-action session state. |
| `list_devices` | `session` | `list_devices` | - | List discovered iOS devices and configured connection targets. |
| `list_heists` | `heistRuntime` | `list_heists` | direct | List the root entry and reusable heists in a plan. Use `detail: "detailed"` when composing against available capabilities. |
| `list_targets` | `session` | `list_targets` | - | List configured connection targets and the default target. |
| `long_press` | `spatialAction` | `long_press` | - | Explicit mechanical/spatial long press. Element targets dispatch at their activation point unless unitPoint supplies an element-frame override; point supplies a raw screen coordinate. |
| `one_finger_tap` | `spatialAction` | `one_finger_tap` | - | Explicit mechanical/spatial tap. Element targets dispatch at their activation point unless unitPoint supplies an element-frame override; point supplies a raw screen coordinate. ordinary accessible controls should use the semantic command path. |
| `perform` | `heistRuntime` | - | direct | Run one ButtonHeist DSL instruction from `step`: one action or one simple wait. |
| `ping` | `session` | `ping` | - | Check connection health without reading accessibility state. |
| `rotor` | `semanticAction` | `rotor` | - | Move through an element rotor by direction. The server holds the rotor cursor while in rotor mode (entering at the first item); any other interaction exits rotor mode and drops the cursor. |
| `run_heist` | `heistRuntime` | `run_heist` | direct | Run a full heist from ButtonHeist DSL source in `plan`, or from a generated `.heist` package at `path`. |
| `scroll` | `viewportDebug` | `scroll` | - | Explicit viewport/debug operation: scroll one page in the visible viewport, within a semantic target's owning scroll ancestor, or for direct debug requests, within a current containerName. |
| `scroll_to_edge` | `viewportDebug` | `scroll_to_edge` | - | Explicit viewport/debug operation: scroll the visible viewport, a semantic target's owning scroll ancestor, or for direct debug requests, a current containerName, to a requested edge. |
| `scroll_to_visible` | `viewportDebug` | `scroll_to_visible` | - | Explicit viewport/debug operation: move the viewport until a semantic target is visible and report its fresh geometry. |
| `set_pasteboard` | `semanticAction` | `set_pasteboard` | - | Write text to the general pasteboard from within the app. |
| `swipe` | `spatialAction` | `swipe` | - | Explicit mechanical/spatial swipe using exactly one typed intent: elementDirection, elementUnitPoints, pointToPoint, or pointDirection. |
| `type_text` | `semanticAction` | `type_text` | - | Type non-empty text. With an element target, Button Heist resolves and reveals the field before focusing it. |
| `wait` | `assertion` | `wait` | - | Assert that an accessibility predicate is satisfied within timeout by evaluating settled accessibility state. |

## StringMatch

`stringMatch` fields such as `label`, `identifier`, `value`, and update `from`/`to` filters accept object form `{ "mode": "exact|contains|prefix|suffix", "value": "..." }`. Use `exact` for exact matching; broad modes require a non-empty value. Element matcher fields `label`, `identifier`, and `value` may also accept an array of StringMatch objects; every object in the array must match the same property. Prefer `checks` for ordered element predicate chains, including repeated string checks and trait checks. A string check item is `{ "kind": "label|identifier|value", "match": { "mode": "...", "value": "..." } }`; a trait check item is `{ "kind": "traits|excludeTraits", "values": ["button"] }`. Update `from` and `to` filters remain single StringMatch objects.

## Details

### `activate`

Perform primary accessibility activation on a semantic UI element, or one of its named accessibility actions.

- Family: `semanticAction`
- CLI: direct command `activate`
- MCP: not exposed
- Connection before dispatch: yes

Parameters:

| Parameter | Type | Required | Default | Values |
|-----------|------|----------|---------|--------|
| `target` | `object` | no | - | - |
| `action` | `string` | no | - | - |
| `expect` | `object` | no | - | - |
| `timeout` | `number` | no | - | - |

### `connect`

Establish or switch the active connection to a Button Heist app.

- Family: `session`
- CLI: direct command `connect`
- MCP: direct tool
- Connection before dispatch: no

Parameters:

| Parameter | Type | Required | Default | Values |
|-----------|------|----------|---------|--------|
| `target` | `string` | no | - | - |
| `device` | `string` | no | - | - |
| `token` | `string` | no | - | - |

### `describe_heist`

Describe one root entry or reusable heist from a plan so an agent can call it safely.

- Family: `heistRuntime`
- CLI: direct command `describe_heist`
- MCP: direct tool
- Connection before dispatch: no

Parameters:

| Parameter | Type | Required | Default | Values |
|-----------|------|----------|---------|--------|
| `heist` | `string` | yes | - | - |
| `path` | `string` | no | - | - |
| `plan` | `string` | no | - | - |

### `dismiss_keyboard`

Dismiss the on-screen keyboard through the current first responder or keyboard action path.

- Family: `semanticAction`
- CLI: direct command `dismiss_keyboard`
- MCP: not exposed
- Connection before dispatch: yes

Parameters:

| Parameter | Type | Required | Default | Values |
|-----------|------|----------|---------|--------|
| `expect` | `object` | no | - | - |
| `timeout` | `number` | no | - | - |

### `drag`

Explicit mechanical/spatial drag using exactly one typed intent: elementToPoint (activation point or unit start override) or pointToPoint.

- Family: `spatialAction`
- CLI: direct command `drag`
- MCP: not exposed
- Connection before dispatch: yes

Parameters:

| Parameter | Type | Required | Default | Values |
|-----------|------|----------|---------|--------|
| `elementToPoint` | `object` | no | - | - |
| `pointToPoint` | `object` | no | - | - |
| `duration` | `number` | no | - | - |
| `expect` | `object` | no | - | - |
| `timeout` | `number` | no | - | - |

### `edit_action`

Perform an edit action on the current first responder.

- Family: `semanticAction`
- CLI: direct command `edit_action`
- MCP: not exposed
- Connection before dispatch: yes

Parameters:

| Parameter | Type | Required | Default | Values |
|-----------|------|----------|---------|--------|
| `action` | `string` | yes | - | `copy`, `paste`, `cut`, `select`, `selectAll`, `delete` |
| `expect` | `object` | no | - | - |
| `timeout` | `number` | no | - | - |

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
- CLI: direct command `get_interface`
- MCP: direct tool
- Connection before dispatch: yes

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
- CLI: direct command `get_pasteboard`
- MCP: direct tool
- Connection before dispatch: yes

Parameters:

_None._

### `get_screen`

Capture a PNG screenshot with visible interface state.

- Family: `observation`
- CLI: direct command `get_screen`
- MCP: direct tool
- Connection before dispatch: yes

Parameters:

| Parameter | Type | Required | Default | Values |
|-----------|------|----------|---------|--------|
| `output` | `string` | no | - | - |
| `inlineData` | `boolean` | no | - | - |

### `get_session_state`

Inspect connection, device, and last-action session state.

- Family: `session`
- CLI: direct command `get_session_state`
- MCP: direct tool
- Connection before dispatch: no

Parameters:

_None._

### `list_devices`

List discovered iOS devices and configured connection targets.

- Family: `session`
- CLI: direct command `list_devices`
- MCP: not exposed
- Connection before dispatch: no

Parameters:

_None._

### `list_heists`

List the root entry and reusable heists in a plan. Use `detail: "detailed"` when composing against available capabilities.

- Family: `heistRuntime`
- CLI: direct command `list_heists`
- MCP: direct tool
- Connection before dispatch: no

Parameters:

| Parameter | Type | Required | Default | Values |
|-----------|------|----------|---------|--------|
| `detail` | `string` | no | `"summary"` | `summary`, `detailed` |
| `path` | `string` | no | - | - |
| `plan` | `string` | no | - | - |

### `list_targets`

List configured connection targets and the default target.

- Family: `session`
- CLI: direct command `list_targets`
- MCP: not exposed
- Connection before dispatch: no

Parameters:

_None._

### `long_press`

Explicit mechanical/spatial long press. Element targets dispatch at their activation point unless unitPoint supplies an element-frame override; point supplies a raw screen coordinate.

- Family: `spatialAction`
- CLI: direct command `long_press`
- MCP: not exposed
- Connection before dispatch: yes

Parameters:

| Parameter | Type | Required | Default | Values |
|-----------|------|----------|---------|--------|
| `element` | `object` | no | - | - |
| `unitPoint` | `object` | no | - | - |
| `point` | `object` | no | - | - |
| `duration` | `number` | no | - | - |
| `expect` | `object` | no | - | - |
| `timeout` | `number` | no | - | - |

### `one_finger_tap`

Explicit mechanical/spatial tap. Element targets dispatch at their activation point unless unitPoint supplies an element-frame override; point supplies a raw screen coordinate. ordinary accessible controls should use the semantic command path.

- Family: `spatialAction`
- CLI: direct command `one_finger_tap`
- MCP: not exposed
- Connection before dispatch: yes

Parameters:

| Parameter | Type | Required | Default | Values |
|-----------|------|----------|---------|--------|
| `element` | `object` | no | - | - |
| `unitPoint` | `object` | no | - | - |
| `point` | `object` | no | - | - |
| `expect` | `object` | no | - | - |
| `timeout` | `number` | no | - | - |

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
- CLI: not exposed
- MCP: direct tool
- Connection before dispatch: yes

Parameters:

| Parameter | Type | Required | Default | Values |
|-----------|------|----------|---------|--------|
| `step` | `string` | yes | - | - |

### `ping`

Check connection health without reading accessibility state.

- Family: `session`
- CLI: direct command `ping`
- MCP: not exposed
- Connection before dispatch: no

Parameters:

_None._

### `rotor`

Move through an element rotor by direction. The server holds the rotor cursor while in rotor mode (entering at the first item); any other interaction exits rotor mode and drops the cursor.

- Family: `semanticAction`
- CLI: direct command `rotor`
- MCP: not exposed
- Connection before dispatch: yes

Parameters:

| Parameter | Type | Required | Default | Values |
|-----------|------|----------|---------|--------|
| `target` | `object` | no | - | - |
| `rotor` | `string` | no | - | - |
| `rotorIndex` | `integer` | no | - | - |
| `direction` | `string` | no | `"next"` | `next`, `previous` |
| `expect` | `object` | no | - | - |
| `timeout` | `number` | no | - | - |

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
- CLI: direct command `run_heist`
- MCP: direct tool
- Connection before dispatch: yes

Parameters:

| Parameter | Type | Required | Default | Values |
|-----------|------|----------|---------|--------|
| `argument` | `object` | no | - | - |
| `path` | `string` | no | - | - |
| `plan` | `string` | no | - | - |

### `scroll`

Explicit viewport/debug operation: scroll one page in the visible viewport, within a semantic target's owning scroll ancestor, or for direct debug requests, within a current containerName.

- Family: `viewportDebug`
- CLI: direct command `scroll`
- MCP: not exposed
- Connection before dispatch: yes

Parameters:

| Parameter | Type | Required | Default | Values |
|-----------|------|----------|---------|--------|
| `target` | `object` | no | - | - |
| `container` | `string` | no | - | - |
| `direction` | `string` | no | `"down"` | `up`, `down`, `left`, `right` |
| `expect` | `object` | no | - | - |
| `timeout` | `number` | no | - | - |

### `scroll_to_edge`

Explicit viewport/debug operation: scroll the visible viewport, a semantic target's owning scroll ancestor, or for direct debug requests, a current containerName, to a requested edge.

- Family: `viewportDebug`
- CLI: direct command `scroll_to_edge`
- MCP: not exposed
- Connection before dispatch: yes

Parameters:

| Parameter | Type | Required | Default | Values |
|-----------|------|----------|---------|--------|
| `target` | `object` | no | - | - |
| `container` | `string` | no | - | - |
| `edge` | `string` | no | `"top"` | `top`, `bottom`, `left`, `right` |
| `expect` | `object` | no | - | - |
| `timeout` | `number` | no | - | - |

### `scroll_to_visible`

Explicit viewport/debug operation: move the viewport until a semantic target is visible and report its fresh geometry.

- Family: `viewportDebug`
- CLI: direct command `scroll_to_visible`
- MCP: not exposed
- Connection before dispatch: yes

Parameters:

| Parameter | Type | Required | Default | Values |
|-----------|------|----------|---------|--------|
| `target` | `object` | no | - | - |
| `expect` | `object` | no | - | - |
| `timeout` | `number` | no | - | - |

### `set_pasteboard`

Write text to the general pasteboard from within the app.

- Family: `semanticAction`
- CLI: direct command `set_pasteboard`
- MCP: not exposed
- Connection before dispatch: yes

Parameters:

| Parameter | Type | Required | Default | Values |
|-----------|------|----------|---------|--------|
| `text` | `string` | yes | - | - |
| `expect` | `object` | no | - | - |
| `timeout` | `number` | no | - | - |

### `swipe`

Explicit mechanical/spatial swipe using exactly one typed intent: elementDirection, elementUnitPoints, pointToPoint, or pointDirection.

- Family: `spatialAction`
- CLI: direct command `swipe`
- MCP: not exposed
- Connection before dispatch: yes

Parameters:

| Parameter | Type | Required | Default | Values |
|-----------|------|----------|---------|--------|
| `elementDirection` | `object` | no | - | - |
| `elementUnitPoints` | `object` | no | - | - |
| `pointToPoint` | `object` | no | - | - |
| `pointDirection` | `object` | no | - | - |
| `duration` | `number` | no | - | - |
| `expect` | `object` | no | - | - |
| `timeout` | `number` | no | - | - |

### `type_text`

Type non-empty text. With an element target, Button Heist resolves and reveals the field before focusing it.

- Family: `semanticAction`
- CLI: direct command `type_text`
- MCP: not exposed
- Connection before dispatch: yes

Parameters:

| Parameter | Type | Required | Default | Values |
|-----------|------|----------|---------|--------|
| `target` | `object` | no | - | - |
| `text` | `string` | yes | - | - |
| `expect` | `object` | no | - | - |
| `timeout` | `number` | no | - | - |

### `wait`

Assert that an accessibility predicate is satisfied within timeout by evaluating settled accessibility state.

- Family: `assertion`
- CLI: direct command `wait`
- MCP: not exposed
- Connection before dispatch: yes

Parameters:

| Parameter | Type | Required | Default | Values |
|-----------|------|----------|---------|--------|
| `predicate` | `object` | yes | - | - |
| `timeout` | `number` | no | - | - |

