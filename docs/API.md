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

Existing configs may still contain `certFingerprint`; the current
Network.framework PSK transport ignores it and uses the target token instead.

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
