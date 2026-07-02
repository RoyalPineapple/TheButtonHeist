#if canImport(UIKit)
import ButtonHeistTestSupport
import Foundation
import ThePlans
@testable import TheInsideJob
@testable import TheScore

import AccessibilitySnapshotModel

enum TestInterfaceNode {
    case element(AccessibilityElement, actions: [ElementAction] = [])
    case container(AccessibilityContainer, containerName: ContainerName? = nil, children: [TestInterfaceNode])

    static func heistElement(
        label: String? = "Element",
        value: String? = nil,
        identifier: String? = nil,
        traits: [HeistTrait] = [.staticText],
        frameX: Double = 0,
        frameY: Double = 0,
        frameWidth: Double = 100,
        frameHeight: Double = 44,
        actions: [ElementAction]? = nil
    ) -> TestInterfaceNode {
        .heistElement(makeTestHeistElement(
            label: label,
            value: value,
            identifier: identifier,
            traits: traits,
            frameX: frameX,
            frameY: frameY,
            frameWidth: frameWidth,
            frameHeight: frameHeight,
            actions: actions
        ))
    }

    static func heistElement(_ element: HeistElement) -> TestInterfaceNode {
        .element(
            AccessibilityElement(
                description: element.description,
                label: element.label,
                value: element.value,
                traits: AccessibilityTraits.fromNames(element.traits.map(\.rawValue)),
                identifier: element.identifier,
                hint: element.hint,
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
                respondsToUserInteraction: element.respondsToUserInteraction
            ),
            actions: element.actions
        )
    }

    @MainActor
    static func screenElement(_ element: Screen.ScreenElement) -> TestInterfaceNode {
        .element(
            element.element,
            actions: TheStash.WireConversion.convert(element.element).actions
        )
    }
}

struct TestInterfaceFixture {
    let nodes: [TestInterfaceNode]
    let timestamp: Date

    init(
        nodes: [TestInterfaceNode],
        timestamp: Date = Date(timeIntervalSince1970: 0)
    ) {
        self.nodes = nodes
        self.timestamp = timestamp
    }

    init(
        elements: [HeistElement],
        timestamp: Date = Date(timeIntervalSince1970: 0)
    ) {
        self.init(nodes: elements.map(TestInterfaceNode.heistElement), timestamp: timestamp)
    }

    var interface: Interface {
        var traversalIndex = 0
        var elementAnnotations: [InterfaceElementAnnotation] = []
        var containerAnnotations: [InterfaceContainerAnnotation] = []

        func convert(_ node: TestInterfaceNode, path: TreePath) -> AccessibilityHierarchy {
            switch node {
            case .element(let element, let actions):
                let index = traversalIndex
                traversalIndex += 1
                elementAnnotations.append(InterfaceElementAnnotation(
                    path: path,
                    actions: actions
                ))
                return .element(element, traversalIndex: index)

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

        return Interface(
            timestamp: timestamp,
            tree: nodes.enumerated().map { offset, node in
                convert(node, path: TreePath([offset]))
            },
            annotations: InterfaceAnnotations(elements: elementAnnotations, containers: containerAnnotations)
        )
    }
}

func testElement(_ element: HeistElement) -> TestInterfaceNode {
    .heistElement(element)
}

func testElement(
    label: String? = "Element",
    value: String? = nil,
    identifier: String? = nil,
    traits: [HeistTrait] = [.staticText],
    frameX: Double = 0,
    frameY: Double = 0,
    frameWidth: Double = 100,
    frameHeight: Double = 44,
    actions: [ElementAction]? = nil
) -> TestInterfaceNode {
    .heistElement(
        label: label,
        value: value,
        identifier: identifier,
        traits: traits,
        frameX: frameX,
        frameY: frameY,
        frameWidth: frameWidth,
        frameHeight: frameHeight,
        actions: actions
    )
}

func testContainer(
    _ container: AccessibilityContainer,
    containerName: ContainerName? = nil,
    children: [TestInterfaceNode]
) -> TestInterfaceNode {
    .container(container, containerName: containerName, children: children)
}

func makeTestInterface(
    elements: [HeistElement],
    timestamp: Date = Date(timeIntervalSince1970: 0)
) -> Interface {
    TestInterfaceFixture(elements: elements, timestamp: timestamp).interface
}

func makeTestInterface(
    nodes: [TestInterfaceNode],
    timestamp: Date = Date(timeIntervalSince1970: 0)
) -> Interface {
    TestInterfaceFixture(nodes: nodes, timestamp: timestamp).interface
}

func makeTestHeistElement(
    label: String? = "Element",
    value: String? = nil,
    identifier: String? = nil,
    hint: String? = nil,
    traits: [HeistTrait] = [.staticText],
    frameX: Double = 0,
    frameY: Double = 0,
    frameWidth: Double = 100,
    frameHeight: Double = 44,
    activationPointX: Double? = nil,
    activationPointY: Double? = nil,
    respondsToUserInteraction: Bool = true,
    actions: [ElementAction]? = nil
) -> HeistElement {
    HeistElement(
        description: label ?? identifier ?? "Element",
        label: label,
        value: value,
        identifier: identifier,
        hint: hint,
        traits: traits,
        frameX: frameX,
        frameY: frameY,
        frameWidth: frameWidth,
        frameHeight: frameHeight,
        activationPointX: activationPointX,
        activationPointY: activationPointY,
        respondsToUserInteraction: respondsToUserInteraction,
        actions: actions ?? (traits.contains(.button) ? [.activate] : [])
    )
}

func makeTestAccessibilityContainer(
    type: AccessibilityContainer.ContainerType = .semanticGroup(label: nil, value: nil, identifier: nil),
    frameX: Double = 0,
    frameY: Double = 0,
    frameWidth: Double = 100,
    frameHeight: Double = 100,
    isModalBoundary: Bool = false
) -> AccessibilityContainer {
    AccessibilityContainer(
        type: type,
        frame: AccessibilityRect(x: frameX, y: frameY, width: frameWidth, height: frameHeight),
        isModalBoundary: isModalBoundary
    )
}

#endif // canImport(UIKit)
