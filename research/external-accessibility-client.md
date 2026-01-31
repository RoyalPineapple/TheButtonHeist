# External Accessibility Client Research

**Date:** 2026-01-31
**Goal:** Build an external tool that can access other apps' accessibility hierarchies

---

## Overview

This document explores how to build an **external accessibility client** - a tool that can inspect accessibility hierarchies of other apps, similar to:
- VoiceOver
- Accessibility Inspector (Xcode)
- Switch Control

This is different from the in-app approach in `swiftui-accessibility-insights.md`.

---

## iOS vs macOS: Key Differences

### macOS (Public APIs)
```swift
import ApplicationServices

// AXUIElement is public on macOS
let app = AXUIElementCreateApplication(pid)
var children: CFTypeRef?
AXUIElementCopyAttributeValue(app, kAXChildrenAttribute, &children)
```

### iOS (Private APIs)
```swift
// Must load AXRuntime.framework
dlopen("/System/Library/PrivateFrameworks/AXRuntime.framework/AXRuntime", RTLD_NOW)

// Classes available but undocumented
let axUIElement = NSClassFromString("AXUIElement")
let axElement = NSClassFromString("AXElement")
```

---

## Required Entitlements for External Access

External accessibility clients require **privileged entitlements** that Apple doesn't grant to App Store apps:

```xml
<!-- Entitlements for external accessibility access -->
<key>com.apple.private.accessibility.send</key>
<true/>
<key>com.apple.private.accessibility.receive</key>
<true/>
<key>com.apple.private.accessibility.observe</key>
<true/>
<key>com.apple.private.security.storage.AccessibilityStorage</key>
<true/>
```

**Where these entitlements are found:**
- `/System/Library/AccessibilityBundles/` - VoiceOver, Switch Control
- System daemons in `/System/Library/PrivateFrameworks/`
- Accessibility Inspector (macOS Xcode tool)

---

## Enabling Like AccessibilitySnapshot

AccessibilitySnapshot uses two key patterns we can build on:

### Pattern 1: Enable Automation Mode
```objective-c
// From ASAccessibilityEnabler.m
void *handle = dlopen("/usr/lib/libAccessibility.dylib", RTLD_NOW);
void (*_AXSSetAutomationEnabled)(int) = dlsym(handle, "_AXSSetAutomationEnabled");
_AXSSetAutomationEnabled(YES);
```

This enables **in-process** accessibility. For **external** access, we need more.

### Pattern 2: Enable Inspector Mode
```swift
// From PrivateAccessibilityExplorer.swift
typealias SetAXInspectorFunc = @convention(c) (Int32) -> Void
let setFunc = dlsym(libHandle, "_AXSAXInspectorSetEnabled")
let setter = unsafeBitCast(setFunc, to: SetAXInspectorFunc.self)
setter(1)
```

This enables **inspector mode** but still in-process.

---

## External Client Implementation

### Step 1: Load Private Frameworks
```swift
final class ExternalAccessibilityClient {
    private var axRuntimeHandle: UnsafeMutableRawPointer?
    private var libAccessibilityHandle: UnsafeMutableRawPointer?

    init() {
        // Load AXRuntime.framework
        axRuntimeHandle = dlopen(
            "/System/Library/PrivateFrameworks/AXRuntime.framework/AXRuntime",
            RTLD_NOW
        )

        // Load libAccessibility.dylib
        libAccessibilityHandle = dlopen(
            "/usr/lib/libAccessibility.dylib",
            RTLD_NOW
        )
    }
}
```

### Step 2: Enable Required Services
```swift
extension ExternalAccessibilityClient {
    func enableServices() {
        // 1. Enable automation
        callPrivateFunc("_AXSSetAutomationEnabled", arg: 1)

        // 2. Enable AX inspector
        callPrivateFunc("_AXSAXInspectorSetEnabled", arg: 1)

        // 3. Enable accessibility (required for simulator)
        callPrivateFunc("_AXSApplicationAccessibilitySetEnabled", arg: 1)
    }

    private func callPrivateFunc(_ name: String, arg: Int32) {
        guard let handle = libAccessibilityHandle else { return }
        typealias FuncType = @convention(c) (Int32) -> Void
        if let sym = dlsym(handle, name) {
            let fn = unsafeBitCast(sym, to: FuncType.self)
            fn(arg)
        }
    }
}
```

### Step 3: Get System-Wide Element
```swift
extension ExternalAccessibilityClient {
    func getSystemWideElement() -> AnyObject? {
        guard let axUIElement = NSClassFromString("AXUIElement") else {
            return nil
        }

        let sel = NSSelectorFromString("systemWideAXUIElement")
        return (axUIElement as AnyObject).perform(sel)?.takeUnretainedValue()
    }
}
```

### Step 4: Get App Element by PID
```swift
extension ExternalAccessibilityClient {
    func getApplicationElement(pid: pid_t) -> AnyObject? {
        guard let axUIElement = NSClassFromString("AXUIElement") else {
            return nil
        }

        // uiApplicationWithPid: requires NSNumber argument
        let sel = NSSelectorFromString("uiApplicationWithPid:")
        let pidNum = NSNumber(value: pid)
        return (axUIElement as AnyObject).perform(sel, with: pidNum)?.takeUnretainedValue()
    }
}
```

### Step 5: Traverse Children
```swift
extension ExternalAccessibilityClient {
    func getChildren(of element: AnyObject) -> [AnyObject]? {
        // For AXUIElement
        let childrenSel = NSSelectorFromString("children")
        if element.responds(to: childrenSel) {
            return element.perform(childrenSel)?.takeUnretainedValue() as? [AnyObject]
        }

        // For AXElement (higher-level wrapper)
        let elemChildrenSel = NSSelectorFromString("children")
        if element.responds(to: elemChildrenSel) {
            return element.perform(elemChildrenSel)?.takeUnretainedValue() as? [AnyObject]
        }

        return nil
    }

    func getLabel(of element: AnyObject) -> String? {
        let labelSel = NSSelectorFromString("label")
        return element.perform(labelSel)?.takeUnretainedValue() as? String
    }

    func getFrame(of element: AnyObject) -> CGRect? {
        let frameSel = NSSelectorFromString("frame")
        if let value = element.perform(frameSel)?.takeUnretainedValue() as? NSValue {
            return value.cgRectValue
        }
        return nil
    }
}
```

---

## AXElementFetcher for Real-Time Monitoring

For a VoiceOver-like experience that monitors accessibility changes:

```swift
extension ExternalAccessibilityClient {
    func createElementFetcher() -> AnyObject? {
        guard let fetcherClass = NSClassFromString("AXElementFetcher") else {
            return nil
        }

        // Complex initialization required:
        // initWithDelegate:fetchEvents:enableEventManagement:
        //     enableGrouping:shouldIncludeNonScannerElements:beginEnabled:

        let allocSel = NSSelectorFromString("alloc")
        guard let allocated = (fetcherClass as AnyObject)
            .perform(allocSel)?.takeUnretainedValue() else {
            return nil
        }

        // For full functionality, implement AXElementFetcherDelegate protocol
        // and use the complex initializer

        return allocated
    }
}
```

---

## Platforms Where This Works

### 1. macOS (Recommended for Development)
- AXUIElement is public API
- No special entitlements needed (just Accessibility permission)
- Use Accessibility Inspector as reference

```swift
// macOS - fully public
import ApplicationServices

func inspectApp(pid: pid_t) {
    let app = AXUIElementCreateApplication(pid)
    var children: CFTypeRef?
    AXUIElementCopyAttributeValue(app, kAXChildrenAttribute as CFString, &children)
    // Process children...
}
```

### 2. iOS Simulator
- Private frameworks available
- Some functionality works without entitlements
- Good for development testing

### 3. iOS Device (Jailbroken)
- Full access with proper entitlements
- Can sign with private entitlements
- Useful for research

### 4. iOS Device (App Store)
- **Cannot access other apps' accessibility**
- Only in-app accessibility via public UIAccessibility APIs
- Must use window access pattern instead

---

## Practical Approach: Mac Catalyst or Companion App

For a practical external client, consider:

### Option A: macOS Companion App
Build a macOS app that:
1. Connects to iOS Simulator via Accessibility Inspector protocol
2. Uses public macOS AXUIElement APIs
3. Communicates with iOS app via network/IPC

### Option B: Mac Catalyst App (Hybrid)
```swift
#if targetEnvironment(macCatalyst)
import ApplicationServices

func inspectAccessibility() {
    // Use public macOS APIs
    let systemElement = AXUIElementCreateSystemWide()
    // ...
}
#else
// iOS: Use UIAccessibility APIs
#endif
```

### Option C: Xcode Accessibility Inspector Integration
The Xcode Accessibility Inspector can already:
- Connect to iOS Simulator
- Show accessibility hierarchy
- Export accessibility data

Consider building tooling around its output.

---

## Key Private Functions Reference

| Function | Library | Purpose |
|----------|---------|---------|
| `_AXSSetAutomationEnabled` | libAccessibility | Enable automation mode |
| `_AXSAXInspectorSetEnabled` | libAccessibility | Enable inspector mode |
| `_AXSApplicationAccessibilitySetEnabled` | libAccessibility | Enable app accessibility |
| `_AXSAccessibilitySetEnabled` | libAccessibility | Master accessibility switch |

---

## Key AXRuntime Classes

| Class | Purpose |
|-------|---------|
| `AXUIElement` | Low-level element (wraps `__AXUIElement` C struct) |
| `AXElement` | High-level element with 120+ properties |
| `AXElementFetcher` | Monitors and fetches accessibility changes |
| `AXSimpleRuntimeManager` | Singleton runtime manager |
| `AXRemoteElement` | Cross-process element access |

---

## Bypassing Entitlements (Non-App Store Distribution)

Since you're not distributing through the App Store, there are several ways to get private entitlements working:

### Option 1: iOS Simulator (Easiest)
The Simulator has **relaxed entitlement enforcement**. Many private APIs work without special signing.

```bash
# Just build and run in Simulator
# No special steps needed
```

### Option 2: TrollStore (iOS 14.0 - 17.0)
TrollStore exploits a CoreTrust bug to install apps with arbitrary entitlements.

```bash
# 1. Install ldid
brew install ldid

# 2. Build your app

# 3. Sign with private entitlements
ldid -SPrivateAccessibilityEntitlements.plist YourApp.app/YourApp

# 4. Create IPA
cd build && zip -r YourApp.ipa Payload/

# 5. Install via TrollStore on device
```

**Supported versions**: iOS 14.0 beta 2 through 16.6.1, 16.7 RC, and 17.0
**NOT supported**: iOS 17.0.1+ or iOS 18.x (patched)

### Option 3: Jailbroken Device (Most Flexible)
Full access on PaleRa1n or Dopamine jailbreak.

```bash
# 1. Install AppSync Unified on jailbroken device

# 2. Sign your app
ldid -SPrivateAccessibilityEntitlements.plist YourApp.app/YourApp

# 3. Install
ideviceinstaller -i YourApp.ipa
# Or transfer via Filza
```

### Option 4: macOS (Recommended for External Client)
On macOS, `AXUIElement` is **public API**. No entitlements needed.

```swift
import ApplicationServices

// This is PUBLIC API on macOS
let app = AXUIElementCreateApplication(pid)
var children: CFTypeRef?
AXUIElementCopyAttributeValue(app, kAXChildrenAttribute as CFString, &children)
```

### Entitlements File
See `test-aoo/test-aoo/PrivateAccessibilityEntitlements.plist` for required entitlements:
- `com.apple.private.accessibility.send`
- `com.apple.private.accessibility.receive`
- `com.apple.private.accessibility.observe`
- `platform-application`
- `com.apple.private.security.no-sandbox`

### Build Script
Use `test-aoo/scripts/sign-with-private-entitlements.sh`:
```bash
./scripts/sign-with-private-entitlements.sh build/test-aoo.app
```

---

## Recommendations

1. **For in-app SwiftUI accessibility**: Use the window access pattern (no private APIs needed)

2. **For external inspection during development**:
   - **Quick test**: iOS Simulator (may work without entitlements)
   - **Full access**: TrollStore on iOS 14-17 or jailbroken device
   - **Production quality**: macOS companion app with public APIs

3. **For production external client**: Build a macOS app using public `AXUIElement` APIs

4. **For research/testing**: iOS Simulator + private framework exploration provides good insight

---

## Code Example: Complete External Client

See `test-aoo/test-aoo/ExternalAccessibilityClient.swift` for a working implementation that demonstrates these patterns.

---

## References

- macOS Accessibility API: [developer.apple.com/accessibility](https://developer.apple.com/documentation/applicationservices/axuielement_h)
- AXRuntime class dumps: See `swiftui-accessibility-insights.md`
- AccessibilitySnapshot patterns: `ASAccessibilityEnabler.m`
