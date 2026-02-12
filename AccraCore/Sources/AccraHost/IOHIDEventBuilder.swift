#if canImport(UIKit)
import UIKit

/// Creates IOHIDEvent structures for touch injection.
/// Uses dynamic loading to access IOKit private APIs.
@MainActor
final class IOHIDEventBuilder {

    /// Create an IOHIDEvent for a set of touches
    /// - Parameters:
    ///   - touches: Array of (touch, location) tuples
    ///   - isTouching: True for began phase, false for ended phase
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

// MARK: - IOHIDEvent Constants

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
