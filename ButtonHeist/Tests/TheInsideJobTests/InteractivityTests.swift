#if canImport(UIKit)
import XCTest
@testable import AccessibilitySnapshotParser
@testable import TheInsideJob
@testable import TheScore

@MainActor
final class InteractivityTests: XCTestCase {

    // MARK: - Helpers

    private func makeElement(
        label: String? = nil,
        traits: UIAccessibilityTraits = [],
        customActions: [AccessibilityElement.CustomAction] = [],
        respondsToUserInteraction: Bool = false
    ) -> AccessibilityElement {
        AccessibilityElement(
            description: label ?? "",
            label: label,
            value: nil,
            traits: traits,
            identifier: nil,
            hint: nil,
            userInputLabels: nil,
            shape: .frame(.zero),
            activationPoint: .zero,
            usesDefaultActivationPoint: true,
            customActions: customActions,
            customContent: [],
            customRotors: [],
            accessibilityLanguage: nil,
            respondsToUserInteraction: respondsToUserInteraction
        )
    }

    // MARK: - isInteractive

    func testRespondsToUserInteractionIsInteractive() {
        let element = makeElement(respondsToUserInteraction: true)
        XCTAssertTrue(TheStash.Interactivity.isInteractive(element: element))
    }

    func testAdjustableTraitIsInteractive() {
        let element = makeElement(traits: .adjustable)
        XCTAssertTrue(TheStash.Interactivity.isInteractive(element: element))
    }

    func testCustomActionsIsInteractive() {
        let element = makeElement(customActions: [.init(name: "Delete")])
        XCTAssertTrue(TheStash.Interactivity.isInteractive(element: element))
    }

    func testButtonTraitIsInteractive() {
        let element = makeElement(traits: .button)
        XCTAssertTrue(TheStash.Interactivity.isInteractive(element: element))
    }

    func testLinkTraitIsInteractive() {
        let element = makeElement(traits: .link)
        XCTAssertTrue(TheStash.Interactivity.isInteractive(element: element))
    }

    func testSearchFieldTraitIsInteractive() {
        let element = makeElement(traits: .searchField)
        XCTAssertTrue(TheStash.Interactivity.isInteractive(element: element))
    }

    func testKeyboardKeyTraitIsInteractive() {
        let element = makeElement(traits: .keyboardKey)
        XCTAssertTrue(TheStash.Interactivity.isInteractive(element: element))
    }

    func testBackButtonTraitIsInteractive() {
        let element = makeElement(traits: UIAccessibilityTraits.fromNames(["backButton"]))
        XCTAssertTrue(TheStash.Interactivity.isInteractive(element: element))
    }

    func testSwitchButtonTraitIsInteractive() {
        let element = makeElement(traits: UIAccessibilityTraits.fromNames(["switchButton"]))
        XCTAssertTrue(TheStash.Interactivity.isInteractive(element: element))
    }

    func testStaticTextNotInteractive() {
        let element = makeElement(label: "Hello", traits: .staticText)
        XCTAssertFalse(TheStash.Interactivity.isInteractive(element: element))
    }

    func testNoTraitsNoInteraction() {
        let element = makeElement(label: "Plain")
        XCTAssertFalse(TheStash.Interactivity.isInteractive(element: element))
    }

    // MARK: - checkInteractivity

    func testDisabledElementIsBlocked() {
        let element = makeElement(traits: .notEnabled)
        let result = TheStash.Interactivity.checkInteractivity(element)
        switch result {
        case .blocked(let reason):
            XCTAssertTrue(reason.contains("disabled"))
        case .interactive(_):
            XCTFail("Expected blocked for notEnabled trait")
        }
    }

    func testEnabledButtonIsInteractive() {
        let element = makeElement(traits: .button)
        let result = TheStash.Interactivity.checkInteractivity(element)
        switch result {
        case .interactive(_):
            break
        case .blocked(let reason):
            XCTFail("Expected interactive, got blocked: \(reason)")
        }
    }

    func testStaticOnlyElementStillReturnsInteractive() {
        let element = makeElement(traits: .staticText)
        let result = TheStash.Interactivity.checkInteractivity(element)
        switch result {
        case .interactive(let warning):
            XCTAssertNotNil(warning, "Static-only element should surface an advisory warning")
            XCTAssertTrue(warning?.contains("static traits") ?? false)
        case .blocked(let reason):
            XCTFail("Expected interactive (with warning), got blocked: \(reason)")
        }
    }

    func testInteractiveElementHasNoWarning() {
        let element = makeElement(traits: .button)
        let result = TheStash.Interactivity.checkInteractivity(element)
        switch result {
        case .interactive(let warning):
            XCTAssertNil(warning, "Fully interactive element should not carry a warning")
        case .blocked(let reason):
            XCTFail("Expected interactive, got blocked: \(reason)")
        }
    }

    func testNotEnabledTakesPrecedence() {
        let element = makeElement(traits: [.button, .notEnabled])
        let result = TheStash.Interactivity.checkInteractivity(element)
        switch result {
        case .blocked:
            break
        case .interactive(_):
            XCTFail("Expected blocked — notEnabled should override button trait")
        }
    }
}

#endif
