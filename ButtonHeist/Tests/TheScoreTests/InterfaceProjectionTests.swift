import XCTest

import TheScore

final class InterfaceProjectionTests: XCTestCase {

    func testMatcherProjectsMatchingLeaves() {
        let projection = makeInterface().projecting(InterfaceQuery(
            matcher: ElementMatcher(label: "Submit")
        ))

        XCTAssertNil(projection.error)
        XCTAssertEqual(projection.filteredFrom, 4)
        XCTAssertEqual(projection.interface.elements.map(\.heistId), ["submit"])
    }

    func testElementIdsProjectMatchingLeaves() {
        let projection = makeInterface().projecting(InterfaceQuery(elementIds: ["cancel"]))

        XCTAssertNil(projection.error)
        XCTAssertEqual(projection.filteredFrom, 4)
        XCTAssertEqual(projection.interface.elements.map(\.heistId), ["cancel"])
    }

    func testElementSubtreeProjectsMatchingLeaf() {
        let projection = makeInterface().projecting(InterfaceQuery(
            subtree: .element(ElementMatcher(identifier: "submit_button"))
        ))

        XCTAssertNil(projection.error)
        XCTAssertEqual(projection.filteredFrom, 4)
        XCTAssertEqual(projection.interface.elements.map(\.heistId), ["submit"])
    }

    func testContainerSubtreeProjectsMatchingContainer() {
        let projection = makeInterface().projecting(InterfaceQuery(
            subtree: .container(ContainerMatcher(stableId: "semantic_actions__actions"))
        ))

        XCTAssertNil(projection.error)
        XCTAssertEqual(projection.filteredFrom, 4)
        XCTAssertEqual(projection.interface.elements.map(\.heistId), ["submit", "cancel"])
    }

    func testAmbiguousSubtreeReportsCandidates() {
        let projection = makeInterface(includeDuplicateGroup: true).projecting(InterfaceQuery(
            subtree: .container(ContainerMatcher(label: "Actions"))
        ))

        XCTAssertNotNil(projection.error)
        XCTAssertTrue(projection.error?.contains("matched 2 nodes") == true)
        XCTAssertTrue(projection.error?.contains("semantic_actions__actions") == true)
        XCTAssertTrue(projection.error?.contains("semantic_actions__secondary_actions") == true)
    }

    func testOrdinalDisambiguatesSubtreeCandidates() {
        let projection = makeInterface(includeDuplicateGroup: true).projecting(InterfaceQuery(
            subtree: .container(ContainerMatcher(label: "Actions"), ordinal: 1)
        ))

        XCTAssertNil(projection.error)
        XCTAssertEqual(projection.filteredFrom, 5)
        XCTAssertEqual(projection.interface.elements.map(\.heistId), ["archive"])
    }

    func testMissingSubtreeReportsError() {
        let projection = makeInterface().projecting(InterfaceQuery(
            subtree: .container(ContainerMatcher(stableId: "missing"))
        ))

        XCTAssertNotNil(projection.error)
        XCTAssertTrue(projection.error?.contains("matched no nodes") == true)
        XCTAssertNil(projection.filteredFrom)
    }

    private func makeInterface(includeDuplicateGroup: Bool = false) -> Interface {
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

    private func makeActionsContainer(stableId: String, y: Double = 40) -> ContainerInfo {
        ContainerInfo(
            type: .semanticGroup(label: "Actions", value: nil, identifier: "actions"),
            stableId: stableId,
            frameX: 0,
            frameY: y,
            frameWidth: 200,
            frameHeight: 100
        )
    }

    private func makeElement(
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
