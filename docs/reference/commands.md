# ButtonHeist Command Reference

_Generated from `TheFence.Command.descriptors`._

## Summary

| Command | CLI | MCP | Batch | Description |
|---------|-----|-----|-------|-------------|
| `activate` | `activate` | direct | yes | Activate a UI element (VoiceOver-style double-tap): tap buttons, follow links, toggle controls. Pass 'action' to invoke a named action like "increment", "decrement", or any entry from the element's actions array. |
| `archive_session` | `archive_session` | direct | no | Close and compress the current session into a .tar.gz archive; returns the path. |
| `connect` | `connect` | direct | no | Establish or switch the active connection to an iOS app with Button Heist enabled. Three patterns: target=NAME from .buttonheist.json, device=HOST:PORT + token, or BUTTONHEIST_DEVICE/BUTTONHEIST_TOKEN env vars. Tears down any existing session first. Returns session state; call get_interface explicitly to observe UI hierarchy. |
| `decrement` | `activate` | - | yes | Execute the decrement Button Heist tool. |
| `dismiss_keyboard` | `dismiss_keyboard` | `edit_action` | yes | Execute the dismiss_keyboard Button Heist tool. |
| `drag` | `drag` | `gesture` | yes | Execute the drag Button Heist tool. |
| `draw_bezier` | `draw_bezier` | `gesture` | yes | Execute the draw_bezier Button Heist tool. |
| `draw_path` | `draw_path` | `gesture` | yes | Execute the draw_path Button Heist tool. |
| `edit_action` | `edit_action` | direct | yes | Perform an edit or keyboard action on the current first responder. Actions: copy, paste, cut, select, selectAll, delete, dismiss (dismiss the keyboard). |
| `element_search` | `element_search` | `scroll` | yes | Execute the element_search Button Heist tool. |
| `exit` | `exit` | - | no | Execute the exit Button Heist tool. |
| `get_interface` | `get_interface` | direct | no | Read the app accessibility hierarchy. Call once on a new screen, then track changes via action deltas — re-fetch only when you need elements the delta didn't cover. Omit subtree for the whole hierarchy, or pass subtree to select the returned tree from a selected leaf or container node. |
| `get_pasteboard` | `get_pasteboard` | direct | no | Read text from the general pasteboard. iOS may show "Allow Paste" if the content was written by another app. |
| `get_screen` | `get_screen` | direct | no | Capture a PNG screenshot from the connected device. Returns metadata plus an artifact path by default. Set inlineData=true to return capped base64 PNG data inline; set includeInterface=true to include the fresh visible accessibility tree. |
| `get_session_log` | `get_session_log` | direct | no | Return the current session log snapshot: commands executed and artifacts produced. |
| `get_session_state` | `get_session_state` | direct | no | Inspect the current Button Heist session: connection status, device/app identity, recording state, client timeouts, and a lightweight summary of the last action. |
| `help` | `help` | - | no | Execute the help Button Heist tool. |
| `increment` | `activate` | - | yes | Execute the increment Button Heist tool. |
| `list_devices` | `list_devices` | direct | no | List iOS devices discovered via Bonjour plus named targets from .buttonheist.json. Empty when Bonjour is blocked and no config targets exist — use connect(device:token:) directly. |
| `list_targets` | `list_targets` | direct | no | List named connection targets from .buttonheist.json (or ~/.config/buttonheist/config.json), including each target's address and which one is the default. |
| `long_press` | `long_press` | `gesture` | yes | Execute the long_press Button Heist tool. |
| `one_finger_tap` | `one_finger_tap` | `gesture` | yes | Execute the one_finger_tap Button Heist tool. |
| `perform_custom_action` | `activate` | - | yes | Execute the perform_custom_action Button Heist tool. |
| `pinch` | `pinch` | `gesture` | yes | Execute the pinch Button Heist tool. |
| `ping` | `ping` | direct | no | Check Button Heist connection health. Returns cheap static app/server identity facts without reading UI hierarchy or accessibility state. |
| `play_heist` | `play_heist` | direct | no | Play back a .heist file. Steps execute sequentially; playback stops on the first failed step. On failure, returns full diagnostics: command, target, error, action result, expectation result, and a complete interface snapshot at the failure point. |
| `quit` | `quit` | - | no | Execute the quit Button Heist tool. |
| `rotate` | `rotate` | `gesture` | yes | Execute the rotate Button Heist tool. |
| `rotor` | `rotor` | direct | yes | Move through a rotor exposed by an element. Defaults to next. Use rotors listed by get_interface to pick rotor or rotorIndex; pass currentHeistId from the previous object result to continue like a VoiceOver user. For text-range results, also pass the returned start and end offsets. |
| `run_batch` | `run_batch` | direct | no | Execute multiple commands in one call. Each step is a JSON object with 'command' set to a canonical TheFence.Command name plus that command's parameters; grouped MCP tool names and selector shapes are not accepted inside batches. Attach 'expect' per step to verify inline. Returns ordered per-step results. policy=stop_on_error (default) or continue_on_error. |
| `scroll` | `scroll` | direct | yes | Scroll within scroll views. mode=page scrolls one page in 'direction'; mode=to_visible brings a known element into view; mode=search scrolls until a matching element is found; mode=to_edge scrolls to a top/bottom/left/right edge. |
| `scroll_to_edge` | `scroll_to_edge` | `scroll` | yes | Execute the scroll_to_edge Button Heist tool. |
| `scroll_to_visible` | `scroll_to_visible` | `scroll` | yes | Execute the scroll_to_visible Button Heist tool. |
| `set_pasteboard` | `set_pasteboard` | direct | yes | Write text to the general pasteboard from within the app. Content written by the app itself does not trigger the iOS "Allow Paste" dialog when subsequently read. |
| `start_heist` | `start_heist` | direct | no | Start recording a heist. Successful commands become steps in a .heist file; the recorder derives minimum matcher fields for durable element targeting; heistId remains recording evidence only. Attach 'expect' to validate outcomes during playback. |
| `start_recording` | `start_recording` | direct | no | Start an H.264/MP4 screen recording. Recording runs until max duration unless inactivity_timeout is explicitly supplied. |
| `status` | `status` | - | no | Execute the status Button Heist tool. |
| `stop_heist` | `stop_heist` | direct | no | Stop recording and save the heist as a self-contained JSON playback script. Returns the file path and step count. At least one step must have been recorded. |
| `stop_recording` | `stop_recording` | direct | no | Stop an in-progress screen recording. Returns artifact path and metadata by default. Set inlineData=true and/or includeInteractionLog=true for a capped expanded JSON response. |
| `swipe` | `swipe` | `gesture` | yes | Execute the swipe Button Heist tool. |
| `two_finger_tap` | `two_finger_tap` | `gesture` | yes | Execute the two_finger_tap Button Heist tool. |
| `type_text` | `type_text` | direct | yes | Type non-empty text via keyboard injection. Optionally target an element to focus it first and read back the resulting value. |
| `wait_for` | `wait_for` | direct | yes | Wait for an element matching a predicate to appear, or to disappear with absent=true. Polls on UI settle events. Returns the matched element or diagnostic info on timeout. |
| `wait_for_change` | `wait_for_change` | direct | yes | Wait for the UI to change. With no expect, returns on any tree change. With expect, rides through intermediate states (spinners, loading) until the expectation is met. Use after an action whose delta showed a transient state and the expectation wasn't met yet. |

## Details

### `activate`

Activate a UI element (VoiceOver-style double-tap): tap buttons, follow links, toggle controls. Pass 'action' to invoke a named action like "increment", "decrement", or any entry from the element's actions array.

- CLI: direct command `activate`
- MCP: direct tool
- Batch: yes
- Playback: yes
- Connection before dispatch: yes

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

- CLI: direct command `archive_session`
- MCP: direct tool
- Batch: no
- Playback: no
- Connection before dispatch: no

Parameters:

| Parameter | Type | Required | Default | Values |
|-----------|------|----------|---------|--------|
| `delete_source` | `boolean` | no | - | - |

### `connect`

Establish or switch the active connection to an iOS app with Button Heist enabled. Three patterns: target=NAME from .buttonheist.json, device=HOST:PORT + token, or BUTTONHEIST_DEVICE/BUTTONHEIST_TOKEN env vars. Tears down any existing session first. Returns session state; call get_interface explicitly to observe UI hierarchy.

- CLI: direct command `connect`
- MCP: direct tool
- Batch: no
- Playback: no
- Connection before dispatch: no

Parameters:

| Parameter | Type | Required | Default | Values |
|-----------|------|----------|---------|--------|
| `target` | `string` | no | - | - |
| `device` | `string` | no | - | - |
| `token` | `string` | no | - | - |

### `decrement`

Execute the decrement Button Heist tool.

- CLI: grouped under `activate`
- MCP: not exposed
- Batch: yes
- Playback: yes
- Connection before dispatch: yes

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
| `count` | `integer` | no | - | - |
| `expect` | `object` | no | - | - |
| `timeout` | `number` | no | - | - |

### `dismiss_keyboard`

Execute the dismiss_keyboard Button Heist tool.

- CLI: direct command `dismiss_keyboard`
- MCP: grouped under `edit_action`
- Batch: yes
- Playback: yes
- Connection before dispatch: yes

Parameters:

| Parameter | Type | Required | Default | Values |
|-----------|------|----------|---------|--------|
| `expect` | `object` | no | - | - |
| `timeout` | `number` | no | - | - |

### `drag`

Execute the drag Button Heist tool.

- CLI: direct command `drag`
- MCP: grouped under `gesture`
- Batch: yes
- Playback: yes
- Connection before dispatch: yes

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
| `endX` | `number` | yes | - | - |
| `endY` | `number` | yes | - | - |
| `startX` | `number` | no | - | - |
| `startY` | `number` | no | - | - |
| `duration` | `number` | no | - | - |
| `expect` | `object` | no | - | - |
| `timeout` | `number` | no | - | - |

### `draw_bezier`

Execute the draw_bezier Button Heist tool.

- CLI: direct command `draw_bezier`
- MCP: grouped under `gesture`
- Batch: yes
- Playback: yes
- Connection before dispatch: yes

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

Execute the draw_path Button Heist tool.

- CLI: direct command `draw_path`
- MCP: grouped under `gesture`
- Batch: yes
- Playback: yes
- Connection before dispatch: yes

Parameters:

| Parameter | Type | Required | Default | Values |
|-----------|------|----------|---------|--------|
| `points` | `array` | yes | - | - |
| `duration` | `number` | no | - | - |
| `velocity` | `number` | no | - | - |
| `expect` | `object` | no | - | - |
| `timeout` | `number` | no | - | - |

### `edit_action`

Perform an edit or keyboard action on the current first responder. Actions: copy, paste, cut, select, selectAll, delete, dismiss (dismiss the keyboard).

- CLI: direct command `edit_action`
- MCP: direct tool
- Batch: yes
- Playback: yes
- Connection before dispatch: yes
- Human aliases: `copy`, `cut`, `delete`, `paste`, `select`, `select_all`

Parameters:

| Parameter | Type | Required | Default | Values |
|-----------|------|----------|---------|--------|
| `action` | `string` | yes | - | `copy`, `paste`, `cut`, `select`, `selectAll`, `delete` |
| `expect` | `object` | no | - | - |
| `timeout` | `number` | no | - | - |

### `element_search`

Execute the element_search Button Heist tool.

- CLI: direct command `element_search`
- MCP: grouped under `scroll`
- Batch: yes
- Playback: yes
- Connection before dispatch: yes

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
| `direction` | `string` | no | - | `down`, `up`, `left`, `right` |
| `expect` | `object` | no | - | - |
| `timeout` | `number` | no | - | - |

### `exit`

Execute the exit Button Heist tool.

- CLI: session-only `exit`
- MCP: not exposed
- Batch: no
- Playback: no
- Connection before dispatch: yes

Parameters:

_None._

### `get_interface`

Read the app accessibility hierarchy. Call once on a new screen, then track changes via action deltas — re-fetch only when you need elements the delta didn't cover. Omit subtree for the whole hierarchy, or pass subtree to select the returned tree from a selected leaf or container node.

- CLI: direct command `get_interface`
- MCP: direct tool
- Batch: no
- Playback: no
- Connection before dispatch: yes
- Human aliases: `ui`

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

- CLI: direct command `get_pasteboard`
- MCP: direct tool
- Batch: no
- Playback: no
- Connection before dispatch: yes

Parameters:

_None._

### `get_screen`

Capture a PNG screenshot from the connected device. Returns metadata plus an artifact path by default. Set inlineData=true to return capped base64 PNG data inline; set includeInterface=true to include the fresh visible accessibility tree.

- CLI: direct command `get_screen`
- MCP: direct tool
- Batch: no
- Playback: no
- Connection before dispatch: yes
- Human aliases: `screen`, `screenshot`

Parameters:

| Parameter | Type | Required | Default | Values |
|-----------|------|----------|---------|--------|
| `output` | `string` | no | - | - |
| `inlineData` | `boolean` | no | - | - |
| `includeInterface` | `boolean` | no | - | - |

### `get_session_log`

Return the current session log snapshot: commands executed and artifacts produced.

- CLI: direct command `get_session_log`
- MCP: direct tool
- Batch: no
- Playback: no
- Connection before dispatch: no

Parameters:

_None._

### `get_session_state`

Inspect the current Button Heist session: connection status, device/app identity, recording state, client timeouts, and a lightweight summary of the last action.

- CLI: direct command `get_session_state`
- MCP: direct tool
- Batch: no
- Playback: no
- Connection before dispatch: no

Parameters:

_None._

### `help`

Execute the help Button Heist tool.

- CLI: session-only `help`
- MCP: not exposed
- Batch: no
- Playback: no
- Connection before dispatch: yes

Parameters:

_None._

### `increment`

Execute the increment Button Heist tool.

- CLI: grouped under `activate`
- MCP: not exposed
- Batch: yes
- Playback: yes
- Connection before dispatch: yes

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
| `count` | `integer` | no | - | - |
| `expect` | `object` | no | - | - |
| `timeout` | `number` | no | - | - |

### `list_devices`

List iOS devices discovered via Bonjour plus named targets from .buttonheist.json. Empty when Bonjour is blocked and no config targets exist — use connect(device:token:) directly.

- CLI: direct command `list_devices`
- MCP: direct tool
- Batch: no
- Playback: no
- Connection before dispatch: no
- Human aliases: `devices`, `list`

Parameters:

_None._

### `list_targets`

List named connection targets from .buttonheist.json (or ~/.config/buttonheist/config.json), including each target's address and which one is the default.

- CLI: direct command `list_targets`
- MCP: direct tool
- Batch: no
- Playback: no
- Connection before dispatch: no

Parameters:

_None._

### `long_press`

Execute the long_press Button Heist tool.

- CLI: direct command `long_press`
- MCP: grouped under `gesture`
- Batch: yes
- Playback: yes
- Connection before dispatch: yes
- Human aliases: `press`

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
| `duration` | `number` | no | - | - |
| `expect` | `object` | no | - | - |
| `timeout` | `number` | no | - | - |

### `one_finger_tap`

Execute the one_finger_tap Button Heist tool.

- CLI: direct command `one_finger_tap`
- MCP: grouped under `gesture`
- Batch: yes
- Playback: yes
- Connection before dispatch: yes
- Human aliases: `tap`

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

### `perform_custom_action`

Execute the perform_custom_action Button Heist tool.

- CLI: grouped under `activate`
- MCP: not exposed
- Batch: yes
- Playback: yes
- Connection before dispatch: yes

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
| `container` | `object` | no | - | - |
| `action` | `string` | yes | - | - |
| `expect` | `object` | no | - | - |
| `timeout` | `number` | no | - | - |

### `pinch`

Execute the pinch Button Heist tool.

- CLI: direct command `pinch`
- MCP: grouped under `gesture`
- Batch: yes
- Playback: yes
- Connection before dispatch: yes

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
| `scale` | `number` | yes | - | - |
| `centerX` | `number` | no | - | - |
| `centerY` | `number` | no | - | - |
| `spread` | `number` | no | - | - |
| `duration` | `number` | no | - | - |
| `expect` | `object` | no | - | - |
| `timeout` | `number` | no | - | - |

### `ping`

Check Button Heist connection health. Returns cheap static app/server identity facts without reading UI hierarchy or accessibility state.

- CLI: direct command `ping`
- MCP: direct tool
- Batch: no
- Playback: no
- Connection before dispatch: no

Parameters:

_None._

### `play_heist`

Play back a .heist file. Steps execute sequentially; playback stops on the first failed step. On failure, returns full diagnostics: command, target, error, action result, expectation result, and a complete interface snapshot at the failure point.

- CLI: direct command `play_heist`
- MCP: direct tool
- Batch: no
- Playback: no
- Connection before dispatch: yes

Parameters:

| Parameter | Type | Required | Default | Values |
|-----------|------|----------|---------|--------|
| `input` | `string` | yes | - | - |

### `quit`

Execute the quit Button Heist tool.

- CLI: session-only `quit`
- MCP: not exposed
- Batch: no
- Playback: no
- Connection before dispatch: yes

Parameters:

_None._

### `rotate`

Execute the rotate Button Heist tool.

- CLI: direct command `rotate`
- MCP: grouped under `gesture`
- Batch: yes
- Playback: yes
- Connection before dispatch: yes

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
| `angle` | `number` | yes | - | - |
| `centerX` | `number` | no | - | - |
| `centerY` | `number` | no | - | - |
| `radius` | `number` | no | - | - |
| `duration` | `number` | no | - | - |
| `expect` | `object` | no | - | - |
| `timeout` | `number` | no | - | - |

### `rotor`

Move through a rotor exposed by an element. Defaults to next. Use rotors listed by get_interface to pick rotor or rotorIndex; pass currentHeistId from the previous object result to continue like a VoiceOver user. For text-range results, also pass the returned start and end offsets.

- CLI: direct command `rotor`
- MCP: direct tool
- Batch: yes
- Playback: yes
- Connection before dispatch: yes

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

- CLI: direct command `run_batch`
- MCP: direct tool
- Batch: no
- Playback: no
- Connection before dispatch: yes

Parameters:

| Parameter | Type | Required | Default | Values |
|-----------|------|----------|---------|--------|
| `steps` | `array` | yes | - | - |
| `policy` | `string` | no | - | `stop_on_error`, `continue_on_error` |

### `scroll`

Scroll within scroll views. mode=page scrolls one page in 'direction'; mode=to_visible brings a known element into view; mode=search scrolls until a matching element is found; mode=to_edge scrolls to a top/bottom/left/right edge.

- CLI: direct command `scroll`
- MCP: direct tool
- Batch: yes
- Playback: yes
- Connection before dispatch: yes

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

### `scroll_to_edge`

Execute the scroll_to_edge Button Heist tool.

- CLI: direct command `scroll_to_edge`
- MCP: grouped under `scroll`
- Batch: yes
- Playback: yes
- Connection before dispatch: yes

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
| `edge` | `string` | no | `"top"` | `top`, `bottom`, `left`, `right` |
| `expect` | `object` | no | - | - |
| `timeout` | `number` | no | - | - |

### `scroll_to_visible`

Execute the scroll_to_visible Button Heist tool.

- CLI: direct command `scroll_to_visible`
- MCP: grouped under `scroll`
- Batch: yes
- Playback: yes
- Connection before dispatch: yes

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
| `expect` | `object` | no | - | - |
| `timeout` | `number` | no | - | - |

### `set_pasteboard`

Write text to the general pasteboard from within the app. Content written by the app itself does not trigger the iOS "Allow Paste" dialog when subsequently read.

- CLI: direct command `set_pasteboard`
- MCP: direct tool
- Batch: yes
- Playback: yes
- Connection before dispatch: yes

Parameters:

| Parameter | Type | Required | Default | Values |
|-----------|------|----------|---------|--------|
| `text` | `string` | yes | - | - |
| `expect` | `object` | no | - | - |
| `timeout` | `number` | no | - | - |

### `start_heist`

Start recording a heist. Successful commands become steps in a .heist file; the recorder derives minimum matcher fields for durable element targeting; heistId remains recording evidence only. Attach 'expect' to validate outcomes during playback.

- CLI: direct command `start_heist`
- MCP: direct tool
- Batch: no
- Playback: no
- Connection before dispatch: no

Parameters:

| Parameter | Type | Required | Default | Values |
|-----------|------|----------|---------|--------|
| `app` | `string` | no | - | - |
| `identifier` | `string` | no | - | - |

### `start_recording`

Start an H.264/MP4 screen recording. Recording runs until max duration unless inactivity_timeout is explicitly supplied.

- CLI: direct command `start_recording`
- MCP: direct tool
- Batch: no
- Playback: no
- Connection before dispatch: yes
- Human aliases: `record`

Parameters:

| Parameter | Type | Required | Default | Values |
|-----------|------|----------|---------|--------|
| `fps` | `integer` | no | - | - |
| `scale` | `number` | no | - | - |
| `max_duration` | `number` | no | - | - |
| `inactivity_timeout` | `number` | no | - | - |

### `status`

Execute the status Button Heist tool.

- CLI: session-only `status`
- MCP: not exposed
- Batch: no
- Playback: no
- Connection before dispatch: no

Parameters:

_None._

### `stop_heist`

Stop recording and save the heist as a self-contained JSON playback script. Returns the file path and step count. At least one step must have been recorded.

- CLI: direct command `stop_heist`
- MCP: direct tool
- Batch: no
- Playback: no
- Connection before dispatch: no

Parameters:

| Parameter | Type | Required | Default | Values |
|-----------|------|----------|---------|--------|
| `output` | `string` | yes | - | - |

### `stop_recording`

Stop an in-progress screen recording. Returns artifact path and metadata by default. Set inlineData=true and/or includeInteractionLog=true for a capped expanded JSON response.

- CLI: direct command `stop_recording`
- MCP: direct tool
- Batch: no
- Playback: no
- Connection before dispatch: yes

Parameters:

| Parameter | Type | Required | Default | Values |
|-----------|------|----------|---------|--------|
| `output` | `string` | no | - | - |
| `inlineData` | `boolean` | no | - | - |
| `includeInteractionLog` | `boolean` | no | - | - |

### `swipe`

Execute the swipe Button Heist tool.

- CLI: direct command `swipe`
- MCP: grouped under `gesture`
- Batch: yes
- Playback: yes
- Connection before dispatch: yes

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

Execute the two_finger_tap Button Heist tool.

- CLI: direct command `two_finger_tap`
- MCP: grouped under `gesture`
- Batch: yes
- Playback: yes
- Connection before dispatch: yes

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
| `centerX` | `number` | no | - | - |
| `centerY` | `number` | no | - | - |
| `spread` | `number` | no | - | - |
| `expect` | `object` | no | - | - |
| `timeout` | `number` | no | - | - |

### `type_text`

Type non-empty text via keyboard injection. Optionally target an element to focus it first and read back the resulting value.

- CLI: direct command `type_text`
- MCP: direct tool
- Batch: yes
- Playback: yes
- Connection before dispatch: yes
- Human aliases: `type`

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

- CLI: direct command `wait_for`
- MCP: direct tool
- Batch: yes
- Playback: yes
- Connection before dispatch: yes
- Human aliases: `wait`

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

- CLI: direct command `wait_for_change`
- MCP: direct tool
- Batch: yes
- Playback: yes
- Connection before dispatch: yes
- Human aliases: `change`, `idle`

Parameters:

| Parameter | Type | Required | Default | Values |
|-----------|------|----------|---------|--------|
| `expect` | `object` | no | - | - |
| `timeout` | `number` | no | - | - |

