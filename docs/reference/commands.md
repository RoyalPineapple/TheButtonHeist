# ButtonHeist Command Reference

_Generated from `TheFence.Command.descriptors`._

## Summary

| Command | CLI | MCP | Heist | Description |
|---------|-----|-----|-------|-------------|
| `activate` | `activate` | direct | yes | Activate a semantic UI element or one of its named accessibility actions. |
| `connect` | `connect` | direct | no | Establish or switch the active connection to a Button Heist app. |
| `dismiss_keyboard` | `dismiss_keyboard` | direct | yes | Dismiss the on-screen keyboard through the current first responder or keyboard action path. |
| `drag` | `drag` | direct | yes | Drag using exactly one typed intent: elementToPoint or pointToPoint. |
| `edit_action` | `edit_action` | direct | yes | Perform an edit action on the current first responder. |
| `get_interface` | `get_interface` | direct | no | Read the app accessibility hierarchy, optionally scoped to a subtree. |
| `get_pasteboard` | `get_pasteboard` | direct | no | Read text from the general pasteboard. |
| `get_screen` | `get_screen` | direct | no | Capture a PNG screenshot with optional inline data and interface state. |
| `get_session_state` | `get_session_state` | direct | no | Inspect connection, device, and last-action session state. |
| `list_devices` | `list_devices` | direct | no | List discovered iOS devices and configured connection targets. |
| `list_targets` | `list_targets` | direct | no | List configured connection targets and the default target. |
| `long_press` | `long_press` | direct | yes | Long-press an explicit point or semantic element for a resolved duration. |
| `one_finger_tap` | `one_finger_tap` | direct | yes | Tap an explicit point or semantic element after actionability resolution. |
| `ping` | `ping` | direct | no | Check connection health without reading accessibility state. |
| `play_heist` | `play_heist` | direct | no | Play back a heist file and return step diagnostics on failure. |
| `rotor` | `rotor` | direct | yes | Move through an element rotor by direction. The server holds the rotor cursor while in rotor mode (entering at the first item); any other interaction exits rotor mode and drops the cursor. |
| `run_heist` | `run_heist` | direct | no | Execute an inline typed heist plan. |
| `scroll` | `scroll` | direct | yes | Scroll one page in the visible viewport, or within a semantic target's owning scroll ancestor. |
| `scroll_to_edge` | `scroll_to_edge` | direct | yes | Scroll the visible viewport, or a semantic target's owning scroll ancestor, to a requested edge. |
| `scroll_to_visible` | `scroll_to_visible` | direct | yes | Make a semantic target actionable and report its fresh geometry. |
| `set_pasteboard` | `set_pasteboard` | direct | yes | Write text to the general pasteboard from within the app. |
| `start_heist` | `start_heist` | direct | no | Start recording replayable heist steps from successful commands. |
| `stop_heist` | `stop_heist` | direct | no | Stop heist recording and save a deterministic heist fixture. |
| `swipe` | `swipe` | direct | yes | Swipe using exactly one typed intent: elementDirection, elementUnitPoints, pointToPoint, or pointDirection. |
| `type_text` | `type_text` | direct | yes | Type non-empty text, optionally after making a semantic target actionable. |
| `wait` | `wait` | direct | yes | Wait until an accessibility predicate is satisfied: present/absent poll the current interface; changed rides settled UI transitions. |

## Details

### `activate`

Activate a semantic UI element or one of its named accessibility actions.

- CLI: direct command `activate`
- MCP: direct tool
- Heist: yes
- Connection before dispatch: yes

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

- CLI: direct command `connect`
- MCP: direct tool
- Heist: no
- Connection before dispatch: no

Parameters:

| Parameter | Type | Required | Default | Values |
|-----------|------|----------|---------|--------|
| `target` | `string` | no | - | - |
| `device` | `string` | no | - | - |
| `token` | `string` | no | - | - |

### `dismiss_keyboard`

Dismiss the on-screen keyboard through the current first responder or keyboard action path.

- CLI: direct command `dismiss_keyboard`
- MCP: direct tool
- Heist: yes
- Connection before dispatch: yes

Parameters:

| Parameter | Type | Required | Default | Values |
|-----------|------|----------|---------|--------|
| `expect` | `object` | no | - | - |
| `timeout` | `number` | no | - | - |

### `drag`

Drag using exactly one typed intent: elementToPoint or pointToPoint.

- CLI: direct command `drag`
- MCP: direct tool
- Heist: yes
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

- CLI: direct command `edit_action`
- MCP: direct tool
- Heist: yes
- Connection before dispatch: yes

Parameters:

| Parameter | Type | Required | Default | Values |
|-----------|------|----------|---------|--------|
| `action` | `string` | yes | - | `copy`, `paste`, `cut`, `select`, `selectAll`, `delete` |
| `expect` | `object` | no | - | - |
| `timeout` | `number` | no | - | - |

### `get_interface`

Read the app accessibility hierarchy, optionally scoped to a subtree.

- CLI: direct command `get_interface`
- MCP: direct tool
- Heist: no
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

- CLI: direct command `get_pasteboard`
- MCP: direct tool
- Heist: no
- Connection before dispatch: yes

Parameters:

_None._

### `get_screen`

Capture a PNG screenshot with optional inline data and interface state.

- CLI: direct command `get_screen`
- MCP: direct tool
- Heist: no
- Connection before dispatch: yes

Parameters:

| Parameter | Type | Required | Default | Values |
|-----------|------|----------|---------|--------|
| `output` | `string` | no | - | - |
| `inlineData` | `boolean` | no | - | - |
| `includeInterface` | `boolean` | no | - | - |

### `get_session_state`

Inspect connection, device, and last-action session state.

- CLI: direct command `get_session_state`
- MCP: direct tool
- Heist: no
- Connection before dispatch: no

Parameters:

_None._

### `list_devices`

List discovered iOS devices and configured connection targets.

- CLI: direct command `list_devices`
- MCP: direct tool
- Heist: no
- Connection before dispatch: no

Parameters:

_None._

### `list_targets`

List configured connection targets and the default target.

- CLI: direct command `list_targets`
- MCP: direct tool
- Heist: no
- Connection before dispatch: no

Parameters:

_None._

### `long_press`

Long-press an explicit point or semantic element for a resolved duration.

- CLI: direct command `long_press`
- MCP: direct tool
- Heist: yes
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

Tap an explicit point or semantic element after actionability resolution.

- CLI: direct command `one_finger_tap`
- MCP: direct tool
- Heist: yes
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

- CLI: direct command `ping`
- MCP: direct tool
- Heist: no
- Connection before dispatch: no

Parameters:

_None._

### `play_heist`

Play back a heist file and return step diagnostics on failure.

- CLI: direct command `play_heist`
- MCP: direct tool
- Heist: no
- Connection before dispatch: yes

Parameters:

| Parameter | Type | Required | Default | Values |
|-----------|------|----------|---------|--------|
| `input` | `string` | yes | - | - |

### `rotor`

Move through an element rotor by direction. The server holds the rotor cursor while in rotor mode (entering at the first item); any other interaction exits rotor mode and drops the cursor.

- CLI: direct command `rotor`
- MCP: direct tool
- Heist: yes
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

Execute an inline typed heist plan.

- CLI: direct command `run_heist`
- MCP: direct tool
- Heist: no
- Connection before dispatch: yes

Parameters:

| Parameter | Type | Required | Default | Values |
|-----------|------|----------|---------|--------|
| `version` | `integer` | yes | - | - |
| `body` | `array` | yes | - | - |

### `scroll`

Scroll one page in the visible viewport, or within a semantic target's owning scroll ancestor.

- CLI: direct command `scroll`
- MCP: direct tool
- Heist: yes
- Connection before dispatch: yes

Parameters:

| Parameter | Type | Required | Default | Values |
|-----------|------|----------|---------|--------|
| `target` | `object` | no | - | - |
| `direction` | `string` | no | `"down"` | `up`, `down`, `left`, `right` |
| `expect` | `object` | no | - | - |
| `timeout` | `number` | no | - | - |

### `scroll_to_edge`

Scroll the visible viewport, or a semantic target's owning scroll ancestor, to a requested edge.

- CLI: direct command `scroll_to_edge`
- MCP: direct tool
- Heist: yes
- Connection before dispatch: yes

Parameters:

| Parameter | Type | Required | Default | Values |
|-----------|------|----------|---------|--------|
| `target` | `object` | no | - | - |
| `edge` | `string` | no | `"top"` | `top`, `bottom`, `left`, `right` |
| `expect` | `object` | no | - | - |
| `timeout` | `number` | no | - | - |

### `scroll_to_visible`

Make a semantic target actionable and report its fresh geometry.

- CLI: direct command `scroll_to_visible`
- MCP: direct tool
- Heist: yes
- Connection before dispatch: yes

Parameters:

| Parameter | Type | Required | Default | Values |
|-----------|------|----------|---------|--------|
| `target` | `object` | no | - | - |
| `expect` | `object` | no | - | - |
| `timeout` | `number` | no | - | - |

### `set_pasteboard`

Write text to the general pasteboard from within the app.

- CLI: direct command `set_pasteboard`
- MCP: direct tool
- Heist: yes
- Connection before dispatch: yes

Parameters:

| Parameter | Type | Required | Default | Values |
|-----------|------|----------|---------|--------|
| `text` | `string` | yes | - | - |
| `expect` | `object` | no | - | - |
| `timeout` | `number` | no | - | - |

### `start_heist`

Start recording replayable heist steps from successful commands.

- CLI: direct command `start_heist`
- MCP: direct tool
- Heist: no
- Connection before dispatch: no

Parameters:

| Parameter | Type | Required | Default | Values |
|-----------|------|----------|---------|--------|
| `app` | `string` | no | - | - |
| `identifier` | `string` | no | - | - |

### `stop_heist`

Stop heist recording and save a deterministic heist fixture.

- CLI: direct command `stop_heist`
- MCP: direct tool
- Heist: no
- Connection before dispatch: no

Parameters:

| Parameter | Type | Required | Default | Values |
|-----------|------|----------|---------|--------|
| `output` | `string` | yes | - | - |

### `swipe`

Swipe using exactly one typed intent: elementDirection, elementUnitPoints, pointToPoint, or pointDirection.

- CLI: direct command `swipe`
- MCP: direct tool
- Heist: yes
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

Type non-empty text, optionally after making a semantic target actionable.

- CLI: direct command `type_text`
- MCP: direct tool
- Heist: yes
- Connection before dispatch: yes

Parameters:

| Parameter | Type | Required | Default | Values |
|-----------|------|----------|---------|--------|
| `target` | `object` | no | - | - |
| `text` | `string` | yes | - | - |
| `expect` | `object` | no | - | - |
| `timeout` | `number` | no | - | - |

### `wait`

Wait until an accessibility predicate is satisfied: present/absent poll the current interface; changed rides settled UI transitions.

- CLI: direct command `wait`
- MCP: direct tool
- Heist: yes
- Connection before dispatch: yes

Parameters:

| Parameter | Type | Required | Default | Values |
|-----------|------|----------|---------|--------|
| `predicate` | `object` | yes | - | - |
| `timeout` | `number` | no | - | - |

