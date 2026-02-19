---
date: 2026-02-19T00:00:00Z
researcher: claude
git_commit: 004c463c34cb0f929a30459e728f74e87ae290e0
branch: RoyalPineapple/ai-fuzz-framework
repository: minnetonka
topic: "Full PR review: ai-fuzz-framework branch"
tags: [research, pr-review, insideman, mcp, delta, overlay, fuzzer]
status: complete
last_updated: 2026-02-19
last_updated_by: claude
---

# PR Review: ai-fuzz-framework

**Branch**: `RoyalPineapple/ai-fuzz-framework`
**Commits**: 45 commits from `main` to `004c463`
**Stats**: 71 files changed, ~11,700 lines added, ~209 removed

## Summary

This branch adds an AI-powered fuzzing framework for ButtonHeist and makes significant improvements to InsideMan's intelligence — richer element data, interface delta reporting, overlay visibility, animation-aware settling, and MCP connection resilience. The bulk of the line count is fuzzer documentation/references (additive, low-risk). The core Swift changes are concentrated in 6 files.

## Core Swift Changes

### 1. InsideMan.swift — Major Overhaul (+642 lines net)

**UIElement → HeistElement rename**: `AccessibilityMarker` → `AccessibilityElement`, `convertMarker` → `convertElement`, with richer wire fields: `hint`, `traits`, `activationPointX/Y`, `respondsToUserInteraction`, `customContent`.

**Window traversal rewrite**: `getRootView()` (single window, rootVC.view) replaced by `getTraversableWindows()` (all windows in foreground scene, passing UIWindow itself as rootView). This makes system overlays (UIMenu, UIDatePicker, UIColorPicker) visible to the accessibility parser.

**Multi-window refreshAccessibilityData**: Iterates all traversable windows, merging their accessibility trees. When multiple windows are present, wraps each in a container node with the window class name. Interactive object indices are globally offset.

**Screen capture compositing**: `broadcastScreen()` and `handleScreen()` now composite all traversable windows bottom-to-top via `captureScreen()`, so screenshots include overlay content.

**Animation detection**: New `hasActiveAnimations()` walks the CALayer tree of all traversable windows looking for animation keys, ignoring `_UIParallaxMotionEffect`. `waitForAnimationsToSettle()` polls every 10ms with a configurable timeout.

**Interface delta system**: Every action handler now takes a before-snapshot, performs the action, waits for settle, takes an after-snapshot, and computes a delta. `computeDelta()` uses:
- Hash equality for quick no-change detection
- Identifier overlap ratio for screen-change detection (<50% overlap)
- Identifier-based value/description/label comparison
- Order-based comparison for unidentified elements (segmented controls)

**Settle strategy in actionResultWithDelta**:
- No animations: 50ms yield
- Animations: 0.5s animation settle (10ms polling, exits early)
- If change detected + still animating: 1s fixed delay, re-snapshot

**sendInterface now async**: Checks for active animations and settles (0.5s) before snapshotting.

**All handlers now async**: Message handler, all action handlers, all gesture handlers — everything awaits rather than spawning nested Tasks.

**New handlers**: `handleEditAction` (copy/paste/cut/select/selectAll via responder chain), `handleWaitForIdle` (explicit animation wait with configurable timeout).

### 2. Messages.swift (TheGoods) — Wire Protocol Additions (+160 lines)

**HeistElement**: Replaces `UIElement` with richer fields: `hint`, `traits: [String]`, `activationPointX/Y`, `respondsToUserInteraction`, `customContent: [HeistCustomContent]?`.

**InterfaceDelta**: New type with `DeltaKind` enum (noChange, valuesChanged, elementsChanged, screenChanged), element count, added/removed elements, value changes, and optional full new interface for screen changes.

**ValueChange**: Tracks per-element changes with order, identifier, old/new values.

**ActionResult**: Extended with `interfaceDelta: InterfaceDelta?` and `animating: Bool?`.

**New message types**: `ClientMessage.editAction(EditActionTarget)`, `ClientMessage.waitForIdle(WaitForIdleTarget)`.

**New action methods**: `.editAction`, `.waitForIdle`.

### 3. main.swift (MCP Server) — Resilience + New Tools (+174 lines)

**Connection guard**: `sendAction()` checks `client.connectionState == .connected` before sending. On timeout, calls `forceDisconnect()` to trigger reconnect.

**Auto-reconnect**: `onDisconnected` callback watches for new device instances for up to 60 seconds, reconnects automatically when the app relaunches.

**requestInterface extracted**: Moved from inline in tool handler to standalone function with connection guard and force-disconnect on timeout.

**Delta pass-through**: Action results now serialize and forward `interfaceDelta` JSON and `animating` warnings to MCP tool output.

**New tools**: `edit_action` (copy/paste/cut/select/selectAll), `wait_for_idle` (explicit animation wait).

**Updated tool description**: `wait_for_idle` notes that actions and `get_interface` settle automatically.

### 4. HeistClient.swift — Keepalive + Force Disconnect (+26 lines)

**Keepalive**: Sends `.ping` every 3 seconds to detect dead TCP connections early.

**forceDisconnect()**: Public method to forcefully close a stale connection and trigger `onDisconnected`, used by MCP server on action timeout.

### 5. SafeCracker.swift — Edit Actions (+29 lines)

**EditAction enum**: Maps string names to UIResponderStandardEditActions selectors.

**performEditAction()**: Routes through `UIApplication.shared.sendAction()` — works regardless of edit menu visibility, following KIF's pattern.

### 6. TapVisualizerView.swift — Visibility Change (+2 lines)

`TapOverlayWindow` changed from `private` to `internal` so `getTraversableWindows()` can filter it with `!(window is TapOverlayWindow)`.

## Test Changes

Tests updated for `UIElement` → `HeistElement` rename. No new test coverage for delta computation, animation detection, or overlay traversal — these are validated end-to-end via MCP tools.

## Fuzzer Framework (Additive)

The `ai-fuzzer/` directory contains Claude Code skills, references, and session infrastructure for autonomous iOS app fuzzing. Includes strategies (swarm testing, boundary testing, invariant testing), trace format spec, simulator lifecycle docs, and example reports. All documentation — no runtime code.

## Architecture Observations

- **InsideMan is now the intelligence layer**: Animation detection, tree settling, delta computation, and overlay traversal all happen inside InsideMan. The MCP server is a thin pass-through.
- **All action handlers follow the same pattern**: refresh → snapshot before → perform action → settle → snapshot after → compute delta → return enriched result.
- **Window-as-root traversal**: UIWindow (a UIView subclass) is passed directly to the accessibility parser instead of rootViewController.view, making overlay content visible without multi-scene expansion.
- **Settle strategy is tiered**: instant (no animation) → 0.5s quick settle → 1s fixed delay for navigation springs. Avoids expensive repeated tree traversal during animation.
