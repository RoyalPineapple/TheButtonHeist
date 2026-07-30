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

/// A canonical semantic snapshot containing these elements.
package func makeTestObservationSnapshot(
    labels: [String],
    timestamp: Date = Date(timeIntervalSince1970: 0)
) -> Observation.Snapshot {
    makeTestObservationSnapshot(
        elements: labels.map {
            makeTestHeistElement(description: $0, label: $0)
        },
        timestamp: timestamp
    )
}

package func makeTestObservationSnapshot(
    elements: [HeistElement],
    timestamp: Date = Date(timeIntervalSince1970: 0)
) -> Observation.Snapshot {
    Observation.Snapshot(
        interface: makeTestInterface(elements: elements, timestamp: timestamp),
        context: .empty
    )
}

package func makeTestObservationSnapshot(
    nodes: [TestInterfaceNode],
    timestamp: Date = Date(timeIntervalSince1970: 0)
) -> Observation.Snapshot {
    Observation.Snapshot(
        interface: makeTestInterface(nodes: nodes, timestamp: timestamp),
        context: .empty
    )
}

package func makeTestObservationEvidence(
    baseline: Observation.Snapshot? = nil,
    current: Observation.Snapshot? = nil,
    events: [Observation.Event] = [],
    coverage: Observation.Coverage = .complete
) -> Observation.Evidence {
    Observation.Evidence(
        baseline: baseline,
        events: events,
        current: current,
        coverage: coverage
    )
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
        let geometry: HeistElement.Geometry
        switch node {
        case .element(let heistElement):
            element = makeTestAccessibilityElement(heistElement)
            actions = heistElement.semantics.assertable.orderedActions
            geometry = heistElement.geometry
        case .parsedElement(let parsedElement, let parsedActions):
            element = parsedElement
            actions = parsedActions
            geometry = testGeometry(for: parsedElement, ownerPath: path.parent ?? .root)
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
        elementAnnotations.append(
            InterfaceElementAnnotation(path: path, actions: actions, geometry: geometry)
        )
        return .element(element, traversalIndex: index)
    }

    let tree = nodes.enumerated().map { offset, node in
        convert(node, path: TreePath([offset]))
    }
    let annotations = InterfaceAnnotations(elements: elementAnnotations, containers: containerAnnotations)
    return Interface(
        timestamp: timestamp,
        projecting: tree,
        elementMetadata: { path, _, _ in
            guard let annotation = annotations.elementByPath[path] else { return nil }
            return InterfaceElementProjectionMetadata(
                actions: annotation.actions,
                geometry: annotation.geometry
            )
        },
        containerMetadata: { path, _ in
            guard let annotation = annotations.containerByPath[path] else { return nil }
            return InterfaceContainerProjectionMetadata(
                containerName: annotation.containerName,
                scrollInventory: annotation.scrollInventory
            )
        }
    )
}

private func testGeometry(
    for element: AccessibilityElement,
    ownerPath: TreePath
) -> HeistElement.Geometry {
    let screenFrame = ScreenFrameEvidence(element.shape)
    let screenActivationPoint: ActivationPointEvidence
    if element.usesDefaultActivationPoint,
       let frame = screenFrame.rect,
       let x = try? FiniteCoordinate(validating: frame.midX),
       let y = try? FiniteCoordinate(validating: frame.midY) {
        screenActivationPoint = .defaultCenter(ScreenPoint(x: x, y: y))
    } else if let x = try? FiniteCoordinate(validating: element.activationPoint.x),
              let y = try? FiniteCoordinate(validating: element.activationPoint.y) {
        screenActivationPoint = .explicit(ScreenPoint(x: x, y: y))
    } else {
        screenActivationPoint = .unavailable
    }
    let viewActivationPoint = try? ViewPoint(
        validating: CGPoint(
            x: element.activationPoint.x,
            y: element.activationPoint.y
        )
    )
    return HeistElement.Geometry(
        screen: .onscreen(frame: screenFrame, activationPoint: screenActivationPoint),
        view: HeistElement.Geometry.ViewSpace(
            ownerPath: ownerPath,
            frame: screenFrame.rect.flatMap { try? ViewRect(validating: $0.cgRect) },
            activationPoint: viewActivationPoint
        )
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
    let frame = try? ScreenRect(validating: CGRect(
        x: frameX,
        y: frameY,
        width: frameWidth,
        height: frameHeight
    ))
    let defaultActivationPointEvidence: ActivationPointEvidence
    if let frame,
       let x = try? FiniteCoordinate(validating: frame.midX),
       let y = try? FiniteCoordinate(validating: frame.midY) {
        defaultActivationPointEvidence = .defaultCenter(ScreenPoint(x: x, y: y))
    } else if let x = try? FiniteCoordinate(validating: frameX + frameWidth / 2),
       let y = try? FiniteCoordinate(validating: frameY + frameHeight / 2) {
        defaultActivationPointEvidence = .defaultCenter(ScreenPoint(x: x, y: y))
    } else {
        defaultActivationPointEvidence = .unavailable
    }
    let screenActivationPoint = activationPointEvidence ?? defaultActivationPointEvidence
    let viewActivationPoint = screenActivationPoint.point.flatMap { point in
        try? ViewPoint(validating: CGPoint(x: point.x, y: point.y))
    }
    return HeistElement(
        semantics: HeistElement.Semantics(
            spokenDescription: description ?? label ?? identifier ?? "Element",
            assertable: HeistElement.Semantics.AssertableProperties(
                label: label,
                value: value,
                identifier: identifier,
                hint: hint,
                traits: Set(traits),
                customContent: customContent ?? [],
                rotors: Set(rotors ?? []),
                actions: Set(actions ?? (traits.contains(.button) ? [.activate] : []))
            ),
            respondsToUserInteraction: respondsToUserInteraction
        ),
        geometry: HeistElement.Geometry(
            screen: .onscreen(
                frame: frame.map(ScreenFrameEvidence.available) ?? .unavailable,
                activationPoint: screenActivationPoint
            ),
            view: HeistElement.Geometry.ViewSpace(
                ownerPath: .root,
                frame: frame.flatMap { try? ViewRect(validating: $0.cgRect) },
                activationPoint: viewActivationPoint
            )
        )
    )
}

package func makeTestAccessibilityElement(_ element: HeistElement) -> AccessibilityElement {
    let semantics = element.semantics
    let assertable = semantics.assertable
    guard case .onscreen(let frameEvidence, let activationPointEvidence) = element.geometry.screen,
          let frame = frameEvidence.rect else {
        preconditionFailure("parser-backed test elements require available frame evidence")
    }
    let activationPoint: AccessibilityPoint
    let usesDefaultActivationPoint: Bool
    switch activationPointEvidence {
    case .unavailable:
        activationPoint = AccessibilityPoint(
            x: frame.midX,
            y: frame.midY
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
        description: semantics.spokenDescription,
        label: assertable.label,
        value: assertable.value,
        traits: AccessibilityTraits.fromNames(assertable.traits.map(\.rawValue)),
        identifier: assertable.identifier,
        hint: assertable.hint,
        userInputLabels: nil,
        shape: .frame(AccessibilityRect(
            x: frame.x.value,
            y: frame.y.value,
            width: frame.width.value,
            height: frame.height.value
        )),
        activationPoint: activationPoint,
        usesDefaultActivationPoint: usesDefaultActivationPoint,
        customActions: [],
        customContent: assertable.orderedCustomContent.map {
            AccessibilityElement.CustomContent(
                label: $0.label,
                value: $0.value,
                isImportant: $0.isImportant
            )
        },
        customRotors: assertable.orderedRotors.map { AccessibilityElement.CustomRotor(name: $0.name) },
        accessibilityLanguage: nil,
        respondsToUserInteraction: semantics.respondsToUserInteraction
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
