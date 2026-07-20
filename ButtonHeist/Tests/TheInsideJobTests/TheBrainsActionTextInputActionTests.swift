#if canImport(UIKit)
import ButtonHeistSupport
import ButtonHeistTestSupport
import XCTest
@testable import AccessibilitySnapshotParser
@_spi(ButtonHeistInternals) @testable import ThePlans
@testable import TheInsideJob
@_spi(ButtonHeistInternals) @testable import TheScore

@MainActor
extension TheBrainsActionTests {

    func testExecuteTypeTextIntoTargetFocusesWithAccessibilityActivateBeforeTyping() async throws {
        let rootView = UIView(frame: UIScreen.main.bounds)
        rootView.backgroundColor = .white

        let textField = ActionActivatingTextField(frame: CGRect(x: 48, y: 180, width: 240, height: 44))
        textField.borderStyle = .roundedRect
        textField.isAccessibilityElement = true
        textField.accessibilityLabel = "Message"
        textField.accessibilityIdentifier = "message_field"
        textField.accessibilityValue = ""
        rootView.addSubview(textField)

        let window = try installModalWindow(rootView: rootView)
        defer {
            brains.stopSemanticObservation()
            brains.tripwire.stopPulse()
            window.rootViewController?.view.accessibilityViewIsModal = false
            window.isHidden = true
        }

        let keyboardImpl = ActionTextInputKeyboardImpl(textField: textField) { [weak self] in
            self?.brains.vault.invalidateSettledObservationFromTripwire()
        }
        replaceBrains(keyboardInput: SafecrackerKeyboardInput(
            keyboardBridgeProvider: { keyboardImpl.bridge() }
        ))
        brains.tripwire.startPulse()
        await brains.tripwire.yieldFrames(3)

        let heistId: HeistId = "message_field"
        let element = AccessibilityElement.make(
            label: "Message",
            identifier: heistId.rawValue,
            traits: .textEntry,
            frame: textField.frame
        )
        let staleTextField = ActionActivatingTextField()
        installScreen(elements: [(element, heistId)], objects: [heistId: staleTextField])
        visibleObservationSource.observation = .makeForTests(
            elements: [(element, heistId)],
            objects: [heistId: textField]
        )

        XCTAssertFalse(textField.isFirstResponder)
        XCTAssertFalse(
            brains.safecracker.isKeyboardVisible,
            "targeted typing must work when an active input has no software keyboard"
        )

        let command = try HeistActionCommand.typeText(
            text: "hello",
            target: .identifier("message_field")
        ).resolve(in: .empty)
        let result = await brains.executeRuntimeAction(command)

        XCTAssertTrue(result.outcome.isSuccess, result.message ?? "type_text failed")
        XCTAssertEqual(result.method, .typeText)
        XCTAssertEqual(result.subjectEvidence?.element.identifier, heistId.rawValue)
        XCTAssertEqual(staleTextField.activationCount, 0)
        XCTAssertEqual(textField.activationCount, 1)
        XCTAssertTrue(textField.isFirstResponder)
        XCTAssertEqual(textField.text, "hello")
    }

    func testExecuteTypeTextKeepsCommittedHeistIdWhenOrdinalOrderChangesBeforeFocus() async throws {
        brains.stopSemanticObservation()
        let selectedId: HeistId = "selected_message"
        let otherId: HeistId = "other_message"
        let selectedTextField = ActionActivatingTextField(
            frame: CGRect(x: 48, y: 180, width: 240, height: 44)
        )
        let otherTextField = ActionActivatingTextField(
            frame: CGRect(x: 48, y: 240, width: 240, height: 44)
        )
        let rootView = UIView(frame: UIScreen.main.bounds)
        rootView.backgroundColor = .white
        for (textField, identifier) in [(selectedTextField, selectedId), (otherTextField, otherId)] {
            textField.isAccessibilityElement = true
            textField.accessibilityLabel = "Repeated Message"
            textField.accessibilityIdentifier = identifier.rawValue
            rootView.addSubview(textField)
        }
        let window = try installModalWindow(rootView: rootView)
        defer {
            window.rootViewController?.view.accessibilityViewIsModal = false
            window.isHidden = true
        }

        let selectedElement = AccessibilityElement.make(
            label: "Repeated Message",
            identifier: selectedId.rawValue,
            traits: .textEntry,
            frame: selectedTextField.frame
        )
        let otherElement = AccessibilityElement.make(
            label: "Repeated Message",
            identifier: otherId.rawValue,
            traits: .textEntry,
            frame: otherTextField.frame
        )
        let keyboardImpl = ActionTextInputKeyboardImpl(textField: selectedTextField) {}
        replaceBrains(keyboardInput: SafecrackerKeyboardInput(
            keyboardBridgeProvider: { keyboardImpl.bridge() }
        ))
        brains.stopSemanticObservation()
        installScreen(elements: [
            (selectedElement, selectedId),
            (otherElement, otherId),
        ])

        let resolvedTarget = try AccessibilityTarget.target(
            .label("Repeated Message"),
            ordinal: 0
        ).resolve(in: .empty)
        let actionTask = Task { @MainActor in
            await brains.actions.executeTypeText(
                text: "hello",
                target: resolvedTarget
            )
        }

        await waitForSettledSemanticWaiter(on: brains.vault)
        let reorderedScreen = InterfaceObservation.makeForTests(
            elements: [
                (otherElement, otherId),
                (selectedElement, selectedId),
            ],
            objects: [
                selectedId: selectedTextField,
                otherId: otherTextField,
            ]
        )
        _ = brains.vault.semanticObservationStream.commitVisibleObservationForTesting(reorderedScreen)
        visibleObservationSource.observation = reorderedScreen

        let result = await actionTask.value

        XCTAssertTrue(result.success, result.message ?? "type_text failed")
        XCTAssertEqual(result.resolvedElementId, selectedId)
        XCTAssertEqual(selectedTextField.activationCount, 1)
        XCTAssertEqual(otherTextField.activationCount, 0)
        XCTAssertEqual(selectedTextField.text, "hello")
    }

    func testExecuteTypeTextReportsFinalValueFromInteractionAfterState() async throws {
        let rootView = UIView(frame: UIScreen.main.bounds)
        rootView.backgroundColor = .white

        let textField = UITextField(frame: CGRect(x: 48, y: 180, width: 240, height: 44))
        textField.borderStyle = .roundedRect
        textField.isAccessibilityElement = true
        textField.accessibilityLabel = "Message"
        textField.accessibilityIdentifier = "message_field"
        textField.accessibilityValue = ""
        rootView.addSubview(textField)

        let window = try installModalWindow(rootView: rootView)
        defer {
            brains.stopSemanticObservation()
            brains.tripwire.stopPulse()
            window.rootViewController?.view.accessibilityViewIsModal = false
            window.isHidden = true
        }

        let keyboardImpl = ActionTextInputKeyboardImpl(textField: textField) { [weak self] in
            self?.brains.vault.invalidateSettledObservationFromTripwire()
        }
        replaceBrains(keyboardInput: SafecrackerKeyboardInput(
            keyboardBridgeProvider: { keyboardImpl.bridge() }
        ))
        brains.tripwire.startPulse()
        await brains.tripwire.yieldFrames(3)

        let command = try HeistActionCommand.typeText(
            text: "hello",
            target: .identifier("message_field")
        ).resolve(in: .empty)
        let result = await brains.executeRuntimeAction(command)

        XCTAssertTrue(result.outcome.isSuccess, result.message ?? "type_text failed")
        XCTAssertEqual(result.method, .typeText)
        let subjectEvidence = try XCTUnwrap(result.subjectEvidence)
        XCTAssertEqual(subjectEvidence.source, .textInputTarget)
        XCTAssertEqual(subjectEvidence.element.identifier, "message_field")
        XCTAssertEqual(textField.text, "hello")
        guard case .typeText(let value?) = result.payload else {
            XCTFail("Expected final text value payload, got \(String(describing: result.payload))")
            return
        }
        XCTAssertEqual(value, "hello")
    }

    func testExecuteTypeTextReplacingExistingReportsReplacementValueFromInteractionAfterState() async throws {
        let rootView = UIView(frame: UIScreen.main.bounds)
        rootView.backgroundColor = .white

        let textField = UITextField(frame: CGRect(x: 48, y: 180, width: 240, height: 44))
        textField.borderStyle = .roundedRect
        textField.text = "a"
        textField.isAccessibilityElement = true
        textField.accessibilityLabel = "Message"
        textField.accessibilityIdentifier = "message_field"
        textField.accessibilityValue = "a"
        rootView.addSubview(textField)

        let window = try installModalWindow(rootView: rootView)
        defer {
            brains.stopSemanticObservation()
            brains.tripwire.stopPulse()
            window.rootViewController?.view.accessibilityViewIsModal = false
            window.isHidden = true
        }

        let keyboardImpl = ActionTextInputKeyboardImpl(textField: textField) { [weak self] in
            self?.brains.vault.invalidateSettledObservationFromTripwire()
        }
        replaceBrains(keyboardInput: SafecrackerKeyboardInput(
            keyboardBridgeProvider: { keyboardImpl.bridge() }
        ))
        brains.tripwire.startPulse()
        await brains.tripwire.yieldFrames(3)

        let command = try HeistActionCommand.typeText(
            text: .replacing("b"),
            target: .identifier("message_field")
        ).resolve(in: .empty)
        let result = await brains.executeRuntimeAction(command)

        XCTAssertTrue(result.outcome.isSuccess, result.message ?? "type_text replacement failed")
        XCTAssertEqual(result.method, .typeText)
        XCTAssertEqual(result.subjectEvidence?.element.identifier, "message_field")
        XCTAssertEqual(textField.text, "b")
        guard case .typeText(let value?) = result.payload else {
            XCTFail("Expected final text value payload, got \(String(describing: result.payload))")
            return
        }
        XCTAssertEqual(value, "b")
    }

    func testExecuteTypeTextReplacingExistingWithEmptyTextClearsField() async throws {
        let rootView = UIView(frame: UIScreen.main.bounds)
        rootView.backgroundColor = .white

        let textField = UITextField(frame: CGRect(x: 48, y: 180, width: 240, height: 44))
        textField.borderStyle = .roundedRect
        textField.text = "abc"
        textField.isAccessibilityElement = true
        textField.accessibilityLabel = "Message"
        textField.accessibilityIdentifier = "message_field"
        textField.accessibilityValue = "abc"
        rootView.addSubview(textField)

        let window = try installModalWindow(rootView: rootView)
        defer {
            brains.stopSemanticObservation()
            brains.tripwire.stopPulse()
            window.rootViewController?.view.accessibilityViewIsModal = false
            window.isHidden = true
        }

        let keyboardImpl = ActionTextInputKeyboardImpl(textField: textField) { [weak self] in
            self?.brains.vault.invalidateSettledObservationFromTripwire()
        }
        replaceBrains(keyboardInput: SafecrackerKeyboardInput(
            keyboardBridgeProvider: { keyboardImpl.bridge() }
        ))
        brains.tripwire.startPulse()
        await brains.tripwire.yieldFrames(3)

        let command = try HeistActionCommand.typeText(
            text: .replacing(""),
            target: .identifier("message_field")
        ).resolve(in: .empty)
        let result = await brains.executeRuntimeAction(command)

        XCTAssertTrue(result.outcome.isSuccess, result.message ?? "type_text clear failed")
        XCTAssertEqual(result.method, .typeText)
        XCTAssertEqual(result.subjectEvidence?.element.identifier, "message_field")
        XCTAssertEqual(textField.text, "")
        guard case .typeText(let value?) = result.payload else {
            XCTFail("Expected final text value payload, got \(String(describing: result.payload))")
            return
        }
        XCTAssertEqual(value, "")
    }

    func testExecuteTypeTextWithoutActiveInputReportsFocusState() async {
        _ = brains.safecracker.dismissKeyboard()

        let result = await brains.actions.executeTypeText(
            text: "hello",
            target: nil
        )

        XCTAssertFalse(result.success)
        XCTAssertEqual(result.method, .typeText)
        XCTAssertNil(result.subjectEvidence)
        XCTAssertNil(result.resolvedElementId)
        XCTAssertDiagnostic(result.message, contains: [
            "text entry failed",
            "focus=none",
            "keyboardVisible=false",
            "activeTextInput=false",
            "try provide target for a text field",
        ])
    }

    func testExecuteTypeTextReportsKeyboardInjectionFailure() async {
        let keyboardImpl = KeyboardInjectionKeyboardImpl()
        replaceBrains(keyboardInput: SafecrackerKeyboardInput(
            keyboardBridgeProvider: { keyboardImpl.bridge(missingSelector: "addInputString:withFlags:") }
        ))

        let result = await brains.actions.executeTypeText(
            text: "hello",
            target: nil
        )

        XCTAssertFalse(result.success)
        XCTAssertEqual(result.method, .typeText)
        XCTAssertDiagnostic(result.message, contains: [
            "UIKeyboardImplTextInjection failed",
            "missing selector addInputString:withFlags:",
            "while typing \"h\"",
        ])
        XCTAssertTrue(keyboardImpl.inputStrings.isEmpty)
    }

    func testExecuteEditActionWithoutResponderReportsFocusState() async {
        _ = brains.safecracker.dismissKeyboard()

        let result = await brains.actions.executeEditAction(EditActionTarget(action: .copy))

        XCTAssertFalse(result.success)
        XCTAssertEqual(result.method, .editAction)
        XCTAssertDiagnostic(result.message, contains: [
            "edit action failed",
            "action=\"copy\"",
            "focus=none",
            "keyboardVisible=false",
            "activeTextInput=false",
            "try focus editable text before copy",
        ])
    }

    func testExecuteDeleteEditActionWithoutResponderReportsFocusState() async {
        _ = brains.safecracker.dismissKeyboard()

        let result = await brains.actions.executeEditAction(EditActionTarget(action: .delete))

        XCTAssertFalse(result.success)
        XCTAssertEqual(result.method, .editAction)
        XCTAssertDiagnostic(result.message, contains: [
            "edit action failed",
            "action=\"delete\"",
            "focus=none",
            "keyboardVisible=false",
            "activeTextInput=false",
            "try focus editable text before delete",
        ])
    }

    func testExecuteResignFirstResponderWithoutResponderReportsFocusState() async {
        _ = brains.safecracker.dismissKeyboard()

        let result = await brains.actions.executeResignFirstResponder()

        XCTAssertFalse(result.success)
        XCTAssertEqual(result.method, .dismissKeyboard)
        XCTAssertNil(result.subjectEvidence)
        XCTAssertNil(result.resolvedElementId)
        XCTAssertDiagnostic(result.message, contains: [
            "resign first responder failed",
            "focus=none",
            "keyboardVisible=false",
            "activeTextInput=false",
            "try focus a text input before dismissing the keyboard",
        ])
    }

    func testExecuteResignFirstResponderUsesReplacementObjectForCommittedHeistId() async throws {
        let rootView = UIView(frame: UIScreen.main.bounds)
        rootView.backgroundColor = .white
        let replacementTextField = ResignationTrackingTextField(
            frame: CGRect(x: 48, y: 180, width: 240, height: 44)
        )
        replacementTextField.isAccessibilityElement = true
        replacementTextField.accessibilityLabel = "Message"
        replacementTextField.accessibilityIdentifier = "message_field"
        rootView.addSubview(replacementTextField)

        let window = try installModalWindow(rootView: rootView)
        defer {
            window.rootViewController?.view.accessibilityViewIsModal = false
            window.isHidden = true
        }
        XCTAssertTrue(replacementTextField.becomeFirstResponder())

        let heistId: HeistId = "message_field"
        let element = AccessibilityElement.make(
            label: "Message",
            identifier: heistId.rawValue,
            traits: .textEntry,
            frame: replacementTextField.frame
        )
        let staleTextField = ResignationTrackingTextField(frame: replacementTextField.frame)
        brains.vault.installObservationForTesting(.makeForTests(
            elements: [(element, heistId)],
            objects: [heistId: staleTextField],
            firstResponderHeistId: heistId
        ))
        visibleObservationSource.observation = .makeForTests(
            elements: [(element, heistId)],
            objects: [heistId: replacementTextField],
            firstResponderHeistId: heistId
        )

        let result = await brains.actions.executeResignFirstResponder()

        XCTAssertTrue(result.success, result.message ?? "resign first responder failed")
        XCTAssertEqual(result.method, .dismissKeyboard)
        XCTAssertEqual(staleTextField.resignationCount, 0)
        XCTAssertEqual(replacementTextField.resignationCount, 1)
        XCTAssertFalse(replacementTextField.isFirstResponder)
        XCTAssertEqual(brains.vault.interfaceTree.firstResponderHeistId, heistId)
    }

}

#endif
