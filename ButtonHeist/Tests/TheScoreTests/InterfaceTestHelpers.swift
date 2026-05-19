import AccessibilitySnapshotModel
import Foundation
@testable import TheScore

enum TestInterfaceNode {
    case element(HeistElement)
    case container(AccessibilityContainer, stableId: HeistContainer?, children: [TestInterfaceNode])
}

func testElement(_ element: HeistElement) -> TestInterfaceNode {
    .element(element)
}

func testContainer(
    _ container: AccessibilityContainer,
    stableId: HeistContainer? = nil,
    children: [TestInterfaceNode]
) -> TestInterfaceNode {
    .container(container, stableId: stableId, children: children)
}

func makeTestInterface(
    elements: [HeistElement],
    timestamp: Date = Date(timeIntervalSince1970: 0)
) -> Interface {
    makeTestInterface(nodes: elements.map(TestInterfaceNode.element), timestamp: timestamp)
}

func makeTestInterface(
    nodes: [TestInterfaceNode],
    timestamp: Date = Date(timeIntervalSince1970: 0)
) -> Interface {
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
                heistId: element.heistId,
                actions: element.actions
            ))
            return .element(makeTestAccessibilityElement(element), traversalIndex: index)
        case .container(let container, let stableId, let children):
            containerAnnotations.append(InterfaceContainerAnnotation(path: path, stableId: stableId))
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
        timestamp: timestamp,
        tree: tree,
        annotations: InterfaceAnnotations(elements: elementAnnotations, containers: containerAnnotations)
    )
}

func makeTestAccessibilityElement(_ element: HeistElement) -> AccessibilityElement {
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
        customContent: element.customContent?.map {
            AccessibilityElement.CustomContent(
                label: $0.label,
                value: $0.value,
                isImportant: $0.isImportant
            )
        } ?? [],
        customRotors: element.rotors?.map { AccessibilityElement.CustomRotor(name: $0.name) } ?? [],
        accessibilityLanguage: nil,
        respondsToUserInteraction: element.respondsToUserInteraction
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
