---
date: 2026-02-12T19:05:53Z
researcher: aodawa
git_commit: eb36fb015c62a07c008387dbda9466c1debd0bf4
branch: RoyalPineapple/heist-rebrand
repository: accra
topic: "Python test interface design: current state and integration points"
tags: [research, codebase, python, testing, wire-protocol, cli, wheelman]
status: complete
last_updated: 2026-02-12
last_updated_by: aodawa
---

# Research: Python Test Interface Design

**Date**: 2026-02-12T19:05:53Z
**Researcher**: aodawa
**Git Commit**: eb36fb015c62a07c008387dbda9466c1debd0bf4
**Branch**: RoyalPineapple/heist-rebrand
**Repository**: accra

## Research Question

We want ButtonHeist to be easy to use for writing tests. What should the test interface look like, and how can we best integrate with Python?

## Summary

ButtonHeist already has the building blocks for Python integration: a simple newline-delimited JSON wire protocol over TCP, an existing Python USB connection module (`scripts/buttonheist_usb.py`), and a CLI that provides a reference implementation of the full command→response round trip. The existing Python module covers ~30% of the wire protocol surface (connect, get_hierarchy, activate, tap, ping, find_element) but is missing touch gestures, screenshots, subscriptions, and the `_0` wrapper pattern is inconsistently applied. The Swift test suite covers protocol encoding/decoding exhaustively but has no integration tests against a real device. The gap is a proper Python client library designed around a test-friendly API.

## Detailed Findings

### 1. Wire Protocol (The Integration Contract)

The wire protocol is the integration boundary. A Python client must match it exactly.

**Transport**: TCP socket, newline-delimited JSON (UTF-8), port 1455.

**Key protocol detail - the `_0` wrapper**: Swift's Codable enum encoding wraps associated values in `{"_0": ...}`. Every message with a payload uses this:
- `{"activate":{"_0":{"identifier":"loginButton"}}}` (not `{"activate":{"identifier":"loginButton"}}`)
- `{"info":{"_0":{"protocolVersion":"2.0",...}}}` (server sends this)
- `{"error":{"_0":"message"}}` (string wrapped in `_0` too)

Simple cases produce empty objects: `{"ping":{}}`, `{"subscribe":{}}`.

**Full message catalog (16 client, 6 server)**:

Client → Server:
- 5 simple: `requestSnapshot`, `subscribe`, `unsubscribe`, `ping`, `requestScreenshot`
- 4 element actions: `activate`, `increment`, `decrement`, `performCustomAction`
- 7 touch gestures: `touchTap`, `touchLongPress`, `touchSwipe`, `touchDrag`, `touchPinch`, `touchRotate`, `touchTwoFingerTap`

Server → Client:
- `info`, `hierarchy`/`snapshot`, `pong`, `error`, `actionResult`, `screenshot`

**Reference**: `docs/WIRE-PROTOCOL.md`, `ButtonHeist/Sources/TheGoods/Messages.swift`

### 2. Existing Python Module (`scripts/buttonheist_usb.py`)

Single file, ~380 lines. Provides `ButtonHeistUSBConnection` class with context manager support.

**What it covers**:
- USB device discovery via `xcrun devicectl` + `lsof` IPv6 tunnel detection
- App launching via `xcrun devicectl device process launch`
- Port scanning (parallel scan of 52500-53500) or fixed port connection
- Newline-delimited JSON send/receive
- Methods: `get_hierarchy()`, `activate()`, `tap()`, `ping()`, `find_element()`

**What it's missing**:
- Touch gestures (longpress, swipe, drag, pinch, rotate, two-finger-tap)
- Screenshot capture
- Subscribe/unsubscribe
- WiFi/Bonjour discovery (USB-only)
- Async message handling (blocking reads only)
- No waiting patterns for action results with timeout
- `tap()` sends `{"tap":{"_0":...}}` but wire protocol expects `{"touchTap":{"_0":...}}`
- `get_hierarchy()` sends `{"requestHierarchy":{}}` but protocol expects `{"requestSnapshot":{}}`

**Error hierarchy**: `ButtonHeistUSBError` → `DeviceNotFoundError`, `ConnectionError`

### 3. Existing Swift Test Suite

17 test files across 3 targets (TheGoodsTests, WheelmanTests, ButtonHeistCLITests), all XCTest.

**Patterns**:
- Inline data creation (no fixtures)
- `if case .enumCase(let value) = decoded` pattern matching
- ISO8601 date encoding/decoding for timestamps
- No mocking, no async tests, no device interaction
- CLI tests duplicate formatting functions because executable can't be `@testable import`ed

**Coverage**: Protocol encoding/decoding is well-covered. Element equality, hashability, state machines tested. Zero integration tests with actual devices.

### 4. CLI Round-Trip Flow (Reference Implementation)

The CLI demonstrates the full pattern a Python client needs:

1. Discover device (Bonjour NWBrowser)
2. Connect TCP socket to `127.0.0.1:resolvedPort`
3. Auto-send: subscribe + requestSnapshot + requestScreenshot
4. Receive `info` message (server sends automatically)
5. Send command (e.g., `{"activate":{"_0":{"identifier":"btn"}}}`)
6. Read until `actionResult` message arrives
7. Parse result: `response["actionResult"]["_0"]["success"]`

**Exit codes**: 0=success, 1=connectionFailed, 2=noDeviceFound, 3=timeout

### 5. Wheelman Async Patterns

`waitForActionResult(timeout:)` and `waitForScreenshot(timeout:)` use continuation + timeout task pattern. Python equivalent: blocking read with `socket.settimeout()` or `asyncio.wait_for()`.

Key detail: Wheelman sends subscribe/requestSnapshot/requestScreenshot automatically on connect. Any Python client should replicate this for consistency.

## Architecture Documentation

### Current Integration Points

```
Python Test Script
    │
    ├── Option A: Direct TCP socket (current buttonheist_usb.py approach)
    │   └── Connect to IPv6 tunnel address:1455
    │       └── Send/receive newline-delimited JSON
    │
    ├── Option B: CLI subprocess
    │   └── Shell out to `buttonheist` CLI
    │       └── Parse stdout JSON output
    │
    └── Option C: Python client library (proposed)
        └── Higher-level API wrapping TCP socket
            └── pytest fixtures, element queries, assertions
```

### Wire Protocol Message Flow for Tests

```
Test Setup:
  connect() → TCP socket to device
  ← info message (automatic)
  → subscribe
  → requestSnapshot
  ← hierarchy message

Test Action:
  → touchTap / activate / etc.
  ← actionResult (success/fail + method)
  ← hierarchy (auto-pushed after UI change)

Test Assertion:
  → requestSnapshot (or use auto-pushed one)
  ← hierarchy message
  → requestScreenshot
  ← screenshot message (base64 PNG)
```

### Target Type Quick Reference (for Python implementation)

| Target | Required Fields | Optional Fields |
|--------|----------------|-----------------|
| ActionTarget | (at least one of:) identifier, order | |
| TouchTapTarget | (one of:) elementTarget OR pointX+pointY | |
| LongPressTarget | (one of:) elementTarget OR pointX+pointY | duration (default 0.5) |
| SwipeTarget | (one of:) elementTarget OR startX+startY | endX+endY OR direction+distance, duration |
| DragTarget | endX, endY | elementTarget OR startX+startY, duration |
| PinchTarget | scale | elementTarget OR centerX+centerY, spread, duration |
| RotateTarget | angle | elementTarget OR centerX+centerY, radius, duration |
| TwoFingerTapTarget | | elementTarget OR centerX+centerY, spread |
| CustomActionTarget | elementTarget, actionName | |

## Code References

- `scripts/buttonheist_usb.py:42-350` - Existing Python client class
- `ButtonHeist/Sources/TheGoods/Messages.swift:12-64` - ClientMessage enum (16 cases)
- `ButtonHeist/Sources/TheGoods/Messages.swift:277-295` - ServerMessage enum (6 cases)
- `ButtonHeist/Sources/TheGoods/Messages.swift:69-273` - All target type definitions
- `ButtonHeist/Sources/Wheelman/DeviceConnection.swift:146-231` - Message send/receive/decode
- `ButtonHeist/Sources/Wheelman/Wheelman.swift:197-242` - Async wait patterns
- `ButtonHeistCLI/Sources/ActionCommand.swift:110-154` - CLI action round-trip
- `ButtonHeistCLI/Sources/TouchCommand.swift:39-388` - All touch command implementations
- `ButtonHeist/Tests/TheGoodsTests/` - Protocol encoding test suite

## Related Research

- `thoughts/shared/research/2026-02-12-external-api-surface-review.md` - API surface review
- `thoughts/shared/research/2026-02-05-accra-full-codebase-review.md` - Full codebase review
- `thoughts/shared/research/2026-02-04-ios26-interaction-support.md` - iOS 26 touch injection

## Open Questions

1. **WiFi vs USB**: Should the Python library support both? Current module is USB-only. Bonjour discovery from Python requires `pyobjc` or `zeroconf` package.
2. **Sync vs async**: Should the Python API be synchronous (simpler for pytest) or asyncio-based (better for subscriptions)?
3. **Message naming discrepancy**: Wire protocol docs say "hierarchy" but Swift code encodes as "snapshot" — which does the server actually send on the wire?
4. **Existing module bugs**: `buttonheist_usb.py` sends `{"requestHierarchy":{}}` and `{"tap":{}}` which don't match the wire protocol (`{"requestSnapshot":{}}` and `{"touchTap":{}}`). Need to verify what the server actually accepts.
