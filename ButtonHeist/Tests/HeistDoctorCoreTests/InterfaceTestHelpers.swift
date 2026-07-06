import AccessibilitySnapshotModel
import ButtonHeistTestSupport
import Foundation
import ThePlans
import TheScore

typealias TestInterfaceNode = ButtonHeistTestSupport.TestInterfaceNode

func testElement(_ element: HeistElement) -> TestInterfaceNode {
    ButtonHeistTestSupport.testElement(element)
}

func testContainer(
    _ container: AccessibilityContainer,
    containerName: ContainerName? = nil,
    children: [TestInterfaceNode]
) -> TestInterfaceNode {
    ButtonHeistTestSupport.testContainer(container, containerName: containerName, children: children)
}

func makeTestInterface(
    elements: [HeistElement],
    timestamp: Date = Date(timeIntervalSince1970: 0)
) -> Interface {
    ButtonHeistTestSupport.makeTestInterface(elements: elements, timestamp: timestamp)
}

func makeTestInterface(
    nodes: [TestInterfaceNode],
    timestamp: Date = Date(timeIntervalSince1970: 0)
) -> Interface {
    ButtonHeistTestSupport.makeTestInterface(nodes: nodes, timestamp: timestamp)
}

func makeTestAccessibilityElement(_ element: HeistElement) -> AccessibilityElement {
    ButtonHeistTestSupport.makeTestAccessibilityElement(element)
}

func makeTestAccessibilityContainer(
    type: AccessibilityContainer.ContainerType = .semanticGroup(label: nil, value: nil, identifier: nil),
    frameX: Double = 0,
    frameY: Double = 0,
    frameWidth: Double = 100,
    frameHeight: Double = 100,
    isModalBoundary: Bool = false
) -> AccessibilityContainer {
    ButtonHeistTestSupport.makeTestAccessibilityContainer(
        type: type,
        frameX: frameX,
        frameY: frameY,
        frameWidth: frameWidth,
        frameHeight: frameHeight,
        isModalBoundary: isModalBoundary
    )
}
