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
        XCTAssertTrue(isTopologyChanged(before: before, after: after))
    }

    func testBackButtonDisappearedIsTopologyChange() {
        let before = [makeElement(label: "Back", traits: UIAccessibilityTraits.backButton)]
        let after = [makeElement(label: "Title", traits: .header)]
        XCTAssertTrue(isTopologyChanged(before: before, after: after))
    }

    func testBackButtonUnchangedIsNotTopologyChange() {
        let elements = [
            makeElement(label: "Back", traits: UIAccessibilityTraits.backButton),
            makeElement(label: "Title", traits: .header),
        ]
        XCTAssertFalse(isTopologyChanged(before: elements, after: elements))
    }

    // MARK: - Header Structure

    func testDisjointHeadersIsTopologyChange() {
        let before = [makeElement(label: "Settings", traits: .header)]
        let after = [makeElement(label: "Profile", traits: .header)]
        XCTAssertTrue(isTopologyChanged(before: before, after: after))
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
        XCTAssertFalse(isTopologyChanged(before: before, after: after))
    }

    func testEmptyHeadersBeforeIsNotTopologyChange() {
        let before = [makeElement(label: "OK", traits: .button)]
        let after = [makeElement(label: "Profile", traits: .header)]
        XCTAssertFalse(isTopologyChanged(before: before, after: after))
    }

    func testNoElementChangesIsNotTopologyChange() {
        let elements = [makeElement(label: "OK", traits: .button)]
        XCTAssertFalse(isTopologyChanged(before: elements, after: elements))
    }

    // MARK: - Tab Bar Content Change

    func testTabSwitchContentReplacedIsTopologyChange() {
        // Tab bar container with 3 tabs; content area fully replaced.
        let tabElements = ["Checkout", "Transactions", "Account"].map { label in
            makeElement(label: label, traits: .button)
        }
        let tabBarContainer = AccessibilityContainer(type: .tabBar, frame: .zero)

        let checkoutContent = (1...8).map { makeElement(label: "Item \($0)") }
        let transactionsContent = (1...10).map { makeElement(label: "Transaction \($0)") }

        let beforeHierarchy: [AccessibilityHierarchy] = [
            .container(tabBarContainer, children: tabElements.enumerated().map { .element($1, traversalIndex: $0) }),
        ] + checkoutContent.enumerated().map { .element($1, traversalIndex: 100 + $0) }

        let afterHierarchy: [AccessibilityHierarchy] = [
            .container(tabBarContainer, children: tabElements.enumerated().map { .element($1, traversalIndex: $0) }),
        ] + transactionsContent.enumerated().map { .element($1, traversalIndex: 100 + $0) }

        let beforeElements = beforeHierarchy.sortedElements
        let afterElements = afterHierarchy.sortedElements

        XCTAssertTrue(bagman.burglar.isTopologyChanged(
            before: beforeElements, after: afterElements,
            beforeHierarchy: beforeHierarchy, afterHierarchy: afterHierarchy
        ))
    }

    func testSameTabContentUnchangedIsNotTopologyChange() {
        let tabElements = ["Home", "Search"].map { makeElement(label: $0, traits: .button) }
        let tabBarContainer = AccessibilityContainer(type: .tabBar, frame: .zero)
        let content = (1...6).map { makeElement(label: "Row \($0)") }

        let hierarchy: [AccessibilityHierarchy] = [
            .container(tabBarContainer, children: tabElements.enumerated().map { .element($1, traversalIndex: $0) }),
        ] + content.enumerated().map { .element($1, traversalIndex: 100 + $0) }

        let elements = hierarchy.sortedElements

        XCTAssertFalse(bagman.burglar.isTopologyChanged(
            before: elements, after: elements,
            beforeHierarchy: hierarchy, afterHierarchy: hierarchy
        ))
    }

    func testNoTabBarContainerIsNotTopologyChange() {
        // Content fully replaced but no .tabBar container — not a tab switch.
        let beforeContent = (1...8).map { makeElement(label: "Old \($0)") }
        let afterContent = (1...8).map { makeElement(label: "New \($0)") }

        let beforeHierarchy = beforeContent.enumerated().map {
            AccessibilityHierarchy.element($1, traversalIndex: $0)
        }
        let afterHierarchy = afterContent.enumerated().map {
            AccessibilityHierarchy.element($1, traversalIndex: $0)
        }

        XCTAssertFalse(bagman.burglar.isTopologyChanged(
            before: beforeContent, after: afterContent,
            beforeHierarchy: beforeHierarchy, afterHierarchy: afterHierarchy
        ))
    }

    func testNestedTabBarContentReplacedIsTopologyChange() {
        // UIKit-style: .tabBar container nested inside a semantic group (window container).
        let tabElements = ["Home", "Settings"].map { makeElement(label: $0, traits: .button) }
        let tabBarContainer = AccessibilityContainer(type: .tabBar, frame: .zero)
        let windowContainer = AccessibilityContainer(
            type: .semanticGroup(label: nil, value: nil, identifier: nil), frame: .zero
        )

        let homeContent = (1...6).map { makeElement(label: "Home item \($0)") }
        let settingsContent = (1...6).map { makeElement(label: "Setting \($0)") }

        let tabBarNode: AccessibilityHierarchy = .container(
            tabBarContainer,
            children: tabElements.enumerated().map { .element($1, traversalIndex: $0) }
        )
        let beforeHierarchy: [AccessibilityHierarchy] = [
            .container(windowContainer, children: [tabBarNode]
                + homeContent.enumerated().map { .element($1, traversalIndex: 10 + $0) }),
        ]
        let afterHierarchy: [AccessibilityHierarchy] = [
            .container(windowContainer, children: [tabBarNode]
                + settingsContent.enumerated().map { .element($1, traversalIndex: 10 + $0) }),
        ]

        XCTAssertTrue(bagman.burglar.isTopologyChanged(
            before: beforeHierarchy.sortedElements, after: afterHierarchy.sortedElements,
            beforeHierarchy: beforeHierarchy, afterHierarchy: afterHierarchy
        ))
    }

    func testScrollWithTabBarIsNotTopologyChange() {
        // Tab bar present, but only a few content elements replaced (scroll).
        let tabElements = ["Home", "Search"].map { makeElement(label: $0, traits: .button) }
        let tabBarContainer = AccessibilityContainer(type: .tabBar, frame: .zero)
        let persistent = (1...8).map { makeElement(label: "Row \($0)") }
        let scrolledOff = [makeElement(label: "Row 9"), makeElement(label: "Row 10")]
        let scrolledIn = [makeElement(label: "Row 11"), makeElement(label: "Row 12")]

        let tabNodes: [AccessibilityHierarchy] = [
            .container(tabBarContainer, children: tabElements.enumerated().map { .element($1, traversalIndex: $0) }),
        ]
        let beforeHierarchy = tabNodes + (persistent + scrolledOff).enumerated().map {
            AccessibilityHierarchy.element($1, traversalIndex: 100 + $0)
        }
        let afterHierarchy = tabNodes + (persistent + scrolledIn).enumerated().map {
            AccessibilityHierarchy.element($1, traversalIndex: 100 + $0)
        }

        XCTAssertFalse(bagman.burglar.isTopologyChanged(
            before: beforeHierarchy.sortedElements, after: afterHierarchy.sortedElements,
            beforeHierarchy: beforeHierarchy, afterHierarchy: afterHierarchy
        ))
    }

    // MARK: - Helpers

    /// Convenience for tests that don't need hierarchy (back button, header checks).
    private func isTopologyChanged(
        before: [AccessibilityElement],
        after: [AccessibilityElement]
    ) -> Bool {
        bagman.burglar.isTopologyChanged(
            before: before, after: after,
            beforeHierarchy: [], afterHierarchy: []
        )
    }

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
