#if canImport(UIKit)
import XCTest
import ThePlans
@testable import TheInsideJob

@MainActor
final class TheSafecrackerTests: XCTestCase {

    // MARK: - Keyboard Visibility

    func testKeyboardNotVisibleByDefault() {
        let safecracker = TheSafecracker()

        XCTAssertFalse(safecracker.isKeyboardVisible)
    }

    func testKeyboardVisibilityDoesNotInferFromFocusedTextInput() {
        let keyboardImpl = KeyboardInjectionKeyboardImpl()
        let safecracker = TheSafecracker(keyboardInput: SafecrackerKeyboardInput(
            keyboardBridgeProvider: { keyboardImpl.bridge() }
        ))

        XCTAssertTrue(safecracker.hasActiveTextInput)
        XCTAssertFalse(safecracker.isKeyboardVisible)
    }

    // MARK: - Text Injection

    func testTextInjectionReportsMissingAddInputStringSelector() {
        let keyboardImpl = KeyboardInjectionKeyboardImpl()
        let injection = UIKeyboardImplTextInjection(
            impl: keyboardImpl,
            runtime: keyboardImpl.runtime(missingSelector: "addInputString:withFlags:")
        )

        let result = injection.type("h")

        XCTAssertEqual(
            result.diagnostic,
            KeyboardTextInjectionDiagnostic.missingSelector(
                "addInputString:withFlags:",
                strategy: UIKeyboardImplTextInjection.strategyName,
                character: "h"
            )
        )
        XCTAssertTrue(keyboardImpl.inputStrings.isEmpty)
    }

    func testTextInjectionDispatchesComposedGraphemeAsOneLiteralInsertion() {
        let keyboardImpl = KeyboardInjectionKeyboardImpl()
        let injection = UIKeyboardImplTextInjection(impl: keyboardImpl)
        let grapheme: Character = "e\u{301}"

        let result = injection.type(grapheme)

        XCTAssertEqual(result, .dispatched)
        XCTAssertEqual(keyboardImpl.inputStrings, [String(grapheme)])
        XCTAssertEqual(
            keyboardImpl.inputFlags,
            [UIKeyboardImplTextInjection.literalInsertionFlags]
        )
        XCTAssertEqual(keyboardImpl.taskQueueObject?.waitCount, 1)
    }

    func testTypeTextDispatchesEachCharacterLiterallyAndDrainsAfterEach() async {
        let keyboardImpl = KeyboardInjectionKeyboardImpl()
        let safecracker = TheSafecracker(keyboardInput: SafecrackerKeyboardInput(
            keyboardBridgeProvider: { keyboardImpl.bridge() }
        ))

        let result = await safecracker.typeText("teh", interKeyDelay: 0)

        XCTAssertEqual(result, .dispatched)
        XCTAssertEqual(keyboardImpl.inputStrings, ["t", "e", "h"])
        XCTAssertEqual(
            keyboardImpl.inputFlags,
            Array(repeating: UIKeyboardImplTextInjection.literalInsertionFlags, count: 3)
        )
        XCTAssertEqual(keyboardImpl.taskQueueObject?.waitCount, 3)
    }

    func testDeleteBackwardRoutesThroughKeyboardImplNotDelegate() {
        let keyboardImpl = KeyboardInjectionKeyboardImpl()
        let bridge = keyboardImpl.bridge()

        let result = bridge.deleteBackward()

        XCTAssertEqual(result, .dispatched)
        XCTAssertEqual(keyboardImpl.deleteFromInputCount, 1)
        XCTAssertEqual(keyboardImpl.inputDelegate.directDeleteCount, 0)
        XCTAssertEqual(keyboardImpl.taskQueueObject?.waitCount, 1)
    }

    func testClearTextCountsBackspacesFromDocumentText() async {
        let keyboardImpl = KeyboardInjectionKeyboardImpl()
        let textField = UITextField()
        textField.text = "15%"
        keyboardImpl.delegateOverride = textField
        let input = SafecrackerKeyboardInput(
            keyboardBridgeProvider: { keyboardImpl.bridge() }
        )

        let result = await input.clearText(existingValue: nil, interKeyDelay: 0)

        XCTAssertEqual(result, .dispatched)
        XCTAssertEqual(keyboardImpl.deleteFromInputCount, 3)
    }

    func testClearTextOnEmptyDocumentDispatchesWithoutDeletes() async {
        let keyboardImpl = KeyboardInjectionKeyboardImpl()
        let textField = UITextField()
        textField.text = ""
        keyboardImpl.delegateOverride = textField
        let input = SafecrackerKeyboardInput(
            keyboardBridgeProvider: { keyboardImpl.bridge() }
        )

        // The accessibility value of an empty field echoes its placeholder;
        // the document text must win so an empty field sends zero deletes.
        let result = await input.clearText(existingValue: "Placeholder", interKeyDelay: 0)

        XCTAssertEqual(result, .dispatched)
        XCTAssertEqual(keyboardImpl.deleteFromInputCount, 0)
    }

    func testDeleteBackwardReportsMissingDeleteFromInputSelector() {
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
        let safecracker = TheSafecracker(keyboardInput: SafecrackerKeyboardInput(
            keyboardBridgeProvider: { keyboardImpl.bridge(missingSelector: "addInputString:withFlags:") }
        ))

        let result = await safecracker.typeText("hello")

        XCTAssertEqual(
            result.diagnostic,
            KeyboardTextInjectionDiagnostic.missingSelector(
                "addInputString:withFlags:",
                strategy: UIKeyboardImplTextInjection.strategyName,
                character: "h"
            )
        )
    }

}
#endif
