# ButtonHeist MCP Tool Reference

_Generated from `TheFence.Command.mcpToolContracts`._

## Summary

| Tool | Description |
|------|-------------|
| `activate` | Activate a semantic UI element or one of its named accessibility actions. |
| `connect` | Establish or switch the active connection to a Button Heist app. |
| `dismiss_keyboard` | Dismiss the on-screen keyboard through the current first responder or keyboard action path. |
| `drag` | Drag from one point to another using explicit coordinates or a semantic target. |
| `draw_bezier` | Draw a Bezier path from a start point through one or more curve segments. |
| `draw_path` | Draw a free-form path through explicit screen-coordinate points. |
| `edit_action` | Perform an edit action on the current first responder. |
| `element_search` | Search scrollable content for a semantic element match without performing an action. |
| `get_interface` | Read the app accessibility hierarchy, optionally scoped to a subtree. |
| `get_pasteboard` | Read text from the general pasteboard. |
| `get_screen` | Capture a PNG screenshot with optional inline data and interface state. |
| `get_session_state` | Inspect connection, device, and last-action session state. |
| `list_devices` | List discovered iOS devices and configured connection targets. |
| `list_targets` | List configured connection targets and the default target. |
| `long_press` | Long-press a coordinate or semantic target for a resolved duration. |
| `one_finger_tap` | Tap a coordinate or semantic target after actionability resolution. |
| `pinch` | Pinch around a resolved center point using scale, angle, and duration. |
| `ping` | Check connection health without reading accessibility state. |
| `play_heist` | Play back a heist file and return step diagnostics on failure. |
| `rotate` | Rotate around a resolved center point using angle, radius, and duration. |
| `rotor` | Move through an element rotor using direction and continuation metadata. |
| `run_batch` | Execute ordered command steps with batch policy and per-step expectations. |
| `scroll` | Scroll one page in a selected container or semantic target's owning scroll ancestor. |
| `scroll_to_edge` | Scroll the selected container, or the target's owning scroll ancestor, to a requested edge. |
| `scroll_to_visible` | Make a semantic target actionable and report its fresh geometry. |
| `set_pasteboard` | Write text to the general pasteboard from within the app. |
| `start_heist` | Start recording replayable heist steps from successful commands. |
| `stop_heist` | Stop heist recording and save a JSON playback script. |
| `swipe` | Swipe in a direction or between explicit points; semantic targets are made actionable first. |
| `two_finger_tap` | Tap with two fingers at a coordinate or actionable semantic target. |
| `type_text` | Type non-empty text, optionally after making a semantic target actionable. |
| `wait_for` | Wait for a semantic element to appear or disappear. |
| `wait_for_change` | Wait for any UI change or for an expectation to become true. |

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

Drag from one point to another using explicit coordinates or a semantic target.

Parameters:

| Parameter | Type | Required | Default | Values |
|-----------|------|----------|---------|--------|
| `target` | `object` | no | - | - |
| `endX` | `number` | yes | - | - |
| `endY` | `number` | yes | - | - |
| `startX` | `number` | no | - | - |
| `startY` | `number` | no | - | - |
| `duration` | `number` | no | - | - |
| `expect` | `object` | no | - | - |
| `timeout` | `number` | no | - | - |

### `draw_bezier`

Draw a Bezier path from a start point through one or more curve segments.

Parameters:

| Parameter | Type | Required | Default | Values |
|-----------|------|----------|---------|--------|
| `startX` | `number` | yes | - | - |
| `startY` | `number` | yes | - | - |
| `segments` | `array` | yes | - | - |
| `samplesPerSegment` | `integer` | no | - | - |
| `duration` | `number` | no | - | - |
| `velocity` | `number` | no | - | - |
| `expect` | `object` | no | - | - |
| `timeout` | `number` | no | - | - |

### `draw_path`

Draw a free-form path through explicit screen-coordinate points.

Parameters:

| Parameter | Type | Required | Default | Values |
|-----------|------|----------|---------|--------|
| `points` | `array` | yes | - | - |
| `duration` | `number` | no | - | - |
| `velocity` | `number` | no | - | - |
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

### `element_search`

Search scrollable content for a semantic element match without performing an action.

Parameters:

| Parameter | Type | Required | Default | Values |
|-----------|------|----------|---------|--------|
| `target` | `object` | no | - | - |
| `direction` | `string` | no | - | `down`, `up`, `left`, `right` |
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

Long-press a coordinate or semantic target for a resolved duration.

Parameters:

| Parameter | Type | Required | Default | Values |
|-----------|------|----------|---------|--------|
| `target` | `object` | no | - | - |
| `x` | `number` | no | - | - |
| `y` | `number` | no | - | - |
| `duration` | `number` | no | - | - |
| `expect` | `object` | no | - | - |
| `timeout` | `number` | no | - | - |

### `one_finger_tap`

Tap a coordinate or semantic target after actionability resolution.

Parameters:

| Parameter | Type | Required | Default | Values |
|-----------|------|----------|---------|--------|
| `target` | `object` | no | - | - |
| `x` | `number` | no | - | - |
| `y` | `number` | no | - | - |
| `expect` | `object` | no | - | - |
| `timeout` | `number` | no | - | - |

### `pinch`

Pinch around a resolved center point using scale, angle, and duration.

Parameters:

| Parameter | Type | Required | Default | Values |
|-----------|------|----------|---------|--------|
| `target` | `object` | no | - | - |
| `scale` | `number` | yes | - | - |
| `centerX` | `number` | no | - | - |
| `centerY` | `number` | no | - | - |
| `spread` | `number` | no | - | - |
| `duration` | `number` | no | - | - |
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

### `rotate`

Rotate around a resolved center point using angle, radius, and duration.

Parameters:

| Parameter | Type | Required | Default | Values |
|-----------|------|----------|---------|--------|
| `target` | `object` | no | - | - |
| `angle` | `number` | yes | - | - |
| `centerX` | `number` | no | - | - |
| `centerY` | `number` | no | - | - |
| `radius` | `number` | no | - | - |
| `duration` | `number` | no | - | - |
| `expect` | `object` | no | - | - |
| `timeout` | `number` | no | - | - |

### `rotor`

Move through an element rotor using direction and continuation metadata.

Parameters:

| Parameter | Type | Required | Default | Values |
|-----------|------|----------|---------|--------|
| `target` | `object` | no | - | - |
| `rotor` | `string` | no | - | - |
| `rotorIndex` | `integer` | no | - | - |
| `direction` | `string` | no | `"next"` | `next`, `previous` |
| `currentHeistId` | `string` | no | - | - |
| `currentTextStartOffset` | `integer` | no | - | - |
| `currentTextEndOffset` | `integer` | no | - | - |
| `expect` | `object` | no | - | - |
| `timeout` | `number` | no | - | - |

### `run_batch`

Execute ordered command steps with batch policy and per-step expectations.

Parameters:

| Parameter | Type | Required | Default | Values |
|-----------|------|----------|---------|--------|
| `steps` | `array` | yes | - | - |
| `policy` | `string` | no | - | `stop_on_error`, `continue_on_error` |

### `scroll`

Scroll one page in a selected container or semantic target's owning scroll ancestor.

Parameters:

| Parameter | Type | Required | Default | Values |
|-----------|------|----------|---------|--------|
| `stableId` | `string` | no | - | - |
| `captureLocalRef` | `string` | no | - | - |
| `container` | `object` | no | - | - |
| `target` | `object` | no | - | - |
| `direction` | `string` | no | `"down"` | `up`, `down`, `left`, `right` |
| `expect` | `object` | no | - | - |
| `timeout` | `number` | no | - | - |

### `scroll_to_edge`

Scroll the selected container, or the target's owning scroll ancestor, to a requested edge.

Parameters:

| Parameter | Type | Required | Default | Values |
|-----------|------|----------|---------|--------|
| `stableId` | `string` | no | - | - |
| `captureLocalRef` | `string` | no | - | - |
| `container` | `object` | no | - | - |
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

Stop heist recording and save a JSON playback script.

Parameters:

| Parameter | Type | Required | Default | Values |
|-----------|------|----------|---------|--------|
| `output` | `string` | yes | - | - |

### `swipe`

Swipe in a direction or between explicit points; semantic targets are made actionable first.

Parameters:

| Parameter | Type | Required | Default | Values |
|-----------|------|----------|---------|--------|
| `target` | `object` | no | - | - |
| `direction` | `string` | no | - | `up`, `down`, `left`, `right` |
| `start` | `object` | no | - | - |
| `end` | `object` | no | - | - |
| `startX` | `number` | no | - | - |
| `startY` | `number` | no | - | - |
| `endX` | `number` | no | - | - |
| `endY` | `number` | no | - | - |
| `duration` | `number` | no | - | - |
| `expect` | `object` | no | - | - |
| `timeout` | `number` | no | - | - |

### `two_finger_tap`

Tap with two fingers at a coordinate or actionable semantic target.

Parameters:

| Parameter | Type | Required | Default | Values |
|-----------|------|----------|---------|--------|
| `target` | `object` | no | - | - |
| `centerX` | `number` | no | - | - |
| `centerY` | `number` | no | - | - |
| `spread` | `number` | no | - | - |
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

### `wait_for`

Wait for a semantic element to appear or disappear.

Parameters:

| Parameter | Type | Required | Default | Values |
|-----------|------|----------|---------|--------|
| `target` | `object` | no | - | - |
| `absent` | `boolean` | no | - | - |
| `timeout` | `number` | no | - | - |
| `expect` | `object` | no | - | - |

### `wait_for_change`

Wait for any UI change or for an expectation to become true.

Parameters:

| Parameter | Type | Required | Default | Values |
|-----------|------|----------|---------|--------|
| `expect` | `object` | no | - | - |
| `timeout` | `number` | no | - | - |

