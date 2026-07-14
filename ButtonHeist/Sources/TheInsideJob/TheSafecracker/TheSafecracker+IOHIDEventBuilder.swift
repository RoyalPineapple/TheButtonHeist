#if canImport(UIKit)
#if DEBUG
import UIKit

// This file bridges to IOKit's private HID event API. Raw SPI names, framework
// paths, dlsym, and typed C casts live in `ButtonHeistPrivateSPI`. The immutable
// function table below is loaded once on the main actor before touch assembly.

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

    private static let functions = SafecrackerIOHIDFunctions.load()

    static func createEvent(for fingers: [TheSafecracker.SyntheticTouch]) -> TheSafecracker.HIDEvent? {
        guard let functions else { return nil }
        let timestamp = mach_absolute_time()
        let anyTouching = fingers.contains { $0.phase != .ended && $0.phase != .cancelled }

        guard let handEvent = functions.createDigitizerEvent(
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

        functions.setFloatValue(handEvent, UInt32(kIOHIDEventFieldDigitizerIsDisplayIntegrated), 1.0)

        for (index, finger) in fingers.enumerated() {
            let isTouching = finger.phase == .began || finger.phase == .moved || finger.phase == .stationary
            let eventMask: UInt32 = (finger.phase == .moved || finger.phase == .stationary)
                ? kIOHIDDigitizerEventPosition
                : (kIOHIDDigitizerEventRange | kIOHIDDigitizerEventTouch)

            let fingerEvent = functions.createDigitizerFingerEventWithQuality(
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
                functions.setFloatValue(fingerEvent, UInt32(kIOHIDEventFieldDigitizerIsDisplayIntegrated), 1.0)
                functions.appendEvent(handEvent, fingerEvent, 0)
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

@MainActor
private final class SafecrackerIOHIDFunctions {
    let createDigitizerEvent: ButtonHeistPrivateSPI.IOHIDEventCreateDigitizerEventFunction
    let createDigitizerFingerEventWithQuality:
        ButtonHeistPrivateSPI.IOHIDEventCreateDigitizerFingerEventWithQualityFunction
    let appendEvent: ButtonHeistPrivateSPI.IOHIDEventAppendEventFunction
    let setFloatValue: ButtonHeistPrivateSPI.IOHIDEventSetFloatValueFunction

    private let libraryHandle: ButtonHeistPrivateSPI.LibraryHandle

    private init(
        libraryHandle: ButtonHeistPrivateSPI.LibraryHandle,
        createDigitizerEvent: @escaping ButtonHeistPrivateSPI.IOHIDEventCreateDigitizerEventFunction,
        createDigitizerFingerEventWithQuality:
            @escaping ButtonHeistPrivateSPI.IOHIDEventCreateDigitizerFingerEventWithQualityFunction,
        appendEvent: @escaping ButtonHeistPrivateSPI.IOHIDEventAppendEventFunction,
        setFloatValue: @escaping ButtonHeistPrivateSPI.IOHIDEventSetFloatValueFunction
    ) {
        self.libraryHandle = libraryHandle
        self.createDigitizerEvent = createDigitizerEvent
        self.createDigitizerFingerEventWithQuality = createDigitizerFingerEventWithQuality
        self.appendEvent = appendEvent
        self.setFloatValue = setFloatValue
    }

    static func load() -> SafecrackerIOHIDFunctions? {
        guard let handle = ButtonHeistPrivateSPI.open(.ioKit) else {
            insideJobLogger.error("Failed to load IOKit")
            return nil
        }
        guard let createDigitizerEvent = ButtonHeistPrivateSPI.function(
            .ioHIDEventCreateDigitizerEvent,
            in: handle
        ), let createDigitizerFingerEventWithQuality = ButtonHeistPrivateSPI.function(
            .ioHIDEventCreateDigitizerFingerEventWithQuality,
            in: handle
        ), let appendEvent = ButtonHeistPrivateSPI.function(
            .ioHIDEventAppendEvent,
            in: handle
        ), let setFloatValue = ButtonHeistPrivateSPI.function(
            .ioHIDEventSetFloatValue,
            in: handle
        ) else {
            insideJobLogger.error("Failed to resolve required IOKit HID functions")
            return nil
        }
        return SafecrackerIOHIDFunctions(
            libraryHandle: handle,
            createDigitizerEvent: createDigitizerEvent,
            createDigitizerFingerEventWithQuality: createDigitizerFingerEventWithQuality,
            appendEvent: appendEvent,
            setFloatValue: setFloatValue
        )
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
