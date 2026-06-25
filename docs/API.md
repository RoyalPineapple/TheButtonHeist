# Button Heist API

This page documents the public integration contracts and invariants around
Button Heist. It is not a command or parameter catalog.

Generated references are the source of truth for executable surface area:

- [Accessibility Contract](ACCESSIBILITY-CONTRACT.md) - canonical product
  contract, boundary map, and conformance cases
- [Command Reference](reference/commands.md) - canonical `TheFence.Command`
  names, CLI exposure, heist execution eligibility, and parameters
- [MCP Tool Reference](reference/mcp-tools.md) - MCP adapter tools projected
  from the Fence command contract
- [Wire Protocol](WIRE-PROTOCOL.md) - transport envelopes, handshake,
  authentication, and wire-only examples
- [Heist Format](HEIST-FORMAT.md) - generated heist artifact and plan IR format

## Contract Layers

Button Heist has one product command contract: `TheFence.Command`. CLI
commands, JSON-lines stdin, MCP tools, and heist execution all route through
that contract. MCP exposes one tool per exposed command, projected from
Fence-owned command descriptors.

The raw wire protocol lives one layer lower in TheScore. Wire message
discriminators such as `requestInterface` and `heistPlan` are transport names,
not the public CLI/MCP command namespace. Side-effecting public commands lower
to one-step or composed `HeistPlan`s before crossing the device wire.

## Public Surface Matrix

| Surface | Public status | Entry points | Contract source | Compatibility policy |
|---------|---------------|--------------|-----------------|----------------------|
| SwiftPM products and modules | Public integration surface | `TheInsideJob`, `ButtonHeist`, `ButtonHeistDSL`, `TheScore`, `ThePlans`, `heist-plan` | `Package.swift`, this document, `api-baselines/swift/*.symbols.txt`, [Swift Heist Authoring](SWIFT-HEIST-AUTHORING.md), and [Wire Protocol](WIRE-PROTOCOL.md) | Released as one product version. Use matching package, CLI, MCP, and embedded app builds. |
| SwiftPM experimental tools | Public experimental, SwiftPM-only | `heist-doctor` | [Heist Doctor](HEIST-DOCTOR.md) | Suggestion-only receipt analysis. Not installed by Homebrew and not a major-version stability contract. |
| Homebrew release | Public install surface | `buttonheist`, `buttonheist-mcp`, `heist-plan`, installed `ThePlans` compiler artifacts | `Formula/buttonheist.rb` and `scripts/release-contract.sh` | Formula and release archives use SemVer `MAJOR.MINOR.PATCH`. Experimental `heist-doctor` is intentionally excluded. |
| CLI commands | Public command surface | `buttonheist <command>` | Generated [Command Reference](reference/commands.md) | Command names, CLI exposure, and parameters are descriptor-owned. Regenerate references after command changes. |
| JSON-lines input | Public CLI session surface | `buttonheist json_lines` | Generated [Command Reference](reference/commands.md) and `TheFence.Command` descriptors | Each line is a JSON object using CLI-exposed Fence commands. MCP-only tools are excluded. Raw plan IR fields are not the public `run_heist` input shape. |
| MCP tools | Public agent tool surface | `buttonheist-mcp` tools | Generated [MCP Tool Reference](reference/mcp-tools.md) | Tool names and schemas are descriptor-owned. `perform` is MCP-only; `run_heist` accepts source `plan` or `.heist` `path`. |
| `.heist` artifact format | Public generated artifact | `<name>.heist/manifest.json` and `plan.json` | [Heist Format](HEIST-FORMAT.md) | Generated package artifact. Do not hand-author it; regenerate artifacts when the plan or manifest contract changes. |
| Plan DSL/source | Public authoring source | Swift DSL files, canonical ButtonHeist source strings, `heist-plan compile`, `run_heist --plan`, MCP `run_heist(plan:)` | [Swift Heist Authoring](SWIFT-HEIST-AUTHORING.md) and [Heist Format](HEIST-FORMAT.md) | Source must compile to canonical `HeistPlan` IR. MCP and JSON-lines should pass source or paths, not raw IR fields. |
| Config and environment keys | Public runtime configuration | `.buttonheist.json`, `~/.config/buttonheist/config.json`, `BUTTONHEIST_*`, `INSIDEJOB_*` | This document, [Authentication](AUTH.md), and command help | Explicit flags and target config win over environment values where command-specific precedence applies. Unknown keys must fail or be ignored only as documented. |
| Wire compatibility policy | Public transport contract | TheScore newline-delimited TLS JSON | [Wire Protocol](WIRE-PROTOCOL.md) | Exact product-version lockstep. Client and server `buttonHeistVersion` must match exactly; mismatch returns `protocolMismatch` and closes the connection. |

## Swift API Baselines

CI checks compiler-exported public symbol snapshots for `ThePlans`,
`TheScore`, `ButtonHeistDSL`, `ButtonHeist`, and `TheInsideJob` with:

```bash
scripts/check-swift-api-baseline.sh
```

The snapshots live in `api-baselines/swift/`. `ThePlans`, `TheScore`,
`ButtonHeistDSL`, and `ButtonHeist` are extracted from the macOS SwiftPM build.
`TheInsideJob` is extracted separately from an iOS simulator DEBUG SwiftPM build
because its public module is UIKit/DEBUG-gated. `ButtonHeistDSL` and
`ButtonHeist` are extracted with their public re-exported modules included, so
removing a re-export or changing a re-exported symbol changes the product
snapshot. The external import fixtures compile consumers from outside the
repository to prove the documented macOS products and iOS DEBUG `TheInsideJob`
import work in SwiftPM.

For an intentional public Swift API change, update snapshots with:

```bash
scripts/check-swift-api-baseline.sh --update
```

Review the generated diff before committing. Do not hand-edit snapshot files;
the checked-in text is generated from Swift symbol graphs so CI can distinguish
intentional contract changes from accidental public API drift.

The baseline lane is pinned to the same Xcode and Swift toolchain used by CI.
GitHub Actions selects that toolchain before running the check. Locally, set
`DEVELOPER_DIR` to the matching developer directory before checking or
updating. The script fails fast with the expected Swift version and an example
command when a different toolchain is active.

```bash
DEVELOPER_DIR=/Applications/<CI_XCODE>.app/Contents/Developer scripts/check-swift-api-baseline.sh --update
```

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
```

Default scope is `simulator,usb`. WiFi/LAN exposure is opt-in with
`network`; only that mode requires Bonjour Info.plist entries.

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
identity, not coordinates. Button Heist owns the element inflation loop:

1. Resolve the semantic target against current accessibility state.
2. Reveal it if viewport movement is required.
3. Refresh after movement or state change.
4. Acquire fresh live geometry.
5. Dispatch through the command-specific action path.

This applies to activation, adjustable actions, named custom actions, text
focus, and targeted gestures. If identity, element inflation, or live geometry
cannot be proven, the command fails with diagnostics instead of acting on stale
state.

Explicit viewport commands are different: `scroll`, `scroll_to_visible`, and
`scroll_to_edge` expose viewport state because moving the viewport is the
caller's intent. They are direct viewport/debug commands, not durable heist
primitives, but they still execute through the heist pipeline as public
side-effecting commands.

## Element Identity

`heistId` is a current-capture annotation. It can appear in interface captures
and diagnostics to correlate current tree entries. Public action targets use
`ElementTarget` predicate fields: label, identifier, value, traits,
excluded traits, and optional ordinal. `heistId` is not a replay selector and it
is not geometry authority.

Durable flows use semantic selectors and matchers: accessibility identifier,
label, value, traits, excluded traits, and ordinal as a last-resort
disambiguator. Minimum matcher utilities can derive portable suggestions from
settled captures without depending on transient handles or coordinates.

## Captures, Traces, and Deltas

The accessibility trace stores captures. Segments are derived projections used
to compare captures, format action results, validate expectations, and report
diagnostics. Segments are not a second source of truth.

Responses may include compact deltas such as `noChange`, `elementsChanged`, or
`screenChanged`. Those deltas summarize what changed between trace captures;
they do not replace the underlying captures.

## Interface Rendering Receipt

Public interface JSON responses include `rendering` so machine clients can
distinguish complete captures from bounded projections. The state vocabulary is:

| State | Meaning |
|-------|---------|
| `full` | The response rendered every observed element in the requested projection. |
| `filtered` | The caller requested a scoped projection, such as a subtree, and the response is complete for that scope. |
| `truncated` | Button Heist intentionally omitted part of an otherwise available projection to keep the response bounded. |
| `sparse` | The runtime had only partial semantic evidence for the screen. Clients may inspect it, but should not treat absence as conclusive. |
| `failed` | The runtime could not produce a usable semantic projection. The response should carry the product error instead of a partial tree. |

The current `get_interface` projection emits `full` or `truncated`.
`filtered`, `sparse`, and `failed` are reserved contract states for scoped or
degraded projections; they must use the same rendering object before they are
exposed. For huge scroll views, Button Heist bounds each scrollable subtree by
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

Use the generated [Command Reference](reference/commands.md) for command names
and parameters.

### Command Invariants

- `connect` verifies transport, handshake/authentication, and session
  ownership. Observation still starts with `get_interface`.
- `run_heist` accepts a typed `HeistPlan`; execution uses the same plan contract
  for source strings and `.heist` artifacts.
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

ButtonHeistMCP exposes MCP tools projected from `TheFence.Command`. The
generated [MCP Tool Reference](reference/mcp-tools.md) is the source of truth
for tools and schemas.

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

The CLI is an adapter over TheFence. Run `buttonheist --help` for local usage
text and use the generated [Command Reference](reference/commands.md) for the
checked-in command contract.

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
shape carries a canonical tree plus Button Heist annotations. Flat element
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
`{"type":"screen_changed"}` or
`{"type":"present","element":{"label":{"mode":"exact","value":"Success"}}}`.

Expectations use the current object grammar at every public boundary. Element
expectations select subjects with predicate fields, not `heistId`.

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

For command details, continue to the generated
[Command Reference](reference/commands.md).
