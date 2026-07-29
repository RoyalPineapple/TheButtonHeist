#if canImport(UIKit)
import Foundation

@testable import AccessibilitySnapshotParser
@testable import TheInsideJob
@testable import TheScore

func heistSnapshot(
    labels: [String],
    timestamp: Date = Date(timeIntervalSince1970: 1)
) -> Observation.Snapshot {
    heistSnapshot(
        elements: labels.map { AccessibilityElement.make(label: $0) },
        timestamp: timestamp
    )
}

func heistSnapshot(
    elements: [AccessibilityElement],
    timestamp: Date = Date(timeIntervalSince1970: 1)
) -> Observation.Snapshot {
    let indexedElements = elements.enumerated().map { index, element in
        let path = TreePath([index])
        let geometry = testGeometry(
            for: element,
            ownerPath: .root,
            screen: element.visibility == .onscreen
                ? TheVault.onscreenSpace(for: element)
                : .offscreen
        )
        return (
            hierarchy: AccessibilityHierarchy.element(
                element,
                traversalIndex: index
            ),
            annotation: InterfaceElementAnnotation(
                path: path,
                actions: [],
                geometry: geometry
            )
        )
    }
    guard let interface = try? Interface(
        timestamp: timestamp,
        tree: indexedElements.map(\.hierarchy),
        annotations: InterfaceAnnotations(
            elements: indexedElements.map(\.annotation),
            containers: []
        )
    ) else {
        preconditionFailure("The test snapshot must contain admitted geometry")
    }
    return Observation.Snapshot(interface: interface, context: .empty)
}
#endif
