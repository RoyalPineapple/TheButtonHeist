#if canImport(UIKit)
import XCTest
@testable import TheInsideJob

@MainActor
final class KeyboardInjectionTextInputDelegate: NSObject, UIKeyInput {
    private(set) var insertedText: [String] = []
    private(set) var deleteBackwardCount = 0

    var hasText: Bool { !insertedText.isEmpty }

    func insertText(_ text: String) {
        insertedText.append(text)
    }

    func deleteBackward() {
        deleteBackwardCount += 1
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
    let inputDelegate = KeyboardInjectionTextInputDelegate()
    var taskQueueObject: KeyboardInjectionTaskQueue? = KeyboardInjectionTaskQueue()
    private(set) var inputStrings: [String] = []
    private(set) var deleteFromInputCount = 0

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

    @objc(deleteFromInput)
    func deleteFromInput() {
        deleteFromInputCount += 1
    }

    @MainActor
    func bridge(missingSelector selector: String? = nil) -> KeyboardBridge {
        let injection = UIKeyboardImplTextInjection(impl: self) { name, target in
            guard name != selector else { return nil }
            return ObjCRuntime.message(name, to: target)
        }
        return KeyboardBridge(impl: self, textInjection: injection)
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
        let injection = UIKeyboardImplTextInjection(impl: keyboardImpl) { name, target in
            guard name != "addInputString:" else { return nil }
            return ObjCRuntime.message(name, to: target)
        }

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
        let injection = UIKeyboardImplTextInjection(impl: keyboardImpl) { name, target in
            guard name != "waitUntilAllTasksAreFinished" else { return nil }
            return ObjCRuntime.message(name, to: target)
        }

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

    func testDeleteBackwardRoutesThroughKeyboardInjection() {
        let keyboardImpl = KeyboardInjectionKeyboardImpl()
        let bridge = keyboardImpl.bridge()

        let result = bridge.deleteBackward()

        XCTAssertEqual(result, .dispatched)
        XCTAssertEqual(keyboardImpl.deleteFromInputCount, 1)
        XCTAssertEqual(keyboardImpl.taskQueueObject?.waitCount, 1)
    }

    func testDeleteBackwardReportsMissingSelector() {
        let keyboardImpl = KeyboardInjectionKeyboardImpl()
        let bridge = keyboardImpl.bridge(missingSelector: "deleteFromInput")

        let result = bridge.deleteBackward()

        XCTAssertEqual(
            result.diagnostic,
            KeyboardTextInjectionDiagnostic.missingSelector(
                "deleteFromInput",
                strategy: UIKeyboardImplTextInjection.strategyName,
                character: nil
            )
        )
        XCTAssertEqual(keyboardImpl.deleteFromInputCount, 0)
        XCTAssertEqual(keyboardImpl.taskQueueObject?.waitCount, 0)
    }

    func testDeleteBackwardReportsMissingDrainSelectorAfterDispatch() {
        let keyboardImpl = KeyboardInjectionKeyboardImpl()
        let bridge = keyboardImpl.bridge(missingSelector: "waitUntilAllTasksAreFinished")

        let result = bridge.deleteBackward()

        XCTAssertEqual(keyboardImpl.deleteFromInputCount, 1)
        XCTAssertEqual(
            result.diagnostic,
            KeyboardTextInjectionDiagnostic.missingSelector(
                "waitUntilAllTasksAreFinished",
                strategy: UIKeyboardImplTextInjection.strategyName,
                character: nil
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
