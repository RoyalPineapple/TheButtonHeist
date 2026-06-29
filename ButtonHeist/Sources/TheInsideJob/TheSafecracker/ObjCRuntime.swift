#if canImport(UIKit)
#if DEBUG
import UIKit

/// Type-safe wrappers for ObjC runtime dispatch to private UIKit APIs.
///
/// Runtime selectors are modeled as typed method values. Each method carries a
/// phantom argument signature, so call sites can only invoke the method with the
/// Swift shape it was declared to accept. Raw Objective-C `id` dispatch,
/// `perform`, and IMP casting stay isolated in `RawObjCMessageBridge`.
enum ObjCRuntime {

    enum NoArguments {}
    enum IntArgument {}
    enum BoolArgument {}
    enum DoubleArgument {}
    enum PointerArgument {}
    enum PointBoolArguments {}

    struct ObjectArgument<Argument: NSObject> {}
    struct ObjectBoolArguments<Argument: NSObject> {}
    struct ObjectReturningBoolArgument<Argument: NSObject> {}
    struct PointRadiusArguments<Result: NSObject> {}

    struct ClassName: Equatable, CustomStringConvertible {
        let rawValue: String

        fileprivate init(_ rawValue: String) {
            self.rawValue = rawValue
        }

        var description: String { rawValue }
    }

    struct ObjectMethod<Arguments>: CustomStringConvertible {
        let rawValue: String
        fileprivate let selector: Selector

        fileprivate init(_ rawValue: String) {
            self.rawValue = rawValue
            selector = NSSelectorFromString(rawValue)
        }

        fileprivate init(_ selector: Selector) {
            self.rawValue = NSStringFromSelector(selector)
            self.selector = selector
        }

        var description: String { rawValue }
    }

    struct ClassMethod<Arguments>: CustomStringConvertible {
        let rawValue: String
        fileprivate let selector: Selector

        fileprivate init(_ rawValue: String) {
            self.rawValue = rawValue
            selector = NSSelectorFromString(rawValue)
        }

        var description: String { rawValue }
    }

    /// A verified object + typed selector pair. Created by `message(_:to:)`.
    struct Message<Target: NSObject, Arguments> {
        let target: Target
        let method: ObjectMethod<Arguments>
        private let bridge: RawObjCMessageBridge

        fileprivate init?(target: Target, method: ObjectMethod<Arguments>) {
            guard let bridge = RawObjCMessageBridge(target: target, selector: method.selector) else {
                return nil
            }
            self.target = target
            self.method = method
            self.bridge = bridge
        }
    }

    /// A verified class object + typed selector pair. Created by
    /// `classMessage(_:on:)`.
    struct ClassMessage<Arguments> {
        let method: ClassMethod<Arguments>
        private let bridge: RawObjCMessageBridge

        fileprivate init?(targetClass: AnyClass, method: ClassMethod<Arguments>) {
            guard let bridge = RawObjCMessageBridge(targetClass: targetClass, selector: method.selector) else {
                return nil
            }
            self.method = method
            self.bridge = bridge
        }
    }

    // MARK: - Factory

    static func message<Target: NSObject, Arguments>(
        _ method: ObjectMethod<Arguments>,
        to target: Target
    ) -> Message<Target, Arguments>? {
        Message(target: target, method: method)
    }

    static func classMessage<Arguments>(
        _ method: ClassMethod<Arguments>,
        on className: ClassName
    ) -> ClassMessage<Arguments>? {
        guard let cls = NSClassFromString(className.rawValue) else { return nil }
        return ClassMessage(targetClass: cls, method: method)
    }
}

// MARK: - Typed Method Catalog

extension ObjCRuntime.ClassName {
    static let uiKeyboardImpl = ObjCRuntime.ClassName("UIKeyboardImpl")
    static let uiHitTestContext = ObjCRuntime.ClassName("_UIHitTestContext")
}

extension ObjCRuntime.ClassMethod where Arguments == ObjCRuntime.NoArguments {
    static let sharedInstance = ObjCRuntime.ClassMethod<Arguments>("sharedInstance")
}

extension ObjCRuntime.ClassMethod where Arguments == ObjCRuntime.PointRadiusArguments<NSObject> {
    static let contextWithPointRadius = ObjCRuntime.ClassMethod<Arguments>("contextWithPoint:radius:")
}

extension ObjCRuntime.ObjectMethod where Arguments == ObjCRuntime.NoArguments {
    static let keyboardDelegate = ObjCRuntime.ObjectMethod<Arguments>("delegate")
    static let keyboardTaskQueue = ObjCRuntime.ObjectMethod<Arguments>("taskQueue")
    static let keyboardWaitUntilAllTasksAreFinished = ObjCRuntime.ObjectMethod<Arguments>(
        "waitUntilAllTasksAreFinished"
    )
    static let applicationTouchesEvent = ObjCRuntime.ObjectMethod<Arguments>("_touchesEvent")
    static let eventClearTouches = ObjCRuntime.ObjectMethod<Arguments>("_clearTouches")
}

extension ObjCRuntime.ObjectMethod where Arguments == ObjCRuntime.ObjectArgument<NSString> {
    static let keyboardAddInputString = ObjCRuntime.ObjectMethod<Arguments>("addInputString:")
}

extension ObjCRuntime.ObjectMethod where Arguments == ObjCRuntime.ObjectArgument<UIWindow> {
    static let touchSetWindow = ObjCRuntime.ObjectMethod<Arguments>("setWindow:")
}

extension ObjCRuntime.ObjectMethod where Arguments == ObjCRuntime.ObjectArgument<UIResponder> {
    static let touchSetView = ObjCRuntime.ObjectMethod<Arguments>("setView:")
    static let touchSetGestureView = ObjCRuntime.ObjectMethod<Arguments>("setGestureView:")
}

extension ObjCRuntime.ObjectMethod where Arguments == ObjCRuntime.ObjectArgument<NSObject> {
    static let viewHitTestWithContext = ObjCRuntime.ObjectMethod<Arguments>("_hitTestWithContext:")
}

extension ObjCRuntime.ObjectMethod where Arguments == ObjCRuntime.IntArgument {
    static let touchSetPhase = ObjCRuntime.ObjectMethod<Arguments>("setPhase:")
    static let touchSetTapCount = ObjCRuntime.ObjectMethod<Arguments>("setTapCount:")
}

extension ObjCRuntime.ObjectMethod where Arguments == ObjCRuntime.BoolArgument {
    static let touchSetIsFirstTouchForView = ObjCRuntime.ObjectMethod<Arguments>("_setIsFirstTouchForView:")
    static let touchSetIsTap = ObjCRuntime.ObjectMethod<Arguments>("setIsTap:")
}

extension ObjCRuntime.ObjectMethod where Arguments == ObjCRuntime.DoubleArgument {
    static let touchSetTimestamp = ObjCRuntime.ObjectMethod<Arguments>("setTimestamp:")
}

extension ObjCRuntime.ObjectMethod where Arguments == ObjCRuntime.PointerArgument {
    static let eventSetHIDEvent = ObjCRuntime.ObjectMethod<Arguments>("_setHIDEvent:")
    static let touchSetHIDEvent = ObjCRuntime.ObjectMethod<Arguments>("_setHidEvent:")
}

extension ObjCRuntime.ObjectMethod where Arguments == ObjCRuntime.PointBoolArguments {
    static let touchSetLocationInWindow = ObjCRuntime.ObjectMethod<Arguments>(
        "_setLocationInWindow:resetPrevious:"
    )
}

extension ObjCRuntime.ObjectMethod where Arguments == ObjCRuntime.ObjectBoolArguments<UITouch> {
    static let eventAddTouchForDelayedDelivery = ObjCRuntime.ObjectMethod<Arguments>(
        "_addTouch:forDelayedDelivery:"
    )
}

extension ObjCRuntime.ObjectMethod where Arguments == ObjCRuntime.ObjectReturningBoolArgument<UIAccessibilityCustomAction> {
    static func accessibilityCustomAction(_ selector: Selector) -> Self {
        Self(selector)
    }
}

// MARK: - Typed Object Calls

extension ObjCRuntime.Message where Arguments == ObjCRuntime.NoArguments {
    func call() {
        bridge.sendVoid()
    }

    func call<Result: NSObject>() -> Result? {
        bridge.sendObject()
    }
}

extension ObjCRuntime.Message {
    func send<Argument: NSObject>(_ argument: Argument) where Arguments == ObjCRuntime.ObjectArgument<Argument> {
        bridge.sendVoid(argument)
    }

    func call<Argument: NSObject, Result: NSObject>(_ argument: Argument) -> Result?
        where Arguments == ObjCRuntime.ObjectArgument<Argument> {
        bridge.sendObject(argument)
    }

    func send<Argument: NSObject>(_ argument: Argument, _ flag: Bool)
        where Arguments == ObjCRuntime.ObjectBoolArguments<Argument> {
        bridge.sendVoid(argument, flag)
    }

    func call<Argument: NSObject>(_ argument: Argument) -> Bool
        where Arguments == ObjCRuntime.ObjectReturningBoolArgument<Argument> {
        bridge.sendBool(argument)
    }
}

extension ObjCRuntime.Message where Arguments == ObjCRuntime.IntArgument {
    func call(_ value: Int) {
        bridge.sendVoid(value)
    }
}

extension ObjCRuntime.Message where Arguments == ObjCRuntime.BoolArgument {
    func call(_ value: Bool) {
        bridge.sendVoid(value)
    }
}

extension ObjCRuntime.Message where Arguments == ObjCRuntime.DoubleArgument {
    func call(_ value: Double) {
        bridge.sendVoid(value)
    }
}

extension ObjCRuntime.Message where Arguments == ObjCRuntime.PointerArgument {
    func call(_ pointer: UnsafeMutableRawPointer) {
        bridge.sendVoid(pointer)
    }
}

extension ObjCRuntime.Message where Arguments == ObjCRuntime.PointBoolArguments {
    func call(_ point: CGPoint, resetPrevious: Bool) {
        bridge.sendVoid(point, resetPrevious)
    }
}

// MARK: - Typed Class Calls

extension ObjCRuntime.ClassMessage where Arguments == ObjCRuntime.NoArguments {
    func call<Result: NSObject>() -> Result? {
        bridge.sendObject()
    }
}

extension ObjCRuntime.ClassMessage {
    func call<Result: NSObject>(_ point: CGPoint, radius: CGFloat) -> Result?
        where Arguments == ObjCRuntime.PointRadiusArguments<Result> {
        bridge.sendObject(point, radius: radius)
    }
}

/// The only raw Objective-C bridge primitive in this file.
///
/// It owns `AnyObject`, `perform`, and IMP casting so the rest of the runtime
/// bridge can expose NSObject-backed Swift APIs.
private struct RawObjCMessageBridge {

    private typealias IMPInt = @convention(c) (AnyObject, Selector, Int) -> Void
    private typealias IMPBool = @convention(c) (AnyObject, Selector, Bool) -> Void
    private typealias IMPDouble = @convention(c) (AnyObject, Selector, Double) -> Void
    private typealias IMPPointer = @convention(c) (AnyObject, Selector, UnsafeMutableRawPointer) -> Void
    private typealias IMPPointBool = @convention(c) (AnyObject, Selector, CGPoint, Bool) -> Void
    private typealias IMPObjectBoolVoid = @convention(c) (AnyObject, Selector, AnyObject, Bool) -> Void
    private typealias IMPObjectBool = @convention(c) (AnyObject, Selector, AnyObject) -> Bool
    private typealias IMPPointRadiusObject = @convention(c) (AnyObject, Selector, CGPoint, CGFloat) -> AnyObject?

    private let target: AnyObject
    private let selector: Selector

    init?<Target: NSObject>(target: Target, selector: Selector) {
        let receiver = target as AnyObject
        guard receiver.responds(to: selector) else { return nil }
        self.target = receiver
        self.selector = selector
    }

    init?(targetClass: AnyClass, selector: Selector) {
        let receiver = targetClass as AnyObject
        guard receiver.responds(to: selector) else { return nil }
        self.target = receiver
        self.selector = selector
    }

    func sendVoid() {
        _ = target.perform(selector)
    }

    func sendVoid<Argument: NSObject>(_ argument: Argument) {
        _ = target.perform(selector, with: argument)
    }

    func sendVoid(_ value: Int) {
        imp(as: IMPInt.self)(target, selector, value)
    }

    func sendVoid(_ value: Bool) {
        imp(as: IMPBool.self)(target, selector, value)
    }

    func sendVoid(_ value: Double) {
        imp(as: IMPDouble.self)(target, selector, value)
    }

    func sendVoid(_ pointer: UnsafeMutableRawPointer) {
        imp(as: IMPPointer.self)(target, selector, pointer)
    }

    func sendVoid(_ point: CGPoint, _ flag: Bool) {
        imp(as: IMPPointBool.self)(target, selector, point, flag)
    }

    func sendVoid<Argument: NSObject>(_ argument: Argument, _ flag: Bool) {
        imp(as: IMPObjectBoolVoid.self)(target, selector, argument, flag)
    }

    func sendObject<Result: NSObject>() -> Result? {
        target.perform(selector)?.takeUnretainedValue() as? Result
    }

    func sendObject<Argument: NSObject, Result: NSObject>(_ argument: Argument) -> Result? {
        target.perform(selector, with: argument)?.takeUnretainedValue() as? Result
    }

    func sendObject<Result: NSObject>(_ point: CGPoint, radius: CGFloat) -> Result? {
        imp(as: IMPPointRadiusObject.self)(target, selector, point, radius) as? Result
    }

    func sendBool<Argument: NSObject>(_ argument: Argument) -> Bool {
        imp(as: IMPObjectBool.self)(target, selector, argument)
    }

    private func imp<Function>(as type: Function.Type) -> Function {
        unsafeBitCast(target.method(for: selector), to: Function.self)
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
