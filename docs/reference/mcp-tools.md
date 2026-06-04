# ButtonHeist MCP Tool Reference

_Generated from `TheFence.Command.descriptors`._

## Summary

| Tool | Family | Recordable | Description |
|------|--------|------------|-------------|
| `activate` | `semanticAction` | yes | Perform primary accessibility activation on a semantic UI element, or one of its named accessibility actions. |
| `connect` | `session` | no | Establish or switch the active connection to a Button Heist app. |
| `dismiss_keyboard` | `semanticAction` | yes | Dismiss the on-screen keyboard through the current first responder or keyboard action path. |
| `drag` | `spatialAction` | yes | Explicit mechanical/spatial drag using exactly one typed intent: elementToPoint or pointToPoint. |
| `edit_action` | `semanticAction` | yes | Perform an edit action on the current first responder. |
| `get_interface` | `observation` | no | Read the app accessibility hierarchy, optionally scoped to a subtree. |
| `get_pasteboard` | `observation` | no | Read text from the general pasteboard. |
| `get_screen` | `observation` | no | Capture a PNG screenshot with optional inline data and interface state. |
| `get_session_state` | `session` | no | Inspect connection, device, and last-action session state. |
| `list_devices` | `session` | no | List discovered iOS devices and configured connection targets. |
| `list_targets` | `session` | no | List configured connection targets and the default target. |
| `long_press` | `spatialAction` | yes | Explicit mechanical/spatial long press on a point or element-relative point for a resolved duration. |
| `one_finger_tap` | `spatialAction` | yes | Explicit mechanical/spatial tap. An element target supplies live geometry; ordinary accessible controls should use the semantic command path. |
| `ping` | `session` | no | Check connection health without reading accessibility state. |
| `play_heist` | `heistRecording` | no | Play back a heist file and return step diagnostics on failure. |
| `rotor` | `semanticAction` | yes | Move through an element rotor by direction. The server holds the rotor cursor while in rotor mode (entering at the first item); any other interaction exits rotor mode and drops the cursor. |
| `run_heist` | `heistRuntime` | no | Execute an inline typed heist plan. |
| `scroll` | `viewportDebug` | no | Explicit viewport/debug operation: scroll one page in the visible viewport, within a semantic target's owning scroll ancestor, or for direct debug requests, within a current containerName. |
| `scroll_to_edge` | `viewportDebug` | no | Explicit viewport/debug operation: scroll the visible viewport, a semantic target's owning scroll ancestor, or for direct debug requests, a current containerName, to a requested edge. |
| `scroll_to_visible` | `viewportDebug` | no | Explicit viewport/debug operation: move the viewport until a semantic target is visible and report its fresh geometry. |
| `set_pasteboard` | `semanticAction` | yes | Write text to the general pasteboard from within the app. |
| `start_heist` | `heistRecording` | no | Start composing successful interactions into a semantic heist test. |
| `stop_heist` | `heistRecording` | no | Stop heist recording and save a deterministic semantic heist fixture. |
| `swipe` | `spatialAction` | yes | Explicit mechanical/spatial swipe using exactly one typed intent: elementDirection, elementUnitPoints, pointToPoint, or pointDirection. |
| `type_text` | `semanticAction` | yes | Type non-empty text, optionally after inflating a semantic target. |
| `wait` | `observation` | yes | Wait until an accessibility predicate is satisfied within timeout by evaluating settled semantic observations. |

## Details

### `activate`

Perform primary accessibility activation on a semantic UI element, or one of its named accessibility actions.

- Family: `semanticAction`
- Recordable: yes

Parameters:

| Parameter | Type | Required | Default | Values |
|-----------|------|----------|---------|--------|
| `target` | `object` | no | - | - |
| `action` | `string` | no | - | - |
| `count` | `integer` | no | - | - |
| `expect` | `object` | no | - | - |
| `timeout` | `number` | no | - | - |

### `connect`

Establish or switch the active connection to a Button Heist app.

- Family: `session`
- Recordable: no

Parameters:

| Parameter | Type | Required | Default | Values |
|-----------|------|----------|---------|--------|
| `target` | `string` | no | - | - |
| `device` | `string` | no | - | - |
| `token` | `string` | no | - | - |

### `dismiss_keyboard`

Dismiss the on-screen keyboard through the current first responder or keyboard action path.

- Family: `semanticAction`
- Recordable: yes

Parameters:

| Parameter | Type | Required | Default | Values |
|-----------|------|----------|---------|--------|
| `expect` | `object` | no | - | - |
| `timeout` | `number` | no | - | - |

### `drag`

Explicit mechanical/spatial drag using exactly one typed intent: elementToPoint or pointToPoint.

- Family: `spatialAction`
- Recordable: yes

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
- Recordable: yes

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
- Recordable: no

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
- Recordable: no

Parameters:

_None._

### `get_screen`

Capture a PNG screenshot with optional inline data and interface state.

- Family: `observation`
- Recordable: no

Parameters:

| Parameter | Type | Required | Default | Values |
|-----------|------|----------|---------|--------|
| `output` | `string` | no | - | - |
| `inlineData` | `boolean` | no | - | - |
| `includeInterface` | `boolean` | no | - | - |

### `get_session_state`

Inspect connection, device, and last-action session state.

- Family: `session`
- Recordable: no

Parameters:

_None._

### `list_devices`

List discovered iOS devices and configured connection targets.

- Family: `session`
- Recordable: no

Parameters:

_None._

### `list_targets`

List configured connection targets and the default target.

- Family: `session`
- Recordable: no

Parameters:

_None._

### `long_press`

Explicit mechanical/spatial long press on a point or element-relative point for a resolved duration.

- Family: `spatialAction`
- Recordable: yes

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
- Recordable: yes

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
- Recordable: no

Parameters:

_None._

### `play_heist`

Play back a heist file and return step diagnostics on failure.

- Family: `heistRecording`
- Recordable: no

Parameters:

| Parameter | Type | Required | Default | Values |
|-----------|------|----------|---------|--------|
| `input` | `string` | yes | - | - |

### `rotor`

Move through an element rotor by direction. The server holds the rotor cursor while in rotor mode (entering at the first item); any other interaction exits rotor mode and drops the cursor.

- Family: `semanticAction`
- Recordable: yes

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

Execute an inline typed heist plan.

- Family: `heistRuntime`
- Recordable: no

Parameters:

| Parameter | Type | Required | Default | Values |
|-----------|------|----------|---------|--------|
| `version` | `integer` | yes | - | - |
| `body` | `array` | yes | - | - |

### `scroll`

Explicit viewport/debug operation: scroll one page in the visible viewport, within a semantic target's owning scroll ancestor, or for direct debug requests, within a current containerName.

- Family: `viewportDebug`
- Recordable: no

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
- Recordable: no

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
- Recordable: no

Parameters:

| Parameter | Type | Required | Default | Values |
|-----------|------|----------|---------|--------|
| `target` | `object` | no | - | - |
| `expect` | `object` | no | - | - |
| `timeout` | `number` | no | - | - |

### `set_pasteboard`

Write text to the general pasteboard from within the app.

- Family: `semanticAction`
- Recordable: yes

Parameters:

| Parameter | Type | Required | Default | Values |
|-----------|------|----------|---------|--------|
| `text` | `string` | yes | - | - |
| `expect` | `object` | no | - | - |
| `timeout` | `number` | no | - | - |

### `start_heist`

Start composing successful interactions into a semantic heist test.

- Family: `heistRecording`
- Recordable: no

Parameters:

| Parameter | Type | Required | Default | Values |
|-----------|------|----------|---------|--------|
| `app` | `string` | no | - | - |
| `identifier` | `string` | no | - | - |

### `stop_heist`

Stop heist recording and save a deterministic semantic heist fixture.

- Family: `heistRecording`
- Recordable: no

Parameters:

| Parameter | Type | Required | Default | Values |
|-----------|------|----------|---------|--------|
| `output` | `string` | yes | - | - |

### `swipe`

Explicit mechanical/spatial swipe using exactly one typed intent: elementDirection, elementUnitPoints, pointToPoint, or pointDirection.

- Family: `spatialAction`
- Recordable: yes

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
- Recordable: yes

Parameters:

| Parameter | Type | Required | Default | Values |
|-----------|------|----------|---------|--------|
| `target` | `object` | no | - | - |
| `text` | `string` | yes | - | - |
| `expect` | `object` | no | - | - |
| `timeout` | `number` | no | - | - |

### `wait`

Wait until an accessibility predicate is satisfied within timeout by evaluating settled semantic observations.

- Family: `observation`
- Recordable: yes

Parameters:

| Parameter | Type | Required | Default | Values |
|-----------|------|----------|---------|--------|
| `predicate` | `object` | yes | - | - |
| `timeout` | `number` | no | - | - |

