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

    // MARK: - Disabled State

    func testDisabledElementIsBlocked() {
        let element = makeElement(traits: .notEnabled)
        XCTAssertTrue(
            TheVault.Interactivity.blockedReason(element)?.contains("disabled") == true
        )
    }

    func testEnabledButtonIsInteractive() {
        let element = makeElement(traits: .button)
        XCTAssertNil(TheVault.Interactivity.blockedReason(element))
    }

    func testNotEnabledTakesPrecedence() {
        let element = makeElement(traits: [.button, .notEnabled])
        XCTAssertNotNil(TheVault.Interactivity.blockedReason(element))
    }
}

#endif
