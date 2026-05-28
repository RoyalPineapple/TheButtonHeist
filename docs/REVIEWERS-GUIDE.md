# Reviewer's Guide

A quick orientation for anyone reviewing the ButtonHeist codebase for the first time.

## What Is This?

Button Heist lets AI agents (and humans) inspect and control iOS apps programmatically. Embed the `TheInsideJob` framework in your iOS app, then connect over WiFi or USB to tap buttons, read UI hierarchies, type text, swipe, scroll, take screenshots, and record video — all without manual interaction.

## Common Starter Flow

Most usage starts with this CLI loop:

```bash
buttonheist list_devices                      # Find running apps
buttonheist get_interface                     # Read the UI element tree
buttonheist activate --identifier "loginBtn"  # Tap a control
buttonheist type_text "hello@example.com"     # Type into a field
buttonheist get_screen                        # Capture the screen
```

The generated command reference is the source of truth for the full command contract.

## Why So Many Commands?

The `TheFence.Command` enum is the source of truth for the public command contract; CLI and MCP project from the same Fence-owned contract. This is driven by **iOS interaction coverage** — each command maps to a distinct iOS capability (accessibility activation, gesture types, scroll operations, text editing, recording, etc.).

Both interfaces expose canonical command names. Common operations like `activate`, `type_text`, `get_interface`, `swipe`, and `scroll_to_visible` stay top-level in both.

## TheFence and TheHandoff

- **TheHandoff** owns transport: Bonjour discovery, TCP/TLS connection lifecycle, message send/receive, session state tracking. It exposes callback-based APIs and injectable closures for test mocking.
- **TheFence** owns command dispatch and request-response correlation (matching responses to requests via `requestId` continuations). It talks to TheHandoff directly — no intermediate wrapper.

This boundary exists so that **tests can inject mock connections** at the TheHandoff level via factory closures, while TheFence handles the command-level concerns independently.

## Why `activate` and `one_finger_tap` Both Exist

- **`activate`** is the primary interaction command. It resolves semantic identity, reveals the element when needed, acquires fresh accessibility geometry, then dispatches the primary activation policy. This abstracts viewport position across SwiftUI, UIKit, and custom controls.
- **`one_finger_tap`** dispatches a synthetic tap after the same semantic actionability path when given an element target, or at explicit coordinates for canvas-like UIs, maps, and other coordinate surfaces.

Rule of thumb: use `activate` for controls when accessibility activation applies, and use `one_finger_tap` when the intended product action is specifically a tap.

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

## Heist-Themed Names

The names (TheFence, TheSafecracker, TheHandoff, etc.) are the project's identity. Each maps to a clear architectural role — see the README's "Meet the Crew" section for the full cast. The metaphor is consistent: TheFence dispatches commands, TheHandoff manages the connection, TheSafecracker cracks the UI, TheInsideJob runs inside the target app.
