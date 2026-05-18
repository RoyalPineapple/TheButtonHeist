#if canImport(UIKit)
import XCTest

import TheScore
@testable import TheInsideJob

final class InterfaceSelectorTests: XCTestCase {

    func testMatcherSelectsMatchingLeaves() throws {
        let interface = try select(InterfaceQuery(
            matcher: ElementMatcher(label: "Submit")
        ))
        XCTAssertEqual(interface.elements.map(\.heistId), ["submit"])
    }

    func testElementIdsSelectMatchingLeaves() throws {
        let interface = try select(InterfaceQuery(elementIds: ["cancel"]))
        XCTAssertEqual(interface.elements.map(\.heistId), ["cancel"])
    }

    func testElementSubtreeSelectsMatchingLeaf() throws {
        let interface = try select(InterfaceQuery(
            subtree: .element(ElementMatcher(identifier: "submit_button"))
        ))
        XCTAssertEqual(interface.elements.map(\.heistId), ["submit"])
    }

    func testContainerSubtreeSelectsMatchingContainer() throws {
        let interface = try select(InterfaceQuery(
            subtree: .container(ContainerMatcher(stableId: "semantic_actions__actions"))
        ))
        XCTAssertEqual(interface.elements.map(\.heistId), ["submit", "cancel"])
    }

    func testAmbiguousSubtreeReportsTypedCandidates() {
        XCTAssertThrowsError(try select(
            InterfaceQuery(subtree: .container(ContainerMatcher(label: "Actions"))),
            in: makeInterface(includeDuplicateGroup: true)
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
            InterfaceQuery(subtree: .container(ContainerMatcher(label: "Actions"), ordinal: 1)),
            in: makeInterface(includeDuplicateGroup: true)
        )
        XCTAssertEqual(interface.elements.map(\.heistId), ["archive"])
    }

    func testMissingSubtreeReportsTypedError() {
        XCTAssertThrowsError(try select(InterfaceQuery(
            subtree: .container(ContainerMatcher(stableId: "missing"))
        ))) { error in
            XCTAssertEqual(error as? InterfaceSelectionError, .subtreeNotFound)
        }
    }

    private func select(
        _ query: InterfaceQuery,
        in interface: Interface = makeInterface()
    ) throws(InterfaceSelectionError) -> Interface {
        try InterfaceSelector(interface: interface).select(query)
    }

    private static func makeInterface(includeDuplicateGroup: Bool = false) -> Interface {
        let header = makeElement("title", label: "Menu", traits: [.header])
        let submit = makeElement("submit", label: "Submit", identifier: "submit_button", traits: [.button])
        let cancel = makeElement("cancel", label: "Cancel", identifier: "cancel_button", traits: [.button])
        let footer = makeElement("footer", label: "Footer")
        let primaryGroup = makeActionsContainer(stableId: "semantic_actions__actions")

        var tree: [InterfaceNode] = [
            .element(header),
            .container(primaryGroup, children: [.element(submit), .element(cancel)]),
            .element(footer),
        ]

        if includeDuplicateGroup {
            let archive = makeElement("archive", label: "Archive", identifier: "archive_button", traits: [.button])
            let secondaryGroup = makeActionsContainer(stableId: "semantic_actions__secondary_actions", y: 160)
            tree.insert(.container(secondaryGroup, children: [.element(archive)]), at: 2)
        }

        return Interface(timestamp: Date(timeIntervalSince1970: 0), tree: tree)
    }

    private static func makeActionsContainer(stableId: String, y: Double = 40) -> ContainerInfo {
        ContainerInfo(
            type: .semanticGroup(label: "Actions", value: nil, identifier: "actions"),
            stableId: stableId,
            frameX: 0,
            frameY: y,
            frameWidth: 200,
            frameHeight: 100
        )
    }

    private static func makeElement(
        _ heistId: String,
        label: String,
        identifier: String? = nil,
        traits: [HeistTrait] = []
    ) -> HeistElement {
        HeistElement(
            heistId: heistId,
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
