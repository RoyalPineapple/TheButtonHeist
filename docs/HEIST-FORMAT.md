# Heist File Format

**Extension**: `.heist`
**Encoding**: JSON (UTF-8)
**Version**: 6

A `.heist` file stores durable typed command steps. Playback runs those steps
deterministically through the same command contract as live CLI and MCP
commands, removing the agent from the loop.

## Structure

```json
{
  "version": 6,
  "app": "com.buttonheist.testapp",
  "steps": [ ... ]
}
```

| Field | Type | Description |
|-------|------|-------------|
| `version` | `Int` | Format version. Currently `6`. |
| `app` | `String` | Bundle identifier of the app that was running. |
| `steps` | `[HeistStep]` | Ordered list of durable interaction steps. |

Version 6 is the current heist contract. Step targets use flat semantic
matcher fields. Capture-local IDs may appear in live captures or diagnostics,
but are never stored as replay authority.

## Capture Truth

During live execution, Button Heist uses accessibility captures as the source
of truth. Segments and compact deltas are derived projections used for
diagnostics, matcher derivation, expectation checks, and failure reporting;
they are not stored as heist truth.

Actions may explore scroll views to refresh off-screen state, and
`get_interface` may refresh the hierarchy it returns. That exploration scope
does not decide trace history scope. Screen-change classification determines
how captures are grouped for derived segment views.

## Steps

Each step is a closed playback object. Top-level fields are limited to
`command`, optional durable semantic `target`, optional `arguments`, and
optional semantic `expectation`.

Durable replay identity lives under the flat matcher fields in `target`.
Capture-local IDs are never durable playback authority and are not stored in
heist steps.

### Element-targeting step

```json
{
  "command": "activate",
  "target": {
    "label": "Review PR, High priority",
    "traits": ["button"]
  },
  "expectation": {
    "type": "compound",
    "expectations": [
      {"type": "element_updated", "property": "value", "newValue": "Completed"},
      {"type": "element_appeared", "matcher": {"label": "8 items remaining", "traits": ["staticText"]}}
    ]
  }
}
```

### Non-element step

```json
{
  "command": "type_text",
  "arguments": {
    "text": "Ship release"
  },
  "expectation": {"type": "element_updated", "property": "traits", "newValue": "button"}
}
```

### Coordinate-only gesture

```json
{
  "command": "one_finger_tap",
  "arguments": {
    "x": 200,
    "y": 500
  }
}
```

### Field reference

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `command` | `String` | Yes | Canonical `TheFence.Command` name (`activate`, `type_text`, `swipe`, etc.) |
| `target` | `Object` | No | Durable semantic target. Contains flat matcher fields; never contains `heistId`. |
| `target.label` | `String` | No | Element matcher: case-insensitive equality (typography-folded) on accessibility label |
| `target.identifier` | `String` | No | Element matcher: case-insensitive equality (typography-folded) on accessibility identifier |
| `target.value` | `String` | No | Element matcher: case-insensitive equality (typography-folded) on accessibility value |
| `target.traits` | `[String]` | No | Element matcher: all listed traits must be present |
| `target.excludeTraits` | `[String]` | No | Element matcher: none of these traits may be present |
| `target.ordinal` | `Int` | No | 0-based index among matcher results; only valid with at least one matcher field |
| `arguments` | `Object` | No | Command-specific arguments. Text input, gesture coordinates, durations, and wait options live here. |
| `expectation` | `Object` | No | Semantic outcome expected after the command executes. |

**Note**: `value` and state traits are lower-priority matcher fields. The recorder includes them only when identifier, label, and semantic traits do not uniquely identify the element in the capture. State validation still belongs in expectations when the state itself is the contract being tested.

## Recording Guidance

Minimum matcher is the recording primitive. Given an element in an accessibility capture, Button Heist records the least-specific matcher that uniquely resolves that element in the same capture. Replay durability comes from the derived matcher fields and ordinal, not capture-local IDs.

When recording a heist, public action steps should carry `ElementTarget` predicate fields such as label and traits. The recorder uses current element data to derive a minimum matcher and stores only that matcher on the step.

Ordinal-only steps are the least durable replay target. They are reserved for anonymous elements that have no identifier, label, value, or useful traits; if element order changes, they can target a different element without producing a matcher miss.

**Workflow**: Call `get_interface` before recording actions so the recorder has current element data. Durable heist steps should be the interactions and waits you want to replay; inspection calls help the recorder build good matchers but are not themselves replay steps.

**Example**: You activate the Sign In button with a semantic target. The `.heist` step stores fields like `{"command":"activate","target":{"label":"Sign In","traits":["button"]}}`. Playback targets the matcher, not a live capture ID.

### Async operations

`wait_for` and `wait_for_change` are durable playback steps. They act as timing gates so the next action waits for async UI transitions to complete. Waiting for a visible element to disappear (`absent: true`) is generally more reliable than waiting for an unknown element to appear — you already know what's on screen.

Examples:
- `{"command":"wait_for","target":{"label":"Loading"},"arguments":{"absent":true}}` — waits for an element to disappear (loading indicator gone)
- `{"command":"wait_for","target":{"label":"Confirmation","traits":["staticText"]}}` — waits for an element to appear
- `{"command":"wait_for_change","expectation":{"type":"screen_changed"}}` — waits for a screen transition to finish

## Element Targeting

Matchers describe elements by the least-specific available semantic identity in the capture:

- **Identifier** (developer-assigned `accessibilityIdentifier`) takes priority when stable and unique
- **Label** is next
- **Semantic traits** (`button`, `header`, `textEntry`, etc.) disambiguate labels before state is considered
- **Value** is used only when earlier predicates are still ambiguous
- **State traits** (`selected`, `notEnabled`, `isEditing`, `inactive`, `visited`, `updatesFrequently`) and `excludeTraits` are used before ordinal
- **UUID-containing identifiers** (runtime-generated) are detected and skipped in favor of labels
- **Ordinal** only disambiguates a non-empty matcher; anonymous elements without semantic predicates are not replayable

Matching is exact (case-insensitive, typography-folded); the recorder builds the matcher progressively:
1. Identifier
2. Label
3. Semantic traits
4. Value
5. Stateful traits / `excludeTraits`
6. Ordinal

Every element in a capture can produce a minimum matcher that resolves back to the same element in that capture. If a later capture introduces a conflict, rerun the minimum matcher pass for the new capture. Playback does not silently self-heal stale steps; stale matcher failures should be explicit and diagnostic.

## Expectations

An explicit action expectation is stored as the step's top-level `expectation`.
On playback, Button Heist binds that field through the same `ActionExpectation`
object grammar used by live commands and validates it against the live action
result.

```json
{
  "command": "activate",
  "target": {"label": "Continue", "traits": ["button"]},
  "expectation": {"type": "screen_changed"}
}
```

Matcher-based expectations keep playback portable:

```json
{
  "command": "activate",
  "target": {"label": "Buy groceries", "traits": ["button"]},
  "expectation": {
    "type": "element_appeared",
    "matcher": {"label": "8 items remaining", "traits": ["staticText"]}
  }
}
```

Compound expectations remain object-form payloads inside `expectation`; all
sub-expectations must be met.

## Durable Recording

Button Heist preserves successful interaction steps as the heist is recorded,
then writes the final `.heist` file when you call `stop_heist`. If recording
ends before `stop_heist`, finish the flow again and write a complete fixture;
heist fixtures are the durable replay artifact.

## Recording and Playback Commands

The executable command surface is generated from `TheFence.Command`. See the
[Command Reference](reference/commands.md) and
[MCP Tool Reference](reference/mcp-tools.md) for current CLI and MCP shapes.

Representative CLI flow:

```bash
buttonheist start_heist --app com.example.app
# ... perform actions ...
buttonheist stop_heist --output recording.heist
buttonheist play_heist --input recording.heist
buttonheist play_heist --input recording.heist --junit report.xml
```

The `--junit <path>` flag writes a JUnit XML report to disk. Each heist step becomes a `<testcase>` element; failed steps include a `<failure>` with the error message and typed error kind. The output can be consumed by GitHub Actions, Jenkins, and other CI systems that read JUnit XML.

Representative MCP flow:

- Call MCP tool `start_heist` with `app: "com.example.app"`.
- Call MCP tool `stop_heist` with `output: "/path/to/recording.heist"`.
- Call MCP tool `play_heist` with `input: "/path/to/recording.heist"`.

## Playback Semantics

- Each step is executed through the same public command surface live agent commands use
- top-level `expectation` is validated against the live action result when present
- Playback stops on the first failed action (element not found, timeout, etc.)
- The result reports `completedSteps`, `failedIndex` (if any), and `totalTimingMs`
- Capture-local heistIds are never used as playback targets

### Failure diagnostics

On failure, the response includes a `failure` object with everything needed to diagnose the problem without re-running:

| Field | Type | Description |
|-------|------|-------------|
| `command` | `String` | The command that failed (e.g. `activate`, `type_text`) |
| `target` | `ElementTarget?` | The semantic target from the failed step |
| `error` | `String` | Human-readable error message |
| `actionResult` | `ActionResult?` | Full action result — includes `errorKind`, accessibility trace, delta, etc. |
| `expectation` | `ExpectationResult?` | Expectation check result (when top-level `expectation` was attached to the step) |
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
