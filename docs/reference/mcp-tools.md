# ButtonHeist MCP Tool Reference

_Generated from `TheFence.Command.descriptors`._

## Summary

| Tool | Description |
|------|-------------|
| `activate` | Activate a semantic UI element or one of its named accessibility actions. |
| `connect` | Establish or switch the active connection to a Button Heist app. |
| `dismiss_keyboard` | Dismiss the on-screen keyboard through the current first responder or keyboard action path. |
| `drag` | Drag using exactly one typed intent: elementToPoint or pointToPoint. |
| `edit_action` | Perform an edit action on the current first responder. |
| `get_interface` | Read the app accessibility hierarchy, optionally scoped to a subtree. |
| `get_pasteboard` | Read text from the general pasteboard. |
| `get_screen` | Capture a PNG screenshot with optional inline data and interface state. |
| `get_session_state` | Inspect connection, device, and last-action session state. |
| `list_devices` | List discovered iOS devices and configured connection targets. |
| `list_targets` | List configured connection targets and the default target. |
| `long_press` | Long-press an explicit point or semantic element for a resolved duration. |
| `one_finger_tap` | Tap an explicit point or semantic element after actionability resolution. |
| `ping` | Check connection health without reading accessibility state. |
| `play_heist` | Play back a heist file and return step diagnostics on failure. |
| `rotor` | Move through an element rotor by direction. The server holds the rotor cursor while in rotor mode (entering at the first item); any other interaction exits rotor mode and drops the cursor. |
| `run_heist` | Execute an inline typed heist plan. |
| `scroll` | Scroll one page in the visible viewport, or within a semantic target's owning scroll ancestor. |
| `scroll_to_edge` | Scroll the visible viewport, or a semantic target's owning scroll ancestor, to a requested edge. |
| `scroll_to_visible` | Make a semantic target actionable and report its fresh geometry. |
| `set_pasteboard` | Write text to the general pasteboard from within the app. |
| `start_heist` | Start recording replayable heist steps from successful commands. |
| `stop_heist` | Stop heist recording and save a deterministic heist fixture. |
| `swipe` | Swipe using exactly one typed intent: elementDirection, elementUnitPoints, pointToPoint, or pointDirection. |
| `type_text` | Type non-empty text, optionally after making a semantic target actionable. |
| `wait` | Wait until an accessibility predicate is satisfied: present/absent poll the current interface; changed rides settled UI transitions. |

## Details

### `activate`

Activate a semantic UI element or one of its named accessibility actions.

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

Parameters:

| Parameter | Type | Required | Default | Values |
|-----------|------|----------|---------|--------|
| `target` | `string` | no | - | - |
| `device` | `string` | no | - | - |
| `token` | `string` | no | - | - |

### `dismiss_keyboard`

Dismiss the on-screen keyboard through the current first responder or keyboard action path.

Parameters:

| Parameter | Type | Required | Default | Values |
|-----------|------|----------|---------|--------|
| `expect` | `object` | no | - | - |
| `timeout` | `number` | no | - | - |

### `drag`

Drag using exactly one typed intent: elementToPoint or pointToPoint.

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

Parameters:

| Parameter | Type | Required | Default | Values |
|-----------|------|----------|---------|--------|
| `action` | `string` | yes | - | `copy`, `paste`, `cut`, `select`, `selectAll`, `delete` |
| `expect` | `object` | no | - | - |
| `timeout` | `number` | no | - | - |

### `get_interface`

Read the app accessibility hierarchy, optionally scoped to a subtree.

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

Parameters:

_None._

### `get_screen`

Capture a PNG screenshot with optional inline data and interface state.

Parameters:

| Parameter | Type | Required | Default | Values |
|-----------|------|----------|---------|--------|
| `output` | `string` | no | - | - |
| `inlineData` | `boolean` | no | - | - |
| `includeInterface` | `boolean` | no | - | - |

### `get_session_state`

Inspect connection, device, and last-action session state.

Parameters:

_None._

### `list_devices`

List discovered iOS devices and configured connection targets.

Parameters:

_None._

### `list_targets`

List configured connection targets and the default target.

Parameters:

_None._

### `long_press`

Long-press an explicit point or semantic element for a resolved duration.

Parameters:

| Parameter | Type | Required | Default | Values |
|-----------|------|----------|---------|--------|
| `element` | `object` | no | - | - |
| `point` | `object` | no | - | - |
| `duration` | `number` | no | - | - |
| `expect` | `object` | no | - | - |
| `timeout` | `number` | no | - | - |

### `one_finger_tap`

Tap an explicit point or semantic element after actionability resolution.

Parameters:

| Parameter | Type | Required | Default | Values |
|-----------|------|----------|---------|--------|
| `element` | `object` | no | - | - |
| `point` | `object` | no | - | - |
| `expect` | `object` | no | - | - |
| `timeout` | `number` | no | - | - |

### `ping`

Check connection health without reading accessibility state.

Parameters:

_None._

### `play_heist`

Play back a heist file and return step diagnostics on failure.

Parameters:

| Parameter | Type | Required | Default | Values |
|-----------|------|----------|---------|--------|
| `input` | `string` | yes | - | - |

### `rotor`

Move through an element rotor by direction. The server holds the rotor cursor while in rotor mode (entering at the first item); any other interaction exits rotor mode and drops the cursor.

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

Parameters:

| Parameter | Type | Required | Default | Values |
|-----------|------|----------|---------|--------|
| `version` | `integer` | yes | - | - |
| `body` | `array` | yes | - | - |

### `scroll`

Scroll one page in the visible viewport, or within a semantic target's owning scroll ancestor.

Parameters:

| Parameter | Type | Required | Default | Values |
|-----------|------|----------|---------|--------|
| `target` | `object` | no | - | - |
| `direction` | `string` | no | `"down"` | `up`, `down`, `left`, `right` |
| `expect` | `object` | no | - | - |
| `timeout` | `number` | no | - | - |

### `scroll_to_edge`

Scroll the visible viewport, or a semantic target's owning scroll ancestor, to a requested edge.

Parameters:

| Parameter | Type | Required | Default | Values |
|-----------|------|----------|---------|--------|
| `target` | `object` | no | - | - |
| `edge` | `string` | no | `"top"` | `top`, `bottom`, `left`, `right` |
| `expect` | `object` | no | - | - |
| `timeout` | `number` | no | - | - |

### `scroll_to_visible`

Make a semantic target actionable and report its fresh geometry.

Parameters:

| Parameter | Type | Required | Default | Values |
|-----------|------|----------|---------|--------|
| `target` | `object` | no | - | - |
| `expect` | `object` | no | - | - |
| `timeout` | `number` | no | - | - |

### `set_pasteboard`

Write text to the general pasteboard from within the app.

Parameters:

| Parameter | Type | Required | Default | Values |
|-----------|------|----------|---------|--------|
| `text` | `string` | yes | - | - |
| `expect` | `object` | no | - | - |
| `timeout` | `number` | no | - | - |

### `start_heist`

Start recording replayable heist steps from successful commands.

Parameters:

| Parameter | Type | Required | Default | Values |
|-----------|------|----------|---------|--------|
| `app` | `string` | no | - | - |
| `identifier` | `string` | no | - | - |

### `stop_heist`

Stop heist recording and save a deterministic heist fixture.

Parameters:

| Parameter | Type | Required | Default | Values |
|-----------|------|----------|---------|--------|
| `output` | `string` | yes | - | - |

### `swipe`

Swipe using exactly one typed intent: elementDirection, elementUnitPoints, pointToPoint, or pointDirection.

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

Type non-empty text, optionally after making a semantic target actionable.

Parameters:

| Parameter | Type | Required | Default | Values |
|-----------|------|----------|---------|--------|
| `target` | `object` | no | - | - |
| `text` | `string` | yes | - | - |
| `expect` | `object` | no | - | - |
| `timeout` | `number` | no | - | - |

### `wait`

Wait until an accessibility predicate is satisfied: present/absent poll the current interface; changed rides settled UI transitions.

Parameters:

| Parameter | Type | Required | Default | Values |
|-----------|------|----------|---------|--------|
| `predicate` | `object` | yes | - | - |
| `timeout` | `number` | no | - | - |

