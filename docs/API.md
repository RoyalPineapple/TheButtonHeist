# The Button Heist API

This page documents the public integration contracts and invariants around
The Button Heist. It is not a command or parameter catalog.

Descriptor-owned surfaces are the source of truth for executable behavior:

- [Accessibility Contract](ACCESSIBILITY-CONTRACT.md) - canonical product
  contract, boundary map, and conformance cases
- `buttonheist --help` and `buttonheist <command> --help` - canonical CLI usage
- MCP `tools/list` - MCP adapter tools and input schemas projected from the Fence command contract
- [Wire Protocol](WIRE-PROTOCOL.md) - transport envelopes, handshake,
  authentication, and wire-only examples
- [Heist Format](HEIST-FORMAT.md) - generated heist artifact and plan IR format

## Contract Layers

The Button Heist has one product command contract: `TheFence.Command`. CLI
commands, JSON-lines stdin, MCP tools, and heist execution all route through
that contract. MCP exposes one tool per exposed command, projected from
Fence-owned command descriptors.

The raw wire protocol lives one layer lower in TheScore. Wire message
discriminators such as `requestInterface` and `heistPlan` are transport names,
not the public CLI/MCP command namespace. Side-effecting public commands lower
to one-step or composed `HeistPlan`s before crossing the device wire. The full
module map and the wire boundary are drawn in the
[crew map diagram](diagrams/crew-map.md).

## Public Surface Matrix

| Surface | Public status | Entry points | Contract source | Compatibility policy |
|---------|---------------|--------------|-----------------|----------------------|
| SwiftPM products and modules | Public integration surface | `ButtonHeistTesting`, `TheInsideJob`, `ButtonHeist`, `ButtonHeistDSL`, `TheScore`, `ThePlans`, `heist-plan` | `Package.swift`, this document, [Swift Heist Authoring](SWIFT-HEIST-AUTHORING.md), and [Wire Protocol](WIRE-PROTOCOL.md) | Released as one product version. Use matching package, CLI, MCP, and embedded app builds. |
| SwiftPM experimental tools | Public experimental, SwiftPM-only | `heist-doctor` | [Heist Doctor](HEIST-DOCTOR.md) | Suggestion-only receipt analysis. Not installed by Homebrew and not a major-version stability contract. |
| Homebrew release | Public install surface | `buttonheist`, `buttonheist-mcp`, `heist-plan`, installed `ThePlans` compiler artifacts | `Formula/buttonheist.rb` and `scripts/release-contract.sh` | Formula and release archives use SemVer `MAJOR.MINOR.PATCH`. Experimental `heist-doctor` is intentionally excluded. |
| CLI commands | Public command surface | `buttonheist <command>` | `TheFence.Command` descriptors and `buttonheist --help` | Command names, CLI exposure, and parameters are descriptor-owned. |
| JSON-lines input | Public CLI session surface | `buttonheist json_lines` | `TheFence.Command` descriptors and command help | Each line is a JSON object using CLI-exposed Fence commands. MCP-only tools are excluded. Raw plan IR fields are not the public `run_heist` input shape. |
| MCP tools | Public agent tool surface | `buttonheist-mcp` tools | MCP `tools/list` schemas projected from `TheFence.Command` descriptors | Tool names and schemas are descriptor-owned. `perform` is MCP-only and accepts one durable DSL instruction; `run_heist` accepts durable source `plan` or generated `.heist` `path`. |
| `.heist` artifact format | Public generated artifact | `<name>.heist/manifest.json` and `plan.json` | [Heist Format](HEIST-FORMAT.md) | Generated package artifact. Do not hand-author it; regenerate artifacts when the plan or manifest contract changes. |
| Plan DSL/source | Public authoring source | Swift DSL files, canonical ButtonHeist source strings, `heist-plan compile`, `run_heist --plan`, MCP `run_heist(plan:)` | [Swift Heist Authoring](SWIFT-HEIST-AUTHORING.md) and [Heist Format](HEIST-FORMAT.md) | Source must compile to canonical `HeistPlan` IR. MCP and JSON-lines should pass source or paths, not raw IR fields. |
| Config and environment keys | Public runtime configuration | `.buttonheist.json`, `~/.config/buttonheist/config.json`, `BUTTONHEIST_*`, `INSIDEJOB_*` | This document, [Authentication](AUTH.md), and command help | Explicit flags and target config win over environment values where command-specific precedence applies. Unknown keys must fail or be ignored only as documented. |
| Wire compatibility policy | Public transport contract | TheScore newline-delimited TLS JSON | [Wire Protocol](WIRE-PROTOCOL.md) | Exact product-version lockstep. Client and server `buttonHeistVersion` must match exactly; mismatch returns `protocolMismatch` and closes the connection. |

## Swift API Breakage

CI checks public Swift API compatibility against the latest `v*` release tag
reachable from `origin/main` with:

```bash
scripts/check-swift-api-breaking-changes.sh
```

The script fetches tags and `origin/main`, resolves the newest merged release
tag, and runs SwiftPM's native API breakage diagnostic:

```bash
swift package diagnose-api-breaking-changes "$BASELINE_TAG"
```

Set `BUTTONHEIST_SWIFT_API_BASELINE_TAG` to compare against a specific release
tag locally. The script is strict by default. Intentional source-shape
tightening must be declared as exact SwiftPM breakage lines in the script; any
extra public break still fails CI without forcing compatibility aliases back
into the package. `BUTTONHEIST_SWIFT_API_BREAKAGE_MODE=report` is available for
local investigation only.

## TheInsideJob

**Import**: `import TheInsideJob`

**Platform**: iOS 17.0+

**Location**: `ButtonHeist/Sources/TheInsideJob/TheInsideJob.swift`

TheInsideJob is the iOS framework embedded in the target app. In debug builds
it auto-starts through the ObjC load hook, reads environment and Info.plist
configuration, starts a TLS TCP listener, and maintains settle-driven
accessibility captures.

### Configuration

Environment variables take precedence over Info.plist values.

```bash
INSIDEJOB_DISABLE=true
INSIDEJOB_TOKEN=my-secret-token
INSIDEJOB_ID=my-instance
INSIDEJOB_SESSION_TIMEOUT=30
INSIDEJOB_SCOPE=simulator,usb
INSIDEJOB_FINGERPRINTS=true
```

```xml
<key>InsideJobDisableAutoStart</key>
<false/>
<key>InsideJobToken</key>
<string>my-secret-token</string>
<key>InsideJobInstanceId</key>
<string>my-instance</string>
<key>InsideJobScope</key>
<array>
    <string>simulator</string>
    <string>usb</string>
</array>
<key>InsideJobFingerprintsEnabled</key>
<true/>
```

Default scope is `simulator,usb`. WiFi/LAN exposure is opt-in with
`network`; only that mode requires Bonjour Info.plist entries.
Fingerprints are enabled by default and can also be disabled from code with
`TheInsideJob.configure(fingerprintsEnabled: false)`.

### Lifecycle

`TheInsideJob.shared` owns the listener, Bonjour advertisement when enabled,
session state, current accessibility state, and settle-driven change detection.
Manual `configure`, `start`, and `stop` calls are available for explicit
startup, but normal integrations link the framework and let auto-start do the
work.

Listener setup fails closed when TLS identity or TLS transport parameters
cannot be created.

## Semantic Targeting

Element-targeted semantic commands abstract viewport mechanics. Callers provide
identity, not coordinates. The Button Heist owns the element inflation loop:

1. Resolve the semantic target against current accessibility state.
2. Reveal it if viewport movement is required.
3. Refresh after movement or state change.
4. Acquire fresh live geometry.
5. Dispatch through the command-specific action path.

This applies to activation, adjustable actions, named custom actions, text
focus, and targeted gestures. If identity, element inflation, or live geometry
cannot be proven, the command fails with diagnostics instead of acting on stale
state. The resolution flowchart is drawn in the
[element inflation diagram](diagrams/element-inflation.md); the activation
decision tree is drawn in the
[activation policy diagram](diagrams/activation-policy.md).

Explicit viewport commands are different: `scroll`, `scroll_to_visible`, and
`scroll_to_edge` expose viewport state because moving the viewport is the
caller's intent. They are direct client viewport/debug commands, not HeistPlan
DSL or durable heist primitives, and they execute through direct client
dispatch as public side-effecting commands.

## Element Identity

`heistId` is a current-capture annotation. It can appear in interface captures
and diagnostics to correlate current tree entries. Public action targets use
`ElementTarget` predicate checks: label, identifier, value, hint, traits,
actions, custom content, rotors, recursive exclusion, and optional ordinal.
`heistId` is not a replay selector and it is not geometry authority.
The string fields may be a single StringMatch or an array of StringMatch values
when one property needs multiple checks; every entry for that property must
match. Prefer ordered `checks` when string checks and trait checks belong in one
predicate chain; use `.traits([...])` for required traits and
`.exclude(.traits([...]))` for rejected traits.

Durable flows use semantic selectors and matchers: label, value, traits,
actions, custom content, rotors, recursive exclusion, an accessibility
identifier where a stable product identifier exists, and ordinal as a
last-resort disambiguator. Labels, values, and traits
carry the contract under test — they are the properties assistive technology
actually reads. Identifiers are fixture plumbing: legitimate for stable product
identifiers and test fixtures, but invisible to every accessibility user. An
element that can only be found by its identifier is an accessibility finding,
not a targeting success; the fix is better accessibility, not a better
identifier. Minimum matcher utilities can derive portable suggestions from
settled captures without depending on transient handles or coordinates.

String selector fields match exact-or-miss: case-insensitive equality after
typography folding (curly quotes, long dashes, ellipsis, and typographic spaces
fold to their ASCII equivalents; emoji, accents, and non-Latin scripts pass
through unchanged). There is no substring fallback — a miss returns structured
near-miss suggestions through the diagnostic path. Broad matching modes
(`.contains`, `.prefix`, `.suffix`) are explicit opt-ins with the same
normalization. See [Heist language spec](HEIST-LANGUAGE-SPEC.md) for the full
matching contract.

## Captures, Traces, and Deltas

The accessibility trace stores captures. Segments are derived projections used
to compare captures, format action results, validate expectations, and report
diagnostics. Segments are not a second source of truth.

Responses may include compact deltas such as `noChange`, `elementsChanged`, or
`screenChanged`. Those deltas summarize what changed between trace captures;
they do not replace the underlying captures. The type families behind captures
and targets — and the internal/wire border they respect — are drawn in the
[currency types diagram](diagrams/currency-types.md); a single action's
end-to-end flow is drawn in the
[action pipeline diagram](diagrams/action-pipeline.md).

## Interface Rendering Receipt

Public interface JSON responses include `rendering` so machine clients can
distinguish complete captures from bounded projections. The state vocabulary is:

| State | Meaning |
|-------|---------|
| `full` | The response rendered every observed element in the requested projection. |
| `filtered` | The caller requested a scoped projection, such as a subtree, and the response is complete for that scope. |
| `truncated` | The Button Heist intentionally omitted part of an otherwise available projection to keep the response bounded. |
| `sparse` | The runtime had only partial semantic evidence for the screen. Clients may inspect it, but should not treat absence as conclusive. |
| `failed` | The runtime could not produce a usable semantic projection. The response should carry the product error instead of a partial tree. |

The current `get_interface` projection emits `full` or `truncated`.
`filtered`, `sparse`, and `failed` are reserved contract states for scoped or
degraded projections; they must use the same rendering object before they are
exposed. For huge scroll views, The Button Heist bounds each scrollable subtree by
`BH_SCROLL_SUBTREE_ELEMENT_BUDGET` / `BUTTONHEIST_SCROLL_SUBTREE_ELEMENT_BUDGET`
(default `300`, clamped to `0...1000`). A truncated scroll container keeps its
scroll metrics and `observedElementCount`, renders only the leading elements,
and adds a `truncation` object with:

- `state: "truncated"`
- `reasonCode: "scroll-subtree-element-budget"`
- `observedElementCount`
- `renderedElementCount`
- `omittedElementCount`
- `visibleElementBudget`

Compact output mirrors the same decision with a `subtree truncated` line.

Whole-interface public projection is also capped by `BH_TOTAL_NODE_BUDGET` /
`BUTTONHEIST_TOTAL_NODE_BUDGET` (default and hard cap `5000`). When this cap is
hit, top-level `rendering` reports:

- `state: "truncated"`
- `reasonCode: "total-node-budget"`
- `observedElementCount`
- `renderedElementCount`
- `omittedElementCount`
- `totalNodeBudget`

Compact output mirrors the same decision with an `interface truncated` line.

Runtime knobs are read from the process that uses them. Scroll exploration
limits are app-side InsideJob knobs; public projection budgets are applied by
TheFence and therefore affect CLI, JSON-lines, and MCP output in the client
process. Test runners may prefix the same names with `TEST_RUNNER_`; the
unprefixed name wins when it is valid.

| Variable | Default | Clamp | Purpose |
|----------|---------|-------|---------|
| `BH_POST_SCROLL_LAYOUT_FRAMES` / `BUTTONHEIST_POST_SCROLL_LAYOUT_FRAMES` | `3` | `0...10` | Main-run-loop frames to wait after programmatic scrolling. |
| `BH_TRIPWIRE_PULSE_HZ` / `BUTTONHEIST_TRIPWIRE_PULSE_HZ` | `10` | `1...120` | Accessibility tripwire polling frequency. |
| `BH_MAX_SCROLLS_PER_CONTAINER` / `BUTTONHEIST_MAX_SCROLLS_PER_CONTAINER` | `200` | `1...2000` | Per-container scroll exploration safety limit. |
| `BH_MAX_SCROLLS_PER_DISCOVERY` / `BUTTONHEIST_MAX_SCROLLS_PER_DISCOVERY` | `200` | `1...2000` | Whole-discovery scroll exploration safety limit. |
| `BH_SCROLL_SUBTREE_ELEMENT_BUDGET` / `BUTTONHEIST_SCROLL_SUBTREE_ELEMENT_BUDGET` | `300` | `0...1000` | Per-scroll-container public projection budget. |
| `BH_VISIBLE_ELEMENT_BUDGET` / `BUTTONHEIST_VISIBLE_ELEMENT_BUDGET` | `300` | `0...1000` | Backward-compatible spelling for the same projection budget. |
| `BH_TOTAL_NODE_BUDGET` / `BUTTONHEIST_TOTAL_NODE_BUDGET` | `5000` | `0...5000` | Whole-interface public projection budget. |

## TheFence

**Import**: `import ButtonHeist`

**Platform**: macOS 14.0+

**Location**: `ButtonHeist/Sources/TheButtonHeist/TheFence/`

TheFence is the shared orchestration layer for CLI, JSON-lines stdin, MCP, and
heist execution. It owns command parsing, schema validation, connection
coordination through TheHandoff, typed responses, heist planning, expectations,
receipts, and replay integration.

Use `buttonheist --help`, `buttonheist <command> --help`, and MCP
`tools/list` for command names, parameters, and MCP input schemas. Those
surfaces are projected from the Fence command descriptors.

### Command Invariants

- `connect` verifies transport, handshake/authentication, and session
  ownership. Observation still starts with `get_interface`.
- `perform` accepts one durable ButtonHeist DSL instruction.
- `run_heist` accepts a durable source plan string or generated `.heist`
  package at public boundaries; execution uses the typed `HeistPlan` contract
  after source/package loading.
- Commands that support `expect` validate the expectation against the action
  result and report the observed outcome.
- Typed responses serialize to human, compact, and JSON forms from the same
  response models.

## TheHandoff

**Import**: `import ButtonHeist`

**Platform**: macOS 14.0+

**Location**: `ButtonHeist/Sources/TheButtonHeist/TheHandoff/`

TheHandoff owns client-side connection lifecycle: discovery, direct/named
target resolution, TLS trust, authentication, session state, keepalive, and
bounded reconnect.

Connection diagnostics are exposed as product-level failures: transport
failure, auth failure, session lock, protocol version mismatch, missing token,
backlog
overflow, no discovered device, or no matching target.

Named targets live in `.buttonheist.json` or
`~/.config/buttonheist/config.json`:

```json
{
  "targets": {
    "demo": {
      "device": "<host>:<port>",
      "token": "my-token"
    }
  },
  "default": "demo"
}
```

Configs are strict. Removed fields such as `certFingerprint` are invalid, even
when the file is discovered from a default config path.

## ButtonHeistMCP

**Location**: `ButtonHeistMCP/`

**Binary**: `buttonheist-mcp`

ButtonHeistMCP exposes MCP tools projected from `TheFence.Command`. The live
MCP `tools/list` response is the source of truth for tools and schemas.

Runtime behavior:

- JSON-RPC over stdio
- One reused `TheFence` instance per MCP server process
- Auto-reconnects to the device on the next tool call after disconnect
- Returns compact text as the first-glance summary and the same public JSON
  response as MCP `structuredContent`
- Returns screenshots as artifact paths by default
- Requires explicit, size-bounded inline screenshot opt-ins

Environment variables:

| Variable | Description |
|----------|-------------|
| `BUTTONHEIST_DEVICE` | Default device filter or named target |
| `BUTTONHEIST_TOKEN` | Auth token |
| `BUTTONHEIST_DRIVER_ID` | Driver identity for session locking |
| `BUTTONHEIST_SESSION_TIMEOUT` | MCP idle disconnect timeout |

## CLI

**Location**: `ButtonHeistCLI/`

**Binary**: `buttonheist`

The CLI is an adapter over TheFence. Run `buttonheist --help` and
`buttonheist <command> --help` for descriptor-backed local usage text.

Common environment variables:

| Variable | Description |
|----------|-------------|
| `BUTTONHEIST_DEVICE` | Default device filter or named target |
| `BUTTONHEIST_TOKEN` | Auth token |
| `BUTTONHEIST_DRIVER_ID` | Driver identity for session locking |
| `BUTTONHEIST_SESSION_TIMEOUT` | Default idle timeout for `buttonheist json_lines` |

Flags take precedence over environment variables.

## Data Model Notes

### Interface

`Interface` is the accessibility capture returned to clients. Its public JSON
shape carries a canonical tree plus ButtonHeist annotations. Flat element
lists are projections for formatting and matching, not a second wire truth.

### HeistElement

`HeistElement.heistId` is scoped to the current capture and may be reported for
correlation or diagnostics. Use semantic matcher fields for actions, durable
heist fixtures, scripts, and replay.

### ActionResult

`ActionResult` reports delivery, the action method used, optional typed error
kind, optional command payload, trace-derived accessibility delta, and
expectation result when one was requested.

For `elementsChanged`, public responses include concrete semantic edits under
`delta.edits.added`, `delta.edits.removed`, and `delta.edits.updated` when
present. For `screenChanged`, public responses include the destination
`delta.newInterface`. Agents should inspect those payloads before deciding
whether the action achieved its intended state or merely observed scroll/loading
churn. Compact text is progressive: successful heist steps summarize the delta
kind, while failed steps include concrete evidence lines when trace evidence is
available.

### Expectations

Expectations use object form with a `type` discriminator, for example
`{"type":"change","scopes":[{"type":"screen"}]}` or
`{"type":"exists","element":{"label":{"mode":"exact","value":"Success"}}}`.

Expectations use the current object grammar at every public boundary. Element
expectations select subjects with predicate fields, not `heistId`.
Element update predicates use `before` and `after` matcher objects for the old
and new element state; raw `from`/`to` string fields are not part of the public
grammar.

## Minimal Integration

```swift
import SwiftUI
import TheInsideJob

@main
struct MyApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
```

For command details, use `buttonheist --help`, `buttonheist <command> --help`,
and MCP `tools/list`.
