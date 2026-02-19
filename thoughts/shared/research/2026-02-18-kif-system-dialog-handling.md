---
date: 2026-02-18T13:47:42Z
researcher: aodawa
git_commit: 15030cb9977c366edb8e16f32264a21a5cce6ed5
branch: RoyalPineapple/ai-fuzz-framework
repository: RoyalPineapple/accra
topic: "How KIF handles system dialogs, edit menus, and multi-window accessibility traversal"
tags: [research, codebase, kif, system-dialogs, accessibility, edit-menu, insideman, multi-window]
status: complete
last_updated: 2026-02-18
last_updated_by: aodawa
---

# Research: How KIF Handles System Dialogs

**Date**: 2026-02-18T13:47:42Z
**Researcher**: aodawa
**Git Commit**: 15030cb
**Branch**: RoyalPineapple/ai-fuzz-framework
**Repository**: RoyalPineapple/accra

## Research Question

How does KIF (Keep It Functional) handle system dialogs, the iOS edit menu (copy/paste/select), and other system-level UI? Use this as a reference for how InsideMan/ButtonHeist should deal with these elements.

## Summary

KIF uses three distinct strategies depending on the type of system UI:

1. **Multi-window traversal** — KIF iterates ALL app windows (including system windows like `UITextEffectsWindow`) via `windowsWithKeyWindow`, searching in reverse order (frontmost first). This catches keyboard windows, picker views, and dimming views.

2. **Direct API access for edit menus** — KIF does NOT find UIMenuController items via accessibility traversal. Instead, it accesses `[UIMenuController sharedMenuController].menuItems` directly and invokes the action selectors on the first responder. This completely bypasses the menu UI.

3. **Private UIAutomation framework for system alerts** (deprecated) — For out-of-process system alerts (permissions dialogs), KIF linked against Apple's private UIAutomation framework. This was **removed in Xcode 12** and no longer works. KIF has no modern replacement.

**InsideMan's current gap**: It only traverses a single window (`windowLevel <= .statusBar`) and misses overlay windows, keyboard windows, and system UI entirely.

## Detailed Findings

### 1. KIF's Multi-Window Traversal

KIF's `UIApplication-KIFAdditions` provides the core window enumeration:

```objc
// UIApplication-KIFAdditions.m
- (NSArray *)windowsWithKeyWindow
{
    NSMutableArray *windows = self.windows.mutableCopy;
    UIWindow *keyWindow = self.keyWindow;
    if (![windows containsObject:keyWindow]) {
        [windows addObject:keyWindow];
    }
    return windows;
}
```

KIF searches all windows in **reverse order** (frontmost first):

```objc
- (UIAccessibilityElement *)accessibilityElementMatchingBlock:
    (BOOL(^)(UIAccessibilityElement *))matchBlock
{
    for (UIWindow *window in [self.windowsWithKeyWindow reverseObjectEnumerator]) {
        UIAccessibilityElement *element = [window accessibilityElementMatchingBlock:matchBlock];
        if (element) {
            return element;
        }
    }
    return nil;
}
```

KIF also has **named window finders** for specific system window types:

```objc
- (UIWindow *)keyboardWindow {
    for (UIWindow *window in self.windowsWithKeyWindow) {
        if ([NSStringFromClass([window class]) isEqual:@"UITextEffectsWindow"]) {
            return window;
        }
    }
    return nil;
}

- (UIWindow *)pickerViewWindow {
    for (UIWindow *window in self.windowsWithKeyWindow) {
        NSArray *pickerViews = [window subviewsWithClassNameOrSuperClassNamePrefix:@"UIPickerView"];
        if (pickerViews.count > 0) return window;
    }
    return nil;
}

- (UIWindow *)dimmingViewWindow {
    for (UIWindow *window in self.windowsWithKeyWindow) {
        NSArray *dimmingViews = [window subviewsWithClassNameOrSuperClassNamePrefix:@"UIDimmingView"];
        if (dimmingViews.count > 0) return window;
    }
    return nil;
}
```

**Key detail**: KIF uses `UIApplication.shared.windows` (deprecated), NOT `connectedScenes`. Still works but will need updating for future iOS versions.

### 2. KIF's Edit Menu (UIMenuController) Handling

KIF does **not** find edit menu items through accessibility traversal. Instead, it directly accesses the UIMenuController API:

```objc
// From community gist (RStankov/4413617)
+ (id)stepToTapUIMenuItemTitled:(NSString *)title
{
    return [KIFTestStep stepWithDescription:@"Tap menu item"
        executionBlock:^KIFTestStepResult(KIFTestStep *step, NSError **error) {

        UIMenuController *menuController = [UIMenuController sharedMenuController];
        NSPredicate *predicate = [NSPredicate predicateWithFormat:@"title like[c] %@", title];
        NSArray *items = [menuController.menuItems filteredArrayUsingPredicate:predicate];

        if (items.count == 0) return KIFTestStepResultFailure;

        UIMenuItem *item = [items objectAtIndex:0];
        UIResponder *firstResponder = [[UIApplication sharedApplication] keyWindow].firstResponder;
        [firstResponder performSelector:item.action];
        menuController.menuVisible = NO;

        return KIFTestStepResultSuccess;
    }];
}
```

**Technique**: Get the `sharedMenuController`, filter `menuItems` by title, then invoke the action selector directly on the first responder. No UI interaction needed.

**For standard actions** (cut/copy/paste/select/selectAll), these are responder chain methods — the first responder always responds to them:

- `cut:` → Cut
- `copy:` → Copy
- `paste:` → Paste
- `select:` → Select
- `selectAll:` → Select All

### 3. System Alerts (Deprecated Approach)

KIF used the private `UIAutomation` framework (via `KIFSystemAlertHandler.m`) to dismiss system permission dialogs. This:

- Only worked on **simulators** (not physical devices)
- Was **removed in Xcode 12** ([Issue #1156](https://github.com/kif-framework/KIF/issues/1156))
- Has no KIF-native replacement

**Modern alternatives** the KIF community uses:
- Method swizzling to stub permission requests
- Pre-configure simulator permissions via `xcrun simctl privacy`
- XCUITest's springboard access: `XCUIApplication(bundleIdentifier: "com.apple.springboard")`

### 4. UIRemoteView Limitation

KIF **cannot** access `UIRemoteView` content ([Issue #893](https://github.com/kif-framework/KIF/issues/893)). Remote views (photo picker, document picker, system preference panels) render in a separate process. Their internal elements are inaccessible from the app process.

### 5. KIF's Element Search Within a Window

KIF uses a two-phase recursive search on each `UIView`:

**Phase 1: Subview Traversal** — Reverse-order iteration of subviews (front to back), recursive.

**Phase 2: Accessibility Container Enumeration** — Stack-based breadth-first walk of `accessibilityElementCount` / `accessibilityElementAtIndex:` for views that act as accessibility containers.

**Tappability validation**: Each match is validated with `isTappableInRect:` using `UIView.hitTest`. Occluded elements are kept as fallbacks.

**Special cases**:
- `UIDatePicker` is skipped (has hundreds of thousands of placeholder elements)
- `UICollectionView` has special cell scrolling logic

### 6. InsideMan's Current Traversal (For Comparison)

InsideMan currently:

1. **Single window** — `getRootView()` at `InsideMan.swift:303` finds the first foreground window with `windowLevel <= .statusBar`
2. **Delegates to AccessibilityHierarchyParser** — `parseAccessibilityHierarchy(in:)` at `AccessibilityHierarchyParser.swift:148`
3. **VoiceOver-style traversal** — `recursiveAccessibilityHierarchy()` at line 701 walks the tree
4. **Spatial sorting** — Elements ordered by VoiceOver navigation rules (top-to-bottom, then horizontal)

**What InsideMan misses**:
- All overlay windows (alerts, action sheets presented at `.alert` window level)
- The keyboard window (`UITextEffectsWindow`)
- Edit menu (UIMenuController / UIEditMenuInteraction)
- Picker views and dimming views
- Any system UI outside the app process

## Actionable Patterns from KIF

### Pattern A: Multi-Window Element Search

Adopt KIF's `windowsWithKeyWindow` + reverse-enumeration pattern. For InsideMan this means:

```swift
// Instead of single-window:
let appWindow = windowScene.windows.first { $0.windowLevel <= .statusBar }

// Search ALL windows in the scene, frontmost first:
let allWindows = windowScene.windows.sorted { $0.windowLevel > $1.windowLevel }
for window in allWindows {
    // parse accessibility hierarchy in each window
}
```

### Pattern B: Direct Edit Menu Access

Instead of trying to find edit menu items in the accessibility tree, access `UIMenuController` directly:

```swift
// Check if edit menu is visible
let menuController = UIMenuController.shared
if menuController.isMenuVisible {
    // Report menu items as virtual accessibility elements
    // Or expose as custom actions on the focused text field
}

// Invoke standard edit actions on the first responder
if let firstResponder = UIApplication.shared.sendAction(#selector(copy:), to: nil, from: nil, for: nil) {
    // Action was handled
}
```

### Pattern C: Standard Edit Actions via Responder Chain

For cut/copy/paste/select/selectAll, invoke directly on the first responder without needing to find the menu:

```swift
UIApplication.shared.sendAction(#selector(UIResponderStandardEditActions.copy), to: nil, from: nil, for: nil)
UIApplication.shared.sendAction(#selector(UIResponderStandardEditActions.paste), to: nil, from: nil, for: nil)
UIApplication.shared.sendAction(#selector(UIResponderStandardEditActions.selectAll), to: nil, from: nil, for: nil)
```

### Pattern D: Named Window Type Detection

Check for known system window class names:

```swift
let className = NSStringFromClass(type(of: window))
switch className {
case "UITextEffectsWindow": // keyboard-related
case "UIRemoteKeyboardWindow": // remote keyboard
case let name where name.contains("Alert"): // alert windows
default: // regular app window
}
```

## Code References

- `InsideMan.swift:303-316` — Current single-window `getRootView()`
- `InsideMan.swift:449` — `parseAccessibilityHierarchy(in:)` call
- `InsideMan.swift:278-288` — `sendInterface(respond:)` handler
- `AccessibilityHierarchyParser.swift:148-161` — Main parser entry point
- `AccessibilityHierarchyParser.swift:701-771` — Recursive traversal
- `SafeCracker.swift` — Already has multi-window traversal for keyboard detection (`findKeyboardFrame()`)

## Sources

- [KIF UIApplication-KIFAdditions.m](https://github.com/cybertk/KIF-Tutorial/blob/master/KIF-2.0.0/Additions/UIApplication-KIFAdditions.m)
- [KIF UIView-KIFAdditions.m](https://github.com/cybertk/KIF-Tutorial/blob/master/KIF-2.0.0/Additions/UIView-KIFAdditions.m)
- [KIF UIMenuController Testing Gist](https://gist.github.com/RStankov/4413617)
- [KIF Issue #1156 — System alerts broken in Xcode 12](https://github.com/kif-framework/KIF/issues/1156)
- [KIF Issue #893 — UIRemoteView inaccessible](https://github.com/kif-framework/KIF/issues/893)
- [KIF PR #510 — System alert handler](https://github.com/kif-framework/KIF/pull/510)
- [KIF PR #1143 — Widen firstResponder search](https://github.com/kif-framework/KIF/pull/1143)

## Open Questions

1. Should InsideMan's `get_interface` return elements from ALL windows merged into one list, or should it tag elements with their source window?
2. For iOS 16+ `UIEditMenuInteraction`, should InsideMan detect the new menu API in addition to the legacy `UIMenuController`?
3. Should edit actions (copy/paste/cut/selectAll) be exposed as custom actions on text field elements, or as separate MCP tool commands?
