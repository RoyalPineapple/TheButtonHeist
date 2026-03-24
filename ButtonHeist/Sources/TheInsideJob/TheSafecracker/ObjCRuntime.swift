#if canImport(UIKit)
#if DEBUG
// swiftlint:disable nesting
import UIKit

/// Type-safe wrappers for ObjC runtime dispatch to private UIKit APIs.
///
/// ## Why this exists
///
/// UIKit's touch injection system (`UITouch`, `UIEvent`, `UIKeyboardImpl`, etc.)
/// exposes critical functionality only through private methods that don't appear
/// in any public header. Calling them from Swift normally requires three steps of
/// boilerplate at every call site:
///
/// 1. **Look up the selector by name** — `NSSelectorFromString("setPhase:")`
/// 2. **Check the object responds** — `touch.responds(to: sel)`
/// 3. **Dispatch** — `perform(_:with:)` for object args, or IMP extraction +
///    `unsafeBitCast` for value types like `Int` and `Bool` that `perform` can't carry.
///
/// This utility collapses all three into one expression:
///
///     ObjCRuntime.message("setPhase:", to: touch)?.call(phase.rawValue)
///
/// If the selector doesn't exist (Apple removed it), `message` returns `nil`
/// and the whole chain no-ops — no crash.
///
/// ## The two dispatch paths
///
/// ObjC method calls send a *message* (selector + args) to an object. Swift's
/// `perform(_:with:)` does this but can only pass object arguments.
///
/// For value types we use the **IMP** (implementation pointer) — a raw C function
/// pointer the ObjC runtime stores for each method. `object.method(for: sel)`
/// returns it, we `unsafeBitCast` to the correct `@convention(c)` signature and
/// call directly. This is what `objc_msgSend` does under the hood.
///
/// The `IMP*` typealiases define these C signatures. Every IMP takes `(self, _cmd)`
/// — the receiver and selector — then the actual arguments.
///
enum ObjCRuntime {

    /// A verified target + selector pair. Created by `message(_:to:)`.
    /// The selector is guaranteed present — all `call` methods are safe to invoke.
    struct Message {
        let target: AnyObject
        let selector: Selector

        // MARK: - IMP Signatures (self, _cmd, ...args)

        private typealias IMPInt = @convention(c) (AnyObject, Selector, Int) -> Void
        private typealias IMPBool = @convention(c) (AnyObject, Selector, Bool) -> Void
        private typealias IMPDouble = @convention(c) (AnyObject, Selector, Double) -> Void
        private typealias IMPPointer = @convention(c) (AnyObject, Selector, UnsafeMutableRawPointer) -> Void
        private typealias IMPPointBool = @convention(c) (AnyObject, Selector, CGPoint, Bool) -> Void

        // MARK: - Void Dispatch

        func call() { _ = target.perform(selector) }
        func call(_ arg: AnyObject) { _ = target.perform(selector, with: arg) }
        func call(_ value: Int) { imp(as: IMPInt.self)(target, selector, value) }
        func call(_ value: Bool) { imp(as: IMPBool.self)(target, selector, value) }
        func call(_ value: Double) { imp(as: IMPDouble.self)(target, selector, value) }
        func call(_ ptr: UnsafeMutableRawPointer) { imp(as: IMPPointer.self)(target, selector, ptr) }
        func call(_ point: CGPoint, _ flag: Bool) { imp(as: IMPPointBool.self)(target, selector, point, flag) }

        // MARK: - Returning Dispatch
        //
        // Uses takeUnretainedValue() — assumes +0 (unretained) return semantics,
        // which is correct for property getters and singleton accessors. Do NOT
        // use for +1 factory methods (e.g., create/copy/new) without switching
        // to takeRetainedValue().

        /// Return type `R` is inferred from assignment context.
        func call<R: AnyObject>() -> R? {
            target.perform(selector)?.takeUnretainedValue() as? R
        }

        /// Pass an object arg, return typed result.
        func call<R: AnyObject>(_ arg: AnyObject) -> R? {
            target.perform(selector, with: arg)?.takeUnretainedValue() as? R
        }

        // MARK: - Escape Hatch

        /// Raw IMP cast to a `@convention(c)` type. Use for signatures that
        /// don't fit the `call` overloads (mixed object + value args, etc.).
        func imp<F>(as type: F.Type) -> F {
            unsafeBitCast(target.method(for: selector), to: F.self)
        }
    }

    // MARK: - Factory

    /// Resolve a selector on a target. Returns `nil` if it doesn't respond.
    static func message(_ name: String, to target: AnyObject) -> Message? {
        let sel = NSSelectorFromString(name)
        guard target.responds(to: sel) else { return nil }
        return Message(target: target, selector: sel)
    }

    /// Resolve a class method on a private class, both looked up by name.
    static func classMessage(_ selectorName: String, on className: String) -> Message? {
        guard let cls = NSClassFromString(className) else { return nil }
        return message(selectorName, to: cls as AnyObject)
    }
}

#endif
#endif
