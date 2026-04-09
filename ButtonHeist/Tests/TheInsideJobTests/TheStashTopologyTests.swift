#if canImport(UIKit)
import XCTest
@testable import AccessibilitySnapshotParser
@testable import TheInsideJob

@MainActor
final class TheStashTopologyTests: XCTestCase {

    private var bagman: TheStash!

    override func setUp() async throws {
        bagman = TheStash(tripwire: TheTripwire())
    }

    override func tearDown() async throws {
        bagman = nil
    }

    // MARK: - Back Button Trait

    func testBackButtonAppearedIsTopologyChange() {
        let before = [makeElement(label: "Title", traits: .header)]
        let after = [
            makeElement(label: "Title", traits: .header),
            makeElement(label: "Back", traits: UIAccessibilityTraits.backButton),
        ]
        XCTAssertTrue(bagman.burglar.isTopologyChanged(before: before, after: after))
    }

    func testBackButtonDisappearedIsTopologyChange() {
        let before = [makeElement(label: "Back", traits: UIAccessibilityTraits.backButton)]
        let after = [makeElement(label: "Title", traits: .header)]
        XCTAssertTrue(bagman.burglar.isTopologyChanged(before: before, after: after))
    }

    func testBackButtonUnchangedIsNotTopologyChange() {
        let elements = [
            makeElement(label: "Back", traits: UIAccessibilityTraits.backButton),
            makeElement(label: "Title", traits: .header),
        ]
        XCTAssertFalse(bagman.burglar.isTopologyChanged(before: elements, after: elements))
    }

    // MARK: - Header Structure

    func testDisjointHeadersIsTopologyChange() {
        let before = [makeElement(label: "Settings", traits: .header)]
        let after = [makeElement(label: "Profile", traits: .header)]
        XCTAssertTrue(bagman.burglar.isTopologyChanged(before: before, after: after))
    }

    func testOverlappingHeadersIsNotTopologyChange() {
        let before = [
            makeElement(label: "Settings", traits: .header),
            makeElement(label: "General", traits: .header),
        ]
        let after = [
            makeElement(label: "Settings", traits: .header),
            makeElement(label: "Privacy", traits: .header),
        ]
        XCTAssertFalse(bagman.burglar.isTopologyChanged(before: before, after: after))
    }

    func testEmptyHeadersBeforeIsNotTopologyChange() {
        let before = [makeElement(label: "OK", traits: .button)]
        let after = [makeElement(label: "Profile", traits: .header)]
        XCTAssertFalse(bagman.burglar.isTopologyChanged(before: before, after: after))
    }

    func testNoElementChangesIsNotTopologyChange() {
        let elements = [makeElement(label: "OK", traits: .button)]
        XCTAssertFalse(bagman.burglar.isTopologyChanged(before: elements, after: elements))
    }

    // MARK: - Tab Bar Selection Change

    func testTabSelectionChangedIsTopologyChange() {
        let tabBarItemTrait = UIAccessibilityTraits(rawValue: 1 << 28)
        let before = [
            makeElement(label: "Checkout", traits: [tabBarItemTrait, .selected]),
            makeElement(label: "Transactions", traits: tabBarItemTrait),
            makeElement(label: "Account", traits: tabBarItemTrait),
        ]
        let after = [
            makeElement(label: "Checkout", traits: tabBarItemTrait),
            makeElement(label: "Transactions", traits: [tabBarItemTrait, .selected]),
            makeElement(label: "Account", traits: tabBarItemTrait),
        ]
        XCTAssertTrue(bagman.burglar.isTopologyChanged(before: before, after: after))
    }

    func testSameTabReselectedIsNotTopologyChange() {
        let tabBarItemTrait = UIAccessibilityTraits(rawValue: 1 << 28)
        let elements = [
            makeElement(label: "Checkout", traits: [tabBarItemTrait, .selected]),
            makeElement(label: "Transactions", traits: tabBarItemTrait),
        ]
        XCTAssertFalse(bagman.burglar.isTopologyChanged(before: elements, after: elements))
    }

    func testNoTabBarItemsIsNotTopologyChange() {
        // Regular buttons with .selected toggling — no tabBarItem trait, not a tab switch.
        let before = [
            makeElement(label: "Option A", traits: [.button, .selected]),
            makeElement(label: "Option B", traits: .button),
        ]
        let after = [
            makeElement(label: "Option A", traits: .button),
            makeElement(label: "Option B", traits: [.button, .selected]),
        ]
        XCTAssertFalse(bagman.burglar.isTopologyChanged(before: before, after: after))
    }

    func testTabBarWithNoSelectionIsNotTopologyChange() {
        // Edge case: tab bar items present but none selected in either snapshot.
        let tabBarItemTrait = UIAccessibilityTraits(rawValue: 1 << 28)
        let elements = [
            makeElement(label: "Home", traits: tabBarItemTrait),
            makeElement(label: "Search", traits: tabBarItemTrait),
        ]
        XCTAssertFalse(bagman.burglar.isTopologyChanged(before: elements, after: elements))
    }

    // MARK: - Helpers

    private func makeElement(
        label: String? = nil,
        identifier: String? = nil,
        traits: UIAccessibilityTraits = .none
    ) -> AccessibilityElement {
        AccessibilityElement(
            description: label ?? "",
            label: label,
            value: nil,
            traits: traits,
            identifier: identifier,
            hint: nil,
            userInputLabels: nil,
            shape: .frame(.zero),
            activationPoint: .zero,
            usesDefaultActivationPoint: true,
            customActions: [],
            customContent: [],
            customRotors: [],
            accessibilityLanguage: nil,
            respondsToUserInteraction: false
        )
    }
}

#endif
