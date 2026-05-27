# ButtonHeist MCP Tool Reference

_Generated from `TheFence.Command.mcpToolContracts`._

## Summary

| Tool | Commands | Selector | Description |
|------|----------|----------|-------------|
| `activate` | `activate` | - | Activate a UI element (VoiceOver-style double-tap): tap buttons, follow links, toggle controls. Pass 'action' to invoke a named action like "increment", "decrement", or any entry from the element's actions array. |
| `archive_session` | `archive_session` | - | Close and compress the current session into a .tar.gz archive; returns the path. |
| `connect` | `connect` | - | Establish or switch the active connection to an iOS app with Button Heist enabled. Three patterns: target=NAME from .buttonheist.json, device=HOST:PORT + token, or BUTTONHEIST_DEVICE/BUTTONHEIST_TOKEN env vars. Tears down any existing session first. Returns session state; call get_interface explicitly to observe UI hierarchy. |
| `edit_action` | `edit_action`, `dismiss_keyboard` | `action` | Perform an edit or keyboard action on the current first responder. Actions: copy, paste, cut, select, selectAll, delete, dismiss (dismiss the keyboard). |
| `gesture` | `one_finger_tap`, `long_press`, `swipe`, `drag`, `pinch`, `rotate`, `two_finger_tap`, `draw_path`, `draw_bezier` | `type` | Perform a touch gesture. Prefer 'activate' for element interactions — gestures are for swipes, drags, pinches, rotates, and free-form path drawing. Set 'type' to one of: swipe, one_finger_tap, drag, long_press, pinch, rotate, two_finger_tap, draw_path, draw_bezier. |
| `get_interface` | `get_interface` | - | Read the app accessibility hierarchy. Call once on a new screen, then track changes via action deltas — re-fetch only when you need elements the delta didn't cover. Omit subtree for the whole hierarchy, or pass subtree to select the returned tree from a selected leaf or container node. |
| `get_pasteboard` | `get_pasteboard` | - | Read text from the general pasteboard. iOS may show "Allow Paste" if the content was written by another app. |
| `get_screen` | `get_screen` | - | Capture a PNG screenshot from the connected device. Returns metadata plus an artifact path by default. Set inlineData=true to return capped base64 PNG data inline; set includeInterface=true to include the fresh visible accessibility tree. |
| `get_session_log` | `get_session_log` | - | Return the current session log snapshot: commands executed and artifacts produced. |
| `get_session_state` | `get_session_state` | - | Inspect the current Button Heist session: connection status, device/app identity, recording state, client timeouts, and a lightweight summary of the last action. |
| `list_devices` | `list_devices` | - | List iOS devices discovered via Bonjour plus named targets from .buttonheist.json. Empty when Bonjour is blocked and no config targets exist — use connect(device:token:) directly. |
| `list_targets` | `list_targets` | - | List named connection targets from .buttonheist.json (or ~/.config/buttonheist/config.json), including each target's address and which one is the default. |
| `ping` | `ping` | - | Check Button Heist connection health. Returns cheap static app/server identity facts without reading UI hierarchy or accessibility state. |
| `play_heist` | `play_heist` | - | Play back a .heist file. Steps execute sequentially; playback stops on the first failed step. On failure, returns full diagnostics: command, target, error, action result, expectation result, and a complete interface snapshot at the failure point. |
| `rotor` | `rotor` | - | Move through a rotor exposed by an element. Defaults to next. Use rotors listed by get_interface to pick rotor or rotorIndex; pass currentHeistId from the previous object result to continue like a VoiceOver user. For text-range results, also pass the returned start and end offsets. |
| `run_batch` | `run_batch` | - | Execute multiple commands in one call. Each step is a JSON object with 'command' set to a canonical TheFence.Command name plus that command's parameters; grouped MCP tool names and selector shapes are not accepted inside batches. Attach 'expect' per step to verify inline. Returns ordered per-step results. policy=stop_on_error (default) or continue_on_error. |
| `scroll` | `scroll`, `scroll_to_visible`, `element_search`, `scroll_to_edge` | `mode` | Scroll within scroll views. mode=page scrolls one page in 'direction'; mode=to_visible brings a known element into view; mode=search scrolls until a matching element is found; mode=to_edge scrolls to a top/bottom/left/right edge. |
| `set_pasteboard` | `set_pasteboard` | - | Write text to the general pasteboard from within the app. Content written by the app itself does not trigger the iOS "Allow Paste" dialog when subsequently read. |
| `start_heist` | `start_heist` | - | Start recording a heist. Successful commands become steps in a .heist file; the recorder derives minimum matcher fields for durable element targeting; heistId remains recording evidence only. Attach 'expect' to validate outcomes during playback. |
| `start_recording` | `start_recording` | - | Start an H.264/MP4 screen recording. Recording runs until max duration unless inactivity_timeout is explicitly supplied. |
| `stop_heist` | `stop_heist` | - | Stop recording and save the heist as a self-contained JSON playback script. Returns the file path and step count. At least one step must have been recorded. |
| `stop_recording` | `stop_recording` | - | Stop an in-progress screen recording. Returns artifact path and metadata by default. Set inlineData=true and/or includeInteractionLog=true for a capped expanded JSON response. |
| `type_text` | `type_text` | - | Type non-empty text via keyboard injection. Optionally target an element to focus it first and read back the resulting value. |
| `wait_for` | `wait_for` | - | Wait for an element matching a predicate to appear, or to disappear with absent=true. Polls on UI settle events. Returns the matched element or diagnostic info on timeout. |
| `wait_for_change` | `wait_for_change` | - | Wait for the UI to change. With no expect, returns on any tree change. With expect, rides through intermediate states (spinners, loading) until the expectation is met. Use after an action whose delta showed a transient state and the expectation wasn't met yet. |

## Details

### `activate`

Activate a UI element (VoiceOver-style double-tap): tap buttons, follow links, toggle controls. Pass 'action' to invoke a named action like "increment", "decrement", or any entry from the element's actions array.

- Commands: `activate`

Parameters:

| Parameter | Type | Required | Default | Values |
|-----------|------|----------|---------|--------|
| `heistId` | `string` | no | - | - |
| `label` | `string` | no | - | - |
| `identifier` | `string` | no | - | - |
| `value` | `string` | no | - | - |
| `traits` | `stringArray` | no | - | - |
| `excludeTraits` | `stringArray` | no | - | - |
| `ordinal` | `integer` | no | - | - |
| `action` | `string` | no | - | - |
| `count` | `integer` | no | - | - |
| `expect` | `object` | no | - | - |
| `timeout` | `number` | no | - | - |

### `archive_session`

Close and compress the current session into a .tar.gz archive; returns the path.

- Commands: `archive_session`

Parameters:

| Parameter | Type | Required | Default | Values |
|-----------|------|----------|---------|--------|
| `delete_source` | `boolean` | no | - | - |

### `connect`

Establish or switch the active connection to an iOS app with Button Heist enabled. Three patterns: target=NAME from .buttonheist.json, device=HOST:PORT + token, or BUTTONHEIST_DEVICE/BUTTONHEIST_TOKEN env vars. Tears down any existing session first. Returns session state; call get_interface explicitly to observe UI hierarchy.

- Commands: `connect`

Parameters:

| Parameter | Type | Required | Default | Values |
|-----------|------|----------|---------|--------|
| `target` | `string` | no | - | - |
| `device` | `string` | no | - | - |
| `token` | `string` | no | - | - |

### `edit_action`

Perform an edit or keyboard action on the current first responder. Actions: copy, paste, cut, select, selectAll, delete, dismiss (dismiss the keyboard).

- Commands: `edit_action`, `dismiss_keyboard`
- Selector: `action`
- Selector routes: `copy` -> `edit_action`, `cut` -> `edit_action`, `delete` -> `edit_action`, `dismiss` -> `dismiss_keyboard`, `paste` -> `edit_action`, `select` -> `edit_action`, `selectAll` -> `edit_action`

Parameters:

| Parameter | Type | Required | Default | Values |
|-----------|------|----------|---------|--------|
| `action` | `string` | yes | - | `copy`, `paste`, `cut`, `select`, `selectAll`, `delete`, `dismiss` |
| `expect` | `object` | no | - | - |
| `timeout` | `number` | no | - | - |

### `gesture`

Perform a touch gesture. Prefer 'activate' for element interactions — gestures are for swipes, drags, pinches, rotates, and free-form path drawing. Set 'type' to one of: swipe, one_finger_tap, drag, long_press, pinch, rotate, two_finger_tap, draw_path, draw_bezier.

- Commands: `one_finger_tap`, `long_press`, `swipe`, `drag`, `pinch`, `rotate`, `two_finger_tap`, `draw_path`, `draw_bezier`
- Selector: `type`
- Selector routes: `drag` -> `drag`, `draw_bezier` -> `draw_bezier`, `draw_path` -> `draw_path`, `long_press` -> `long_press`, `one_finger_tap` -> `one_finger_tap`, `pinch` -> `pinch`, `rotate` -> `rotate`, `swipe` -> `swipe`, `two_finger_tap` -> `two_finger_tap`

Parameters:

| Parameter | Type | Required | Default | Values |
|-----------|------|----------|---------|--------|
| `heistId` | `string` | no | - | - |
| `label` | `string` | no | - | - |
| `identifier` | `string` | no | - | - |
| `value` | `string` | no | - | - |
| `traits` | `stringArray` | no | - | - |
| `excludeTraits` | `stringArray` | no | - | - |
| `ordinal` | `integer` | no | - | - |
| `x` | `number` | no | - | - |
| `y` | `number` | no | - | - |
| `expect` | `object` | no | - | - |
| `timeout` | `number` | no | - | - |
| `duration` | `number` | no | - | - |
| `direction` | `string` | no | - | `up`, `down`, `left`, `right` |
| `start` | `object` | no | - | - |
| `end` | `object` | no | - | - |
| `startX` | `number` | no | - | - |
| `startY` | `number` | no | - | - |
| `endX` | `number` | no | - | - |
| `endY` | `number` | no | - | - |
| `scale` | `number` | yes | - | - |
| `centerX` | `number` | no | - | - |
| `centerY` | `number` | no | - | - |
| `spread` | `number` | no | - | - |
| `angle` | `number` | yes | - | - |
| `radius` | `number` | no | - | - |
| `points` | `array` | yes | - | - |
| `velocity` | `number` | no | - | - |
| `segments` | `array` | yes | - | - |
| `samplesPerSegment` | `integer` | no | - | - |
| `type` | `string` | yes | - | `one_finger_tap`, `long_press`, `swipe`, `drag`, `pinch`, `rotate`, `two_finger_tap`, `draw_path`, `draw_bezier` |

### `get_interface`

Read the app accessibility hierarchy. Call once on a new screen, then track changes via action deltas — re-fetch only when you need elements the delta didn't cover. Omit subtree for the whole hierarchy, or pass subtree to select the returned tree from a selected leaf or container node.

- Commands: `get_interface`

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
| `elements` | `stringArray` | no | - | - |

### `get_pasteboard`

Read text from the general pasteboard. iOS may show "Allow Paste" if the content was written by another app.

- Commands: `get_pasteboard`

Parameters:

_None._

### `get_screen`

Capture a PNG screenshot from the connected device. Returns metadata plus an artifact path by default. Set inlineData=true to return capped base64 PNG data inline; set includeInterface=true to include the fresh visible accessibility tree.

- Commands: `get_screen`

Parameters:

| Parameter | Type | Required | Default | Values |
|-----------|------|----------|---------|--------|
| `output` | `string` | no | - | - |
| `inlineData` | `boolean` | no | - | - |
| `includeInterface` | `boolean` | no | - | - |

### `get_session_log`

Return the current session log snapshot: commands executed and artifacts produced.

- Commands: `get_session_log`

Parameters:

_None._

### `get_session_state`

Inspect the current Button Heist session: connection status, device/app identity, recording state, client timeouts, and a lightweight summary of the last action.

- Commands: `get_session_state`

Parameters:

_None._

### `list_devices`

List iOS devices discovered via Bonjour plus named targets from .buttonheist.json. Empty when Bonjour is blocked and no config targets exist — use connect(device:token:) directly.

- Commands: `list_devices`

Parameters:

_None._

### `list_targets`

List named connection targets from .buttonheist.json (or ~/.config/buttonheist/config.json), including each target's address and which one is the default.

- Commands: `list_targets`

Parameters:

_None._

### `ping`

Check Button Heist connection health. Returns cheap static app/server identity facts without reading UI hierarchy or accessibility state.

- Commands: `ping`

Parameters:

_None._

### `play_heist`

Play back a .heist file. Steps execute sequentially; playback stops on the first failed step. On failure, returns full diagnostics: command, target, error, action result, expectation result, and a complete interface snapshot at the failure point.

- Commands: `play_heist`

Parameters:

| Parameter | Type | Required | Default | Values |
|-----------|------|----------|---------|--------|
| `input` | `string` | yes | - | - |

### `rotor`

Move through a rotor exposed by an element. Defaults to next. Use rotors listed by get_interface to pick rotor or rotorIndex; pass currentHeistId from the previous object result to continue like a VoiceOver user. For text-range results, also pass the returned start and end offsets.

- Commands: `rotor`

Parameters:

| Parameter | Type | Required | Default | Values |
|-----------|------|----------|---------|--------|
| `heistId` | `string` | no | - | - |
| `label` | `string` | no | - | - |
| `identifier` | `string` | no | - | - |
| `value` | `string` | no | - | - |
| `traits` | `stringArray` | no | - | - |
| `excludeTraits` | `stringArray` | no | - | - |
| `ordinal` | `integer` | no | - | - |
| `rotor` | `string` | no | - | - |
| `rotorIndex` | `integer` | no | - | - |
| `direction` | `string` | no | `"next"` | `next`, `previous` |
| `currentHeistId` | `string` | no | - | - |
| `currentTextStartOffset` | `integer` | no | - | - |
| `currentTextEndOffset` | `integer` | no | - | - |
| `expect` | `object` | no | - | - |
| `timeout` | `number` | no | - | - |

### `run_batch`

Execute multiple commands in one call. Each step is a JSON object with 'command' set to a canonical TheFence.Command name plus that command's parameters; grouped MCP tool names and selector shapes are not accepted inside batches. Attach 'expect' per step to verify inline. Returns ordered per-step results. policy=stop_on_error (default) or continue_on_error.

- Commands: `run_batch`

Parameters:

| Parameter | Type | Required | Default | Values |
|-----------|------|----------|---------|--------|
| `steps` | `array` | yes | - | - |
| `policy` | `string` | no | - | `stop_on_error`, `continue_on_error` |

### `scroll`

Scroll within scroll views. mode=page scrolls one page in 'direction'; mode=to_visible brings a known element into view; mode=search scrolls until a matching element is found; mode=to_edge scrolls to a top/bottom/left/right edge.

- Commands: `scroll`, `scroll_to_visible`, `element_search`, `scroll_to_edge`
- Selector: `mode`
- Selector default: `page`
- Selector routes: `page` -> `scroll`, `search` -> `element_search`, `to_edge` -> `scroll_to_edge`, `to_visible` -> `scroll_to_visible`

Parameters:

| Parameter | Type | Required | Default | Values |
|-----------|------|----------|---------|--------|
| `stableId` | `string` | no | - | - |
| `captureLocalRef` | `string` | no | - | - |
| `container` | `object` | no | - | - |
| `heistId` | `string` | no | - | - |
| `label` | `string` | no | - | - |
| `identifier` | `string` | no | - | - |
| `value` | `string` | no | - | - |
| `traits` | `stringArray` | no | - | - |
| `excludeTraits` | `stringArray` | no | - | - |
| `ordinal` | `integer` | no | - | - |
| `direction` | `string` | no | `"down"` | `up`, `down`, `left`, `right`, `next`, `previous` |
| `expect` | `object` | no | - | - |
| `timeout` | `number` | no | - | - |
| `edge` | `string` | no | `"top"` | `top`, `bottom`, `left`, `right` |
| `mode` | `string` | no | - | `page`, `to_visible`, `search`, `to_edge` |

### `set_pasteboard`

Write text to the general pasteboard from within the app. Content written by the app itself does not trigger the iOS "Allow Paste" dialog when subsequently read.

- Commands: `set_pasteboard`

Parameters:

| Parameter | Type | Required | Default | Values |
|-----------|------|----------|---------|--------|
| `text` | `string` | yes | - | - |
| `expect` | `object` | no | - | - |
| `timeout` | `number` | no | - | - |

### `start_heist`

Start recording a heist. Successful commands become steps in a .heist file; the recorder derives minimum matcher fields for durable element targeting; heistId remains recording evidence only. Attach 'expect' to validate outcomes during playback.

- Commands: `start_heist`

Parameters:

| Parameter | Type | Required | Default | Values |
|-----------|------|----------|---------|--------|
| `app` | `string` | no | - | - |
| `identifier` | `string` | no | - | - |

### `start_recording`

Start an H.264/MP4 screen recording. Recording runs until max duration unless inactivity_timeout is explicitly supplied.

- Commands: `start_recording`

Parameters:

| Parameter | Type | Required | Default | Values |
|-----------|------|----------|---------|--------|
| `fps` | `integer` | no | - | - |
| `scale` | `number` | no | - | - |
| `max_duration` | `number` | no | - | - |
| `inactivity_timeout` | `number` | no | - | - |

### `stop_heist`

Stop recording and save the heist as a self-contained JSON playback script. Returns the file path and step count. At least one step must have been recorded.

- Commands: `stop_heist`

Parameters:

| Parameter | Type | Required | Default | Values |
|-----------|------|----------|---------|--------|
| `output` | `string` | yes | - | - |

### `stop_recording`

Stop an in-progress screen recording. Returns artifact path and metadata by default. Set inlineData=true and/or includeInteractionLog=true for a capped expanded JSON response.

- Commands: `stop_recording`

Parameters:

| Parameter | Type | Required | Default | Values |
|-----------|------|----------|---------|--------|
| `output` | `string` | no | - | - |
| `inlineData` | `boolean` | no | - | - |
| `includeInteractionLog` | `boolean` | no | - | - |

### `type_text`

Type non-empty text via keyboard injection. Optionally target an element to focus it first and read back the resulting value.

- Commands: `type_text`

Parameters:

| Parameter | Type | Required | Default | Values |
|-----------|------|----------|---------|--------|
| `heistId` | `string` | no | - | - |
| `label` | `string` | no | - | - |
| `identifier` | `string` | no | - | - |
| `value` | `string` | no | - | - |
| `traits` | `stringArray` | no | - | - |
| `excludeTraits` | `stringArray` | no | - | - |
| `ordinal` | `integer` | no | - | - |
| `text` | `string` | yes | - | - |
| `expect` | `object` | no | - | - |
| `timeout` | `number` | no | - | - |

### `wait_for`

Wait for an element matching a predicate to appear, or to disappear with absent=true. Polls on UI settle events. Returns the matched element or diagnostic info on timeout.

- Commands: `wait_for`

Parameters:

| Parameter | Type | Required | Default | Values |
|-----------|------|----------|---------|--------|
| `heistId` | `string` | no | - | - |
| `label` | `string` | no | - | - |
| `identifier` | `string` | no | - | - |
| `value` | `string` | no | - | - |
| `traits` | `stringArray` | no | - | - |
| `excludeTraits` | `stringArray` | no | - | - |
| `ordinal` | `integer` | no | - | - |
| `absent` | `boolean` | no | - | - |
| `timeout` | `number` | no | - | - |
| `expect` | `object` | no | - | - |

### `wait_for_change`

Wait for the UI to change. With no expect, returns on any tree change. With expect, rides through intermediate states (spinners, loading) until the expectation is met. Use after an action whose delta showed a transient state and the expectation wasn't met yet.

- Commands: `wait_for_change`

Parameters:

| Parameter | Type | Required | Default | Values |
|-----------|------|----------|---------|--------|
| `expect` | `object` | no | - | - |
| `timeout` | `number` | no | - | - |

