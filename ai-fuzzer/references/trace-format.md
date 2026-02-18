# Action Trace Format

The action trace is a complete, append-only log of every tool call in a fuzzing session. It captures exact parameters, before/after state, and results — enough information for another agent to replay the session deterministically.

## File Naming

The trace file is a companion to the session notes file:

```
session/fuzzsession-2026-02-17-1430-fuzz-systematic-traversal.md        ← session notes
session/fuzzsession-2026-02-17-1430-fuzz-systematic-traversal.trace.md  ← action trace
```

Replace the `.md` extension with `.trace.md`. The two files are always paired.

## File Header

Every trace file starts with a header:

```markdown
# Action Trace

- **Session**: fuzzsession-2026-02-17-1430-fuzz-systematic-traversal.md
- **App**: AccessibilityTestApp
- **Device**: iPhone 16 Pro Simulator
- **Started**: 2026-02-17T14:30:00Z
- **Format version**: 1
```

## Entry Format

Each entry is a markdown heading followed by a fenced YAML block, separated by `---` horizontal rules. The heading provides human-scannable context; the YAML provides machine-parseable data.

```markdown
---

### #N | type | screen name
```yaml
[YAML fields]
`` `
```

Where `N` is the monotonically increasing sequence number, `type` is one of `observe`/`interact`/`navigate`/`snapshot`, and `screen name` is the current screen.

### Writing Entries

Append each entry to the end of the trace file. **Never rewrite the entire file.** The trace is append-only — this means you collect all before/after state for an interaction before writing the single complete entry.

Typical cycle: you'll write 2-3 entries per fuzzing action:
1. An `observe` entry for the pre-action `get_interface`
2. An `interact` entry for the action itself (includes before/after state)
3. An `observe` entry for the post-action `get_interface`

To keep the trace compact, you may **omit the separate pre-action observe entry** if the interact entry already captures `screen_before` and `screen_fingerprint_before`. The post-action observe is still valuable as a divergence checkpoint.

## Entry Types

### `observe` — Interface Observation

Written after every `get_interface` call.

```yaml
seq: 1
ts: "2026-02-17T14:30:01Z"
type: observe
tool: get_interface
screen: "Controls Demo"
screen_fingerprint: ["buttonheist.adjustable", "buttonheist.buttons", "buttonheist.text", "buttonheist.toggles"]
element_count: 9
interactive_count: 7
notes: "Main navigation screen, 7 navigation buttons"
```

**Fields:**

| Field | Required | Description |
|-------|----------|-------------|
| `seq` | yes | Sequence number, monotonically increasing across all entry types |
| `ts` | yes | ISO 8601 timestamp |
| `type` | yes | Always `observe` |
| `tool` | yes | Always `get_interface` (don't trace `get_screen` — screenshots aren't replayable) |
| `screen` | yes | Human-readable screen name |
| `screen_fingerprint` | yes | Sorted list of element identifiers (or labels if no identifier). Used for divergence detection during replay. |
| `element_count` | yes | Total elements returned by `get_interface` |
| `interactive_count` | no | Elements with at least one action |
| `notes` | no | Free-text observation |

**Building the fingerprint:** Extract all element identifiers from the interface. If an element has no identifier, use its label. Sort alphabetically. This sorted list is the fingerprint.

### `interact` — Action Execution

Written after every interaction tool call (`activate`, `tap`, `long_press`, `swipe`, `increment`, `decrement`, `type_text`, `pinch`, `rotate`, `two_finger_tap`, `drag`, `draw_path`, `draw_bezier`, `perform_custom_action`).

```yaml
seq: 2
ts: "2026-02-17T14:30:04Z"
type: interact
tool: activate
args:
  order: 3
target:
  label: "Adjustable Controls"
  identifier: null
  order: 3
  value: null
  actions: ["activate"]
screen_before: "Controls Demo"
screen_fingerprint_before: ["buttonheist.adjustable", "buttonheist.buttons", "buttonheist.text", "buttonheist.toggles"]
result:
  status: success
  method: activate
  screen_changed: true
  screen_after: "Adjustable Controls"
  screen_fingerprint_after: ["buttonheist.adjustable.gauge", "buttonheist.adjustable.lastActionLabel", "buttonheist.adjustable.linearProgress", "buttonheist.adjustable.slider", "buttonheist.adjustable.spinnerProgress", "buttonheist.adjustable.stepper-Decrement", "buttonheist.adjustable.stepper-Increment"]
  element_count_after: 10
  value_after: null
  finding: null
```

**Fields:**

| Field | Required | Description |
|-------|----------|-------------|
| `seq` | yes | Sequence number |
| `ts` | yes | ISO 8601 timestamp |
| `type` | yes | Always `interact` |
| `tool` | yes | Exact MCP tool name |
| `args` | yes | Exact arguments passed to the tool (preserve types — integers stay integers, strings stay strings) |
| `target` | yes* | The element being acted upon. Include `label`, `identifier`, `order`, `value` (before), and `actions` list. *Omit for coordinate-only actions like `tap(x:, y:)` with no element. |
| `screen_before` | yes | Screen name before the action |
| `screen_fingerprint_before` | yes | Fingerprint before |
| `result.status` | yes | `success`, `error`, or `crash` |
| `result.method` | no | The method the tool used (e.g., `activate`, `syntheticTap`) — from the tool's response |
| `result.screen_changed` | yes | Boolean — did the screen transition? |
| `result.screen_after` | yes | Screen name after (same as before if no change) |
| `result.screen_fingerprint_after` | yes | Fingerprint after |
| `result.element_count_after` | yes | Element count after |
| `result.value_after` | no | New value of the target element (for sliders, steppers, text fields, toggles) |
| `result.error` | no | Error message if status is `error` |
| `result.finding` | no | Finding ID (e.g., `F-1`) if this action generated a finding |

### `navigate` — Back-Navigation

Written for deliberate navigation actions that are part of traversal, not fuzzing (e.g., pressing Back to return to a previous screen). Same fields as `interact` but with `type: navigate` and an additional `purpose` field.

```yaml
seq: 8
ts: "2026-02-17T14:30:25Z"
type: navigate
tool: activate
args:
  order: 8
purpose: back_navigation
target:
  label: "Controls Demo"
  identifier: null
  order: 8
  value: null
  actions: ["activate"]
screen_before: "Adjustable Controls"
screen_fingerprint_before: ["buttonheist.adjustable.gauge", "buttonheist.adjustable.slider", "buttonheist.adjustable.stepper-Decrement", "buttonheist.adjustable.stepper-Increment"]
result:
  status: success
  method: syntheticTap
  screen_changed: true
  screen_after: "Controls Demo"
  screen_fingerprint_after: ["buttonheist.adjustable", "buttonheist.buttons", "buttonheist.text", "buttonheist.toggles"]
  element_count_after: 9
  value_after: null
  finding: null
```

**Additional field:**

| Field | Required | Description |
|-------|----------|-------------|
| `purpose` | yes | Why this navigation happened: `back_navigation`, `setup`, `reproduction` |

The `navigate` type lets the reproduce command distinguish "actions that are part of reaching the right screen" from "actions that are the actual fuzz test."

### `snapshot` — Simulator State

Written when saving or restoring a simulator snapshot.

```yaml
seq: 25
ts: "2026-02-17T14:35:00Z"
type: snapshot
action: save
name: "fuzz-20260217-settings-modified"
screen: "Settings"
notes: "Dark mode on, notifications off, before destructive test"
```

**Fields:**

| Field | Required | Description |
|-------|----------|-------------|
| `seq` | yes | Sequence number |
| `ts` | yes | ISO 8601 timestamp |
| `type` | yes | Always `snapshot` |
| `action` | yes | `save` or `restore` |
| `name` | yes | Snapshot name |
| `screen` | yes | Current screen at time of snapshot |
| `notes` | no | Why this snapshot was taken/restored |

## Fingerprint Comparison

During replay, the reproduce agent compares actual screen fingerprints against the trace's recorded fingerprints to detect divergence.

### Algorithm

```
expected = set(trace_entry.screen_fingerprint_after)
actual   = set(current_interface_identifiers)

added    = actual - expected       # new elements not in trace
removed  = expected - actual       # elements missing from trace
overlap  = actual & expected       # common elements
similarity = len(overlap) / max(len(expected), len(actual))
```

### Thresholds

| Similarity | Classification | Action |
|-----------|---------------|--------|
| 100% | Exact match | Continue |
| ≥ 80% | Minor drift | Log and continue (extra elements are common — badges, timestamps) |
| ≥ 50% | Significant drift | Warn, attempt to continue, flag reproduction as uncertain |
| < 50% | Major divergence | App is on a different screen. Abort and report. |

### Element Lookup Fallback

When the trace references an element by identifier but the current interface doesn't have it:

1. **Search by label**: Find elements whose label matches the trace's `target.label`
2. **Search by position**: Find elements whose frame overlaps the trace's target frame
3. If found by alternate method: use it, but log the identifier mismatch
4. If not found at all: skip the action, report "element not found" divergence

## Rapid-Fire Summarization

For stress-test sequences (20x rapid taps, etc.), tracing every individual action creates excessive bloat. Instead, use a summary entry:

```yaml
seq: 15
ts: "2026-02-17T14:32:00Z"
type: interact
tool: tap
args:
  identifier: "loginButton"
target:
  label: "Login"
  identifier: "loginButton"
  order: 2
  value: null
  actions: ["activate"]
screen_before: "Main Menu"
screen_fingerprint_before: ["loginButton", "signUpButton", "forgotPassword"]
result:
  status: success
  screen_changed: false
  screen_after: "Main Menu"
  screen_fingerprint_after: ["loginButton", "signUpButton", "forgotPassword"]
  element_count_after: 8
  value_after: null
  finding: null
  rapid_fire:
    count: 20
    all_succeeded: true
    notes: "20x rapid tap, no state change, no errors"
```

Trace the first action individually, then use `rapid_fire` summary for the batch. If any action in the batch produces an unexpected result, trace that action individually too.

## Complete Example

Below is what a real trace file looks like. Each entry starts with a `### #N` heading followed by a fenced YAML block, separated by `---` rules.

````markdown
# Action Trace

- **Session**: fuzzsession-2026-02-17-1430-fuzz-systematic-traversal.md
- **App**: AccessibilityTestApp
- **Device**: iPhone 16 Pro Simulator
- **Started**: 2026-02-17T14:30:00Z
- **Format version**: 1

---

### #1 | observe | Controls Demo
```yaml
seq: 1
ts: "2026-02-17T14:30:01Z"
type: observe
tool: get_interface
screen: "Controls Demo"
screen_fingerprint: ["buttonheist.adjustable", "buttonheist.alerts", "buttonheist.buttons", "buttonheist.disclosure", "buttonheist.display", "buttonheist.text", "buttonheist.toggles"]
element_count: 9
interactive_count: 7
notes: "Initial screen, 7 navigation buttons"
```

---

### #2 | interact | Controls Demo
```yaml
seq: 2
ts: "2026-02-17T14:30:04Z"
type: interact
tool: activate
args:
  order: 3
target:
  label: "Adjustable Controls"
  identifier: null
  order: 3
  value: null
  actions: ["activate"]
screen_before: "Controls Demo"
screen_fingerprint_before: ["buttonheist.adjustable", "buttonheist.alerts", "buttonheist.buttons", "buttonheist.disclosure", "buttonheist.display", "buttonheist.text", "buttonheist.toggles"]
result:
  status: success
  method: activate
  screen_changed: true
  screen_after: "Adjustable Controls"
  screen_fingerprint_after: ["buttonheist.adjustable.gauge", "buttonheist.adjustable.lastActionLabel", "buttonheist.adjustable.linearProgress", "buttonheist.adjustable.slider", "buttonheist.adjustable.spinnerProgress", "buttonheist.adjustable.stepper-Decrement", "buttonheist.adjustable.stepper-Increment"]
  element_count_after: 10
  value_after: null
  finding: null
```

---

### #3 | observe | Adjustable Controls
```yaml
seq: 3
ts: "2026-02-17T14:30:06Z"
type: observe
tool: get_interface
screen: "Adjustable Controls"
screen_fingerprint: ["buttonheist.adjustable.gauge", "buttonheist.adjustable.lastActionLabel", "buttonheist.adjustable.linearProgress", "buttonheist.adjustable.slider", "buttonheist.adjustable.spinnerProgress", "buttonheist.adjustable.stepper-Decrement", "buttonheist.adjustable.stepper-Increment"]
element_count: 10
interactive_count: 6
notes: "Slider at 50, stepper at 0, gauge at 50%"
```

---

### #4 | interact | Adjustable Controls
```yaml
seq: 4
ts: "2026-02-17T14:30:09Z"
type: interact
tool: increment
args:
  order: 0
target:
  label: "Volume"
  identifier: "buttonheist.adjustable.slider"
  order: 0
  value: "50"
  actions: ["activate", "increment", "decrement"]
screen_before: "Adjustable Controls"
screen_fingerprint_before: ["buttonheist.adjustable.gauge", "buttonheist.adjustable.lastActionLabel", "buttonheist.adjustable.linearProgress", "buttonheist.adjustable.slider", "buttonheist.adjustable.spinnerProgress", "buttonheist.adjustable.stepper-Decrement", "buttonheist.adjustable.stepper-Increment"]
result:
  status: success
  method: increment
  screen_changed: false
  screen_after: "Adjustable Controls"
  screen_fingerprint_after: ["buttonheist.adjustable.gauge", "buttonheist.adjustable.lastActionLabel", "buttonheist.adjustable.linearProgress", "buttonheist.adjustable.slider", "buttonheist.adjustable.spinnerProgress", "buttonheist.adjustable.stepper-Decrement", "buttonheist.adjustable.stepper-Increment"]
  element_count_after: 10
  value_after: "60"
  finding: null
```

---

### #5 | interact | Adjustable Controls
```yaml
seq: 5
ts: "2026-02-17T14:30:12Z"
type: interact
tool: activate
args:
  identifier: "buttonheist.adjustable.stepper-Increment"
target:
  label: "Quantity: 0, Increment"
  identifier: "buttonheist.adjustable.stepper-Increment"
  order: 2
  value: "0"
  actions: ["activate"]
screen_before: "Adjustable Controls"
screen_fingerprint_before: ["buttonheist.adjustable.gauge", "buttonheist.adjustable.lastActionLabel", "buttonheist.adjustable.linearProgress", "buttonheist.adjustable.slider", "buttonheist.adjustable.spinnerProgress", "buttonheist.adjustable.stepper-Decrement", "buttonheist.adjustable.stepper-Increment"]
result:
  status: success
  method: syntheticTap
  screen_changed: false
  screen_after: "Adjustable Controls"
  screen_fingerprint_after: ["buttonheist.adjustable.gauge", "buttonheist.adjustable.lastActionLabel", "buttonheist.adjustable.linearProgress", "buttonheist.adjustable.slider", "buttonheist.adjustable.spinnerProgress", "buttonheist.adjustable.stepper-Decrement", "buttonheist.adjustable.stepper-Increment"]
  element_count_after: 10
  value_after: "1"
  finding: null
```

---

### #6 | navigate | Adjustable Controls
```yaml
seq: 6
ts: "2026-02-17T14:30:15Z"
type: navigate
tool: activate
args:
  order: 8
purpose: back_navigation
target:
  label: "Controls Demo"
  identifier: null
  order: 8
  value: null
  actions: ["activate"]
screen_before: "Adjustable Controls"
screen_fingerprint_before: ["buttonheist.adjustable.gauge", "buttonheist.adjustable.lastActionLabel", "buttonheist.adjustable.linearProgress", "buttonheist.adjustable.slider", "buttonheist.adjustable.spinnerProgress", "buttonheist.adjustable.stepper-Decrement", "buttonheist.adjustable.stepper-Increment"]
result:
  status: success
  method: syntheticTap
  screen_changed: true
  screen_after: "Controls Demo"
  screen_fingerprint_after: ["buttonheist.adjustable", "buttonheist.alerts", "buttonheist.buttons", "buttonheist.disclosure", "buttonheist.display", "buttonheist.text", "buttonheist.toggles"]
  element_count_after: 9
  value_after: null
  finding: null
```
````
