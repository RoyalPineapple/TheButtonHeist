# Reviewer's Guide

A quick orientation for anyone reviewing the ButtonHeist codebase for the first time.

## What Is This?

Button Heist lets AI agents (and humans) inspect and control iOS apps programmatically. Embed the `TheInsideJob` framework in your iOS app, then connect over WiFi or USB to tap buttons, read UI hierarchies, type text, swipe, scroll, take screenshots, and record video — all without manual interaction.

## The 5-Command Happy Path

Most usage boils down to five CLI commands:

```bash
buttonheist list                              # Find running apps
buttonheist get_interface                     # Read the UI element tree
buttonheist activate --identifier "loginBtn"  # Tap a control
buttonheist type_text "hello@example.com"     # Type into a field
buttonheist get_screen                        # Capture the screen
```

Everything else builds on this core loop.

## Why So Many Commands?

The `TheFence.Command` enum has 42 cases, the CLI has grouped top-level subcommands, and the MCP exposes 23 tools. This is driven by **iOS interaction coverage** — each command maps to a distinct iOS capability (accessibility activation, gesture types, scroll modes, text editing, recording, etc.).

Both interfaces use the same **grouping strategy**: gesture variants fold into one surface (`gesture` in MCP, `touch` in CLI), scroll variants fold into `scroll`, and edit menu operations fold into `edit_action`. Common operations like `activate`, `type_text`, and `get_interface` stay top-level in both.

## TheFence and TheHandoff

- **TheHandoff** owns transport: Bonjour discovery, TCP/TLS connection lifecycle, message send/receive, session state tracking. It exposes callback-based APIs and injectable closures for test mocking.
- **TheFence** owns command dispatch and request-response correlation (matching responses to requests via `requestId` continuations). It talks to TheHandoff directly — no intermediate wrapper.

This boundary exists so that **tests can inject mock connections** at the TheHandoff level via factory closures, while TheFence handles the command-level concerns independently.

## Why `activate` and `one_finger_tap` Both Exist

- **`activate`** is the primary interaction command. It calls `accessibilityActivate()` first (the same path VoiceOver uses), then falls back to a synthetic tap. This works reliably across SwiftUI, UIKit, and custom controls.
- **`one_finger_tap`** is a raw synthetic tap at exact coordinates. Use it for canvas-like UIs, maps, or other cases where accessibility activation doesn't apply.

Rule of thumb: use `activate` for controls, `one_finger_tap` for coordinates.

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

Protocol v8.0. Request/response with `requestId` correlation via `RequestEnvelope`/`ResponseEnvelope`; interface payloads use the canonical `InterfaceNode` tree, not a parallel flat element array. Messages are JSON over TLS-encrypted TCP. Push notifications (interface updates, interaction broadcasts) use `requestId: nil`. See `docs/WIRE-PROTOCOL.md` for the full spec.

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
