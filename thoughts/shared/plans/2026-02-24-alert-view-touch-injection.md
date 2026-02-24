# Alert View Touch Injection Implementation Plan

## Overview

Make SafeCracker's synthetic touch injection work on alert windows. Currently, `SafeCracker.getKeyWindow()` only returns windows with `windowLevel <= .normal`, so alert windows (`windowLevel = .alert`) are invisible to touch injection. When `accessibilityActivate()` fails on an alert button, the synthetic tap fallback silently targets the wrong window.

Following KIF's pattern of searching all windows frontmost-first, we replace `getKeyWindow()` with a point-aware `windowForPoint(_:)` that finds the correct window for any screen coordinate.

## Current State Analysis

**What already works:**
- `getTraversableWindows()` (`InsideMan.swift:384-398`) includes all windows sorted by `windowLevel` — alert elements appear in `get_interface` output
- `accessibilityActivate()` (`InsideMan.swift:581-583`) works on live alert button objects — this is the primary activation path and usually succeeds for `UIAlertController` buttons
- Screen capture (`InsideMan.swift:497-510`) composites all windows including alerts

**What's broken:**
- `SafeCracker.getKeyWindow()` (`SafeCracker.swift:506-511`) filters to `windowLevel <= .normal`, excluding alert windows
- When `accessibilityActivate()` returns `false`, `safeCracker.tap(at: point)` sends the touch to the main app window behind the alert
- `hitTest` on the main window either returns `nil` (dimming view blocks) or hits the wrong view

### Key Discoveries:
- `SafeCracker.getKeyWindow()` at `SafeCracker.swift:506-511` — the root cause, filters `windowLevel <= .normal`
- `SafeCracker.touchesDown(at:)` at `SafeCracker.swift:398-441` — the only caller of `getKeyWindow()`, uses it for hit testing and event dispatch
- KIF's approach (documented in `thoughts/shared/research/2026-02-18-kif-system-dialog-handling.md:57-70`) — iterates all windows in reverse order, calls `hitTest` on each, uses the first hit
- `TapOverlayWindow` at `TapVisualizerView.swift:78` — must be excluded from window search (already excluded in `getTraversableWindows()` by type check)

## Desired End State

SafeCracker can inject synthetic touches into any visible window, including alert and action sheet windows. The window selection is automatic based on the tap point — frontmost window whose `hitTest` succeeds at that point receives the touch.

### Verification:
1. Launch TestApp, present an alert via "Show Alert" button
2. `buttonheist watch --once` shows alert elements (already works)
3. `buttonheist action --identifier OK` dismisses the alert (activation path)
4. Present alert again, `buttonheist touch-tap --point-x <x> --point-y <y>` on the OK button coordinates also dismisses it (synthetic tap path — currently broken, will be fixed)

## What We're NOT Doing

- **System permission alerts** (camera, location, etc.) — these render in SpringBoard (separate process), inaccessible from within the app. Same limitation as KIF. Documented as known limitation.
- **Tap-outside-to-dismiss** — not supporting tapping the dimming view to dismiss alerts. Only direct button taps.
- **`UIRemoteView` content** (photo picker, document picker) — cross-process boundary, inaccessible.
- **New wire protocol messages** — no protocol changes needed, existing `touchTap` and `activate` messages work.

## Implementation Approach

Single change to SafeCracker: replace the fixed-window `getKeyWindow()` with a point-aware lookup that follows KIF's frontmost-first search pattern. All callers (`touchesDown`) already have the target point available.

---

## Phase 1: Make SafeCracker Window-Aware

### Overview
Replace `getKeyWindow()` with `windowForPoint(_:)` that iterates all windows frontmost-first and returns the first whose `hitTest` succeeds at the given point. This routes synthetic touches to alert windows when they're frontmost.

### Changes Required:

#### 1. SafeCracker.swift — Replace `getKeyWindow()` with `windowForPoint(_:)`

**File**: `ButtonHeist/Sources/InsideMan/SafeCracker.swift`

Replace the `getKeyWindow()` method (lines 506-512) with a point-aware window lookup:

```swift
/// Find the correct window for a tap at the given screen point.
/// Iterates all windows frontmost-first (highest windowLevel first),
/// following KIF's pattern from UIApplication-KIFAdditions.m.
/// Returns the first window whose hitTest succeeds at the point.
private func windowForPoint(_ point: CGPoint) -> UIWindow? {
    let allWindows = UIApplication.shared.connectedScenes
        .compactMap { $0 as? UIWindowScene }
        .flatMap { $0.windows }
        .filter { !($0 is TapOverlayWindow) && !$0.isHidden }
        .sorted { $0.windowLevel > $1.windowLevel }

    for window in allWindows {
        let windowPoint = window.convert(point, from: nil)
        if window.hitTest(windowPoint, with: nil) != nil {
            return window
        }
    }
    return nil
}
```

#### 2. SafeCracker.swift — Update `touchesDown(at:)` to use `windowForPoint(_:)`

**File**: `ButtonHeist/Sources/InsideMan/SafeCracker.swift`

In `touchesDown(at:)` (line 398-441), replace the `getKeyWindow()` call with `windowForPoint(_:)` using the first point:

Change:
```swift
guard let window = getKeyWindow() else {
```

To:
```swift
guard let window = windowForPoint(points[0]) else {
```

#### 3. SafeCracker.swift — Remove `getKeyWindow()`

**File**: `ButtonHeist/Sources/InsideMan/SafeCracker.swift`

Delete the now-unused `getKeyWindow()` method (lines 506-512).

### Success Criteria:

#### Automated Verification:
- [ ] InsideMan builds: `xcodebuild -workspace ButtonHeist.xcworkspace -scheme InsideMan -destination 'generic/platform=iOS' build`
- [ ] TheGoods builds: `xcodebuild -workspace ButtonHeist.xcworkspace -scheme TheGoods build`
- [ ] Wheelman builds: `xcodebuild -workspace ButtonHeist.xcworkspace -scheme Wheelman build`
- [ ] ButtonHeist builds: `xcodebuild -workspace ButtonHeist.xcworkspace -scheme ButtonHeist build`
- [ ] AccessibilityTestApp builds: `xcodebuild -workspace ButtonHeist.xcworkspace -scheme AccessibilityTestApp -destination 'platform=iOS Simulator,id=$SIM_UDID' build`
- [ ] Existing tests pass: `xcodebuild -workspace ButtonHeist.xcworkspace -scheme TheGoodsTests test`

---

## Phase 2: End-to-End Verification

### Overview
Build and deploy to simulator, verify alert button tapping works through both activation and synthetic touch paths.

### Steps:

#### 1. Build and deploy test app
```bash
SIM_UDID=<pick-available-simulator>
xcrun simctl boot "$SIM_UDID"
xcodebuild -workspace ButtonHeist.xcworkspace -scheme AccessibilityTestApp \
  -destination "platform=iOS Simulator,id=$SIM_UDID" build
APP=$(ls -td ~/Library/Developer/Xcode/DerivedData/ButtonHeist*/Build/Products/Debug-iphonesimulator/AccessibilityTestApp.app | head -1)
xcrun simctl install "$SIM_UDID" "$APP"
xcrun simctl launch "$SIM_UDID" com.buttonheist.testapp
```

#### 2. Build CLI
```bash
cd ButtonHeistCLI && swift build -c release && cd ..
export PATH="$PWD/ButtonHeistCLI/.build/release:$PATH"
export BUTTONHEIST_HOST=127.0.0.1
export BUTTONHEIST_PORT=1455
```

#### 3. Verify alert button tapping

**Test A — Activation path (existing, should still work):**
```bash
# Navigate to Alerts & Sheets screen
buttonheist action --identifier "buttonheist.presentation.alertButton"
sleep 1
# Verify alert is visible
buttonheist watch --once  # Should show "Alert Title", "OK" button
# Dismiss via activation
buttonheist action --identifier "OK"  # or by label
sleep 1
buttonheist watch --once  # Alert should be gone
```

**Test B — Synthetic touch path (the fix):**
```bash
# Present alert again
buttonheist action --identifier "buttonheist.presentation.alertButton"
sleep 1
# Get the OK button coordinates from interface
buttonheist watch --once  # Note the OK button's frameX/Y/Width/Height
# Tap using raw coordinates (bypasses accessibilityActivate, goes straight to SafeCracker)
buttonheist touch-tap --point-x <center_x> --point-y <center_y>
sleep 1
buttonheist watch --once  # Alert should be dismissed
```

**Test C — Confirmation dialog:**
```bash
buttonheist action --identifier "buttonheist.presentation.confirmButton"
sleep 1
buttonheist watch --once  # Should show "Save", "Discard", "Cancel"
buttonheist action --identifier "Save"  # or touch-tap at coordinates
```

### Success Criteria:

#### CLI Verification:
- [ ] Alert appears in `watch --once` output with button elements
- [ ] `activate` on alert button dismisses the alert
- [ ] `touch-tap` at alert button coordinates dismisses the alert
- [ ] Confirmation dialog buttons are tappable
- [ ] After alert dismissal, tapping normal app elements still works (regression check)

---

## Testing Strategy

### Automated Tests:
- Existing `TheGoodsTests` and `WheelmanTests` cover wire protocol and message encoding — no changes needed since no protocol changes
- Existing `ButtonHeistTests` cover action dispatch — should pass unchanged

### Integration Tests (via CLI on simulator):
- Present alert → verify elements in interface → tap button → verify dismissed
- Present confirmation dialog → tap action → verify dismissed
- Present alert → dismiss → tap normal button → verify still works
- These follow the project's CLI-first development approach

## References

- KIF research: `thoughts/shared/research/2026-02-18-kif-system-dialog-handling.md`
- KIF's `windowsWithKeyWindow` reverse enumeration: lines 57-70 of research doc
- Previous multi-window plan (already implemented): `thoughts/shared/plans/2026-02-18-multi-window-and-edit-actions.md`
- Test app alert demo: `TestApp/Sources/AlertsSheetDemo.swift`
- SafeCracker current `getKeyWindow()`: `SafeCracker.swift:506-511`
