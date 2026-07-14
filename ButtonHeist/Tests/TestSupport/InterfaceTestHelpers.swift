import AccessibilitySnapshotModel
import Foundation
import ThePlans
@testable import TheScore

package enum TestInterfaceNode {
    case element(HeistElement)
    case parsedElement(AccessibilityElement, actions: [ElementAction])
    case container(AccessibilityContainer, containerName: ContainerName?, children: [TestInterfaceNode])
}

package func testElement(_ element: HeistElement) -> TestInterfaceNode {
    .element(element)
}

package func testElement(
    label: String? = "Element",
    value: String? = nil,
    identifier: String? = nil,
    hint: String? = nil,
    traits: [HeistTrait] = [.staticText],
    frameX: Double = 0,
    frameY: Double = 0,
    frameWidth: Double = 100,
    frameHeight: Double = 44,
    activationPointEvidence: ActivationPointEvidence? = nil,
    respondsToUserInteraction: Bool = true,
    customContent: [HeistCustomContent]? = nil,
    rotors: [HeistRotor]? = nil,
    actions: [ElementAction]? = nil
) -> TestInterfaceNode {
    .element(makeTestHeistElement(
        label: label,
        value: value,
        identifier: identifier,
        hint: hint,
        traits: traits,
        frameX: frameX,
        frameY: frameY,
        frameWidth: frameWidth,
        frameHeight: frameHeight,
        activationPointEvidence: activationPointEvidence,
        respondsToUserInteraction: respondsToUserInteraction,
        customContent: customContent,
        rotors: rotors,
        actions: actions
    ))
}

package func testParsedElement(
    _ element: AccessibilityElement,
    actions: [ElementAction] = []
) -> TestInterfaceNode {
    .parsedElement(element, actions: actions)
}

package func testContainer(
    _ container: AccessibilityContainer,
    containerName: ContainerName? = nil,
    children: [TestInterfaceNode]
) -> TestInterfaceNode {
    .container(container, containerName: containerName, children: children)
}

package func makeTestInterface(
    elements: [HeistElement],
    timestamp: Date = Date(timeIntervalSince1970: 0)
) -> Interface {
    makeTestInterface(nodes: elements.map(TestInterfaceNode.element), timestamp: timestamp)
}

package func makeTestInterface(
    nodes: [TestInterfaceNode],
    timestamp: Date = Date(timeIntervalSince1970: 0)
) -> Interface {
    var traversalIndex = 0
    var elementAnnotations: [InterfaceElementAnnotation] = []
    var containerAnnotations: [InterfaceContainerAnnotation] = []

    func convert(_ node: TestInterfaceNode, path: TreePath) -> AccessibilityHierarchy {
        let element: AccessibilityElement
        let actions: [ElementAction]
        switch node {
        case .element(let heistElement):
            element = makeTestAccessibilityElement(heistElement)
            actions = heistElement.actions
        case .parsedElement(let parsedElement, let parsedActions):
            element = parsedElement
            actions = parsedActions
        case .container(let container, let containerName, let children):
            containerAnnotations.append(InterfaceContainerAnnotation(path: path, containerName: containerName))
            return .container(
                container,
                children: children.enumerated().map { offset, child in
                    convert(child, path: path.appending(offset))
                }
            )
        }

        let index = traversalIndex
        traversalIndex += 1
        elementAnnotations.append(InterfaceElementAnnotation(path: path, actions: actions))
        return .element(element, traversalIndex: index)
    }

    return Interface(
        timestamp: timestamp,
        tree: nodes.enumerated().map { offset, node in
            convert(node, path: TreePath([offset]))
        },
        annotations: InterfaceAnnotations(elements: elementAnnotations, containers: containerAnnotations)
    )
}

package func makeTestInterface(
    elementCount: Int,
    prefix: String = "element",
    timestamp: Date = Date(timeIntervalSince1970: 0)
) -> Interface {
    makeTestInterface(
        elements: (0..<elementCount).map { makeTestHeistElement(label: "\(prefix) \($0)") },
        timestamp: timestamp
    )
}

package func makeTestHeistElement(
    description: String? = nil,
    label: String? = "Element",
    value: String? = nil,
    identifier: String? = nil,
    hint: String? = nil,
    traits: [HeistTrait] = [.staticText],
    frameX: Double = 0,
    frameY: Double = 0,
    frameWidth: Double = 100,
    frameHeight: Double = 44,
    activationPointEvidence: ActivationPointEvidence? = nil,
    respondsToUserInteraction: Bool = true,
    customContent: [HeistCustomContent]? = nil,
    rotors: [HeistRotor]? = nil,
    actions: [ElementAction]? = nil
) -> HeistElement {
    HeistElement(
        description: description ?? label ?? identifier ?? "Element",
        label: label,
        value: value,
        identifier: identifier,
        hint: hint,
        traits: traits,
        frameX: frameX,
        frameY: frameY,
        frameWidth: frameWidth,
        frameHeight: frameHeight,
        activationPointEvidence: activationPointEvidence ?? .defaultCenter(ScreenPoint(
            x: frameX + frameWidth / 2,
            y: frameY + frameHeight / 2
        )),
        respondsToUserInteraction: respondsToUserInteraction,
        customContent: customContent,
        rotors: rotors,
        actions: actions ?? (traits.contains(.button) ? [.activate] : [])
    )
}

package func makeTestAccessibilityElement(_ element: HeistElement) -> AccessibilityElement {
    let activationPoint: AccessibilityPoint
    let usesDefaultActivationPoint: Bool
    switch element.activationPointEvidence {
    case .unavailable:
        activationPoint = AccessibilityPoint(
            x: element.frameX + element.frameWidth / 2,
            y: element.frameY + element.frameHeight / 2
        )
        usesDefaultActivationPoint = true
    case .explicit(let point):
        activationPoint = AccessibilityPoint(x: point.x, y: point.y)
        usesDefaultActivationPoint = false
    case .defaultCenter(let point):
        activationPoint = AccessibilityPoint(x: point.x, y: point.y)
        usesDefaultActivationPoint = true
    }

    return AccessibilityElement(
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
        activationPoint: activationPoint,
        usesDefaultActivationPoint: usesDefaultActivationPoint,
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

package func defaultActivationPoint(
    frameX: Double,
    frameY: Double,
    frameWidth: Double,
    frameHeight: Double
) -> (x: Double, y: Double) {
    (
        x: frameX + frameWidth / 2,
        y: frameY + frameHeight / 2
    )
}

package func makeTestAccessibilityContainer(
    type: AccessibilityContainer.ContainerType = .semanticGroup(label: nil, value: nil),
    identifier: String? = nil,
    scrollableContentSize: AccessibilitySize? = nil,
    frameX: Double = 0,
    frameY: Double = 0,
    frameWidth: Double = 100,
    frameHeight: Double = 100,
    isModalBoundary: Bool = false,
    customActions: [AccessibilityElement.CustomAction] = []
) -> AccessibilityContainer {
    AccessibilityContainer(
        type: type,
        identifier: identifier,
        scrollableContentSize: scrollableContentSize,
        frame: AccessibilityRect(x: frameX, y: frameY, width: frameWidth, height: frameHeight),
        isModalBoundary: isModalBoundary,
        customActions: customActions
    )
}

package func makeTestSemanticContainer(
    label: String? = nil,
    value: String? = nil,
    identifier: String? = nil,
    frameX: Double = 0,
    frameY: Double = 0,
    frameWidth: Double = 100,
    frameHeight: Double = 100,
    isModalBoundary: Bool = false,
    customActions: [AccessibilityElement.CustomAction] = []
) -> AccessibilityContainer {
    makeTestAccessibilityContainer(
        type: .semanticGroup(label: label, value: value),
        identifier: identifier,
        frameX: frameX,
        frameY: frameY,
        frameWidth: frameWidth,
        frameHeight: frameHeight,
        isModalBoundary: isModalBoundary,
        customActions: customActions
    )
}

package func makeTestScrollableContainer(
    contentWidth: Double,
    contentHeight: Double,
    frameX: Double = 0,
    frameY: Double = 0,
    frameWidth: Double = 100,
    frameHeight: Double = 100,
    isModalBoundary: Bool = false,
    customActions: [AccessibilityElement.CustomAction] = []
) -> AccessibilityContainer {
    makeTestAccessibilityContainer(
        type: .none,
        scrollableContentSize: AccessibilitySize(width: contentWidth, height: contentHeight),
        frameX: frameX,
        frameY: frameY,
        frameWidth: frameWidth,
        frameHeight: frameHeight,
        isModalBoundary: isModalBoundary,
        customActions: customActions
    )
}

package func makeTestTrace(
    before beforeInterface: Interface,
    after afterInterface: Interface,
    beforeScreenId: String? = "screen",
    afterScreenId: String? = "screen",
    afterTransition: AccessibilityTrace.Transition = .init()
) -> AccessibilityTrace {
    let beforeCapture = AccessibilityTrace.Capture(
        sequence: 1,
        interface: beforeInterface,
        context: AccessibilityTrace.Context(screenId: beforeScreenId)
    )
    let afterCapture = AccessibilityTrace.Capture(
        sequence: 2,
        interface: afterInterface,
        parentHash: beforeCapture.hash,
        context: AccessibilityTrace.Context(screenId: afterScreenId),
        transition: afterTransition
    )
    return AccessibilityTrace(captures: [beforeCapture, afterCapture])
}

package func makeTestScreenChangedTransition(sequence: UInt64 = 1) -> AccessibilityTrace.Transition {
    AccessibilityTrace.Transition(accessibilityNotifications: [
        AccessibilityNotificationEvidence(
            sequence: sequence,
            kind: .screenChanged,
            timestamp: Date(timeIntervalSince1970: TimeInterval(sequence)),
            notificationData: .none,
            associatedElement: .none
        ),
    ])
}
