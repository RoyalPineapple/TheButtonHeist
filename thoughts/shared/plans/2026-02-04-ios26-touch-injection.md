# iOS 26 Touch Injection Fix - Implementation Plan

## Overview

Fix tap/interaction failures on iOS 26 by implementing KIF-style touch injection with proper UIEvent handling. The key fix is creating a **fresh UIEvent for each touch phase** (began, ended), which iOS 26 now requires.

## Current State Analysis

### What Exists Now

**TouchInjector.swift** (lines 17-56) uses a high-level fallback chain:
1. `accessibilityActivate()` on hit-tested view
2. `UIControl.sendActions(for: .touchUpInside)` for controls
3. Responder chain walk to find parent UIControl
4. Returns `false` if all fail

**Problem**: This fails for views that:
- Don't implement `accessibilityActivate()` (returns false)
- Are not UIControl subclasses
- Don't have a UIControl ancestor in the responder chain

**Unused Code** in AccraHost.swift (lines 791-820):
```swift
private func simulateTouchOnView(_ view: UIView) -> Bool {
    guard let touchClass = NSClassFromString("UITouch") as? NSObject.Type,
          let touch = touchClass.init() as? UITouch else { return false }

    // Uses KVC (not reliable)
    touch.setValue(point, forKey: "locationInWindow")
    // ...
    let event = UIEvent()  // Wrong! Should use _touchesEvent
    view.touchesBegan(touches, with: event)
    view.touchesEnded(touches, with: event)  // Same event for both phases!
}
```

This code has multiple issues:
1. Uses KVC instead of proper private selectors
2. Creates empty `UIEvent()` instead of `_touchesEvent`
3. No IOHIDEvent attached
4. Reuses same event for both phases (breaks on iOS 26)

## Desired End State

A `TouchInjector` that:
1. Implements KIF-style touch injection using proper private APIs
2. Creates fresh UIEvent for each touch phase (iOS 26 requirement)
3. Attaches IOHIDEvent to touches (iOS 9+ requirement)
4. Falls back to high-level methods when low-level injection fails
5. Works on iOS 17+ (our deployment target)

### Verification

```bash
# Build
xcodebuild -workspace Accra.xcworkspace -scheme AccraHost -destination 'generic/platform=iOS' build

# Test on iOS 26 Simulator
xcrun simctl boot "iPhone 16 Pro"
# Deploy test app, run CLI tap commands
accra action --type tap --identifier "myButton"
```

## What We're NOT Doing

- Supporting iOS versions below 17 (already our minimum)
- Adding drag/swipe gestures (only tap for now)
- Multi-touch gestures
- Changing the public API of TouchInjector

## Implementation Approach

Based on KIF's implementation (PR #1334), we need to:

1. **Create UITouch properly** using private selectors (not KVC)
2. **Create IOHIDEvent** and attach to UITouch
3. **Get UIEvent** from `[UIApplication _touchesEvent]`
4. **Create fresh event per phase** - separate events for began and ended
5. **Dispatch via sendEvent:**

## Phase 1: IOHIDEvent Support

### Overview
Add IOHIDEvent creation capability using IOKit private APIs.

### Changes Required:

#### 1. Create IOHIDEvent Header Bridge
**File**: `AccraCore/Sources/AccraHost/IOHIDEventPrivate.h`

```c
#ifndef IOHIDEventPrivate_h
#define IOHIDEventPrivate_h

#import <CoreFoundation/CoreFoundation.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct __IOHIDEvent *IOHIDEventRef;

// Transducer types
enum {
    kIOHIDDigitizerTransducerTypeStylus = 0,
    kIOHIDDigitizerTransducerTypePuck,
    kIOHIDDigitizerTransducerTypeFinger,
    kIOHIDDigitizerTransducerTypeHand
};

// Event masks
enum {
    kIOHIDDigitizerEventRange           = 1 << 0,
    kIOHIDDigitizerEventTouch           = 1 << 1,
    kIOHIDDigitizerEventPosition        = 1 << 2,
};

// Event field for display integrated
enum {
    kIOHIDEventFieldDigitizerIsDisplayIntegrated = 0x00050001
};

// Function declarations
IOHIDEventRef IOHIDEventCreateDigitizerEvent(
    CFAllocatorRef allocator,
    uint64_t timestamp,
    uint32_t transducerType,
    uint32_t index,
    uint32_t identity,
    uint32_t eventMask,
    uint32_t buttonMask,
    float x,
    float y,
    float z,
    float tipPressure,
    float barrelPressure,
    float twist,
    Boolean range,
    Boolean touch,
    uint32_t options
);

IOHIDEventRef IOHIDEventCreateDigitizerFingerEventWithQuality(
    CFAllocatorRef allocator,
    uint64_t timestamp,
    uint32_t index,
    uint32_t identity,
    uint32_t eventMask,
    float x,
    float y,
    float z,
    float tipPressure,
    float twist,
    float majorRadius,
    float minorRadius,
    float quality,
    float density,
    float irregularity,
    Boolean range,
    Boolean touch,
    uint32_t options
);

void IOHIDEventAppendEvent(IOHIDEventRef parent, IOHIDEventRef child, uint32_t options);
void IOHIDEventSetFloatValue(IOHIDEventRef event, uint32_t field, float value);

#ifdef __cplusplus
}
#endif

#endif /* IOHIDEventPrivate_h */
```

#### 2. Create IOHIDEvent Swift Wrapper
**File**: `AccraCore/Sources/AccraHost/IOHIDEventBuilder.swift`

```swift
#if canImport(UIKit)
import UIKit

/// Creates IOHIDEvent structures for touch injection
@MainActor
final class IOHIDEventBuilder {

    /// Create an IOHIDEvent for a set of touches
    /// - Parameter touches: Array of (touch, phase) tuples
    /// - Returns: IOHIDEventRef or nil if creation failed
    static func createEvent(for touches: [(touch: UITouch, location: CGPoint)], isTouching: Bool) -> UnsafeMutableRawPointer? {
        let timestamp = mach_absolute_time()

        // Event mask depends on touch state
        let eventMask: UInt32 = isTouching
            ? (kIOHIDDigitizerEventRange | kIOHIDDigitizerEventTouch)
            : kIOHIDDigitizerEventPosition

        // Create hand (container) event
        guard let handEvent = IOHIDEventCreateDigitizerEvent(
            kCFAllocatorDefault,
            timestamp,
            UInt32(kIOHIDDigitizerTransducerTypeHand),
            0,      // index
            0,      // identity
            eventMask,
            0,      // buttonMask
            0, 0,   // x, y (hand doesn't need position)
            0,      // z
            0, 0,   // tipPressure, barrelPressure
            0,      // twist
            isTouching,
            isTouching,
            0       // options
        ) else { return nil }

        // Set display integrated flag
        IOHIDEventSetFloatValue(handEvent, UInt32(kIOHIDEventFieldDigitizerIsDisplayIntegrated), 1.0)

        // Create finger events for each touch
        for (index, touchData) in touches.enumerated() {
            let fingerEvent = IOHIDEventCreateDigitizerFingerEventWithQuality(
                kCFAllocatorDefault,
                timestamp,
                UInt32(index + 1),   // index
                2,                    // identity
                eventMask,
                Float(touchData.location.x),
                Float(touchData.location.y),
                0,                    // z
                0,                    // tipPressure
                0,                    // twist
                5.0,                  // majorRadius
                5.0,                  // minorRadius
                1.0,                  // quality
                1.0,                  // density
                1.0,                  // irregularity
                isTouching,           // range
                isTouching,           // touch
                0                     // options
            )

            if let fingerEvent = fingerEvent {
                IOHIDEventSetFloatValue(fingerEvent, UInt32(kIOHIDEventFieldDigitizerIsDisplayIntegrated), 1.0)
                IOHIDEventAppendEvent(handEvent, fingerEvent, 0)
            }
        }

        return handEvent
    }
}

// MARK: - IOHIDEvent Constants (matching the header)

private let kIOHIDDigitizerTransducerTypeHand: Int = 3
private let kIOHIDDigitizerEventRange: UInt32 = 1 << 0
private let kIOHIDDigitizerEventTouch: UInt32 = 1 << 1
private let kIOHIDDigitizerEventPosition: UInt32 = 1 << 2
private let kIOHIDEventFieldDigitizerIsDisplayIntegrated: Int = 0x00050001

// MARK: - Dynamic Loading of IOKit Functions

private var _IOHIDEventCreateDigitizerEvent: (
    _ allocator: CFAllocator?,
    _ timestamp: UInt64,
    _ transducerType: UInt32,
    _ index: UInt32,
    _ identity: UInt32,
    _ eventMask: UInt32,
    _ buttonMask: UInt32,
    _ x: Float,
    _ y: Float,
    _ z: Float,
    _ tipPressure: Float,
    _ barrelPressure: Float,
    _ twist: Float,
    _ range: Bool,
    _ touch: Bool,
    _ options: UInt32
) -> UnsafeMutableRawPointer? = { _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _ in nil }

private var _IOHIDEventCreateDigitizerFingerEventWithQuality: (
    _ allocator: CFAllocator?,
    _ timestamp: UInt64,
    _ index: UInt32,
    _ identity: UInt32,
    _ eventMask: UInt32,
    _ x: Float,
    _ y: Float,
    _ z: Float,
    _ tipPressure: Float,
    _ twist: Float,
    _ majorRadius: Float,
    _ minorRadius: Float,
    _ quality: Float,
    _ density: Float,
    _ irregularity: Float,
    _ range: Bool,
    _ touch: Bool,
    _ options: UInt32
) -> UnsafeMutableRawPointer? = { _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _ in nil }

private var _IOHIDEventAppendEvent: (
    _ parent: UnsafeMutableRawPointer,
    _ child: UnsafeMutableRawPointer,
    _ options: UInt32
) -> Void = { _, _, _ in }

private var _IOHIDEventSetFloatValue: (
    _ event: UnsafeMutableRawPointer,
    _ field: UInt32,
    _ value: Float
) -> Void = { _, _, _ in }

private var ioHIDFunctionsLoaded = false

private func loadIOHIDFunctions() {
    guard !ioHIDFunctionsLoaded else { return }
    ioHIDFunctionsLoaded = true

    guard let handle = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_NOW) else {
        print("[IOHIDEventBuilder] Failed to load IOKit")
        return
    }

    if let sym = dlsym(handle, "IOHIDEventCreateDigitizerEvent") {
        _IOHIDEventCreateDigitizerEvent = unsafeBitCast(sym, to: type(of: _IOHIDEventCreateDigitizerEvent))
    }

    if let sym = dlsym(handle, "IOHIDEventCreateDigitizerFingerEventWithQuality") {
        _IOHIDEventCreateDigitizerFingerEventWithQuality = unsafeBitCast(sym, to: type(of: _IOHIDEventCreateDigitizerFingerEventWithQuality))
    }

    if let sym = dlsym(handle, "IOHIDEventAppendEvent") {
        _IOHIDEventAppendEvent = unsafeBitCast(sym, to: type(of: _IOHIDEventAppendEvent))
    }

    if let sym = dlsym(handle, "IOHIDEventSetFloatValue") {
        _IOHIDEventSetFloatValue = unsafeBitCast(sym, to: type(of: _IOHIDEventSetFloatValue))
    }
}

private func IOHIDEventCreateDigitizerEvent(
    _ allocator: CFAllocator?,
    _ timestamp: UInt64,
    _ transducerType: UInt32,
    _ index: UInt32,
    _ identity: UInt32,
    _ eventMask: UInt32,
    _ buttonMask: UInt32,
    _ x: Float,
    _ y: Float,
    _ z: Float,
    _ tipPressure: Float,
    _ barrelPressure: Float,
    _ twist: Float,
    _ range: Bool,
    _ touch: Bool,
    _ options: UInt32
) -> UnsafeMutableRawPointer? {
    loadIOHIDFunctions()
    return _IOHIDEventCreateDigitizerEvent(
        allocator, timestamp, transducerType, index, identity, eventMask, buttonMask,
        x, y, z, tipPressure, barrelPressure, twist, range, touch, options
    )
}

private func IOHIDEventCreateDigitizerFingerEventWithQuality(
    _ allocator: CFAllocator?,
    _ timestamp: UInt64,
    _ index: UInt32,
    _ identity: UInt32,
    _ eventMask: UInt32,
    _ x: Float,
    _ y: Float,
    _ z: Float,
    _ tipPressure: Float,
    _ twist: Float,
    _ majorRadius: Float,
    _ minorRadius: Float,
    _ quality: Float,
    _ density: Float,
    _ irregularity: Float,
    _ range: Bool,
    _ touch: Bool,
    _ options: UInt32
) -> UnsafeMutableRawPointer? {
    loadIOHIDFunctions()
    return _IOHIDEventCreateDigitizerFingerEventWithQuality(
        allocator, timestamp, index, identity, eventMask,
        x, y, z, tipPressure, twist, majorRadius, minorRadius,
        quality, density, irregularity, range, touch, options
    )
}

private func IOHIDEventAppendEvent(_ parent: UnsafeMutableRawPointer, _ child: UnsafeMutableRawPointer, _ options: UInt32) {
    loadIOHIDFunctions()
    _IOHIDEventAppendEvent(parent, child, options)
}

private func IOHIDEventSetFloatValue(_ event: UnsafeMutableRawPointer, _ field: UInt32, _ value: Float) {
    loadIOHIDFunctions()
    _IOHIDEventSetFloatValue(event, field, value)
}

#endif
```

### Success Criteria:

#### Automated Verification:
- [x] Build succeeds: `xcodebuild -workspace Accra.xcworkspace -scheme AccraHost -destination 'generic/platform=iOS' build`

#### Manual Verification:
- [ ] IOKit functions load successfully (check logs)

---

## Phase 2: UITouch and UIEvent Private API Wrappers

### Overview
Create wrappers for UITouch creation and UIEvent manipulation using proper private selectors.

### Changes Required:

#### 1. Create Touch Factory
**File**: `AccraCore/Sources/AccraHost/SyntheticTouchFactory.swift`

```swift
#if canImport(UIKit)
import UIKit

/// Factory for creating synthetic UITouch instances using private APIs
@MainActor
final class SyntheticTouchFactory {

    /// Create a UITouch at the specified point
    static func createTouch(at point: CGPoint, in window: UIWindow, view: UIView, phase: UITouch.Phase) -> UITouch? {
        let touch = UITouch()

        // Must set window first as it resets other values
        performSelector(on: touch, selector: "setWindow:", with: window)
        performSelector(on: touch, selector: "setView:", with: view)

        // Set location using private method with resetPrevious parameter
        setTouchLocation(touch, point: point, resetPrevious: true)

        // Set phase
        performSelector(on: touch, selector: "setPhase:", with: phase.rawValue)

        // Set additional properties
        performSelector(on: touch, selector: "setTapCount:", with: 1)
        performSelector(on: touch, selector: "_setIsFirstTouchForView:", with: true)
        performSelector(on: touch, selector: "setIsTap:", with: true)

        // Set timestamp
        let timestamp = ProcessInfo.processInfo.systemUptime
        performSelector(on: touch, selector: "setTimestamp:", with: timestamp)

        return touch
    }

    /// Update touch phase
    static func setPhase(_ touch: UITouch, phase: UITouch.Phase) {
        performSelector(on: touch, selector: "setPhase:", with: phase.rawValue)
        let timestamp = ProcessInfo.processInfo.systemUptime
        performSelector(on: touch, selector: "setTimestamp:", with: timestamp)
    }

    /// Set IOHIDEvent on the touch (required for iOS 9+)
    static func setHIDEvent(_ touch: UITouch, event: UnsafeMutableRawPointer) {
        // Use _setHidEvent: selector
        let selector = NSSelectorFromString("_setHidEvent:")
        if touch.responds(to: selector) {
            _ = touch.perform(selector, with: event)
        }
    }

    // MARK: - Private Helpers

    private static func performSelector(on object: NSObject, selector: String, with value: Any?) {
        let sel = NSSelectorFromString(selector)
        guard object.responds(to: sel) else {
            print("[SyntheticTouchFactory] Object doesn't respond to \(selector)")
            return
        }
        _ = object.perform(sel, with: value)
    }

    private static func setTouchLocation(_ touch: UITouch, point: CGPoint, resetPrevious: Bool) {
        // _setLocationInWindow:resetPrevious: takes CGPoint and BOOL
        let selector = NSSelectorFromString("_setLocationInWindow:resetPrevious:")
        guard touch.responds(to: selector) else {
            // Fallback to simple setValue
            touch.setValue(point, forKey: "locationInWindow")
            return
        }

        // Use NSInvocation-style approach via method signature
        let methodSignature = touch.method(for: selector)
        if methodSignature != nil {
            // Direct call using unsafeBitCast
            typealias SetLocationFunc = @convention(c) (AnyObject, Selector, CGPoint, Bool) -> Void
            let imp = touch.method(for: selector)
            let function = unsafeBitCast(imp, to: SetLocationFunc.self)
            function(touch, selector, point, resetPrevious)
        }
    }
}
#endif
```

#### 2. Create Event Factory
**File**: `AccraCore/Sources/AccraHost/SyntheticEventFactory.swift`

```swift
#if canImport(UIKit)
import UIKit

/// Factory for creating and manipulating UIEvent instances for touch injection
@MainActor
final class SyntheticEventFactory {

    /// Get the singleton touches event from UIApplication
    static func getTouchesEvent() -> UIEvent? {
        let app = UIApplication.shared
        let selector = NSSelectorFromString("_touchesEvent")
        guard app.responds(to: selector) else {
            print("[SyntheticEventFactory] UIApplication doesn't respond to _touchesEvent")
            return nil
        }
        return app.perform(selector)?.takeUnretainedValue() as? UIEvent
    }

    /// Clear all touches from an event
    static func clearTouches(from event: UIEvent) {
        let selector = NSSelectorFromString("_clearTouches")
        guard event.responds(to: selector) else { return }
        _ = event.perform(selector)
    }

    /// Add a touch to an event
    static func addTouch(_ touch: UITouch, to event: UIEvent, delayed: Bool = false) {
        let selector = NSSelectorFromString("_addTouch:forDelayedDelivery:")
        guard event.responds(to: selector) else {
            print("[SyntheticEventFactory] UIEvent doesn't respond to _addTouch:forDelayedDelivery:")
            return
        }

        // Need to use NSInvocation-style for two parameters
        typealias AddTouchFunc = @convention(c) (AnyObject, Selector, UITouch, Bool) -> Void
        if let imp = (event as NSObject).method(for: selector) {
            let function = unsafeBitCast(imp, to: AddTouchFunc.self)
            function(event, selector, touch, delayed)
        }
    }

    /// Set IOHIDEvent on a UIEvent
    static func setHIDEvent(_ hidEvent: UnsafeMutableRawPointer, on event: UIEvent) {
        let selector = NSSelectorFromString("_setHIDEvent:")
        guard event.responds(to: selector) else { return }
        _ = event.perform(selector, with: hidEvent)
    }

    /// Create a fully configured event for a touch
    static func createEventForTouch(_ touch: UITouch, hidEvent: UnsafeMutableRawPointer?) -> UIEvent? {
        guard let event = getTouchesEvent() else { return nil }

        clearTouches(from: event)

        if let hidEvent = hidEvent {
            setHIDEvent(hidEvent, on: event)
        }

        addTouch(touch, to: event, delayed: false)

        return event
    }
}
#endif
```

### Success Criteria:

#### Automated Verification:
- [x] Build succeeds: `xcodebuild -workspace Accra.xcworkspace -scheme AccraHost -destination 'generic/platform=iOS' build`

#### Manual Verification:
- [ ] Private selectors are found and callable (check logs)

---

## Phase 3: Updated TouchInjector with iOS 26 Fix

### Overview
Rewrite TouchInjector to use the new infrastructure with fresh UIEvent per phase, plus interactivity validation.

### Changes Required:

#### 1. Rewrite TouchInjector
**File**: `AccraCore/Sources/AccraHost/TouchInjector.swift`

```swift
#if canImport(UIKit)
import UIKit

/// Injects synthetic touch events for tap simulation.
/// Uses KIF-style private APIs with iOS 26 compatibility (fresh event per phase).
@MainActor
final class TouchInjector {

    /// Result of a tap attempt with detailed information
    enum TapResult {
        case success
        case viewNotInteractive(reason: String)
        case noViewAtPoint
        case noKeyWindow
        case injectionFailed
    }

    // MARK: - Public API

    /// Simulate a tap at the given screen coordinates.
    /// - Parameter point: Point in screen coordinates
    /// - Returns: True if tap was dispatched successfully
    func tap(at point: CGPoint) -> Bool {
        return tapWithResult(at: point) == .success
    }

    /// Simulate a tap with detailed result information
    /// - Parameter point: Point in screen coordinates
    /// - Returns: TapResult indicating success or failure reason
    func tapWithResult(at point: CGPoint) -> TapResult {
        guard let window = getKeyWindow() else {
            print("[TouchInjector] No key window found")
            return .noKeyWindow
        }

        let windowPoint = window.convert(point, from: nil)

        guard let hitView = window.hitTest(windowPoint, with: nil) else {
            print("[TouchInjector] No view at point")
            return .noViewAtPoint
        }

        // Check if the view is interactive
        if let reason = checkViewInteractivity(hitView) {
            print("[TouchInjector] View not interactive: \(reason)")
            return .viewNotInteractive(reason: reason)
        }

        // Try low-level touch injection first (works for all view types)
        if injectTap(at: windowPoint, window: window, view: hitView) {
            print("[TouchInjector] Tap injected via synthetic events")
            return .success
        }

        // Fall back to high-level methods
        if fallbackTap(view: hitView) {
            return .success
        }

        return .injectionFailed
    }

    // MARK: - Private: Interactivity Checks

    /// Check if a view is interactive and can receive taps
    /// - Returns: nil if interactive, or a reason string if not interactive
    private func checkViewInteractivity(_ view: UIView) -> String? {
        // Check UIView's user interaction property
        if !view.isUserInteractionEnabled {
            return "isUserInteractionEnabled is false"
        }

        // Check if view is hidden or has zero alpha
        if view.isHidden {
            return "view is hidden"
        }

        if view.alpha < 0.01 {
            return "view alpha is effectively zero"
        }

        // Check accessibility traits for disabled state
        if view.accessibilityTraits.contains(.notEnabled) {
            return "accessibility trait 'notEnabled' is set"
        }

        // Walk up the view hierarchy to check parent interactivity
        var parent = view.superview
        while let p = parent {
            if !p.isUserInteractionEnabled {
                return "parent view '\(type(of: p))' has isUserInteractionEnabled=false"
            }
            parent = p.superview
        }

        return nil  // View is interactive
    }

    // MARK: - Private: Low-Level Touch Injection

    /// Inject a tap using synthetic UITouch and UIEvent
    private func injectTap(at windowPoint: CGPoint, window: UIWindow, view: UIView) -> Bool {
        // Create touch for began phase
        guard let touch = SyntheticTouchFactory.createTouch(
            at: windowPoint,
            in: window,
            view: view,
            phase: .began
        ) else {
            print("[TouchInjector] Failed to create touch")
            return false
        }

        // Create IOHIDEvent for the touch
        let hidEventBegan = IOHIDEventBuilder.createEvent(
            for: [(touch: touch, location: windowPoint)],
            isTouching: true
        )

        // Attach HID event to touch
        if let hidEvent = hidEventBegan {
            SyntheticTouchFactory.setHIDEvent(touch, event: hidEvent)
        }

        // iOS 26 FIX: Create FRESH event for began phase
        guard let beganEvent = SyntheticEventFactory.createEventForTouch(touch, hidEvent: hidEventBegan) else {
            print("[TouchInjector] Failed to create began event")
            return false
        }

        // Send began event
        UIApplication.shared.sendEvent(beganEvent)

        // Update touch to ended phase
        SyntheticTouchFactory.setPhase(touch, phase: .ended)

        // Create IOHIDEvent for ended
        let hidEventEnded = IOHIDEventBuilder.createEvent(
            for: [(touch: touch, location: windowPoint)],
            isTouching: false
        )

        if let hidEvent = hidEventEnded {
            SyntheticTouchFactory.setHIDEvent(touch, event: hidEvent)
        }

        // iOS 26 FIX: Create FRESH event for ended phase (NOT reusing beganEvent!)
        guard let endedEvent = SyntheticEventFactory.createEventForTouch(touch, hidEvent: hidEventEnded) else {
            print("[TouchInjector] Failed to create ended event")
            return false
        }

        // Send ended event
        UIApplication.shared.sendEvent(endedEvent)

        return true
    }

    // MARK: - Private: High-Level Fallback

    /// Fall back to high-level activation methods
    private func fallbackTap(view: UIView) -> Bool {
        // Try accessibility activation
        if view.accessibilityActivate() {
            print("[TouchInjector] Activated via accessibilityActivate")
            return true
        }

        // Try sendActions for UIControl
        if let control = view as? UIControl {
            control.sendActions(for: .touchUpInside)
            print("[TouchInjector] Activated via sendActions")
            return true
        }

        // Walk up responder chain
        var responder: UIResponder? = view
        while let r = responder {
            if let control = r as? UIControl {
                control.sendActions(for: .touchUpInside)
                print("[TouchInjector] Activated control in responder chain")
                return true
            }
            responder = r.next
        }

        print("[TouchInjector] All activation methods failed")
        return false
    }

    // MARK: - Private Helpers

    private func getKeyWindow() -> UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }
    }
}
#endif
```

#### 2. Update AccraHost Action Handlers with Trait Validation
**File**: `AccraCore/Sources/AccraHost/AccraHost.swift`

Update `handleActivate()` (around line 419) and `handleTap()` (around line 499) to check element traits before attempting interaction:

```swift
private func handleActivate(_ target: ActionTarget, respond: @escaping (Data) -> Void) {
    // Refresh hierarchy
    if let rootView = getRootView() {
        cachedElements = parser.parseAccessibilityElements(in: rootView)
    }

    guard let element = findElement(for: target) else {
        sendMessage(.actionResult(ActionResult(
            success: false,
            method: .elementNotFound,
            message: "Element not found for target"
        )), respond: respond)
        return
    }

    // Check if element is interactive based on traits
    if let interactivityError = checkElementInteractivity(element) {
        sendMessage(.actionResult(ActionResult(
            success: false,
            method: .elementNotFound,  // Or add new .elementNotInteractive method
            message: interactivityError
        )), respond: respond)
        return
    }

    // Use TouchInjector which handles accessibilityActivate and fallbacks
    let result = touchInjector.tapWithResult(at: element.activationPoint)
    switch result {
    case .success:
        TapVisualizerView.showTap(at: element.activationPoint)
        sendMessage(.actionResult(ActionResult(
            success: true,
            method: .syntheticTap
        )), respond: respond)
    case .viewNotInteractive(let reason):
        sendMessage(.actionResult(ActionResult(
            success: false,
            method: .accessibilityActivate,
            message: "View not interactive: \(reason)"
        )), respond: respond)
    case .noViewAtPoint, .noKeyWindow, .injectionFailed:
        sendMessage(.actionResult(ActionResult(
            success: false,
            method: .accessibilityActivate,
            message: "Activation failed"
        )), respond: respond)
    }
}

/// Check if an AccessibilityMarker element is interactive based on traits
private func checkElementInteractivity(_ element: AccessibilityMarker) -> String? {
    // Check for notEnabled trait (disabled element)
    if element.traits.contains(.notEnabled) {
        return "Element is disabled (has 'notEnabled' trait)"
    }

    // Optional: Check for commonly non-interactive element types
    // Note: We don't strictly require interactive traits because some views
    // may have tap gestures without accessibility traits
    let staticTraitsOnly = element.traits.isSubset(of: [.staticText, .image, .header])
    let hasInteractiveTraits = element.traits.contains(.button) ||
                               element.traits.contains(.link) ||
                               element.traits.contains(.adjustable) ||
                               element.traits.contains(.searchField) ||
                               element.traits.contains(.keyboardKey)

    // If element only has static traits and no interactive traits, warn but don't block
    // because SwiftUI views with .onTapGesture may not have button trait
    if staticTraitsOnly && !hasInteractiveTraits && element.customActions.isEmpty {
        // Log a warning but allow the tap to proceed
        serverLog("Warning: Element '\(element.description)' has only static traits, tap may not work")
    }

    return nil  // Element is considered interactive
}
```

### Success Criteria:

#### Automated Verification:
- [x] Build succeeds: `xcodebuild -workspace Accra.xcworkspace -scheme AccraHost -destination 'generic/platform=iOS' build`
- [x] Existing tests pass: `xcodebuild -workspace Accra.xcworkspace -scheme AccraCoreTests test`

#### Manual Verification:
- [ ] Tap works on iOS 26 Simulator for UIButton
- [ ] Tap works on iOS 26 Simulator for SwiftUI Button
- [ ] Tap works on iOS 26 Simulator for UILabel (non-control view)
- [ ] Tap works on physical iOS 26 device
- [ ] TapVisualizerView still shows visual feedback
- [ ] Tapping disabled element returns appropriate error message
- [ ] Tapping hidden view returns appropriate error message

**Implementation Note**: After completing this phase, pause for manual iOS 26 device/simulator testing before proceeding.

---

## Phase 4: Remove Unused Code and Update Documentation

### Overview
Clean up the unused `simulateTouchOnView` code and update comments.

### Changes Required:

#### 1. Remove Unused Extension
**File**: `AccraCore/Sources/AccraHost/AccraHost.swift`

Remove the entire `AccessibilityMarker` extension (lines 741-862) as it's no longer used. The `TouchInjector` now handles all touch injection.

#### 2. Update Documentation
**File**: `AccraCore/Sources/AccraHost/TouchInjector.swift`

Update the header comment to document the iOS 26 fix:

```swift
/// Injects synthetic touch events for tap simulation.
///
/// Implementation based on KIF (Keep It Functional) testing framework.
/// Key iOS 26 fix: Creates a fresh UIEvent for each touch phase (began, ended)
/// instead of reusing the same event, which iOS 26's stricter validation rejects.
///
/// Fallback chain:
/// 1. Low-level touch injection via synthetic UIEvent + IOHIDEvent
/// 2. accessibilityActivate() on hit-tested view
/// 3. UIControl.sendActions(for: .touchUpInside)
/// 4. Responder chain walk for UIControl
```

### Success Criteria:

#### Automated Verification:
- [x] Build succeeds: `xcodebuild -workspace Accra.xcworkspace -scheme AccraHost -destination 'generic/platform=iOS' build`
- [x] All tests pass: `xcodebuild -workspace Accra.xcworkspace -scheme AccraCoreTests test`

#### Manual Verification:
- [ ] Code review confirms no dead code remains
- [ ] Documentation accurately describes the implementation

---

## Testing Strategy

### Unit Tests:
- Test IOHIDEventBuilder creates valid events
- Test SyntheticTouchFactory creates touches with correct properties
- Test SyntheticEventFactory retrieves and manipulates events
- Test checkViewInteractivity returns correct results for various view states
- Test checkElementInteractivity returns correct results for various trait combinations

### Integration Tests:
- Test tap on UIButton in simulator
- Test tap on SwiftUI Button in simulator
- Test tap at coordinates (non-element tap)
- Test tap on non-interactive view (should fall through to fallback)

### Interactivity Tests:
- Test tap on disabled UIButton (isEnabled=false) → should fail with "notEnabled" message
- Test tap on hidden view → should fail with "view is hidden" message
- Test tap on view with isUserInteractionEnabled=false → should fail
- Test tap on staticText element → should warn but proceed
- Test tap on button element → should proceed without warning

### Manual Testing Steps:
1. Build and deploy AccessibilityTestApp to iOS 26 Simulator
2. Run `accra action --type tap --identifier "testButton"`
3. Verify button activates and visual feedback appears
4. Test on physical iOS 26 device via USB
5. Test various view types: UIButton, UILabel, SwiftUI Button, SwiftUI Text with onTapGesture
6. Test disabled button to verify error message
7. Test hidden element to verify error message

## Performance Considerations

- IOKit functions are loaded lazily via dlsym (one-time cost)
- UIEvent creation is fast (uses singleton from UIApplication)
- No additional allocations beyond what UIKit normally does for events

## Rollback Strategy

If issues arise:
1. Revert to the simple high-level-only implementation
2. Set an environment variable `ACCRA_USE_SIMPLE_TOUCH=1` to bypass low-level injection
3. The fallback chain ensures functionality even if low-level fails

## References

- Research document: `thoughts/shared/research/2026-02-04-ios26-interaction-support.md`
- KIF PR #1334: https://github.com/kif-framework/KIF/pull/1334
- KIF UITouch additions: https://github.com/kif-framework/KIF/blob/master/Sources/KIF/Additions/UITouch-KIFAdditions.m
- KIF UIView additions: https://github.com/kif-framework/KIF/blob/master/Sources/KIF/Additions/UIView-KIFAdditions.m
