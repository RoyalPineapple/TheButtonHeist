---
date: 2026-02-02T16:07:56+0100
researcher: Alex Odawa
git_commit: 3c7b3872da55a11f926866c532fd3be1bd032daf
branch: RoyalPineapple/a11y-tree-interact
repository: accra
topic: "Why accessibility notification detection via swizzling isn't working"
tags: [research, accessibility, swizzling, fishhook, uiaccessibility]
status: complete
last_updated: 2026-02-02
last_updated_by: Alex Odawa
---

# Research: Why Accessibility Notification Detection Isn't Working

**Date**: 2026-02-02 16:07:56 +0100
**Researcher**: Alex Odawa
**Git Commit**: 3c7b3872da55a11f926866c532fd3be1bd032daf
**Branch**: RoyalPineapple/a11y-tree-interact
**Repository**: accra

## Research Question
Why is the accessibility notification detection via method swizzling not working?

## Summary

**Root Cause**: The swizzling approach cannot work because `UIAccessibility.post(notification:argument:)` is **NOT an Objective-C method** - it's a Swift wrapper around the C function `UIAccessibilityPostNotification`. Traditional Objective-C method swizzling using `method_exchangeImplementations` only works with Objective-C methods, not C functions.

**Key Facts**:
- The selector `postNotification:argument:` doesn't exist on `UIAccessibility`
- `class_getClassMethod()` returns `nil` because there's no such method
- The swizzle silently fails - no crash, but no interception either
- The underlying implementation is the C function: `void UIAccessibilityPostNotification(UIAccessibilityNotifications notification, id argument)`

## Detailed Findings

### Current Implementation Analysis

**AccessibilityNotificationObserver.swift:25-46** attempts to swizzle like this:
```swift
guard let uiAccessibilityClass = NSClassFromString("UIAccessibility") else { return }

let originalSelector = NSSelectorFromString("postNotification:argument:")  // DOESN'T EXIST
let swizzledSelector = #selector(swizzled_postNotification(_:argument:))

guard let originalMethod = class_getClassMethod(uiAccessibilityClass, originalSelector),  // RETURNS NIL
      let swizzledMethod = class_getClassMethod(AccessibilityNotificationObserver.self, swizzledSelector) else {
    NSLog("[AccessibilityNotificationObserver] Could not find methods to swizzle")
    return  // SILENTLY EXITS HERE
}
```

**Why it fails**:
1. Line 35: `NSSelectorFromString("postNotification:argument:")` - this selector doesn't exist
2. Line 38: `class_getClassMethod` returns `nil` because there's no such Objective-C class method
3. The guard fails silently and returns without swizzling

### What UIAccessibility.post Actually Is

**Swift API**:
```swift
UIAccessibility.post(notification: .layoutChanged, argument: nil)
```

**Underlying C Function** (what Swift actually calls):
```c
UIKIT_EXTERN void UIAccessibilityPostNotification(UIAccessibilityNotifications notification, id argument);
```

This is a **C function**, not an Objective-C method. C functions:
- Don't have selectors
- Don't use Objective-C message dispatch
- Cannot be swizzled with `method_exchangeImplementations`

### Solution: Use Fishhook

[Fishhook](https://github.com/facebook/fishhook) by Facebook enables dynamic symbol rebinding for C functions in Mach-O binaries.

**How it works**:
- Manipulates pointer tables in the `__DATA` segment
- Rebinds symbols by updating lazy/non-lazy pointer sections
- Works on simulator and device

**Implementation**:
```c
#include "fishhook.h"

static void (*original_UIAccessibilityPostNotification)(UIAccessibilityNotifications, id);

void hooked_UIAccessibilityPostNotification(UIAccessibilityNotifications notification, id argument) {
    // Your observer logic here
    NSLog(@"[HOOK] UIAccessibilityPostNotification: %u, %@", notification, argument);

    // Call original
    original_UIAccessibilityPostNotification(notification, argument);
}

void setupAccessibilityHook() {
    struct rebinding rebindings[] = {
        {"UIAccessibilityPostNotification", hooked_UIAccessibilityPostNotification, (void *)&original_UIAccessibilityPostNotification}
    };
    rebind_symbols(rebindings, 1);
}
```

### Alternative: NotificationCenter (Limited)

Some accessibility events post to NotificationCenter:
```swift
NotificationCenter.default.addObserver(
    forName: UIAccessibility.screenChangedNotification,
    object: nil,
    queue: .main
) { notification in
    // Handle
}
```

**Limitations**:
- Only works for specific notification types that happen to post to NotificationCenter
- `UIAccessibility.screenChangedNotification` is for RECEIVING, not for intercepting POSTS
- Doesn't capture all `UIAccessibility.post()` calls

## Code References

- `AccraCore/Sources/AccraHost/AccessibilityNotificationObserver.swift:25-46` - Swizzling setup (fails silently)
- `AccraCore/Sources/AccraHost/AccraHost.swift:265-268` - Observer integration
- `TestApp/Sources/ContentView.swift:87-113` - Test buttons (correctly calling UIAccessibility.post)

## Architecture Documentation

The current flow that SHOULD work (but doesn't due to swizzling failure):

```
TestApp button tap
    ↓
UIAccessibility.post(.layoutChanged, argument: nil)
    ↓
[SWIZZLE INTERCEPT - NOT WORKING]
    ↓
AccessibilityNotificationObserver.onNotification callback
    ↓
AccraHost.handleAccessibilityNotification()
    ↓
Broadcast to Mac clients
```

## Recommended Fix

1. **Add fishhook dependency** via SPM or CocoaPods
2. **Replace swizzling code** with fishhook-based C function interception
3. **Call setupAccessibilityHook()** during AccraHost startup

This will work for development/testing purposes with the iOS Simulator and devices.

## Related Research

- [UIAccessibility.post - Apple Docs](https://developer.apple.com/documentation/uikit/uiaccessibility/1615194-post)
- [fishhook - Facebook GitHub](https://github.com/facebook/fishhook)
- [Dyld Interposing - Emerge Tools](https://www.emergetools.com/blog/posts/DyldInterposing)
- [Method Swizzling - NSHipster](https://nshipster.com/method-swizzling/)

## Open Questions

1. Is fishhook acceptable for the Accra test infrastructure?
2. Should we also intercept other UIKit accessibility functions?
3. Are there App Store restrictions that matter for this use case? (Likely not since this is test tooling)
