# Changelog

All notable changes to ButtonHeist will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

## [Unreleased]

### Added
- **Heist rebrand** - Complete rename from Accra to ButtonHeist with heist film metaphor (TheGoods, InsideMan, Wheelman, Stakeout)
- **iOS 26 touch injection** - Synthetic UITouch + IOHIDEvent injection with iOS 26 compatibility (fresh UIEvent per touch phase)
- **Touch injection fallback chain** - Three-level fallback: synthetic events, accessibilityActivate(), UIControl.sendActions()
- **Interactivity validation** - Element trait-level and view-level checks before tap injection
- **Tap visualization** - Visual overlay showing tap location with fade-out animation
- **Screenshot capture** - PNG screenshot capture via `requestScreenshot` command
- **Screenshot auto-broadcast** - Screenshots automatically sent alongside hierarchy changes during polling
- **CLI action command** - `buttonheist action` for activating, tapping, incrementing, decrementing, and custom actions
- **CLI screenshot command** - `buttonheist screenshot` for capturing device screenshots
- **Increment/decrement commands** - `increment` and `decrement` messages for adjustable elements
- **Custom action support** - `performCustomAction` message for invoking named custom actions
- **Subscribe/unsubscribe** - Explicit subscription control for automatic updates
- **Tree hierarchy** - Optional `tree` field in `HierarchyPayload` with container structure
- **Container types** - Semantic groups, lists, landmarks, data tables, and tab bars in tree hierarchy
- **Async/await client API** - `waitForActionResult(timeout:)` and `waitForScreenshot(timeout:)` on Wheelman
- **Action result details** - `ActionResult` now includes `message` field for error descriptions
- **Device display names** - Smart disambiguation when multiple devices run the same app
- **Stakeout visual mode** - Screenshot display with element overlays and tap/activate gestures
- **Stakeout tree view** - Hierarchical tree display of accessibility containers
- **Element styling** - Color-coded badges and icons by trait type in inspector
- **USB connectivity** - CoreDevice IPv6 tunnel support with helper scripts
- **Python USB module** - `buttonheist_usb.py` for scripted USB connections
- **Auto-start configuration** - Environment variables and Info.plist keys for port, polling interval, and disable
- **Comprehensive test suite** - TheGoodsTests (37 tests), WheelmanTests (12 tests), ButtonHeistCLITests

### Changed
- Protocol version updated to 2.0
- InsideMan uses BSD sockets (SimpleSocketServer) instead of Network framework
- Wheelman uses BSD sockets for data transport (NWConnection only for service resolution)
- `bundleIdentifier` in `ServerInfo` changed from `String?` to `String`
- Bonjour service name format changed to `{AppName}-{DeviceName}`
- Updated AccessibilitySnapshot submodule to latest `a11y-hierarchy-parsing` branch

### Technical Details
- Wire protocol version: 2.0
- Bonjour service type: `_buttonheist._tcp`
- Default port: 1455 (configurable)
- Minimum iOS: 17.0
- Minimum macOS: 14.0
- CLI version: 2.0.0
