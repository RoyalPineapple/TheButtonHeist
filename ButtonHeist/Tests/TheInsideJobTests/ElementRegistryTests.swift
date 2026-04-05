#if canImport(UIKit)
import XCTest
@testable import AccessibilitySnapshotParser
@testable import TheInsideJob
@testable import TheScore

@MainActor
final class ElementRegistryTests: XCTestCase {

    // MARK: - Helpers

    private func makeElement(
        label: String? = nil,
        identifier: String? = nil
    ) -> AccessibilityElement {
        AccessibilityElement(
            description: label ?? "",
            label: label,
            value: nil,
            traits: [],
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

    // MARK: - apply

    func testApplyInsertsNewElements() {
        var registry = TheBagman.ElementRegistry()
        let elementA = makeElement(label: "A")
        let elementB = makeElement(label: "B")

        registry.apply(
            parsedElements: [elementA, elementB],
            heistIds: ["id-a", "id-b"],
            contexts: [:]
        )

        XCTAssertEqual(registry.elements.count, 2)
        XCTAssertNotNil(registry.elements["id-a"])
        XCTAssertNotNil(registry.elements["id-b"])
    }

    func testApplyUpdatesExistingElement() {
        var registry = TheBagman.ElementRegistry()
        let elementV1 = makeElement(label: "Old")
        let elementV2 = makeElement(label: "New")

        registry.apply(
            parsedElements: [elementV1],
            heistIds: ["id-a"],
            contexts: [:]
        )
        registry.apply(
            parsedElements: [elementV2],
            heistIds: ["id-a"],
            contexts: [:]
        )

        XCTAssertEqual(registry.elements.count, 1)
        XCTAssertEqual(registry.elements["id-a"]?.element.label, "New")
    }

    func testApplyRebuildsViewportIds() {
        var registry = TheBagman.ElementRegistry()
        let elementA = makeElement(label: "A")
        let elementB = makeElement(label: "B")

        registry.apply(
            parsedElements: [elementA, elementB],
            heistIds: ["id-a", "id-b"],
            contexts: [:]
        )
        XCTAssertEqual(registry.viewportIds, ["id-a", "id-b"])

        registry.apply(
            parsedElements: [elementB],
            heistIds: ["id-b"],
            contexts: [:]
        )
        XCTAssertEqual(registry.viewportIds, ["id-b"])
    }

    func testApplyBuildsReverseIndex() {
        var registry = TheBagman.ElementRegistry()
        let element = makeElement(label: "Submit")

        registry.apply(
            parsedElements: [element],
            heistIds: ["submit-button"],
            contexts: [:]
        )

        XCTAssertEqual(registry.reverseIndex[element], "submit-button")
    }

    func testApplyPreservesOffScreenElements() {
        var registry = TheBagman.ElementRegistry()
        let elementA = makeElement(label: "A")
        let elementB = makeElement(label: "B")

        registry.apply(
            parsedElements: [elementA, elementB],
            heistIds: ["id-a", "id-b"],
            contexts: [:]
        )

        registry.apply(
            parsedElements: [elementB],
            heistIds: ["id-b"],
            contexts: [:]
        )

        XCTAssertEqual(registry.elements.count, 2, "Off-screen element should persist")
        XCTAssertNotNil(registry.elements["id-a"])
    }

    // MARK: - clear

    func testClearRemovesEverything() {
        var registry = TheBagman.ElementRegistry()
        let element = makeElement(label: "X")

        registry.apply(
            parsedElements: [element],
            heistIds: ["id-x"],
            contexts: [:]
        )
        registry.clear()

        XCTAssertTrue(registry.elements.isEmpty)
        XCTAssertTrue(registry.viewportIds.isEmpty)
        XCTAssertTrue(registry.reverseIndex.isEmpty)
    }

    // MARK: - clearScreen

    func testClearScreenRemovesElementsAndReverseIndex() {
        var registry = TheBagman.ElementRegistry()
        let element = makeElement(label: "X")

        registry.apply(
            parsedElements: [element],
            heistIds: ["id-x"],
            contexts: [:]
        )
        registry.clearScreen()

        XCTAssertTrue(registry.elements.isEmpty)
        XCTAssertTrue(registry.reverseIndex.isEmpty)
    }

    // MARK: - prune

    func testPruneKeepsOnlySpecifiedIds() {
        var registry = TheBagman.ElementRegistry()
        let elementA = makeElement(label: "A")
        let elementB = makeElement(label: "B")
        let elementC = makeElement(label: "C")

        registry.apply(
            parsedElements: [elementA, elementB, elementC],
            heistIds: ["id-a", "id-b", "id-c"],
            contexts: [:]
        )
        registry.prune(keeping: ["id-a", "id-c"])

        XCTAssertEqual(registry.elements.count, 2)
        XCTAssertNotNil(registry.elements["id-a"])
        XCTAssertNil(registry.elements["id-b"])
        XCTAssertNotNil(registry.elements["id-c"])
    }

    func testPruneWithEmptySetRemovesAll() {
        var registry = TheBagman.ElementRegistry()
        let element = makeElement(label: "A")

        registry.apply(
            parsedElements: [element],
            heistIds: ["id-a"],
            contexts: [:]
        )
        registry.prune(keeping: [])

        XCTAssertTrue(registry.elements.isEmpty)
    }
}

#endif
