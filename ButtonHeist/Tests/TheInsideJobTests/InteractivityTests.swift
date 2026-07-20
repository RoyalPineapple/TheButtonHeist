#if canImport(UIKit)
import XCTest
@testable import AccessibilitySnapshotParser
@testable import TheInsideJob
@testable import TheScore

private final class ActivationOverrideView: UIView {
    override func accessibilityActivate() -> Bool {
        true
    }
}

private final class ActivationBlockView: UIView {
    override var accessibilityActivateBlock: (() -> Bool)? {
        get { { true } }
        set { }
    }
}

@MainActor
final class InteractivityTests: XCTestCase {

    // MARK: - Helpers

    private func makeElement(
        label: String? = nil,
        traits: UIAccessibilityTraits = [],
        customActions: [String] = [],
        respondsToUserInteraction: Bool = false
    ) -> AccessibilityElement {
        .make(
            label: label,
            traits: traits,
            customActions: customActions.map(AccessibilityElement.CustomAction.init(name:)),
            respondsToUserInteraction: respondsToUserInteraction
        )
    }

    // MARK: - isInteractive

    func testRespondsToUserInteractionIsInteractive() {
        let element = makeElement(respondsToUserInteraction: true)
        XCTAssertTrue(TheVault.Interactivity.isInteractive(element: element))
    }

    func testActivationBlockIsDetectedAsImplementationWithoutChangingSemanticInteractivity() {
        let object = ActivationBlockView()
        let element = makeElement(label: "Plain")

        XCTAssertFalse(TheVault.Interactivity.isInteractive(element: element))
        XCTAssertTrue(TheVault.Interactivity.implementsAccessibilityActivation(object))
    }

    func testAccessibilityActivateOverrideIsDetectedAsImplementationWithoutChangingSemanticInteractivity() {
        let element = makeElement(label: "Plain")
        let object = ActivationOverrideView()

        XCTAssertFalse(TheVault.Interactivity.isInteractive(element: element))
        XCTAssertTrue(TheVault.Interactivity.implementsAccessibilityActivation(object))
    }

    func testPlainObjectWithoutActivationSignalIsNotInteractive() {
        let element = makeElement(label: "Plain")
        let object = UIView()

        XCTAssertFalse(TheVault.Interactivity.isInteractive(element: element))
        XCTAssertFalse(TheVault.Interactivity.implementsAccessibilityActivation(object))
    }

    func testAdjustableTraitIsInteractive() {
        let element = makeElement(traits: .adjustable)
        XCTAssertTrue(TheVault.Interactivity.isInteractive(element: element))
    }

    func testCustomActionsIsInteractive() {
        let element = makeElement(customActions: ["Delete"])
        XCTAssertTrue(TheVault.Interactivity.isInteractive(element: element))
    }

    func testButtonTraitIsInteractive() {
        let element = makeElement(traits: .button)
        XCTAssertTrue(TheVault.Interactivity.isInteractive(element: element))
    }

    func testLinkTraitIsInteractive() {
        let element = makeElement(traits: .link)
        XCTAssertTrue(TheVault.Interactivity.isInteractive(element: element))
    }

    func testSearchFieldTraitIsInteractive() {
        let element = makeElement(traits: .searchField)
        XCTAssertTrue(TheVault.Interactivity.isInteractive(element: element))
    }

    func testKeyboardKeyTraitIsInteractive() {
        let element = makeElement(traits: .keyboardKey)
        XCTAssertTrue(TheVault.Interactivity.isInteractive(element: element))
    }

    func testBackButtonTraitIsInteractive() {
        let element = makeElement(traits: UIAccessibilityTraits.fromNames(["backButton"]))
        XCTAssertTrue(TheVault.Interactivity.isInteractive(element: element))
    }

    func testSwitchButtonTraitIsInteractive() {
        let element = makeElement(traits: UIAccessibilityTraits.fromNames(["switchButton"]))
        XCTAssertTrue(TheVault.Interactivity.isInteractive(element: element))
    }

    func testStaticTextNotInteractive() {
        let element = makeElement(label: "Hello", traits: .staticText)
        XCTAssertFalse(TheVault.Interactivity.isInteractive(element: element))
    }

    func testNoTraitsNoInteraction() {
        let element = makeElement(label: "Plain")
        XCTAssertFalse(TheVault.Interactivity.isInteractive(element: element))
    }

    // MARK: - checkInteractivity

    func testDisabledElementIsBlocked() {
        let element = makeElement(traits: .notEnabled)
        let result = TheVault.Interactivity.checkInteractivity(element)
        switch result {
        case .blocked(let reason):
            XCTAssertTrue(reason.contains("disabled"))
        case .interactive:
            XCTFail("Expected blocked for notEnabled trait")
        }
    }

    func testEnabledButtonIsInteractive() {
        let element = makeElement(traits: .button)
        let result = TheVault.Interactivity.checkInteractivity(element)
        switch result {
        case .interactive:
            break
        case .blocked(let reason):
            XCTFail("Expected interactive, got blocked: \(reason)")
        }
    }

    func testStaticOnlyElementStillReturnsInteractive() throws {
        let element = makeElement(traits: .staticText)
        let result = TheVault.Interactivity.checkInteractivity(element)
        switch result {
        case .interactive(let warning):
            let warningText = try XCTUnwrap(warning, "Static-only element should surface an advisory warning")
            XCTAssertTrue(warningText.contains("proceeding as VoiceOver would"))
        case .blocked(let reason):
            XCTFail("Expected interactive (with warning), got blocked: \(reason)")
        }
    }

    func testActivationOverrideDoesNotEmitStaticWarning() {
        let element = makeElement(label: "Plain")
        let object = ActivationOverrideView()

        let result = TheVault.Interactivity.checkInteractivity(element, object: object)

        switch result {
        case .interactive(let warning):
            XCTAssertNil(warning, "Default activation support should be treated as a real interaction signal")
        case .blocked(let reason):
            XCTFail("Expected interactive, got blocked: \(reason)")
        }
    }

    func testInteractiveElementHasNoWarning() {
        let element = makeElement(traits: .button)
        let result = TheVault.Interactivity.checkInteractivity(element)
        switch result {
        case .interactive(let warning):
            XCTAssertNil(warning, "Fully interactive element should not carry a warning")
        case .blocked(let reason):
            XCTFail("Expected interactive, got blocked: \(reason)")
        }
    }

    func testNotEnabledTakesPrecedence() {
        let element = makeElement(traits: [.button, .notEnabled])
        let result = TheVault.Interactivity.checkInteractivity(element)
        switch result {
        case .blocked:
            break
        case .interactive:
            XCTFail("Expected blocked — notEnabled should override button trait")
        }
    }
}

#endif
