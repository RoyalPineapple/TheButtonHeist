#if canImport(UIKit)
#if DEBUG
import UIKit

/// Type-safe wrapper around `UIKeyboardImpl` private API.
///
/// All keyboard text injection in Button Heist routes through this bridge.
/// It encapsulates the seven ObjC selectors needed to talk to UIKeyboardImpl
/// behind clean Swift methods, matching the KIF testing framework's approach.
///
/// Uses `sharedInstance` (not `activeInstance`) so it works with both software
/// and hardware keyboards — `activeInstance` returns nil when a hardware
/// keyboard is connected.
///
/// `@MainActor` justification: wraps a UIKit singleton (`AnyObject`); the
/// stored impl is non-Sendable.
@MainActor struct KeyboardBridge { // swiftlint:disable:this agent_main_actor_value_type

    private let impl: AnyObject

    /// Resolve the UIKeyboardImpl singleton. Returns nil if the class or
    /// selector is missing (should never happen on supported iOS versions).
    static func shared() -> KeyboardBridge? {
        guard let impl: AnyObject = ObjCRuntime.classMessage("sharedInstance", on: "UIKeyboardImpl")?.call() else {
            return nil
        }
        return KeyboardBridge(impl: impl)
    }

    /// The keyboard's current input delegate, if any.
    /// Non-nil when a text field or text view is focused.
    var delegate: AnyObject? {
        ObjCRuntime.message("delegate", to: impl)?.call()
    }

    /// Whether the delegate conforms to UIKeyInput (i.e., can accept text).
    var hasActiveInput: Bool {
        delegate is UIKeyInput
    }

    /// Inject a single character into the focused text field.
    /// Routes through UIKeyboardImpl's internal input processing, which
    /// means the character lands via the normal `UIKeyInput.insertText(_:)`
    /// pathway with all responder-chain delegate callbacks.
    func type(_ character: Character) {
        addInputString?.call(String(character) as AnyObject)
        drainTaskQueue()
    }

    /// Send a single backspace event to the focused text field.
    func deleteBackward() {
        deleteFromInput?.call()
        drainTaskQueue()
    }

    // MARK: - Private

    /// Message for `addInputString:` — resolved per access.
    private var addInputString: ObjCRuntime.Message? {
        ObjCRuntime.message("addInputString:", to: impl)
    }

    /// Message for `deleteFromInput` — resolved per access.
    private var deleteFromInput: ObjCRuntime.Message? {
        ObjCRuntime.message("deleteFromInput", to: impl)
    }

    /// Drain UIKeyboardImpl's internal task queue after each keystroke.
    /// Without this, rapid character injection can outpace the keyboard's
    /// processing, causing dropped or reordered characters. This is a
    /// direct port of KIF's `[taskQueue waitUntilAllTasksAreFinished]`.
    private func drainTaskQueue() {
        guard let taskQueue: AnyObject = ObjCRuntime.message("taskQueue", to: impl)?.call() else { return }
        ObjCRuntime.message("waitUntilAllTasksAreFinished", to: taskQueue)?.call()
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
