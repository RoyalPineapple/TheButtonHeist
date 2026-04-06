# Heist File Format

**Extension**: `.heist`
**Encoding**: JSON (UTF-8)
**Version**: 1

A `.heist` file is a recorded session that can be played back deterministically. It captures actions with matcher-based element targeting and auto-generated expectations, removing the agent from the loop.

## Structure

```json
{
  "version": 1,
  "recorded": "2026-04-03T18:00:59Z",
  "app": "com.buttonheist.testapp",
  "steps": [ ... ]
}
```

| Field | Type | Description |
|-------|------|-------------|
| `version` | `Int` | Format version. Currently `1`. |
| `recorded` | `String` | ISO 8601 timestamp of when the recording was made. |
| `app` | `String` | Bundle identifier of the app that was running. |
| `steps` | `[HeistEvidence]` | Ordered list of recorded actions. |

## Evidence (Steps)

Each step is a flat JSON object compatible with `TheFence.execute(request:)` — meaning a `.heist` file's steps can feed directly into the existing command dispatch.

### Element-targeting step

```json
{
  "command": "activate",
  "label": "Review PR, High priority",
  "traits": ["button"],
  "expect": [
    {"elementUpdated": {"property": "value", "newValue": "Completed"}},
    {"elementAppeared": {"label": "8 items remaining", "traits": ["staticText"]}}
  ],
  "_recorded": {
    "heistId": "button_review_pr_high_priority",
    "frame": {"x": 16, "y": 514, "width": 370, "height": 65}
  }
}
```

### Non-element step

```json
{
  "command": "type_text",
  "text": "Ship release",
  "expect": {"elementUpdated": {"property": "traits", "newValue": "button"}}
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
| `command` | `String` | Yes | TheFence command name (`activate`, `type_text`, `swipe`, etc.) |
| `label` | `String` | No | Element matcher: case-insensitive substring match on accessibility label |
| `identifier` | `String` | No | Element matcher: match on accessibility identifier |
| `traits` | `[String]` | No | Element matcher: all listed traits must be present |
| `excludeTraits` | `[String]` | No | Element matcher: none of these traits may be present |
| `expect` | `String \| Object \| Array` | No | Expected outcome — validated on playback |
| `_recorded` | `Object` | No | Recording-time metadata (ignored during playback) |
| *(other keys)* | varies | No | Command-specific arguments (`text`, `direction`, `duration`, etc.) |

**Note**: `value` is intentionally absent from targeting fields. Value is mutable state (slider position, toggle state, text content) — using it in matchers breaks playback when the element's state differs. State validation belongs in expectations, not matchers.

## Element Targeting

Matchers describe elements by **identity**, not state:

- **Label** + **identity traits** is the primary targeting strategy
- **Identifier** (developer-assigned `accessibilityIdentifier`) takes priority when unique
- **State traits** (`selected`, `notEnabled`, `isEditing`, `inactive`, `visited`) are filtered out of matchers
- **UUID-containing identifiers** (runtime-generated) are detected and skipped in favor of labels
- **Value** is never used for identification

The matcher algorithm tries progressively:
1. Identifier alone (if stable — no UUIDs)
2. Label + identity traits
3. Label + identity traits + identifier
4. Label + identity traits (accepts ambiguity rather than using state)

## Expectations

The `expect` field uses the same format as `run_batch` expectations. On playback, `TheFence.execute()` validates each step's `expect` against the live `ActionResult`.

### String expectations

| Value | Validates |
|-------|-----------|
| `"screen_changed"` | View controller identity changed (navigation, modal, tab switch) |
| `"elements_changed"` | Any element added, removed, or updated (or screen changed — superset rule) |

### Object expectations

```json
{"elementUpdated": {"property": "value", "newValue": "50%"}}
```

Checks that some element's property changed to the specified value. All fields are optional filters — provide what you know, omit what you don't. `heistId` is intentionally omitted for portability.

| Field | Type | Description |
|-------|------|-------------|
| `heistId` | `String?` | Filter by specific element (rarely used in heist files) |
| `property` | `String?` | Filter by property: `label`, `value`, `traits`, `hint`, `actions` |
| `oldValue` | `String?` | Expected previous value |
| `newValue` | `String?` | Expected new value |

```json
{"elementAppeared": {"label": "Buy groceries", "traits": ["button"]}}
```

Checks that an element matching this predicate appeared in the delta's added list. The inner object is an `ElementMatcher` — same flat format used for targeting, but **may include state** (value, state traits) when asserting the element's initial condition.

```json
{"elementDisappeared": {"label": "Old Item", "traits": ["button"]}}
```

Checks that an element matching this predicate was in the delta's removed list. Requires a pre-action element cache to resolve removed heistIds.

### Array expectations (compound)

```json
"expect": [
  {"elementUpdated": {"property": "value", "newValue": "Completed"}},
  {"elementAppeared": {"label": "8 items remaining", "traits": ["staticText"]}}
]
```

All sub-expectations must be met. Used when an action produces multiple observable outcomes (e.g., toggling a task changes its value AND updates the counter).

## Recorded Metadata

The `_recorded` key carries debugging context from recording time. It is preserved in the file but **ignored during playback**.

| Field | Type | Description |
|-------|------|-------------|
| `heistId` | `String?` | The heistId that was used to target the element at recording time |
| `frame` | `Object?` | The element's frame at recording time (`x`, `y`, `width`, `height`) |
| `coordinateOnly` | `Bool?` | True if the step used coordinate-only targeting (no element) |

## Durable Recording

Evidence is written incrementally to `heist.jsonl` in the session directory as each action is recorded (append-only JSONL, same pattern as `session.jsonl`). If the session crashes or disconnects before `stop_heist`, the evidence captured up to that point is preserved on disk and recoverable.

`stop_heist` reads the evidence back from `heist.jsonl`, wraps it in the `HeistPlayback` envelope, and writes the final `.heist` file to the specified output path.

## Session Directory Layout

```
$XDG_DATA_HOME/buttonheist/sessions/
└── script-2026-04-03-180059/
    ├── session.jsonl.gz          # compressed session log
    ├── manifest.json             # session manifest
    ├── heist.jsonl               # durable evidence (JSONL, one entry per line)
    ├── screenshots/
    └── recordings/
```

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
```

### MCP

```json
{"name": "start_heist", "arguments": {"app": "com.example.app"}}
{"name": "stop_heist", "arguments": {"output": "/path/to/recording.heist"}}
{"name": "play_heist", "arguments": {"input": "/path/to/recording.heist"}}
```

## Playback Semantics

- Each evidence step is executed via `TheFence.execute()` — the same path live agent commands take
- `expect` is validated by the existing `ActionExpectation.validate(against:)` machinery
- Playback stops on the first failed action (element not found, timeout, etc.)
- The result reports `completedSteps`, `failedIndex` (if any), and `totalTimingMs`
- No `get_interface` calls are injected — the script is replayed exactly as recorded

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
