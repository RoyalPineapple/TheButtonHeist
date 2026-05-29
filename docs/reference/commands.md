# ButtonHeist Command Reference

_Generated from `TheFence.Command.descriptors`._

## Summary

| Command | CLI | MCP | Batch | Description |
|---------|-----|-----|-------|-------------|
| `activate` | `activate` | direct | yes | Activate a UI element (VoiceOver-style double-tap): tap buttons, follow links, toggle controls. Pass 'action' to invoke a named action like "increment", "decrement", or any entry from the element's actions array. |
| `archive_session` | `archive_session` | direct | no | Close and compress the current session into a .tar.gz archive; returns the path. |
| `connect` | `connect` | direct | no | Establish or switch the active connection to an iOS app with Button Heist enabled. Three patterns: target=NAME from .buttonheist.json, device=HOST:PORT + token, or BUTTONHEIST_DEVICE/BUTTONHEIST_TOKEN env vars. Tears down any existing session first. Returns session state; call get_interface explicitly to observe UI hierarchy. |
| `dismiss_keyboard` | `dismiss_keyboard` | direct | yes | Dismiss the on-screen keyboard through the current first responder or keyboard action path. |
| `drag` | `drag` | direct | yes | Drag from one point to another using explicit coordinates or a semantic target. |
| `draw_bezier` | `draw_bezier` | direct | yes | Draw a Bezier path from a start point through one or more curve segments. |
| `draw_path` | `draw_path` | direct | yes | Draw a free-form path through explicit screen-coordinate points. |
| `edit_action` | `edit_action` | direct | yes | Perform an edit or keyboard action on the current first responder. Actions: copy, paste, cut, select, selectAll, delete. Use dismiss_keyboard to dismiss the keyboard. |
| `element_search` | `element_search` | direct | yes | Search scrollable content for a semantic element match without performing an action. |
| `get_interface` | `get_interface` | direct | no | Read the app accessibility hierarchy. Call once on a new screen, then track changes via action deltas — re-fetch only when you need elements the delta didn't cover. Omit subtree for the whole hierarchy, or pass subtree to select the returned tree from a selected leaf or container node. |
| `get_pasteboard` | `get_pasteboard` | direct | no | Read text from the general pasteboard. iOS may show "Allow Paste" if the content was written by another app. |
| `get_screen` | `get_screen` | direct | no | Capture a PNG screenshot from the connected device. Returns metadata plus an artifact path by default. Set inlineData=true to return capped base64 PNG data inline; set includeInterface=true to include the fresh visible accessibility tree. |
| `get_session_log` | `get_session_log` | direct | no | Return the current session log snapshot: commands executed and artifacts produced. |
| `get_session_state` | `get_session_state` | direct | no | Inspect the current Button Heist session: connection status, device/app identity, recording state, client timeouts, and a lightweight summary of the last action. |
| `help` | `help` | - | no | Return descriptor-backed help for the current Button Heist command surface. |
| `list_devices` | `list_devices` | direct | no | List iOS devices discovered via Bonjour plus named targets from .buttonheist.json. Empty when Bonjour is blocked and no config targets exist — use connect(device:token:) directly. |
| `list_targets` | `list_targets` | direct | no | List named connection targets from .buttonheist.json (or ~/.config/buttonheist/config.json), including each target's address and which one is the default. |
| `long_press` | `long_press` | direct | yes | Long-press a coordinate or semantic target for a resolved duration. |
| `one_finger_tap` | `one_finger_tap` | direct | yes | Tap a coordinate or semantic target after actionability resolution. |
| `pinch` | `pinch` | direct | yes | Pinch around a resolved center point using scale, angle, and duration. |
| `ping` | `ping` | direct | no | Check Button Heist connection health. Returns cheap static app/server identity facts without reading UI hierarchy or accessibility state. |
| `play_heist` | `play_heist` | direct | no | Play back a .heist file. Steps execute sequentially; playback stops on the first failed step. On failure, returns full diagnostics: command, target, error, action result, expectation result, and a complete interface snapshot at the failure point. |
| `quit` | `quit` | - | no | End the interactive CLI session. |
| `rotate` | `rotate` | direct | yes | Rotate around a resolved center point using angle, radius, and duration. |
| `rotor` | `rotor` | direct | yes | Move through a rotor exposed by an element. Defaults to next. Use rotors listed by get_interface to pick rotor or rotorIndex; pass currentHeistId from the previous object result to continue like a VoiceOver user. For text-range results, also pass the returned start and end offsets. |
| `run_batch` | `run_batch` | direct | no | Execute multiple commands in one call. Each step is a JSON object with 'command' set to a canonical TheFence.Command name plus that command's parameters. Attach 'expect' per step to verify inline. Returns ordered per-step results. policy=stop_on_error (default) or continue_on_error. |
| `scroll` | `scroll` | direct | yes | Scroll one page within scroll views in the requested direction. Use scroll_to_visible, element_search, or scroll_to_edge for those canonical operations. |
| `scroll_to_edge` | `scroll_to_edge` | direct | yes | Scroll the selected container, or the target's owning scroll ancestor, to a requested edge. |
| `scroll_to_visible` | `scroll_to_visible` | direct | yes | Make a semantic target visible by resolving it, revealing its owning scroll path, refreshing the hierarchy, and returning fresh live geometry. |
| `set_pasteboard` | `set_pasteboard` | direct | yes | Write text to the general pasteboard from within the app. Content written by the app itself does not trigger the iOS "Allow Paste" dialog when subsequently read. |
| `start_heist` | `start_heist` | direct | no | Start recording a heist. Successful commands become steps in a .heist file; the recorder derives minimum matcher fields for durable element targeting; heistId remains recording evidence only. Attach 'expect' to validate outcomes during playback. |
| `start_recording` | `start_recording` | direct | no | Start an H.264/MP4 screen recording. Recording runs until max duration unless inactivity_timeout is explicitly supplied. |
| `stop_heist` | `stop_heist` | direct | no | Stop recording and save the heist as a self-contained JSON playback script. Returns the file path and step count. At least one step must have been recorded. |
| `stop_recording` | `stop_recording` | direct | no | Stop an in-progress screen recording. Returns artifact path and metadata by default. Set inlineData=true and/or includeInteractionLog=true for a capped expanded JSON response. |
| `swipe` | `swipe` | direct | yes | Swipe in a direction or between explicit points; semantic targets are made actionable first. |
| `two_finger_tap` | `two_finger_tap` | direct | yes | Tap with two fingers at a coordinate or actionable semantic target. |
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
| `target` | `object` | no | - | - |
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

### `dismiss_keyboard`

Dismiss the on-screen keyboard through the current first responder or keyboard action path.

- CLI: direct command `dismiss_keyboard`
- MCP: direct tool
- Batch: yes
- Playback: yes
- Connection before dispatch: yes

Parameters:

| Parameter | Type | Required | Default | Values |
|-----------|------|----------|---------|--------|
| `expect` | `object` | no | - | - |
| `timeout` | `number` | no | - | - |

### `drag`

Drag from one point to another using explicit coordinates or a semantic target.

- CLI: direct command `drag`
- MCP: direct tool
- Batch: yes
- Playback: yes
- Connection before dispatch: yes

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

- CLI: direct command `draw_bezier`
- MCP: direct tool
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

Draw a free-form path through explicit screen-coordinate points.

- CLI: direct command `draw_path`
- MCP: direct tool
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

Perform an edit or keyboard action on the current first responder. Actions: copy, paste, cut, select, selectAll, delete. Use dismiss_keyboard to dismiss the keyboard.

- CLI: direct command `edit_action`
- MCP: direct tool
- Batch: yes
- Playback: yes
- Connection before dispatch: yes

Parameters:

| Parameter | Type | Required | Default | Values |
|-----------|------|----------|---------|--------|
| `action` | `string` | yes | - | `copy`, `paste`, `cut`, `select`, `selectAll`, `delete` |
| `expect` | `object` | no | - | - |
| `timeout` | `number` | no | - | - |

### `element_search`

Search scrollable content for a semantic element match without performing an action.

- CLI: direct command `element_search`
- MCP: direct tool
- Batch: yes
- Playback: yes
- Connection before dispatch: yes

Parameters:

| Parameter | Type | Required | Default | Values |
|-----------|------|----------|---------|--------|
| `target` | `object` | no | - | - |
| `direction` | `string` | no | - | `down`, `up`, `left`, `right` |
| `expect` | `object` | no | - | - |
| `timeout` | `number` | no | - | - |

### `get_interface`

Read the app accessibility hierarchy. Call once on a new screen, then track changes via action deltas — re-fetch only when you need elements the delta didn't cover. Omit subtree for the whole hierarchy, or pass subtree to select the returned tree from a selected leaf or container node.

- CLI: direct command `get_interface`
- MCP: direct tool
- Batch: no
- Playback: no
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

Return descriptor-backed help for the current Button Heist command surface.

- CLI: session-only `help`
- MCP: not exposed
- Batch: no
- Playback: no
- Connection before dispatch: no

Parameters:

_None._

### `list_devices`

List iOS devices discovered via Bonjour plus named targets from .buttonheist.json. Empty when Bonjour is blocked and no config targets exist — use connect(device:token:) directly.

- CLI: direct command `list_devices`
- MCP: direct tool
- Batch: no
- Playback: no
- Connection before dispatch: no

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

Long-press a coordinate or semantic target for a resolved duration.

- CLI: direct command `long_press`
- MCP: direct tool
- Batch: yes
- Playback: yes
- Connection before dispatch: yes

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

- CLI: direct command `one_finger_tap`
- MCP: direct tool
- Batch: yes
- Playback: yes
- Connection before dispatch: yes

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

- CLI: direct command `pinch`
- MCP: direct tool
- Batch: yes
- Playback: yes
- Connection before dispatch: yes

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

End the interactive CLI session.

- CLI: session-only `quit`
- MCP: not exposed
- Batch: no
- Playback: no
- Connection before dispatch: yes

Parameters:

_None._

### `rotate`

Rotate around a resolved center point using angle, radius, and duration.

- CLI: direct command `rotate`
- MCP: direct tool
- Batch: yes
- Playback: yes
- Connection before dispatch: yes

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

Move through a rotor exposed by an element. Defaults to next. Use rotors listed by get_interface to pick rotor or rotorIndex; pass currentHeistId from the previous object result to continue like a VoiceOver user. For text-range results, also pass the returned start and end offsets.

- CLI: direct command `rotor`
- MCP: direct tool
- Batch: yes
- Playback: yes
- Connection before dispatch: yes

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

Execute multiple commands in one call. Each step is a JSON object with 'command' set to a canonical TheFence.Command name plus that command's parameters. Attach 'expect' per step to verify inline. Returns ordered per-step results. policy=stop_on_error (default) or continue_on_error.

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

Scroll one page within scroll views in the requested direction. Use scroll_to_visible, element_search, or scroll_to_edge for those canonical operations.

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
| `target` | `object` | no | - | - |
| `direction` | `string` | no | `"down"` | `up`, `down`, `left`, `right` |
| `expect` | `object` | no | - | - |
| `timeout` | `number` | no | - | - |

### `scroll_to_edge`

Scroll the selected container, or the target's owning scroll ancestor, to a requested edge.

- CLI: direct command `scroll_to_edge`
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
| `target` | `object` | no | - | - |
| `edge` | `string` | no | `"top"` | `top`, `bottom`, `left`, `right` |
| `expect` | `object` | no | - | - |
| `timeout` | `number` | no | - | - |

### `scroll_to_visible`

Make a semantic target visible by resolving it, revealing its owning scroll path, refreshing the hierarchy, and returning fresh live geometry.

- CLI: direct command `scroll_to_visible`
- MCP: direct tool
- Batch: yes
- Playback: yes
- Connection before dispatch: yes

Parameters:

| Parameter | Type | Required | Default | Values |
|-----------|------|----------|---------|--------|
| `target` | `object` | no | - | - |
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

Parameters:

| Parameter | Type | Required | Default | Values |
|-----------|------|----------|---------|--------|
| `fps` | `integer` | no | - | - |
| `scale` | `number` | no | - | - |
| `max_duration` | `number` | no | - | - |
| `inactivity_timeout` | `number` | no | - | - |

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

Swipe in a direction or between explicit points; semantic targets are made actionable first.

- CLI: direct command `swipe`
- MCP: direct tool
- Batch: yes
- Playback: yes
- Connection before dispatch: yes

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

- CLI: direct command `two_finger_tap`
- MCP: direct tool
- Batch: yes
- Playback: yes
- Connection before dispatch: yes

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

Type non-empty text via keyboard injection. Optionally target an element to focus it first and read back the resulting value.

- CLI: direct command `type_text`
- MCP: direct tool
- Batch: yes
- Playback: yes
- Connection before dispatch: yes

Parameters:

| Parameter | Type | Required | Default | Values |
|-----------|------|----------|---------|--------|
| `target` | `object` | no | - | - |
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

Parameters:

| Parameter | Type | Required | Default | Values |
|-----------|------|----------|---------|--------|
| `target` | `object` | no | - | - |
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

Parameters:

| Parameter | Type | Required | Default | Values |
|-----------|------|----------|---------|--------|
| `expect` | `object` | no | - | - |
| `timeout` | `number` | no | - | - |

