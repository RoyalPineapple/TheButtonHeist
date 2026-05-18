# Heist File Format

**Extension**: `.heist`
**Encoding**: JSON (UTF-8)
**Version**: 2

A `.heist` file stores durable interaction steps, expected outcomes, and optional recording notes. Playback runs those steps deterministically, ignoring recording notes and removing the agent from the loop.

## Structure

```json
{
  "version": 2,
  "recorded": "2026-04-03T18:00:59Z",
  "app": "com.buttonheist.testapp",
  "steps": [ ... ]
}
```

| Field | Type | Description |
|-------|------|-------------|
| `version` | `Int` | Format version. Currently `2`. |
| `recorded` | `String` | ISO 8601 timestamp of when the recording was made. |
| `app` | `String` | Bundle identifier of the app that was running. |
| `steps` | `[HeistEvidence]` | Ordered list of durable interaction steps. |

Version 2 is intentionally not backward-compatible with the prototype v1 expectation shapes. Re-record old prototypes rather than carrying migration logic in playback.

## Evidence (Steps)

Each step is a flat JSON object using the same command names and argument fields as live Button Heist requests.

### Element-targeting step

```json
{
  "command": "activate",
  "label": "Review PR, High priority",
  "traits": ["button"],
  "expect": {
    "type": "compound",
    "expectations": [
      {"type": "element_updated", "property": "value", "newValue": "Completed"},
      {"type": "element_appeared", "matcher": {"label": "8 items remaining", "traits": ["staticText"]}}
    ]
  },
  "_recorded": {
    "heistId": "button_review_pr_high_priority",
    "frame": {"x": 16, "y": 514, "width": 370, "height": 65},
    "unsupportedArguments": [
      {
        "name": "metadata",
        "valueType": "Data",
        "reason": "not JSON-compatible; omitted from replay arguments"
      }
    ]
  }
}
```

### Non-element step

```json
{
  "command": "type_text",
  "text": "Ship release",
  "expect": {"type": "element_updated", "property": "traits", "newValue": "button"}
}
```

### Coordinate-only gesture

```json
{
  "command": "draw_bezier",
  "startX": 200,
  "startY": 500,
  "segments": [...],
  "duration": 1.5,
  "_recorded": {"coordinateOnly": true}
}
```

### Field reference

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `command` | `String` | Yes | Button Heist command name (`activate`, `type_text`, `swipe`, etc.) |
| `label` | `String` | No | Element matcher: case-insensitive equality (typography-folded) on accessibility label |
| `identifier` | `String` | No | Element matcher: case-insensitive equality (typography-folded) on accessibility identifier |
| `value` | `String` | No | Element matcher: case-insensitive equality (typography-folded) on accessibility value |
| `traits` | `[String]` | No | Element matcher: all listed traits must be present |
| `excludeTraits` | `[String]` | No | Element matcher: none of these traits may be present |
| `ordinal` | `Int` | No | 0-based fallback index among matcher results; can stand alone only when no matcher predicate exists |
| `expect` | `Object` | No | Expected outcome — validated on playback |
| `_recorded` | `Object` | No | Optional recording notes (ignored during playback) |
| *(other keys)* | varies | No | Command-specific arguments (`text`, `direction`, `duration`, etc.) |

**Note**: `value` and state traits are lower-priority matcher fields. The recorder includes them only when identifier, label, and semantic traits do not uniquely identify the element in the capture. State validation still belongs in expectations when the state itself is the contract being tested.

## Recording Guidance

Minimum matcher is the recording primitive. Given an element in an accessibility capture, Button Heist records the least-specific matcher that uniquely resolves that element in the same capture. HeistIds remain useful, readable current-screen handles, but replay durability comes from the derived matcher fields and ordinal.

When recording a heist, it is fine to target a live action by heistId if that is the handle you were handed. The recorder resolves that heistId against the action trace or retained capture, derives a minimum matcher, and stores the matcher on the step. `_recorded.heistId` is evidence only.

Ordinal-only steps are the least durable replay target. They are reserved for anonymous elements that have no identifier, label, value, or useful traits; if element order changes, they can target a different element without producing a matcher miss.

**Workflow**: Call `get_interface` before recording actions so the recorder has current element data. Durable heist steps should be the interactions and waits you want to replay; inspection calls help the recorder build good matchers but are not themselves replay steps.

**Example**: You activate `button_sign_in` in the current interface. The `.heist` step should store fields like `{"command":"activate","label":"Sign In","traits":["button"],"_recorded":{"heistId":"button_sign_in"}}`, not `heistId` as the replay target.

### Async operations

`wait_for` and `wait_for_change` are durable playback steps. They act as timing gates so the next action waits for async UI transitions to complete. Waiting for a visible element to disappear (`absent: true`) is generally more reliable than waiting for an unknown element to appear — you already know what's on screen.

Examples:
- `wait_for(label: "Loading", absent: true)` — waits for an element to disappear (loading indicator gone)
- `wait_for(label: "Confirmation", traits: ["staticText"])` — waits for an element to appear
- `wait_for_change(expect: {"type": "screen_changed"})` — waits for a screen transition to finish

## Element Targeting

Matchers describe elements by the least-specific available evidence in the capture:

- **Identifier** (developer-assigned `accessibilityIdentifier`) takes priority when stable and unique
- **Label** is next
- **Semantic traits** (`button`, `header`, `textEntry`, etc.) disambiguate labels before state is considered
- **Value** is used only when earlier predicates are still ambiguous
- **State traits** (`selected`, `notEnabled`, `isEditing`, `inactive`, `visited`, `updatesFrequently`) and `excludeTraits` are used before ordinal fallback
- **UUID-containing identifiers** (runtime-generated) are detected and skipped in favor of labels
- **Ordinal** is last resort; when an element has no semantic or state predicates, ordinal can be the only replay selector

Matching is exact (case-insensitive, typography-folded); the recorder builds the matcher progressively:
1. Identifier
2. Label
3. Semantic traits
4. Value
5. Stateful traits / `excludeTraits`
6. Ordinal

Every element in a capture can produce a minimum matcher that resolves back to the same element in that capture. If a later capture introduces a conflict, rerun the minimum matcher pass for the new capture. Playback in 0.3.7 does not self-heal or auto-repair stale steps.

## Expectations

The `expect` field uses the same format as `run_batch` expectations. On playback, Button Heist validates each step's `expect` against the live action result.

Expectations use a `type` discriminator that matches the wire Codable shape for `ActionExpectation`, so JSON from a wire log can be pasted straight into a heist file.

Legacy shorthand strings, top-level expectation arrays, and compiler-derived enum wrapper objects are not part of the persisted format.

```json
{"type": "element_updated", "property": "value", "newValue": "50%"}
```

Checks that some element's property changed to the specified value. All non-`type` fields are optional filters — provide what you know, omit what you don't. `heistId` is intentionally omitted for portability.

| Field | Type | Description |
|-------|------|-------------|
| `type` | `String` | `"element_updated"` |
| `heistId` | `String?` | Filter by specific element (rarely used in heist files) |
| `property` | `String?` | Filter by property: `label`, `value`, `traits`, `hint`, `actions`, `frame`, `activationPoint`, `customContent` |
| `oldValue` | `String?` | Expected previous value |
| `newValue` | `String?` | Expected new value |

```json
{"type": "element_appeared", "matcher": {"label": "Buy groceries", "traits": ["button"]}}
```

Checks that an element matching the `matcher` predicate appeared in the delta's added list. The matcher is an `ElementMatcher` — same flat format used for targeting, but **may include state** (value, state traits) when asserting the element's initial condition.

```json
{"type": "element_disappeared", "matcher": {"label": "Old Item", "traits": ["button"]}}
```

Checks that an element matching the `matcher` predicate disappeared from the UI.

### Compound expectations

```json
"expect": {
  "type": "compound",
  "expectations": [
    {"type": "element_updated", "property": "value", "newValue": "Completed"},
    {"type": "element_appeared", "matcher": {"label": "8 items remaining", "traits": ["staticText"]}}
  ]
}
```

All sub-expectations must be met. Used when an action produces multiple observable outcomes (e.g., toggling a task changes its value AND updates the counter).

## Recorded Metadata

The `_recorded` key carries optional recording notes for debugging. It is preserved in the file but **ignored during playback**.

| Field | Type | Description |
|-------|------|-------------|
| `heistId` | `String?` | The heistId that was used to target the element at recording time |
| `frame` | `Object?` | The element's frame at recording time (`x`, `y`, `width`, `height`) |
| `coordinateOnly` | `Bool?` | True if the step used coordinate-only targeting (no element) |
| `unsupportedArguments` | `[Object]?` | Arguments omitted from replay because they were not JSON-compatible. Includes `name`, `valueType`, and `reason`. |
| `caps` | `[Object]?` | Inputs clamped during recording. Includes `name`, `requested`, `applied`, optional `minimum` / `maximum`, and `reason`. |
| `accessibilityTrace` | `Object?` | Capture trace observed while recording |
| `expectation` | `Object?` | Expectation evidence observed while recording |

`_recorded.heistId`, traces, caps, unsupported arguments, and frames are evidence only. Playback ignores `_recorded` entirely; the durable replay contract is the flat step command, matcher fields, ordinal, and command arguments outside `_recorded`. Compact deltas are derived from `_recorded.accessibilityTrace` when needed; they are not stored as separate recorded evidence.

## Durable Recording

Button Heist preserves successful interaction steps as the heist is recorded, then writes the final `.heist` file when you call `stop_heist`. If a session ends before `stop_heist`, the session archive may still contain enough information to recover the completed steps.

## Commands

| Command | Wire name | Description |
|---------|-----------|-------------|
| Start recording | `start_heist` | Begin capturing actions as evidence |
| Stop recording | `stop_heist` | Finalize and write the `.heist` file |
| Play back | `play_heist` | Execute evidence sequentially with expectation validation |

### CLI

```bash
buttonheist start-heist --app com.example.app
# ... perform actions ...
buttonheist stop-heist --output recording.heist
buttonheist play-heist --input recording.heist
buttonheist play-heist --input recording.heist --junit report.xml
```

The `--junit <path>` flag writes a JUnit XML report to disk. Each heist step becomes a `<testcase>` element; failed steps include a `<failure>` with the error message and typed error kind. The output is compatible with GitHub Actions, Jenkins, and other CI systems that consume JUnit XML.

### MCP

```json
{"name": "start_heist", "arguments": {"app": "com.example.app"}}
{"name": "stop_heist", "arguments": {"output": "/path/to/recording.heist"}}
{"name": "play_heist", "arguments": {"input": "/path/to/recording.heist"}}
```

## Playback Semantics

- Each step is executed through the same public command surface live agent commands use
- `expect` is validated against the live action result
- Playback stops on the first failed action (element not found, timeout, etc.)
- The result reports `completedSteps`, `failedIndex` (if any), and `totalTimingMs`
- Recording notes such as `_recorded` are ignored during playback; a readable `heistId` in `_recorded` is never used as a target

### Failure diagnostics

On failure, the response includes a `failure` object with everything needed to diagnose the problem without re-running:

| Field | Type | Description |
|-------|------|-------------|
| `command` | `String` | The command that failed (e.g. `activate`, `type_text`) |
| `target` | `ElementMatcher?` | The element matcher from the failed step |
| `error` | `String` | Human-readable error message |
| `actionResult` | `ActionResult?` | Full action result — includes `errorKind`, `scrollSearchResult`, delta, etc. |
| `expectation` | `ExpectationResult?` | Expectation check result (when `expect` was attached to the step) |
| `interface` | `Interface?` | Complete interface state at time of failure |

The interface state lets you compare the expected target against the actual accessibility elements available when the step failed.

## Playback Performance

Heist playback removes the agent from the loop entirely — no reasoning, no `get_interface` polling, no token consumption. The following data compares a Claude Sonnet 4.6 agent completing benchmark tasks via the `bh` (semantic addressing) config against deterministic playback of `.heist` recordings of the same tasks. Recordings were made on one simulator and played back on a different one to confirm cross-device portability.

| Task | Agent turns | Agent time | Agent tokens | Agent cost | Playback steps | Playback time |
|------|-------------|------------|--------------|------------|----------------|---------------|
| T3-settings-roundtrip | 11 | 58s | 415,260 | $0.20 | 4 | 4.5s |
| T11-increment | 5 | 25s | 181,603 | $0.10 | 7 | 7.9s |
| T5-controls-gauntlet | 15 | 98s | 582,896 | $0.39 | 20 | 22.4s |
| **Total** | **31** | **181s** | **1,179,759** | **$0.70** | **31** | **34.8s** |

Playback is **5x faster** at **zero cost** — no API calls, no tokens, no model variance. The agent spends most of its wall time reading the interface, reasoning about what to do next, and formatting tool calls. Playback skips all of that and fires actions directly.

These numbers are against the `bh` config (semantic addressing). Against coordinate-based configs (`idb`, `mobile-mcp`), the agent gap is wider — those use 2-4x more turns per task because every action requires a screenshot/describe cycle to compute tap coordinates.

### When to use playback vs agents

| Use case | Approach |
|----------|----------|
| Regression testing known flows | Playback — deterministic, fast, free |
| Exploring new UI or unknown state | Agent — needs reasoning to navigate |
| CI smoke tests | Playback — record once, replay on every build |
| Benchmark scoring | Agent — the benchmark measures agent capability |
| Demo recordings | Playback — consistent, reproducible |
