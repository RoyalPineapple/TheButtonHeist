# Exploration Report: ButtonHeist Test App

**Date**: 2026-02-13
**Device**: iPhone 16 Pro (Simulator)
**iOS Version**: 18.5
**Simulator UDID**: 56DC1DDE-5576-4768-8B5C-0383B9F33EC6
**App**: AccessibilityTestApp
**MCP Binary**: `ButtonHeistMCP/.build/release/buttonheist-mcp`
**Strategy**: Manual coordinate-based exploration (fallback due to `get_interface` timeout)

---

## Summary

| Metric               | Value |
|----------------------|-------|
| Screens discovered   | 3 (Main, Controls Demo, Toggles & Pickers) |
| Total screens in app | 9 (determined via source code) |
| Interactions attempted | 5 |
| Successful actions   | 4 (3 taps, 1 swipe) |
| Failed actions       | 1 (toggle tap missed target) |
| Crashes              | 0 |
| Errors               | 0 |
| Anomalies            | 2 |
| Blockers             | 1 (get_interface timeout) |

---

## Findings

### [ANOMALY] `get_interface` consistently times out after initial empty response

**Screen**: All screens
**Action**: `get_interface` via MCP JSON-RPC
**Expected**: Returns the full accessibility element hierarchy (identifiers, labels, values, frames, actions).
**Actual**: The very first call after connection returned successfully but with empty `elements: []` and `tree: []`. All subsequent calls timed out after 10 seconds with `"Action timed out"`.
**Steps to Reproduce**:
1. Launch a fresh `buttonheist-mcp` process.
2. Send the JSON-RPC initialize handshake.
3. Call `tools/call` with `get_interface`.
4. First call returns `{"elements":[],"tree":[]}`.
5. Any subsequent call to `get_interface` returns `{"code":-32603,"data":{"detail":"Action timed out"},"message":"Internal error: Action timed out"}`.

**Notes**: The MCP binary connects successfully to the device (`[DeviceConnection] Connected`, `Received server info: AccessibilityTestApp`). Touch actions (`tap`, `swipe`) work correctly, meaning the communication channel to the app is alive. The issue is specifically with the `requestInterface` message -- the app never sends back the interface payload. This is the primary blocker that forced the exploration to fall back to coordinate-based interaction using `simctl` screenshots. The `get_screen` MCP tool also never returns (the binary only outputs the initialize response and never sends the screenshot response for id:2).

---

### [ANOMALY] Toggle tap at computed coordinates did not activate the toggle

**Screen**: Toggles & Pickers
**Action**: `tap(x: 170, y: 107)`
**Expected**: "Subscribe to newsletter" toggle switches from OFF to ON; "Last action" label updates to "Toggle: ON".
**Actual**: Tap reported `Success (method: syntheticTap)` but the toggle remained OFF and the "Last action" label still showed "None".
**Steps to Reproduce**:
1. From the main screen, tap at (200, 155) to navigate to Controls Demo.
2. Tap at (200, 215) to navigate to Toggles & Pickers.
3. Tap at (170, 107) targeting the toggle switch.
4. Take a screenshot -- toggle is still OFF, "Last action: None".

**Notes**: This is likely a coordinate mapping issue rather than an app bug. Without `get_interface` returning frame data, precise element targeting requires guesswork on coordinate mapping between the 3x retina screenshot pixels and the MCP point coordinate system. The tap may have landed on the label text area rather than the interactive toggle switch.

---

## App Structure (from source code analysis)

The app is a SwiftUI NavigationStack-based demo with the following hierarchy:

```
RootView (ButtonHeist Test App)
|
+-- Controls Demo (ControlsDemoView)
|   |
|   +-- Text Input (TextInputDemo)
|   |   - Name TextField
|   |   - Email TextField
|   |   - Password SecureField
|   |   - Bio TextEditor
|   |
|   +-- Toggles & Pickers (TogglePickerDemo)
|   |   - Subscribe toggle (buttonheist.pickers.subscribeToggle)
|   |   - Frequency menu picker (buttonheist.pickers.menuPicker) [Daily/Weekly/Monthly]
|   |   - Priority segmented picker (buttonheist.pickers.segmentedPicker) [Low/Medium/High]
|   |   - Date picker (buttonheist.pickers.datePicker)
|   |   - Color picker (buttonheist.pickers.colorPicker)
|   |   - Last action label (buttonheist.pickers.lastActionLabel)
|   |
|   +-- Buttons & Actions (ButtonsActionsDemo)
|   |   - Tap count label (buttonheist.actions.tapCountLabel)
|   |   - Last action label (buttonheist.actions.lastActionLabel)
|   |   - Primary Button (buttonheist.actions.primaryButton) [borderedProminent]
|   |   - Bordered Button (buttonheist.actions.borderedButton) [bordered]
|   |   - Destructive Button (buttonheist.actions.destructiveButton) [destructive role]
|   |   - Disabled Button (buttonheist.actions.disabledButton) [disabled]
|   |   - Options Menu (buttonheist.actions.optionsMenu) [Option A, Option B, Delete]
|   |   - Swipe actions item (buttonheist.actions.customActionsItem) [custom: Favorite, Share]
|   |
|   +-- Adjustable Controls (AdjustableControlsDemo)
|   |   - Volume slider (buttonheist.adjustable.slider) [0-100, step 10, initial 50]
|   |   - Quantity stepper (buttonheist.adjustable.stepper) [0-10, initial 0]
|   |   - Level gauge (buttonheist.adjustable.gauge) [tied to slider value]
|   |   - Upload progress bar (buttonheist.adjustable.linearProgress) [0.4]
|   |   - Loading spinner (buttonheist.adjustable.spinnerProgress)
|   |   - Last action label (buttonheist.adjustable.lastActionLabel)
|   |
|   +-- Disclosure & Grouping (DisclosureGroupingDemo)
|   |   - Advanced Settings disclosure (buttonheist.disclosure.advancedGroup)
|   |     - Enable notifications toggle (buttonheist.disclosure.notifToggle) [constant: true]
|   |     - Dark mode toggle (buttonheist.disclosure.darkModeToggle) [constant: false]
|   |   - Version label (buttonheist.disclosure.versionLabel) ["1.0.0"]
|   |   - Build label (buttonheist.disclosure.buildLabel) ["42"]
|   |
|   +-- Alerts & Sheets (AlertsSheetDemo)
|   |   - Show Alert button (buttonheist.presentation.alertButton)
|   |   - Show Confirmation button (buttonheist.presentation.confirmButton)
|   |   - Show Sheet button (buttonheist.presentation.sheetButton)
|   |   - Last action label (buttonheist.presentation.lastActionLabel)
|   |   [Alert: title "Alert Title", message "This is an alert message.", OK button]
|   |   [Confirmation: "Choose Action" with Save, Discard (destructive), Cancel]
|   |   [Sheet: "Sheet Content" title + Dismiss button]
|   |
|   +-- Display (DisplayDemo)
|       - Star image (buttonheist.display.starImage) [accessibilityLabel: "Favorite star"]
|       - Info label (buttonheist.display.infoLabel)
|       - Apple Accessibility link (buttonheist.display.learnMoreLink)
|       - Header text (buttonheist.display.headerText) [isHeader trait]
|       - Static text (buttonheist.display.staticText)
|
+-- Touch Canvas (TouchCanvasView)
    - Canvas drawing area (buttonheist.touchCanvas.canvas) [multi-touch, UIKit-backed]
    - Reset toolbar button (buttonheist.touchCanvas.resetButton)
```

Total interactive elements cataloged: **35**
Total unique accessibility identifiers: **31**

---

## Interaction Log

| # | Screen | Action | Tool | Arguments | Result | State Change |
|---|--------|--------|------|-----------|--------|--------------|
| 1 | Main | Tap "Controls Demo" | tap | `x:200, y:155` | Success (syntheticTap) | Navigated to Controls Demo |
| 2 | Controls Demo | Tap "Toggles & Pickers" | tap | `x:200, y:215` | Success (syntheticTap) | Navigated to Toggles & Pickers |
| 3 | Toggles & Pickers | Tap toggle switch | tap | `x:170, y:107` | Success (syntheticTap) | No change (missed target) |
| 4 | Toggles & Pickers | Swipe right to go back | swipe | `startX:0, startY:400, dir:right, dist:200` | Success (syntheticSwipe) | Navigated back to main screen |
| 5 | Main | Tap "Controls Demo" (re-enter) | tap | `x:200, y:155` | Success (syntheticTap) | Navigated to Controls Demo |

---

## Screens Visited

### 1. Main Screen (RootView)

- **Title**: "ButtonHeist Test App"
- **Elements**: 2 NavigationLinks in a List
  - "Controls Demo" (navigates to ControlsDemoView)
  - "Touch Canvas" (navigates to TouchCanvasView)
- **Observations**: Clean layout. No scrolling required. Both links are visible and tappable.

### 2. Controls Demo Screen

- **Title**: "Controls Demo"
- **Elements**: 7 NavigationLinks in a List
  - Text Input, Toggles & Pickers, Buttons & Actions, Adjustable Controls, Disclosure & Grouping, Alerts & Sheets, Display
- **Navigation**: Back button visible at top-left. Swipe-right from left edge also works.
- **Observations**: All 7 rows visible without scrolling. Standard iOS list layout.

### 3. Toggles & Pickers Screen

- **Title**: "Toggles & Pickers"
- **Elements**:
  - Subscribe to newsletter toggle (OFF)
  - Frequency picker showing "Daily"
  - Priority segmented control showing Low / Medium / High (Low selected)
  - Date picker showing "13 Feb 2026"
  - Accent color picker (blue gradient circle)
  - "Last action: None" label at bottom
- **Observations**: All elements visible without scrolling. Toggle tap at computed coordinates did not register (see ANOMALY above).

---

## Screens Not Visited (identified from source)

| Screen | Reason |
|--------|--------|
| Text Input | Skipped -- text fields are out of scope per fuzzer rules |
| Buttons & Actions | Not reached due to time spent debugging get_interface |
| Adjustable Controls | Not reached |
| Disclosure & Grouping | Not reached |
| Alerts & Sheets | Not reached |
| Display | Not reached |
| Touch Canvas | Not reached |

---

## Blocker Analysis: `get_interface` Timeout

The `get_interface` tool is the primary observation mechanism for the fuzzer. Its failure means:

1. **No element frame data** -- Cannot compute precise tap coordinates from accessibility frames.
2. **No identifier-based targeting** -- Cannot use `tap(identifier: "...")` or `activate(identifier: "...")`.
3. **No accessibility value readback** -- Cannot verify state changes (e.g., toggle ON/OFF, slider value) without visual inspection.
4. **No custom action discovery** -- Cannot discover or invoke custom accessibility actions like "Favorite" and "Share" on the Buttons & Actions screen.

### Root Cause Investigation

From the MCP source code (`ButtonHeistMCP/Sources/main.swift`):

```swift
case "get_interface":
    client.send(.requestInterface)
    let iface: Interface = try await withCheckedThrowingContinuation { continuation in
        var didResume = false
        let timeoutTask = Task {
            try await Task.sleep(nanoseconds: 10_000_000_000) // 10 seconds
            if !didResume {
                didResume = true
                continuation.resume(throwing: HeistClient.ActionError.timeout)
            }
        }
        client.onInterfaceUpdate = { payload in
            if !didResume {
                didResume = true
                timeoutTask.cancel()
                continuation.resume(returning: payload)
            }
        }
    }
```

The MCP sends `requestInterface` to the app via the HeistClient and waits up to 10 seconds for the `onInterfaceUpdate` callback. The callback never fires, meaning the app (InsideMan framework) either:
- Does not receive the `requestInterface` message, or
- Receives it but fails to generate/send back the interface payload, or
- Sends back a response that the HeistClient does not parse as an interface update.

The first call DID return successfully but with empty arrays, suggesting the initial interface response was received but contained no elements. This could indicate the InsideMan accessibility walker is not finding any elements on the root screen.

### Workaround Used

Coordinate-based exploration using `simctl io screenshot` for visual observation and `tap(x, y)` / `swipe(...)` for interaction. This approach works for navigation and simple taps but lacks precision for small targets (toggles, segmented controls) and cannot verify state changes programmatically.

---

## Recommendations

1. **Investigate `get_interface` / InsideMan communication**: The interface request timeout is the critical blocker. Check the InsideMan framework's accessibility walking logic and message handling on the app side. The empty initial response and subsequent timeouts suggest either a race condition or a message handling bug.

2. **Investigate `get_screen` timeout**: The screenshot tool also fails to return. Since it uses `client.waitForScreen(timeout: 30)`, the same underlying communication issue likely affects both observation tools.

3. **Coordinate calibration**: If coordinate-based fallback is needed long-term, document the exact mapping between MCP point coordinates and the device's logical point system. The current exploration required trial-and-error to find correct tap positions.

4. **Re-run full exploration once get_interface works**: The app has 35+ interactive elements across 9 screens. A full systematic traversal with element-level targeting, increment/decrement on adjustable controls, custom action invocation, and alert/sheet/confirmation dialog interaction would provide significantly better coverage.

5. **Priority screens to test next**: Alerts & Sheets (modal presentation/dismissal), Buttons & Actions (custom accessibility actions, disabled button behavior), and Adjustable Controls (slider/stepper boundary testing) are the highest-value targets for finding bugs.

---

## Environment Details

- **Platform**: macOS Darwin 25.2.0
- **Simulator**: iPhone 16 Pro iOS 18.5 (56DC1DDE-5576-4768-8B5C-0383B9F33EC6)
- **Also booted**: iPad Pro 13-inch M5 iOS 26.2 (EEE91622-C333-4C19-9EF9-7E51F175A9D6)
- **MCP connection**: USB/network via HeistClient, connects to device "AccessibilityTestApp-iPhone 16 Pro iOS 18.5"
- **Observation method**: `xcrun simctl io <UDID> screenshot` (fallback)
- **Interaction method**: MCP `tap` and `swipe` via JSON-RPC stdin (working)
