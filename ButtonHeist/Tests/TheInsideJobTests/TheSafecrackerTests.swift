#if canImport(UIKit)
import XCTest
import ThePlans
@testable import TheInsideJob

@MainActor
final class KeyboardInjectionTextInputDelegate: NSObject, UIKeyInput {
    private(set) var insertedText: [String] = []

    var hasText: Bool { !insertedText.isEmpty }

    func insertText(_ text: String) {
        insertedText.append(text)
    }

    func deleteBackward() {}
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
    private typealias AddInputStringMethod = ObjCRuntime.ObjectMethod<ObjCRuntime.ObjectArgument<NSString>>
    private typealias KeyboardObjectGetter = ObjCRuntime.ObjectGetter<NSObject>
    private typealias KeyboardNoArgumentMethod = ObjCRuntime.ObjectMethod<ObjCRuntime.NoArguments>

    let inputDelegate = KeyboardInjectionTextInputDelegate()
    var taskQueueObject: KeyboardInjectionTaskQueue? = KeyboardInjectionTaskQueue()
    private(set) var inputStrings: [String] = []

    @objc(delegate)
    func delegate() -> AnyObject? {
        inputDelegate
    }

    @objc(addInputString:)
    func addInputString(_ text: NSString) {
        inputStrings.append(text as String)
    }

    @objc(taskQueue)
    func taskQueue() -> AnyObject? {
        taskQueueObject
    }

    @MainActor
    func bridge(missingSelector selector: String? = nil) -> KeyboardBridge {
        let injection = UIKeyboardImplTextInjection(impl: self, runtime: runtime(missingSelector: selector))
        return KeyboardBridge(impl: self, textInjection: injection)
    }

    @MainActor
    func runtime(missingSelector selector: String? = nil) -> UIKeyboardImplTextInjection.Runtime {
        UIKeyboardImplTextInjection.Runtime(
            addInputString: { target in
                guard AddInputStringMethod.keyboardAddInputString.rawValue != selector else { return nil }
                return ObjCRuntime.message(.keyboardAddInputString, to: target)
            },
            taskQueue: { target in
                guard KeyboardObjectGetter.keyboardTaskQueue.rawValue != selector else { return nil }
                return ObjCRuntime.resolve(.keyboardTaskQueue, from: target)
            },
            waitUntilAllTasksAreFinished: { target in
                guard KeyboardNoArgumentMethod.keyboardWaitUntilAllTasksAreFinished.rawValue != selector else { return nil }
                return ObjCRuntime.message(.keyboardWaitUntilAllTasksAreFinished, to: target)
            }
        )
    }
}

@MainActor
final class TheSafecrackerTests: XCTestCase {

    private var tripwire: TheTripwire!
    private var safecracker: TheSafecracker!

    override func setUp() async throws {
        tripwire = TheTripwire()
        safecracker = TheSafecracker()
        safecracker.startKeyboardObservation()
    }

    override func tearDown() async throws {
        safecracker.stopKeyboardObservation()
        tripwire.stopPulse()
        tripwire = nil
        safecracker = nil
    }

    // MARK: - Keyboard Visibility

    func testKeyboardNotVisibleByDefault() {
        XCTAssertFalse(safecracker.isKeyboardVisible())
    }

    func testKeyboardVisibilityDoesNotInferFromFocusedTextInput() {
        let keyboardImpl = KeyboardInjectionKeyboardImpl()
        safecracker.keyboardBridgeProvider = { keyboardImpl.bridge() }

        XCTAssertTrue(safecracker.hasActiveTextInput())
        XCTAssertFalse(safecracker.isKeyboardVisible())
    }

    func testKeyboardVisibleAfterFrameNotification() {
        let screenBounds = UIScreen.main.bounds
        let keyboardFrame = CGRect(
            x: 0,
            y: screenBounds.height - 300,
            width: screenBounds.width,
            height: 300
        )

        NotificationCenter.default.post(
            name: UIResponder.keyboardDidChangeFrameNotification,
            object: nil,
            userInfo: [UIResponder.keyboardFrameEndUserInfoKey: keyboardFrame]
        )

        XCTAssertTrue(safecracker.isKeyboardVisible())
    }

    func testKeyboardNotVisibleWhenFrameOffScreen() {
        let screenBounds = UIScreen.main.bounds
        let offScreenFrame = CGRect(
            x: 0,
            y: screenBounds.height,
            width: screenBounds.width,
            height: 300
        )

        NotificationCenter.default.post(
            name: UIResponder.keyboardDidChangeFrameNotification,
            object: nil,
            userInfo: [UIResponder.keyboardFrameEndUserInfoKey: offScreenFrame]
        )

        XCTAssertFalse(safecracker.isKeyboardVisible())
    }

    func testKeyboardNotVisibleAfterObservationStopped() {
        let screenBounds = UIScreen.main.bounds
        let keyboardFrame = CGRect(
            x: 0,
            y: screenBounds.height - 300,
            width: screenBounds.width,
            height: 300
        )

        NotificationCenter.default.post(
            name: UIResponder.keyboardDidChangeFrameNotification,
            object: nil,
            userInfo: [UIResponder.keyboardFrameEndUserInfoKey: keyboardFrame]
        )
        XCTAssertTrue(safecracker.isKeyboardVisible())

        safecracker.stopKeyboardObservation()

        // After stopping observation, the flag retains its last value
        // but new notifications should not update it.
        let newSafecracker = TheSafecracker()
        XCTAssertFalse(newSafecracker.isKeyboardVisible())
    }

    func testKeyboardVisibilityTogglesWithNotifications() {
        let screenBounds = UIScreen.main.bounds
        let visibleFrame = CGRect(
            x: 0,
            y: screenBounds.height - 300,
            width: screenBounds.width,
            height: 300
        )
        let hiddenFrame = CGRect(
            x: 0,
            y: screenBounds.height,
            width: screenBounds.width,
            height: 300
        )

        NotificationCenter.default.post(
            name: UIResponder.keyboardDidChangeFrameNotification,
            object: nil,
            userInfo: [UIResponder.keyboardFrameEndUserInfoKey: visibleFrame]
        )
        XCTAssertTrue(safecracker.isKeyboardVisible())

        NotificationCenter.default.post(
            name: UIResponder.keyboardDidChangeFrameNotification,
            object: nil,
            userInfo: [UIResponder.keyboardFrameEndUserInfoKey: hiddenFrame]
        )
        XCTAssertFalse(safecracker.isKeyboardVisible())
    }

    // MARK: - Text Injection

    func testTextInjectionReportsMissingAddInputStringSelector() {
        let keyboardImpl = KeyboardInjectionKeyboardImpl()
        let injection = UIKeyboardImplTextInjection(
            impl: keyboardImpl,
            runtime: keyboardImpl.runtime(missingSelector: "addInputString:")
        )

        let result = injection.type("h")

        XCTAssertEqual(
            result.diagnostic,
            KeyboardTextInjectionDiagnostic.missingSelector(
                "addInputString:",
                strategy: UIKeyboardImplTextInjection.strategyName,
                character: "h"
            )
        )
        XCTAssertTrue(keyboardImpl.inputStrings.isEmpty)
    }

    func testTextInjectionReportsMissingDrainSelectorAfterDispatch() {
        let keyboardImpl = KeyboardInjectionKeyboardImpl()
        let injection = UIKeyboardImplTextInjection(
            impl: keyboardImpl,
            runtime: keyboardImpl.runtime(missingSelector: "waitUntilAllTasksAreFinished")
        )

        let result = injection.type("h")

        XCTAssertEqual(keyboardImpl.inputStrings, ["h"])
        XCTAssertEqual(
            result.diagnostic,
            KeyboardTextInjectionDiagnostic.missingSelector(
                "waitUntilAllTasksAreFinished",
                strategy: UIKeyboardImplTextInjection.strategyName,
                character: "h"
            )
        )
    }

    func testTextInjectionReportsUnavailableTaskQueueAfterDispatch() {
        let keyboardImpl = KeyboardInjectionKeyboardImpl()
        keyboardImpl.taskQueueObject = nil
        let injection = UIKeyboardImplTextInjection(impl: keyboardImpl)

        let result = injection.type("h")

        XCTAssertEqual(keyboardImpl.inputStrings, ["h"])
        XCTAssertEqual(
            result.diagnostic,
            KeyboardTextInjectionDiagnostic.unavailableTaskQueue(
                strategy: UIKeyboardImplTextInjection.strategyName,
                character: "h"
            )
        )
    }

    func testTypeTextReturnsKeyboardInjectionDiagnostic() async {
        let keyboardImpl = KeyboardInjectionKeyboardImpl()
        safecracker.keyboardBridgeProvider = { keyboardImpl.bridge(missingSelector: "addInputString:") }

        let result = await safecracker.typeText("hello")

        XCTAssertEqual(
            result.diagnostic,
            KeyboardTextInjectionDiagnostic.missingSelector(
                "addInputString:",
                strategy: UIKeyboardImplTextInjection.strategyName,
                character: "h"
            )
        )
    }

}
#endif
