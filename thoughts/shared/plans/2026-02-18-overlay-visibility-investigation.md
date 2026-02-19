# Overlay Visibility Investigation Plan

## Overview

System overlays (UIMenu popups, UIDatePicker inline calendar, UIColorPickerViewController sheets) are invisible to `get_interface`. This plan investigates the root cause and implements a fix to make overlay content visible in the accessibility tree.

## Root Cause Analysis

The parser starts at `window.rootViewController!.view`, but overlays live **outside** that subtree:

| Overlay | Where it lives | Why parser misses it |
|---|---|---|
| UIContextMenu popup | `_UIContextMenuContainerView` — direct child of UIWindow | Sibling of rootVC.view, not a descendant |
| UIColorPicker sheet | `UITransitionView` — standard modal presentation container | Sibling of rootVC.view inside UIWindow |
| UIDatePicker compact | `UIAutoRotatingWindow.sharedPopoverHostingWindow` or popover view in UIWindow | Either separate window or window-level sibling |

**The fix vector is NOT multi-scene expansion** (that caused hangs). The fix is traversing from `UIWindow` itself instead of `rootViewController.view`, so the parser sees ALL of the window's subviews including overlay containers.

### Critical Realization

The previous attempt to use `window` as root view appeared to hang — but "even reverting didn't help." That was the clue that led to discovering the **stale TCP connection** issue. The keepalive/force-disconnect fix is now in place. The previous hang was very likely a false negative caused by the dead connection, not by the traversal change itself.

## What We're NOT Doing

- No multi-scene window expansion (iterating ALL `connectedScenes` caused real hangs with `UITextEffectsWindow` etc.)
- No private API usage (no class-name string matching for system windows)
- No changes to the AccessibilitySnapshot parser itself
- No changes to how the MCP server handles interface data

## Phase 1: Runtime Diagnostics

### Overview
Add temporary diagnostic logging to understand what's in the window hierarchy when overlays are open. No functional changes — purely observational.

### Changes Required:

#### 1. InsideMan.swift — Add diagnostic window logging

**File**: `ButtonHeist/Sources/InsideMan/InsideMan.swift`

Add a diagnostic method and call it from `refreshAccessibilityData()`:

```swift
/// Log window hierarchy for diagnostic purposes.
private func logWindowHierarchy() {
    guard let windowScene = UIApplication.shared.connectedScenes
            .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene else {
        serverLog("DIAG: No foreground active window scene")
        return
    }

    for window in windowScene.windows {
        let className = NSStringFromClass(type(of: window))
        let rootVCType = window.rootViewController.map { NSStringFromClass(type(of: $0)) } ?? "nil"
        let subviewCount = window.subviews.count
        let subviewClasses = window.subviews.map { NSStringFromClass(type(of: $0)) }
        serverLog("DIAG: Window \(className) level=\(window.windowLevel.rawValue) rootVC=\(rootVCType) subviews=\(subviewCount) [\(subviewClasses.joined(separator: ", "))]")
    }
}
```

Call from the top of `refreshAccessibilityData()`.

### Success Criteria:

#### Verification:
- [ ] Build and install test app
- [ ] Open the Toggles & Pickers screen, then:
  - Activate menu picker → check server logs for window/view hierarchy
  - Activate date picker → check server logs
  - Activate color picker → check server logs
- [ ] Confirm overlays are visible as UIWindow subviews or separate windows

**Implementation Note**: This is diagnostic-only. Review the logs before proceeding to Phase 2. If overlays are NOT in the foreground scene's windows at all (e.g., they use a separate system scene), the fix approach needs to change.

---

## Phase 2: Window-as-Root Traversal

### Overview
Change `getTraversableWindows()` to pass `window` (a UIView subclass) to the parser instead of `rootViewController!.view`. This lets the parser see ALL subviews of each window, including overlay containers that are siblings of the root VC's view.

### Changes Required:

#### 1. InsideMan.swift — Update getTraversableWindows

**File**: `ButtonHeist/Sources/InsideMan/InsideMan.swift`

```swift
private func getTraversableWindows() -> [(window: UIWindow, rootView: UIView)] {
    guard let windowScene = UIApplication.shared.connectedScenes
            .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene else {
        return []
    }

    return windowScene.windows
        .filter { window in
            !(window is TapOverlayWindow) &&
            !window.isHidden &&
            window.bounds.size != .zero
        }
        .sorted { $0.windowLevel > $1.windowLevel }
        .map { ($0, $0 as UIView) }
}
```

Key changes from current code:
- `rootView` is now `window` itself (UIWindow is a UIView subclass)
- Filter relaxed: no longer requires `rootViewController?.view != nil` — windows without rootVCs are included
- Added `!window.isHidden` and `window.bounds.size != .zero` safety filters
- Still single foreground-active scene only (no multi-scene expansion)

Since `UIWindow.isAccessibilityElement` is `false` by default, the parser will recurse into `UIWindow.subviews`, which includes both `rootViewController.view` AND any overlay containers.

### Success Criteria:

#### Automated Verification:
- [ ] InsideMan builds: `xcodebuild -workspace ButtonHeist.xcworkspace -scheme InsideMan -destination 'generic/platform=iOS' build`
- [ ] TheGoods tests pass: `xcodebuild -workspace ButtonHeist.xcworkspace -scheme TheGoodsTests test`

#### Functional Verification:
- [ ] `get_interface` returns elements for the normal screen (no regression)
- [ ] Open context menu → `get_interface` shows menu items
- [ ] Open color picker sheet → `get_interface` shows color picker elements
- [ ] Open date picker calendar → `get_interface` shows calendar elements
- [ ] Actions on overlay elements work (tap menu item, tap calendar date)

---

## Phase 3: Safeguards (if Phase 2 hangs)

### Overview
If passing `window` to the parser causes hangs on specific views, add targeted safeguards. Only implement this phase if Phase 2 fails.

### Potential Approaches:

#### A. Per-window traversal timeout
Wrap each `parser.parseAccessibilityHierarchy(in:)` call in a Task with a 2-second timeout. If a window's traversal times out, skip it and log a warning.

#### B. Subview class filtering
Before passing `window` to the parser, check its subviews for known-problematic classes:
```swift
let skipClasses = ["UITextEffectsWindow", "UIRemoteKeyboardWindow"]
// Filter logic
```
This is fragile (private class names) and should be a last resort.

#### C. Hybrid approach — rootVC.view + extra subviews
Instead of passing `window` to the parser, continue using `rootVC.view` but ALSO traverse non-rootVC subviews of the window separately:
```swift
let rootView = window.rootViewController?.view
let extraViews = window.subviews.filter { $0 !== rootView }
// Parse rootView normally, then parse each extraView
```
This is more surgical but loses the benefit of the parser seeing the full window context.

### Success Criteria:
- [ ] `get_interface` never takes longer than 3 seconds per call
- [ ] Normal screens still return correct element counts
- [ ] At least some overlay content is visible

---

## Phase 4: Remove Diagnostics and Verify

### Overview
Remove the diagnostic logging from Phase 1, clean up, and do a final end-to-end verification.

### Changes Required:
- Remove `logWindowHierarchy()` method
- Remove diagnostic call from `refreshAccessibilityData()`

### Success Criteria:

#### Automated Verification:
- [ ] All builds pass (TheGoods, InsideMan, MCP server, test app)
- [ ] All tests pass (TheGoodsTests, ButtonHeistTests)

#### End-to-End Verification:
- [ ] Deploy test app, connect via MCP
- [ ] Navigate to Toggles & Pickers
- [ ] Activate menu picker → menu items visible in `get_interface`
- [ ] Activate date picker → calendar visible in `get_interface`
- [ ] Activate color picker → color picker visible in `get_interface`
- [ ] Normal screens unchanged (element counts match expectations)
- [ ] Delta reporting still works correctly for all actions

---

## Testing Strategy

### Integration Tests (via MCP tools):
1. Normal screen traversal — verify no regression in element counts
2. Context menu — open, verify items in interface, select one
3. Date picker inline — open, verify calendar in interface, select a date
4. Color picker sheet — open, verify elements in interface, dismiss
5. Multiple overlays — open an overlay, dismiss, open another (no stale state)

### Performance:
- `get_interface` response time should not increase by more than 50ms
- No timeouts on any screen

## References

- `getTraversableWindows()`: `InsideMan.swift:310-325`
- `refreshAccessibilityData()`: `InsideMan.swift:460-503`
- `parseAccessibilityHierarchy(in:)`: `AccessibilityHierarchyParser.swift:148`
- `recursiveAccessibilityHierarchy()`: `AccessibilityHierarchyParser.swift:701-771`
- `SafeCracker.findKeyboardFrame()` (all-scenes pattern): `SafeCracker.swift:232-242`
- Previous delta plan: `thoughts/shared/plans/2026-02-18-insideman-interface-delta.md`
- Previous multi-window plan: `thoughts/shared/plans/2026-02-18-multi-window-and-edit-actions.md`
