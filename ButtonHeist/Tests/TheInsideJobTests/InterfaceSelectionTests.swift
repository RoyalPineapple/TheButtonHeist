#if canImport(UIKit)
import ButtonHeistTestSupport
import XCTest
import ThePlans

import AccessibilitySnapshotModel
import TheScore
@testable import TheInsideJob

final class InterfaceSelectorTests: XCTestCase {

    func testElementSubtreeSelectsMatchingLeaf() throws {
        let interface = try select(InterfaceQuery(
            subtree: .identifier("submit_button")
        ))
        XCTAssertEqual(interface.projectedElements.map(\.label), ["Submit"])
    }

    func testElementSubtreeSelectsPredicateLeaf() throws {
        let interface = try select(InterfaceQuery(
            subtree: .identifier("cancel_button")
        ))
        XCTAssertEqual(interface.projectedElements.map(\.label), ["Cancel"])
        XCTAssertEqual(interface.annotations.elements.count, 1)
        XCTAssertTrue(interface.annotations.containers.isEmpty)
    }

    func testCanonicalElementOrdinalSelectsOnce() throws {
        let interface = try select(InterfaceQuery(
            subtree: .predicate(.traits([.button]), ordinal: 1)
        ))

        XCTAssertEqual(interface.projectedElements.map(\.label), ["Cancel"])
    }

    func testContainerSubtreeSelectsMatchingContainer() throws {
        let interface = try select(InterfaceQuery(
            subtree: .container(.identifier("actions"))
        ))
        XCTAssertEqual(interface.projectedElements.map(\.label), ["Submit", "Cancel"])
    }

    func testCanonicalContainerTargetSelectsMatchingContainerSubtree() throws {
        let interface = try select(InterfaceQuery(
            subtree: .container(.identifier("actions"))
        ))

        XCTAssertEqual(interface.projectedElements.map(\.label), ["Submit", "Cancel"])
    }

    func testCanonicalWithinTargetSelectsDescendantElementSubtree() throws {
        let interface = try select(InterfaceQuery(
            subtree: .within(
                container: .identifier("actions"),
                target: .identifier("cancel_button")
            )
        ))

        XCTAssertEqual(interface.projectedElements.map(\.label), ["Cancel"])
    }

    func testAmbiguousSubtreeReportsTypedCandidates() {
        XCTAssertThrowsError(try select(
            InterfaceQuery(subtree: .container(.label("Actions"))),
            in: Self.makeInterface(includeDuplicateGroup: true)
        )) { error in
            guard case InterfaceSelectionError.ambiguousSubtree(let count, let candidates) = error else {
                XCTFail("Expected ambiguousSubtree, got \(error)")
                return
            }
            XCTAssertEqual(count, 2)
            XCTAssertEqual(candidates.count, 2)
            XCTAssertTrue(candidates[0].contains("semantic_actions__actions"))
            XCTAssertTrue(candidates[1].contains("semantic_actions__secondary_actions"))
        }
    }

    func testOrdinalDisambiguatesSubtreeCandidates() throws {
        let interface = try select(
            InterfaceQuery(subtree: .container(.label("Actions"), ordinal: 1)),
            in: Self.makeInterface(includeDuplicateGroup: true)
        )
        XCTAssertEqual(interface.projectedElements.map(\.label), ["Archive"])
    }

    func testOutOfRangeOrdinalReportsCandidateCardinality() {
        XCTAssertThrowsError(try select(
            InterfaceQuery(subtree: .container(.label("Actions"), ordinal: 2)),
            in: Self.makeInterface(includeDuplicateGroup: true)
        )) { error in
            guard case InterfaceSelectionError.subtreeOrdinalOutOfRange(let ordinal, let count, let candidates) = error else {
                XCTFail("Expected subtreeOrdinalOutOfRange, got \(error)")
                return
            }
            XCTAssertEqual(ordinal, 2)
            XCTAssertEqual(count, 2)
            XCTAssertEqual(candidates.count, 2)
        }
    }

    func testMissingSubtreeReportsTypedError() {
        XCTAssertThrowsError(try select(InterfaceQuery(
            subtree: .container(.identifier("missing"))
        ))) { error in
            XCTAssertEqual(error as? InterfaceSelectionError, .subtreeNotFound)
        }
    }

    private func select(
        _ query: InterfaceQuery,
        in interface: Interface = InterfaceSelectorTests.makeInterface()
    ) throws(InterfaceSelectionError) -> Interface {
        try InterfaceSelector(interface: interface).select(query)
    }

    private static func makeInterface(includeDuplicateGroup: Bool = false) -> Interface {
        let header = makeElement(label: "Menu", traits: [.header])
        let submit = makeElement(label: "Submit", identifier: "submit_button", traits: [.button])
        let cancel = makeElement(label: "Cancel", identifier: "cancel_button", traits: [.button])
        let footer = makeElement(label: "Footer")
        let primaryGroup = makeActionsContainer(containerName: "semantic_actions__actions")

        var nodes: [TestInterfaceNode] = [
            .element(header),
            .container(primaryGroup, containerName: "semantic_actions__actions", children: [
                .element(submit),
                .element(cancel),
            ]),
            .element(footer),
        ]

        if includeDuplicateGroup {
            let archive = makeElement(label: "Archive", identifier: "archive_button", traits: [.button])
            let secondaryGroup = makeActionsContainer(containerName: "semantic_actions__secondary_actions", y: 160)
            nodes.insert(
                .container(
                    secondaryGroup,
                    containerName: "semantic_actions__secondary_actions",
                    children: [.element(archive)]
                ),
                at: 2
            )
        }

        return makeTestInterface(nodes: nodes)
    }

    private static func makeActionsContainer(containerName _: String, y: Double = 40) -> AccessibilityContainer {
        AccessibilityContainer(
            type: .semanticGroup(label: "Actions", value: nil), identifier: "actions",
            frame: AccessibilityRect(x: 0, y: y, width: 200, height: 100)
        )
    }

    private static func makeElement(
        label: String,
        identifier: String? = nil,
        traits: [HeistTrait] = []
    ) -> HeistElement {
        HeistElement(
            description: label,
            label: label,
            value: nil,
            identifier: identifier,
            traits: traits,
            frameX: 0,
            frameY: 0,
            frameWidth: 100,
            frameHeight: 44,
            actions: []
        )
    }
}
#endif
