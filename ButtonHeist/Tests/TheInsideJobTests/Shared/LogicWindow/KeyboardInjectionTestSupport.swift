#if canImport(UIKit)
import UIKit

import ThePlans
@testable import TheInsideJob

@MainActor
final class KeyboardInjectionTextInputDelegate: NSObject, UIKeyInput {
    private(set) var insertedText: [String] = []
    private(set) var directDeleteCount = 0

    var hasText: Bool { !insertedText.isEmpty }

    func insertText(_ text: String) {
        insertedText.append(text)
    }

    func deleteBackward() {
        directDeleteCount += 1
    }
}

@MainActor
final class KeyboardInjectionTaskQueue: NSObject {
    private(set) var waitCount = 0

    @objc(waitUntilAllTasksAreFinished)
    func waitUntilAllTasksAreFinished() {
        waitCount += 1
    }
}

@MainActor
final class KeyboardInjectionKeyboardImpl: NSObject {
    private typealias AddInputStringMethod =
        ObjCRuntime.ObjectMethod<ObjCRuntime.ObjectUIntArguments<NSString>>
    private typealias KeyboardObjectGetter = ObjCRuntime.ObjectGetter<NSObject>
    private typealias KeyboardNoArgumentMethod = ObjCRuntime.ObjectMethod<ObjCRuntime.NoArguments>

    let inputDelegate = KeyboardInjectionTextInputDelegate()
    var delegateOverride: NSObject?
    var taskQueueObject: KeyboardInjectionTaskQueue? = KeyboardInjectionTaskQueue()
    private(set) var inputStrings: [String] = []
    private(set) var inputFlags: [UInt] = []
    private(set) var deleteFromInputCount = 0

    @objc(delegate)
    func delegate() -> AnyObject? {
        delegateOverride ?? inputDelegate
    }

    @objc(addInputString:withFlags:)
    func addInputString(_ text: NSString, flags: UInt) {
        inputStrings.append(text as String)
        inputFlags.append(flags)
    }

    @objc(deleteFromInput)
    func deleteFromInput() {
        deleteFromInputCount += 1
    }

    @objc(taskQueue)
    func taskQueue() -> AnyObject? {
        taskQueueObject
    }

    func bridge(missingSelector selector: String? = nil) -> KeyboardBridge {
        let injection = UIKeyboardImplTextInjection(
            impl: self,
            runtime: runtime(missingSelector: selector)
        )
        return KeyboardBridge(impl: self, textInjection: injection)
    }

    func runtime(missingSelector selector: String? = nil) -> UIKeyboardImplTextInjection.Runtime {
        UIKeyboardImplTextInjection.Runtime(
            addInputString: { target in
                guard AddInputStringMethod.keyboardAddLiteralInputString.rawValue != selector else {
                    return nil
                }
                return ObjCRuntime.message(.keyboardAddLiteralInputString, to: target)
            },
            deleteFromInput: { target in
                guard KeyboardNoArgumentMethod.keyboardDeleteFromInput.rawValue != selector else {
                    return nil
                }
                return ObjCRuntime.message(.keyboardDeleteFromInput, to: target)
            },
            taskQueue: { target in
                guard KeyboardObjectGetter.keyboardTaskQueue.rawValue != selector else { return nil }
                return ObjCRuntime.resolve(.keyboardTaskQueue, from: target)
            },
            waitUntilAllTasksAreFinished: { target in
                guard KeyboardNoArgumentMethod.keyboardWaitUntilAllTasksAreFinished.rawValue
                    != selector else {
                    return nil
                }
                return ObjCRuntime.message(.keyboardWaitUntilAllTasksAreFinished, to: target)
            }
        )
    }
}
#endif
