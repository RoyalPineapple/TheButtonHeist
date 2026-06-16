# Reviewer's Guide

A quick orientation for anyone reviewing the ButtonHeist codebase for the first time.

## What Is This?

Button Heist lets AI agents inspect and control iOS apps programmatically. Embed the `TheInsideJob` framework in your iOS app, then connect over WiFi or USB to activate controls, read UI hierarchies, type text, perform explicit gestures, move the viewport, and take screenshots — all without manual interaction.

## Common Starter Flow

Most usage starts with this CLI loop:

```bash
buttonheist list_devices                      # Find running apps
buttonheist get_interface                     # Read the UI element tree
buttonheist activate --identifier "loginBtn"  # Perform accessibility activation
buttonheist type_text --text "hello@example.com" # Type into a field
buttonheist get_screen                        # Capture the screen
```

The generated command reference is the source of truth for the full command contract.

## Why So Many Commands?

The `TheFence.Command` enum is the flat public command-key adapter; command families are the source of truth for product meaning. CLI and MCP project from the same Fence-owned descriptors, and each command maps to a distinct iOS capability (accessibility activation, gesture types, scroll operations, text editing, heist replay, etc.).

Both interfaces expose canonical command names. Semantic operations like `activate`, `type_text`, and `get_interface` stay top-level; mechanical gestures remain explicit action routes, and viewport commands remain direct debug routes.

## TheFence and TheHandoff

- **TheHandoff** owns transport: Bonjour discovery, TCP/TLS connection lifecycle, message send/receive, session state tracking. It exposes callback-based APIs and injectable closures for test mocking.
- **TheFence** owns command dispatch and request-response correlation (matching responses to requests via `requestId` continuations). It talks to TheHandoff directly — no intermediate wrapper.

This boundary exists so that **tests can inject mock connections** at the TheHandoff level via factory closures, while TheFence handles the command-level concerns independently.

## Semantic Commands And Mechanical Gestures

- **`activate`** is the primary interaction command. It resolves semantic identity, reveals the element when needed, acquires fresh accessibility geometry, then dispatches the primary activation policy. This abstracts viewport position across SwiftUI, UIKit, and custom controls.
- **`one_finger_tap`** is an explicit mechanical/spatial gesture. With an element target it still resolves semantic identity and fresh geometry first; with coordinates it acts on the current viewport.

Rule of thumb: use semantic commands for ordinary accessible controls, and use gesture commands only when the intended product action is spatial.

## Module Map

```
TheScore          Shared types (messages, elements) — cross-platform, no networking
TheInsideJob      iOS framework — embedded in the target app, runs the server
ButtonHeist       macOS framework — TheFence (dispatch + correlation), TheHandoff (transport)
ButtonHeistCLI    CLI client — thin wrapper over TheFence
ButtonHeistMCP    MCP server — thin wrapper over TheFence
```

Both CLI and MCP are thin shells. All business logic lives in `TheFence` and below.

## Wire Protocol

JSON-over-TLS request/response with `requestId` correlation via `RequestEnvelope`/`ResponseEnvelope`; envelopes carry `buttonHeistVersion` for exact handshake equality. Interface payloads use the canonical parser `AccessibilityHierarchy` plus Button Heist annotations, not a parallel flat element array. Runtime subscriptions are removed unsupported messages. See `docs/WIRE-PROTOCOL.md` for the full spec.

## Testing

158 tests across 3 test targets. All unit tests are deterministic — no real networking, no Bonjour, no running apps. The mock boundary is at `DeviceConnecting`/`DeviceDiscovering` protocols, injected into TheHandoff via factory closures.

```bash
tuist test TheScoreTests --no-selective-testing       # Protocol types
tuist test ButtonHeistTests --no-selective-testing     # Framework logic
tuist test TheInsideJobTests --platform ios \          # iOS-hosted tests
  --device "iPhone 16 Pro" --os 26.1 --no-selective-testing
```

To demonstrate doctor-ready receipt artifacts without manufacturing a red CI
build:

```bash
scripts/heist-doctor-demo.sh
```

To run a real suite while preserving receipts for doctor analysis:

```bash
scripts/run-with-heist-receipts.sh \
  --suite review \
  --mode failing-and-passing \
  -- tuist test ButtonHeistTests --no-selective-testing
```

## Heist-Themed Names

The names (TheFence, TheSafecracker, TheHandoff, etc.) are the project's identity. Each maps to a clear architectural role — see the README's "Meet the Crew" section for the full cast. The metaphor is consistent: TheFence dispatches commands, TheHandoff manages the connection, TheSafecracker cracks the UI, TheInsideJob runs inside the target app.
