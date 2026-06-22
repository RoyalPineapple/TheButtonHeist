#if canImport(UIKit)
import XCTest
import ThePlans

import AccessibilitySnapshotModel
import TheScore
@testable import TheInsideJob

final class InterfaceSelectorTests: XCTestCase {

    func testMatcherSelectsMatchingLeaves() throws {
        let interface = try select(InterfaceQuery(
            matcher: ElementPredicate(label: "Submit")
        ))
        XCTAssertEqual(interface.projectedElements.map(\.label), ["Submit"])
        XCTAssertEqual(interface.annotations.elements.count, 1)
        XCTAssertTrue(interface.annotations.containers.isEmpty)
    }

    func testElementSubtreeSelectsMatchingLeaf() throws {
        let interface = try select(InterfaceQuery(
            subtree: .element(.predicate(ElementPredicate(identifier: "submit_button")))
        ))
        XCTAssertEqual(interface.projectedElements.map(\.label), ["Submit"])
    }

    func testElementSubtreeSelectsPredicateLeaf() throws {
        let interface = try select(InterfaceQuery(
            subtree: .element(.predicate(ElementPredicate(identifier: "cancel_button")))
        ))
        XCTAssertEqual(interface.projectedElements.map(\.label), ["Cancel"])
        XCTAssertEqual(interface.annotations.elements.count, 1)
        XCTAssertTrue(interface.annotations.containers.isEmpty)
    }

    func testContainerSubtreeSelectsMatchingContainer() throws {
        let interface = try select(InterfaceQuery(
            subtree: .container(ContainerMatcher(containerName: "semantic_actions__actions"))
        ))
        XCTAssertEqual(interface.projectedElements.map(\.label), ["Submit", "Cancel"])
    }

    func testAmbiguousSubtreeReportsTypedCandidates() {
        XCTAssertThrowsError(try select(
            InterfaceQuery(subtree: .container(ContainerMatcher(label: "Actions"))),
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
            InterfaceQuery(subtree: .container(ContainerMatcher(label: "Actions"), ordinal: 1)),
            in: Self.makeInterface(includeDuplicateGroup: true)
        )
        XCTAssertEqual(interface.projectedElements.map(\.label), ["Archive"])
    }

    func testMissingSubtreeReportsTypedError() {
        XCTAssertThrowsError(try select(InterfaceQuery(
            subtree: .container(ContainerMatcher(containerName: "missing"))
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
        let header = makeElement(label: "Menu", traits: [.header])
        let submit = makeElement(label: "Submit", identifier: "submit_button", traits: [.button])
        let cancel = makeElement(label: "Cancel", identifier: "cancel_button", traits: [.button])
        let footer = makeElement(label: "Footer")
        let primaryGroup = makeActionsContainer(containerName: "semantic_actions__actions")

        var nodes: [TestInterfaceNode] = [
            .element(header),
            .container(primaryGroup, containerName: "semantic_actions__actions", children: [.element(submit), .element(cancel)]),
            .element(footer),
        ]

        if includeDuplicateGroup {
            let archive = makeElement(label: "Archive", identifier: "archive_button", traits: [.button])
            let secondaryGroup = makeActionsContainer(containerName: "semantic_actions__secondary_actions", y: 160)
            nodes.insert(.container(secondaryGroup, containerName: "semantic_actions__secondary_actions", children: [.element(archive)]), at: 2)
        }

        return makeInterface(nodes: nodes)
    }

    private static func makeActionsContainer(containerName _: String, y: Double = 40) -> AccessibilityContainer {
        AccessibilityContainer(
            type: .semanticGroup(label: "Actions", value: nil, identifier: "actions"),
            frame: AccessibilityRect(x: 0, y: y, width: 200, height: 100)
        )
    }

    private enum TestInterfaceNode {
        case element(HeistElement)
        case container(AccessibilityContainer, containerName: ContainerName, children: [TestInterfaceNode])
    }

    private static func makeInterface(nodes: [TestInterfaceNode]) -> Interface {
        var traversalIndex = 0
        var elementAnnotations: [InterfaceElementAnnotation] = []
        var containerAnnotations: [InterfaceContainerAnnotation] = []

        func convert(_ node: TestInterfaceNode, path: TreePath) -> AccessibilityHierarchy {
            switch node {
            case .element(let element):
                let index = traversalIndex
                traversalIndex += 1
                elementAnnotations.append(InterfaceElementAnnotation(
                    path: path,
                    actions: element.actions
                ))
                return .element(makeAccessibilityElement(element), traversalIndex: index)
            case .container(let container, let containerName, let children):
                containerAnnotations.append(InterfaceContainerAnnotation(path: path, containerName: containerName))
                return .container(
                    container,
                    children: children.enumerated().map { offset, child in
                        convert(child, path: path.appending(offset))
                    }
                )
            }
        }

        let tree = nodes.enumerated().map { offset, node in
            convert(node, path: TreePath([offset]))
        }
        return Interface(
            timestamp: Date(timeIntervalSince1970: 0),
            tree: tree,
            annotations: InterfaceAnnotations(elements: elementAnnotations, containers: containerAnnotations)
        )
    }

    private static func makeAccessibilityElement(_ element: HeistElement) -> AccessibilityElement {
        AccessibilityElement(
            description: element.description,
            label: element.label,
            value: element.value,
            traits: AccessibilityTraits.fromNames(element.traits.map { $0.rawValue }),
            identifier: element.identifier,
            hint: nil,
            userInputLabels: nil,
            shape: .frame(AccessibilityRect(
                x: element.frameX,
                y: element.frameY,
                width: element.frameWidth,
                height: element.frameHeight
            )),
            activationPoint: AccessibilityPoint(x: element.activationPointX, y: element.activationPointY),
            usesDefaultActivationPoint: true,
            customActions: [],
            customContent: [],
            customRotors: [],
            accessibilityLanguage: nil,
            respondsToUserInteraction: true
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
