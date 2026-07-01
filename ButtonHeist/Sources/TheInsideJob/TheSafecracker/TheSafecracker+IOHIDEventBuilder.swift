#if canImport(UIKit)
#if DEBUG
import UIKit

// This file bridges to IOKit's private HID event API. Raw SPI names, framework
// paths, dlsym, and typed C casts live in `ButtonHeistPrivateSPI`; the
// file-private `nonisolated(unsafe)` globals below only cache resolved function
// pointers written once on first use and read thereafter. Swift has no
// structured way to express "write-once, lazily-initialised C function pointer"
// for synchronous C entry points called from gesture hot paths. This unsafe
// storage is narrowly scoped to the IOKit bridge; do not introduce further
// `nonisolated(unsafe)` declarations elsewhere without a comparable
// justification.

extension TheSafecracker {

    struct HIDEvent {
        private let pointer: UnsafeMutableRawPointer

        fileprivate init(_ pointer: UnsafeMutableRawPointer) {
            self.pointer = pointer
        }

        func withUnsafePointer<Result>(_ body: (UnsafeMutableRawPointer) -> Result) -> Result {
            body(pointer)
        }
    }

    // MARK: - TouchEvent

    /// An assembled UIEvent ready to deliver to UIApplication.
    /// Can only be constructed from `[SyntheticTouch]`, keeping the HID finger
    /// data and touch array together behind this mechanical-input wrapper.
    ///
    /// `@MainActor` justification: wraps a UIEvent reference.
    @MainActor struct TouchEvent { // swiftlint:disable:this agent_main_actor_value_type
        let event: UIEvent

        /// Package touches into a UIEvent with matching IOHIDEvent data.
        init?(touches: [SyntheticTouch]) {
            guard let event: UIEvent = ObjCRuntime.get(.applicationTouchesEvent, from: UIApplication.shared) else {
                insideJobLogger.error("UIApplication doesn't respond to _touchesEvent")
                return nil
            }
            guard let clearTouches = ObjCRuntime.message(.eventClearTouches, to: event) else {
                insideJobLogger.error("UIEvent doesn't respond to _clearTouches")
                return nil
            }
            guard let addTouch = ObjCRuntime.message(.eventAddTouchForDelayedDelivery, to: event) else {
                insideJobLogger.error("UIEvent doesn't respond to _addTouch:forDelayedDelivery:")
                return nil
            }
            guard let hidEvent = SafecrackerIOHIDEventBuilder.createEvent(for: touches) else {
                insideJobLogger.error("Failed to create IOHIDEvent for synthetic touches")
                return nil
            }
            guard let setHIDEvent = ObjCRuntime.message(.eventSetHIDEvent, to: event) else {
                insideJobLogger.error("UIEvent doesn't respond to _setHIDEvent:")
                return nil
            }

            clearTouches.call()
            hidEvent.withUnsafePointer {
                setHIDEvent.call($0)
            }
            for syntheticTouch in touches {
                syntheticTouch.setHIDEvent(hidEvent)
                addTouch.send(syntheticTouch.touch, false)
            }

            self.event = event
        }

        /// Deliver to UIApplication.
        func send() {
            UIApplication.shared.sendEvent(event)
        }
    }
}

// MARK: - IOHIDEvent Construction

/// Creates IOHIDEvent structures for touch injection (IOKit, dlsym).
/// Private to keep raw HID construction behind `TheSafecracker.TouchEvent`.
@MainActor
private final class SafecrackerIOHIDEventBuilder {

    static func createEvent(for fingers: [TheSafecracker.SyntheticTouch]) -> TheSafecracker.HIDEvent? {
        let timestamp = mach_absolute_time()
        let anyTouching = fingers.contains { $0.phase != .ended && $0.phase != .cancelled }

        guard let handEvent = IOHIDEventCreateDigitizerEvent(
            kCFAllocatorDefault,
            timestamp,
            UInt32(kIOHIDDigitizerTransducerTypeHand),
            0,      // index
            0,      // identity
            kIOHIDDigitizerEventRange | kIOHIDDigitizerEventTouch,
            0,      // buttonMask
            0, 0,   // x, y (hand doesn't need position)
            0,      // z
            0, 0,   // tipPressure, barrelPressure
            0,      // twist
            anyTouching,
            anyTouching,
            0       // options
        ) else { return nil }

        IOHIDEventSetFloatValue(handEvent, UInt32(kIOHIDEventFieldDigitizerIsDisplayIntegrated), 1.0)

        for (index, finger) in fingers.enumerated() {
            let isTouching = finger.phase == .began || finger.phase == .moved || finger.phase == .stationary
            let eventMask: UInt32 = (finger.phase == .moved || finger.phase == .stationary)
                ? kIOHIDDigitizerEventPosition
                : (kIOHIDDigitizerEventRange | kIOHIDDigitizerEventTouch)

            let fingerEvent = IOHIDEventCreateDigitizerFingerEventWithQuality(
                kCFAllocatorDefault,
                timestamp,
                UInt32(index + 1),        // index (1-based position)
                UInt32(index + 2),        // identity (unique per finger: 2, 3, 4...)
                eventMask,
                Float(finger.location.x),
                Float(finger.location.y),
                0,                    // z
                isTouching ? 1.0 : 0, // tipPressure (1.0 while touching)
                0,                    // twist
                5.0,                  // majorRadius (matches KIF)
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

        return TheSafecracker.HIDEvent(handEvent)
    }
}

// MARK: - IOHIDEvent Constants (file-private, same file as SafecrackerIOHIDEventBuilder)

private let kIOHIDDigitizerTransducerTypeHand: Int = 3
private let kIOHIDDigitizerEventRange: UInt32 = 1 << 0
private let kIOHIDDigitizerEventTouch: UInt32 = 1 << 1
private let kIOHIDDigitizerEventPosition: UInt32 = 1 << 2
private let kIOHIDEventFieldDigitizerIsDisplayIntegrated: Int = 0x00050001

// MARK: - Dynamic Loading of IOKit Functions

nonisolated(unsafe) private var _IOHIDEventCreateDigitizerEvent:
    ButtonHeistPrivateSPI.IOHIDEventCreateDigitizerEventFunction = { _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _ in nil }

nonisolated(unsafe) private var _IOHIDEventCreateDigitizerFingerEventWithQuality:
    ButtonHeistPrivateSPI.IOHIDEventCreateDigitizerFingerEventWithQualityFunction = { _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _ in nil }

nonisolated(unsafe) private var _IOHIDEventAppendEvent:
    ButtonHeistPrivateSPI.IOHIDEventAppendEventFunction = { _, _, _ in }

nonisolated(unsafe) private var _IOHIDEventSetFloatValue:
    ButtonHeistPrivateSPI.IOHIDEventSetFloatValueFunction = { _, _, _ in }

nonisolated(unsafe) private var ioHIDFunctionsLoaded = false

private func loadIOHIDFunctions() {
    guard !ioHIDFunctionsLoaded else { return }
    ioHIDFunctionsLoaded = true

    guard let handle = ButtonHeistPrivateSPI.open(.ioKit) else {
        insideJobLogger.error("Failed to load IOKit")
        return
    }

    if let function = ButtonHeistPrivateSPI.function(.ioHIDEventCreateDigitizerEvent, in: handle) {
        _IOHIDEventCreateDigitizerEvent = function
    }

    if let function = ButtonHeistPrivateSPI.function(.ioHIDEventCreateDigitizerFingerEventWithQuality, in: handle) {
        _IOHIDEventCreateDigitizerFingerEventWithQuality = function
    }

    if let function = ButtonHeistPrivateSPI.function(.ioHIDEventAppendEvent, in: handle) {
        _IOHIDEventAppendEvent = function
    }

    if let function = ButtonHeistPrivateSPI.function(.ioHIDEventSetFloatValue, in: handle) {
        _IOHIDEventSetFloatValue = function
    }
}

// swiftlint:disable:next function_parameter_count
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

// swiftlint:disable:next function_parameter_count
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

#endif // DEBUG
#endif // canImport(UIKit)
