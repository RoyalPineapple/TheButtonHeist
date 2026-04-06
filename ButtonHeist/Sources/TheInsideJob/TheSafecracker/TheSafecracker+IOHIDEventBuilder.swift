#if canImport(UIKit)
#if DEBUG
import UIKit

extension TheSafecracker {

    struct FingerTouchData {
        let touch: UITouch
        let location: CGPoint
        let phase: UITouch.Phase
    }

    /// Creates IOHIDEvent structures for touch injection (IOKit, dlsym).
    final class IOHIDEventBuilder {

        static func createEvent(for fingers: [FingerTouchData]) -> UnsafeMutableRawPointer? {
            let timestamp = mach_absolute_time()
            let anyTouching = fingers.contains { $0.phase != .ended && $0.phase != .cancelled }

            guard let handEvent = IOHIDEventCreateDigitizerEvent(
                kCFAllocatorDefault,
                timestamp,
                UInt32(kIOHIDDigitizerTransducerTypeHand),
                0,      // index
                0,      // identity
                anyTouching ? (kIOHIDDigitizerEventRange | kIOHIDDigitizerEventTouch) : (kIOHIDDigitizerEventRange | kIOHIDDigitizerEventTouch),
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
                let isTouching = (finger.phase == .began || finger.phase == .moved || finger.phase == .stationary)
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

            return handEvent
        }

        static func createEvent(for touches: [(touch: UITouch, location: CGPoint)], phase: UITouch.Phase) -> UnsafeMutableRawPointer? {
            let fingers = touches.map { FingerTouchData(touch: $0.touch, location: $0.location, phase: phase) }
            return createEvent(for: fingers)
        }
    }
}

// MARK: - IOHIDEvent Constants (file-private, same file as IOHIDEventBuilder)

private let kIOHIDDigitizerTransducerTypeHand: Int = 3
private let kIOHIDDigitizerEventRange: UInt32 = 1 << 0
private let kIOHIDDigitizerEventTouch: UInt32 = 1 << 1
private let kIOHIDDigitizerEventPosition: UInt32 = 1 << 2
private let kIOHIDEventFieldDigitizerIsDisplayIntegrated: Int = 0x00050001

// MARK: - Dynamic Loading of IOKit Functions

nonisolated(unsafe) private var _IOHIDEventCreateDigitizerEvent: @convention(c) (
    CFAllocator?,
    UInt64,
    UInt32,
    UInt32,
    UInt32,
    UInt32,
    UInt32,
    Float,
    Float,
    Float,
    Float,
    Float,
    Float,
    Bool,
    Bool,
    UInt32
) -> UnsafeMutableRawPointer? = { _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _ in nil }

nonisolated(unsafe) private var _IOHIDEventCreateDigitizerFingerEventWithQuality: @convention(c) (
    CFAllocator?,
    UInt64,
    UInt32,
    UInt32,
    UInt32,
    Float,
    Float,
    Float,
    Float,
    Float,
    Float,
    Float,
    Float,
    Float,
    Float,
    Bool,
    Bool,
    UInt32
) -> UnsafeMutableRawPointer? = { _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _ in nil }

nonisolated(unsafe) private var _IOHIDEventAppendEvent: @convention(c) (
    UnsafeMutableRawPointer,
    UnsafeMutableRawPointer,
    UInt32
) -> Void = { _, _, _ in }

nonisolated(unsafe) private var _IOHIDEventSetFloatValue: @convention(c) (
    UnsafeMutableRawPointer,
    UInt32,
    Float
) -> Void = { _, _, _ in }

nonisolated(unsafe) private var ioHIDFunctionsLoaded = false

private func loadIOHIDFunctions() {
    guard !ioHIDFunctionsLoaded else { return }
    ioHIDFunctionsLoaded = true

    guard let handle = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_NOW) else {
        insideJobLogger.error("Failed to load IOKit")
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

#endif
#endif
