# ButtonHeist Command Reference

_Generated from `TheFence.Command.descriptors`._

## Summary

| Command | Family | CLI | MCP | Description |
|---------|--------|-----|-----|-------------|
| `activate` | `semanticAction` | `activate` | direct | Perform primary accessibility activation on a semantic UI element, or one of its named accessibility actions. |
| `connect` | `session` | `connect` | direct | Establish or switch the active connection to a Button Heist app. |
| `describe_heist` | `heistRuntime` | `describe_heist` | direct | Describe one root entry or reusable heist from a runtime-validated plan. The `heist` parameter selects the entry/capability name; the plan is supplied inline (canonical HeistPlan fields: version, name, parameter, definitions, body) or loaded from a `path` to a .heist package artifact. |
| `dismiss_keyboard` | `semanticAction` | `dismiss_keyboard` | direct | Dismiss the on-screen keyboard through the current first responder or keyboard action path. |
| `drag` | `spatialAction` | `drag` | direct | Explicit mechanical/spatial drag using exactly one typed intent: elementToPoint or pointToPoint. |
| `edit_action` | `semanticAction` | `edit_action` | direct | Perform an edit action on the current first responder. |
| `get_interface` | `observation` | `get_interface` | direct | Read the app accessibility hierarchy, optionally scoped to a subtree. |
| `get_pasteboard` | `observation` | `get_pasteboard` | direct | Read text from the general pasteboard. |
| `get_screen` | `observation` | `get_screen` | direct | Capture a PNG screenshot with optional inline data and interface state. |
| `get_session_state` | `session` | `get_session_state` | direct | Inspect connection, device, and last-action session state. |
| `list_devices` | `session` | `list_devices` | direct | List discovered iOS devices and configured connection targets. |
| `list_heists` | `heistRuntime` | `list_heists` | direct | List a summary menu of the root entry and named reusable heists derived from one runtime-validated plan. Set `detail` to `detailed` to include derived command names, nested heist calls, counts, and safe semantic surface summaries. The plan is supplied inline (canonical HeistPlan fields: version, name, parameter, definitions, body) or loaded from a `path` to a .heist package artifact. |
| `list_targets` | `session` | `list_targets` | direct | List configured connection targets and the default target. |
| `long_press` | `spatialAction` | `long_press` | direct | Explicit mechanical/spatial long press on a point or element-relative point for a resolved duration. |
| `one_finger_tap` | `spatialAction` | `one_finger_tap` | direct | Explicit mechanical/spatial tap. An element target supplies live geometry; ordinary accessible controls should use the semantic command path. |
| `ping` | `session` | `ping` | direct | Check connection health without reading accessibility state. |
| `rotor` | `semanticAction` | `rotor` | direct | Move through an element rotor by direction. The server holds the rotor cursor while in rotor mode (entering at the first item); any other interaction exits rotor mode and drops the cursor. |
| `run_heist` | `heistRuntime` | `run_heist` | direct | Execute a typed heist plan, supplied inline (canonical HeistPlan fields: version, name, parameter, definitions, body) or loaded by the fence from a `path` to a .heist package artifact. Provide exactly one source: a path or an inline plan. Use `argument` when the root heist declares a string or element_target parameter. |
| `scroll` | `viewportDebug` | `scroll` | direct | Explicit viewport/debug operation: scroll one page in the visible viewport, within a semantic target's owning scroll ancestor, or for direct debug requests, within a current containerName. |
| `scroll_to_edge` | `viewportDebug` | `scroll_to_edge` | direct | Explicit viewport/debug operation: scroll the visible viewport, a semantic target's owning scroll ancestor, or for direct debug requests, a current containerName, to a requested edge. |
| `scroll_to_visible` | `viewportDebug` | `scroll_to_visible` | direct | Explicit viewport/debug operation: move the viewport until a semantic target is visible and report its fresh geometry. |
| `set_pasteboard` | `semanticAction` | `set_pasteboard` | direct | Write text to the general pasteboard from within the app. |
| `start_heist` | `heistRecording` | `start_heist` | direct | Start composing successful interactions into a semantic heist test. |
| `stop_heist` | `heistRecording` | `stop_heist` | direct | Stop heist recording and save a deterministic semantic heist fixture. |
| `swipe` | `spatialAction` | `swipe` | direct | Explicit mechanical/spatial swipe using exactly one typed intent: elementDirection, elementUnitPoints, pointToPoint, or pointDirection. |
| `type_text` | `semanticAction` | `type_text` | direct | Type non-empty text, optionally after inflating a semantic target. |
| `wait` | `assertion` | `wait` | direct | Assert that an accessibility predicate is satisfied within timeout by evaluating settled accessibility state. |

## Details

### `activate`

Perform primary accessibility activation on a semantic UI element, or one of its named accessibility actions.

- Family: `semanticAction`
- CLI: direct command `activate`
- MCP: direct tool
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

Describe one root entry or reusable heist from a runtime-validated plan. The `heist` parameter selects the entry/capability name; the plan is supplied inline (canonical HeistPlan fields: version, name, parameter, definitions, body) or loaded from a `path` to a .heist package artifact.

- Family: `heistRuntime`
- CLI: direct command `describe_heist`
- MCP: direct tool
- Connection before dispatch: no

Parameters:

| Parameter | Type | Required | Default | Values |
|-----------|------|----------|---------|--------|
| `heist` | `string` | yes | - | - |
| `path` | `string` | no | - | - |
| `version` | `integer` | no | - | - |
| `name` | `string` | no | - | - |
| `parameter` | `object` | no | - | - |
| `definitions` | `array` | no | - | - |
| `body` | `array` | no | - | - |

### `dismiss_keyboard`

Dismiss the on-screen keyboard through the current first responder or keyboard action path.

- Family: `semanticAction`
- CLI: direct command `dismiss_keyboard`
- MCP: direct tool
- Connection before dispatch: yes

Parameters:

| Parameter | Type | Required | Default | Values |
|-----------|------|----------|---------|--------|
| `expect` | `object` | no | - | - |
| `timeout` | `number` | no | - | - |

### `drag`

Explicit mechanical/spatial drag using exactly one typed intent: elementToPoint or pointToPoint.

- Family: `spatialAction`
- CLI: direct command `drag`
- MCP: direct tool
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
- MCP: direct tool
- Connection before dispatch: yes

Parameters:

| Parameter | Type | Required | Default | Values |
|-----------|------|----------|---------|--------|
| `action` | `string` | yes | - | `copy`, `paste`, `cut`, `select`, `selectAll`, `delete` |
| `expect` | `object` | no | - | - |
| `timeout` | `number` | no | - | - |

### `get_interface`

Read the app accessibility hierarchy, optionally scoped to a subtree.

containerName is ButtonHeist's generated name for a container in the current interface capture. It is useful for inspection and viewport/debug commands. It is not a semantic target and is not recorded into heists.

- Family: `observation`
- CLI: direct command `get_interface`
- MCP: direct tool
- Connection before dispatch: yes

Parameters:

| Parameter | Type | Required | Default | Values |
|-----------|------|----------|---------|--------|
| `label` | `string` | no | - | - |
| `identifier` | `string` | no | - | - |
| `value` | `string` | no | - | - |
| `traits` | `stringArray` | no | - | - |
| `excludeTraits` | `stringArray` | no | - | - |
| `subtree` | `object` | no | - | - |
| `detail` | `string` | no | - | `summary`, `full` |

### `get_pasteboard`

Read text from the general pasteboard.

- Family: `observation`
- CLI: direct command `get_pasteboard`
- MCP: direct tool
- Connection before dispatch: yes

Parameters:

_None._

### `get_screen`

Capture a PNG screenshot with optional inline data and interface state.

- Family: `observation`
- CLI: direct command `get_screen`
- MCP: direct tool
- Connection before dispatch: yes

Parameters:

| Parameter | Type | Required | Default | Values |
|-----------|------|----------|---------|--------|
| `output` | `string` | no | - | - |
| `inlineData` | `boolean` | no | - | - |
| `includeInterface` | `boolean` | no | - | - |

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
- MCP: direct tool
- Connection before dispatch: no

Parameters:

_None._

### `list_heists`

List a summary menu of the root entry and named reusable heists derived from one runtime-validated plan. Set `detail` to `detailed` to include derived command names, nested heist calls, counts, and safe semantic surface summaries. The plan is supplied inline (canonical HeistPlan fields: version, name, parameter, definitions, body) or loaded from a `path` to a .heist package artifact.

- Family: `heistRuntime`
- CLI: direct command `list_heists`
- MCP: direct tool
- Connection before dispatch: no

Parameters:

| Parameter | Type | Required | Default | Values |
|-----------|------|----------|---------|--------|
| `detail` | `string` | no | `"summary"` | `summary`, `detailed` |
| `path` | `string` | no | - | - |
| `version` | `integer` | no | - | - |
| `name` | `string` | no | - | - |
| `parameter` | `object` | no | - | - |
| `definitions` | `array` | no | - | - |
| `body` | `array` | no | - | - |

### `list_targets`

List configured connection targets and the default target.

- Family: `session`
- CLI: direct command `list_targets`
- MCP: direct tool
- Connection before dispatch: no

Parameters:

_None._

### `long_press`

Explicit mechanical/spatial long press on a point or element-relative point for a resolved duration.

- Family: `spatialAction`
- CLI: direct command `long_press`
- MCP: direct tool
- Connection before dispatch: yes

Parameters:

| Parameter | Type | Required | Default | Values |
|-----------|------|----------|---------|--------|
| `element` | `object` | no | - | - |
| `point` | `object` | no | - | - |
| `duration` | `number` | no | - | - |
| `expect` | `object` | no | - | - |
| `timeout` | `number` | no | - | - |

### `one_finger_tap`

Explicit mechanical/spatial tap. An element target supplies live geometry; ordinary accessible controls should use the semantic command path.

- Family: `spatialAction`
- CLI: direct command `one_finger_tap`
- MCP: direct tool
- Connection before dispatch: yes

Parameters:

| Parameter | Type | Required | Default | Values |
|-----------|------|----------|---------|--------|
| `element` | `object` | no | - | - |
| `point` | `object` | no | - | - |
| `expect` | `object` | no | - | - |
| `timeout` | `number` | no | - | - |

### `ping`

Check connection health without reading accessibility state.

- Family: `session`
- CLI: direct command `ping`
- MCP: direct tool
- Connection before dispatch: no

Parameters:

_None._

### `rotor`

Move through an element rotor by direction. The server holds the rotor cursor while in rotor mode (entering at the first item); any other interaction exits rotor mode and drops the cursor.

- Family: `semanticAction`
- CLI: direct command `rotor`
- MCP: direct tool
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

Execute a typed heist plan, supplied inline (canonical HeistPlan fields: version, name, parameter, definitions, body) or loaded by the fence from a `path` to a .heist package artifact. Provide exactly one source: a path or an inline plan. Use `argument` when the root heist declares a string or element_target parameter.

- Family: `heistRuntime`
- CLI: direct command `run_heist`
- MCP: direct tool
- Connection before dispatch: yes

Parameters:

| Parameter | Type | Required | Default | Values |
|-----------|------|----------|---------|--------|
| `argument` | `object` | no | - | - |
| `path` | `string` | no | - | - |
| `version` | `integer` | no | - | - |
| `name` | `string` | no | - | - |
| `parameter` | `object` | no | - | - |
| `definitions` | `array` | no | - | - |
| `body` | `array` | no | - | - |

### `scroll`

Explicit viewport/debug operation: scroll one page in the visible viewport, within a semantic target's owning scroll ancestor, or for direct debug requests, within a current containerName.

- Family: `viewportDebug`
- CLI: direct command `scroll`
- MCP: direct tool
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
- MCP: direct tool
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
- MCP: direct tool
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
- MCP: direct tool
- Connection before dispatch: yes

Parameters:

| Parameter | Type | Required | Default | Values |
|-----------|------|----------|---------|--------|
| `text` | `string` | yes | - | - |
| `expect` | `object` | no | - | - |
| `timeout` | `number` | no | - | - |

### `start_heist`

Start composing successful interactions into a semantic heist test.

- Family: `heistRecording`
- CLI: direct command `start_heist`
- MCP: direct tool
- Connection before dispatch: no

Parameters:

| Parameter | Type | Required | Default | Values |
|-----------|------|----------|---------|--------|
| `app` | `string` | no | - | - |
| `identifier` | `string` | no | - | - |

### `stop_heist`

Stop heist recording and save a deterministic semantic heist fixture.

- Family: `heistRecording`
- CLI: direct command `stop_heist`
- MCP: direct tool
- Connection before dispatch: no

Parameters:

| Parameter | Type | Required | Default | Values |
|-----------|------|----------|---------|--------|
| `output` | `string` | yes | - | - |

### `swipe`

Explicit mechanical/spatial swipe using exactly one typed intent: elementDirection, elementUnitPoints, pointToPoint, or pointDirection.

- Family: `spatialAction`
- CLI: direct command `swipe`
- MCP: direct tool
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

Type non-empty text, optionally after inflating a semantic target.

- Family: `semanticAction`
- CLI: direct command `type_text`
- MCP: direct tool
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
- MCP: direct tool
- Connection before dispatch: yes

Parameters:

| Parameter | Type | Required | Default | Values |
|-----------|------|----------|---------|--------|
| `predicate` | `object` | yes | - | - |
| `timeout` | `number` | no | - | - |

