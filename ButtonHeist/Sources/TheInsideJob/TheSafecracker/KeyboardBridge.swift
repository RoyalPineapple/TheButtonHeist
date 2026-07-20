#if canImport(UIKit)
#if DEBUG
import UIKit

enum KeyboardTextInjectionOutcome: Equatable {
    case dispatched
    case failed(KeyboardTextInjectionDiagnostic)

    var diagnostic: KeyboardTextInjectionDiagnostic? {
        guard case .failed(let diagnostic) = self else { return nil }
        return diagnostic
    }
}

enum KeyboardTextInjectionFailureReason: Equatable {
    case missingSelector(String)
    case unavailableTaskQueue
    case noActiveInput
    case unavailableClearTextValue
    case cancelled
}

struct KeyboardTextInjectionDiagnostic: Equatable {
    let strategy: String
    let reason: KeyboardTextInjectionFailureReason
    let character: String?

    var message: String {
        var details: String
        switch reason {
        case .missingSelector(let selector):
            details = "missing selector \(selector)"
        case .unavailableTaskQueue:
            details = "taskQueue unavailable"
        case .noActiveInput:
            details = "no active UIKeyInput delegate"
        case .unavailableClearTextValue:
            details = "cannot clear text because the current value is unavailable"
        case .cancelled:
            details = "cancelled before text dispatch completed"
        }
        if let character {
            details += " while typing \"\(character)\""
        }
        return "\(strategy) failed: \(details)"
    }

    static func missingSelector(_ selector: String, strategy: String, character: String?) -> KeyboardTextInjectionDiagnostic {
        KeyboardTextInjectionDiagnostic(
            strategy: strategy,
            reason: .missingSelector(selector),
            character: character
        )
    }

    static func unavailableTaskQueue(strategy: String, character: String?) -> KeyboardTextInjectionDiagnostic {
        KeyboardTextInjectionDiagnostic(
            strategy: strategy,
            reason: .unavailableTaskQueue,
            character: character
        )
    }

    static func noActiveInput(strategy: String) -> KeyboardTextInjectionDiagnostic {
        KeyboardTextInjectionDiagnostic(
            strategy: strategy,
            reason: .noActiveInput,
            character: nil
        )
    }

    static func cancelled(strategy: String) -> KeyboardTextInjectionDiagnostic {
        KeyboardTextInjectionDiagnostic(
            strategy: strategy,
            reason: .cancelled,
            character: nil
        )
    }

    static func unavailableClearTextValue(strategy: String) -> KeyboardTextInjectionDiagnostic {
        KeyboardTextInjectionDiagnostic(
            strategy: strategy,
            reason: .unavailableClearTextValue,
            character: nil
        )
    }
}

final class UIKeyboardImplTextInjection {

    static let strategyName = "UIKeyboardImplTextInjection"

    /// Bypass the IME candidate engine and commit the supplied text literally.
    static let literalInsertionFlags: UInt = 1 << 7

    private typealias AddInputStringMethod = ObjCRuntime.ObjectMethod<ObjCRuntime.ObjectUIntArguments<NSString>>
    private typealias KeyboardObjectGetter = ObjCRuntime.ObjectGetter<NSObject>
    private typealias KeyboardNoArgumentMethod = ObjCRuntime.ObjectMethod<ObjCRuntime.NoArguments>
    typealias TaskQueueGetter = ObjCRuntime.ResolvedObjectGetter<NSObject, NSObject>

    struct Runtime: Sendable {
        var addInputString: @Sendable (NSObject) -> ObjCRuntime.Message<NSObject, ObjCRuntime.ObjectUIntArguments<NSString>>?
        var taskQueue: @Sendable (NSObject) -> TaskQueueGetter?
        var waitUntilAllTasksAreFinished: @Sendable (NSObject) -> ObjCRuntime.Message<NSObject, ObjCRuntime.NoArguments>?

        static let live = Runtime(
            addInputString: { ObjCRuntime.message(.keyboardAddLiteralInputString, to: $0) },
            taskQueue: { ObjCRuntime.resolve(.keyboardTaskQueue, from: $0) },
            waitUntilAllTasksAreFinished: {
                ObjCRuntime.message(.keyboardWaitUntilAllTasksAreFinished, to: $0)
            }
        )
    }

    private let impl: NSObject
    private let runtime: Runtime

    init(
        impl: NSObject,
        runtime: Runtime = .live
    ) {
        self.impl = impl
        self.runtime = runtime
    }

    func type(_ character: Character) -> KeyboardTextInjectionOutcome {
        let text = String(character)
        guard let addInputString = runtime.addInputString(impl) else {
            return .failed(.missingSelector(
                AddInputStringMethod.keyboardAddLiteralInputString.rawValue,
                strategy: Self.strategyName,
                character: text
            ))
        }
        addInputString.send(text as NSString, flags: Self.literalInsertionFlags)
        return drainTaskQueue(character: text)
    }

    func drainTaskQueue(character: String?) -> KeyboardTextInjectionOutcome {
        guard let taskQueueGetter = runtime.taskQueue(impl) else {
            return .failed(.missingSelector(
                KeyboardObjectGetter.keyboardTaskQueue.rawValue,
                strategy: Self.strategyName,
                character: character
            ))
        }
        guard let taskQueue = taskQueueGetter.get() else {
            return .failed(.unavailableTaskQueue(strategy: Self.strategyName, character: character))
        }
        guard let waitUntilAllTasksAreFinished = runtime.waitUntilAllTasksAreFinished(taskQueue) else {
            return .failed(.missingSelector(
                KeyboardNoArgumentMethod.keyboardWaitUntilAllTasksAreFinished.rawValue,
                strategy: Self.strategyName,
                character: character
            ))
        }
        waitUntilAllTasksAreFinished.call()
        return .dispatched
    }
}

/// Type-safe wrapper around `UIKeyboardImpl` private API.
///
/// All keyboard text injection in Button Heist routes through this bridge.
/// It encapsulates the ObjC selectors needed to talk to UIKeyboardImpl behind
/// clean Swift methods, matching the KIF testing framework's approach.
///
/// Uses `sharedInstance` (not `activeInstance`) so it works with both software
/// and hardware keyboards — `activeInstance` returns nil when a hardware
/// keyboard is connected.
///
/// `@MainActor` justification: wraps a UIKit singleton (`NSObject`); the
/// stored impl is non-Sendable.
@MainActor struct KeyboardBridge {

    private let impl: NSObject
    private let textInjection: UIKeyboardImplTextInjection

    init(impl: NSObject, textInjection: UIKeyboardImplTextInjection? = nil) {
        self.impl = impl
        self.textInjection = textInjection ?? UIKeyboardImplTextInjection(impl: impl)
    }

    /// Resolve the UIKeyboardImpl singleton. Returns nil if the class or
    /// selector is missing (should never happen on supported iOS versions).
    static func shared() -> KeyboardBridge? {
        guard let impl: NSObject = ObjCRuntime.get(.sharedInstance, on: .uiKeyboardImpl) else {
            return nil
        }
        return KeyboardBridge(impl: impl)
    }

    /// The keyboard's current input delegate, if any.
    /// Non-nil when a text field or text view is focused.
    var delegate: NSObject? {
        ObjCRuntime.get(.keyboardDelegate, from: impl)
    }

    /// Whether the delegate conforms to UIKeyInput (i.e., can accept text).
    var hasActiveInput: Bool {
        delegate is UIKeyInput
    }

    /// Inject a single character into the focused text field.
    /// Routes through UIKeyboardImpl's literal insertion path, which bypasses
    /// autocorrection while preserving the normal text-input delegate gates.
    func type(_ character: Character) -> KeyboardTextInjectionOutcome {
        textInjection.type(character)
    }

    func selectAllTextIfPossible() -> Bool {
        guard let textInput = delegate as? UITextInput,
              let range = textInput.textRange(
                from: textInput.beginningOfDocument,
                to: textInput.endOfDocument
              ) else {
            return false
        }
        textInput.selectedTextRange = range
        return true
    }

    func deleteBackward() -> KeyboardTextInjectionOutcome {
        guard let input = delegate as? UIKeyInput else {
            return .failed(.noActiveInput(strategy: UIKeyboardImplTextInjection.strategyName))
        }
        input.deleteBackward()
        return textInjection.drainTaskQueue(character: nil)
    }

}

#endif // DEBUG
#endif // canImport(UIKit)
