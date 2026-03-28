#if canImport(UIKit)
import XCTest
@testable import AccessibilitySnapshotParser
@testable import TheInsideJob

@MainActor
final class TheBagmanTopologyTests: XCTestCase {

    private var bagman: TheBagman!

    override func setUp() {
        super.setUp()
        bagman = TheBagman(tripwire: TheTripwire())
    }

    override func tearDown() {
        bagman = nil
        super.tearDown()
    }

    // MARK: - Back Button Trait

    func testBackButtonAppearedIsTopologyChange() {
        let before = [makeElement(label: "Title", traits: .header)]
        let after = [
            makeElement(label: "Title", traits: .header),
            makeElement(label: "Back", traits: UIAccessibilityTraits.backButton),
        ]
        XCTAssertTrue(bagman.isTopologyChanged(before: before, after: after))
    }

    func testBackButtonDisappearedIsTopologyChange() {
        let before = [makeElement(label: "Back", traits: UIAccessibilityTraits.backButton)]
        let after = [makeElement(label: "Title", traits: .header)]
        XCTAssertTrue(bagman.isTopologyChanged(before: before, after: after))
    }

    func testBackButtonUnchangedIsNotTopologyChange() {
        let elements = [
            makeElement(label: "Back", traits: UIAccessibilityTraits.backButton),
            makeElement(label: "Title", traits: .header),
        ]
        XCTAssertFalse(bagman.isTopologyChanged(before: elements, after: elements))
    }

    // MARK: - Header Structure

    func testDisjointHeadersIsTopologyChange() {
        let before = [makeElement(label: "Settings", traits: .header)]
        let after = [makeElement(label: "Profile", traits: .header)]
        XCTAssertTrue(bagman.isTopologyChanged(before: before, after: after))
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
        XCTAssertFalse(bagman.isTopologyChanged(before: before, after: after))
    }

    func testEmptyHeadersBeforeIsNotTopologyChange() {
        let before = [makeElement(label: "OK", traits: .button)]
        let after = [makeElement(label: "Profile", traits: .header)]
        XCTAssertFalse(bagman.isTopologyChanged(before: before, after: after))
    }

    func testNoElementChangesIsNotTopologyChange() {
        let elements = [makeElement(label: "OK", traits: .button)]
        XCTAssertFalse(bagman.isTopologyChanged(before: elements, after: elements))
    }

    // MARK: - Helpers

    private func makeElement(
        label: String? = nil,
        traits: UIAccessibilityTraits = .none
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
            customActions: [],
            customContent: [],
            customRotors: [],
            accessibilityLanguage: nil,
            respondsToUserInteraction: false
        )
    }
}

#endif
