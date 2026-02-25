# Changelog

All notable changes to ButtonHeist will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

## [Unreleased]

### Added
- **Heist rebrand** - Complete rename from Accra to ButtonHeist with heist film metaphor (TheScore, InsideJob, Wheelman, Stakeout)
- **iOS 26 touch injection** - Synthetic UITouch + IOHIDEvent injection with iOS 26 compatibility (fresh UIEvent per touch phase)
- **Touch injection fallback chain** - Three-level fallback: synthetic events, accessibilityActivate(), UIControl.sendActions()
- **Interactivity validation** - Element trait-level and view-level checks before tap injection
- **Tap visualization** - Visual overlay showing tap location with fade-out animation
- **Screen capture** - PNG screen capture via `requestScreen` command
- **Screen auto-broadcast** - Screen captures automatically sent alongside interface changes during polling
- **CLI action command** - `buttonheist action` for activating, tapping, incrementing, decrementing, and custom actions
- **CLI screenshot command** - `buttonheist screenshot` for capturing device screenshots
- **Increment/decrement commands** - `increment` and `decrement` messages for adjustable elements
- **Custom action support** - `performCustomAction` message for invoking named custom actions
- **Subscribe/unsubscribe** - Explicit subscription control for automatic updates
- **Tree hierarchy** - Optional `tree` field in `Interface` with container structure
- **Container types** - Semantic groups, lists, landmarks, data tables, and tab bars in tree hierarchy
- **Async/await client API** - `waitForActionResult(timeout:)` and `waitForScreen(timeout:)` on TheClient
- **Action result details** - `ActionResult` now includes `message` field for error descriptions
- **Device display names** - Smart disambiguation when multiple devices run the same app
- **Stakeout visual mode** - Screenshot display with element overlays and tap/activate gestures
- **Stakeout tree view** - Hierarchical tree display of accessibility containers
- **Element styling** - Color-coded badges and icons by trait type in inspector
- **USB connectivity** - Automatic CoreDevice IPv6 tunnel discovery via `USBDeviceDiscovery`
- **Auto-start configuration** - Environment variables and Info.plist keys for port, polling interval, and disable
- **Comprehensive test suite** - TheScoreTests (37 tests), WheelmanTests (12 tests), ButtonHeistCLITests
- **Token authentication** - Protocol v3.1 token-based auth with auto-generated or configured secrets, session locking
- **Rate limiting** - 30 messages/second per client, max 5 connections, 10 MB buffer limit
- **Loopback binding** - Simulator builds bind to loopback only by default
- **MCP server** - `buttonheist-mcp` for AI agent integration via Model Context Protocol
- **CLI session command** - Persistent interactive REPL with auto-reconnect
- **CLI type command** - Text entry via UIKeyboardImpl injection
- **CLI touch gestures** - Full gesture simulation (tap, swipe, drag, pinch, rotate, draw)
- **Interface delta** - ActionResult includes compact diff of hierarchy changes
- **Animation detection** - Wait-for-idle support and animation state in action results
- **HeistElement** - Rich element model with traits, hints, activation points, custom content
- **Edit actions** - Copy, paste, cut, select, selectAll via responder chain
- **Multi-window support** - Traverses all visible windows sorted by window level

### Changed
- Protocol version updated to 3.1 (with token authentication and session locking)
- SimpleSocketServer reimplemented with Network framework (NWListener/NWConnection)
- `bundleIdentifier` in `ServerInfo` changed from `String?` to `String`
- Bonjour service name format changed to `{AppName}#{instanceId}`
- Element type renamed from `UIElement` to `HeistElement` with additional fields
- Updated AccessibilitySnapshot submodule to latest `a11y-hierarchy-parsing` branch

### Technical Details
- Wire protocol version: 3.1
- Bonjour service type: `_buttonheist._tcp`
- Default port: 1455 (configurable)
- Minimum iOS: 17.0
- Minimum macOS: 14.0
- CLI version: 2.1.0
