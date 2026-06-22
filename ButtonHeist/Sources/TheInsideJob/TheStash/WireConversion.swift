#if canImport(UIKit)
#if DEBUG
import UIKit
import os.log

import TheScore
import ThePlans

import AccessibilitySnapshotParser

private let wireConversionLogger = Logger(subsystem: "com.buttonheist.theinsidejob", category: "wireConversion")

// MARK: - Float Sanitization

extension CGFloat {
    /// Replace NaN/infinity with 0 so JSONEncoder doesn't throw.
    /// UIPickerView's 3D-transformed cells can produce non-finite frame coordinates.
    var sanitizedForJSON: CGFloat {
        isFinite ? self : 0
    }
}

extension Double {
    /// Replace NaN/infinity with 0 so JSONEncoder doesn't throw.
    /// Portable parser points use Double instead of UIKit's CGFloat.
    var sanitizedForJSON: Double {
        isFinite ? self : 0
    }
}

// MARK: - Wire Conversion

extension TheStash {

    /// Convert internal accessibility types (`AccessibilityElement`,
    /// `AccessibilityHierarchy`, `Screen`) to their wire-facing projections.
    /// Pure transform — no stored state. Delta projection is capture-backed in
    /// TheScore.
    @MainActor enum WireConversion { // swiftlint:disable:this agent_main_actor_value_type

    // MARK: - Element Conversion

    static func convert(_ element: AccessibilityElement) -> HeistElement {
        let frame = element.bhFrame
        let activationPoint = element.bhResolvedActivationPoint
        return HeistElement(
            description: element.description,
            label: element.label,
            value: element.value,
            identifier: element.identifier,
            hint: element.hint,
            traits: element.traits.heistTraits,
            frameX: frame.origin.x.sanitizedForJSON,
            frameY: frame.origin.y.sanitizedForJSON,
            frameWidth: frame.size.width.sanitizedForJSON,
            frameHeight: frame.size.height.sanitizedForJSON,
            activationPointX: activationPoint.x.sanitizedForJSON,
            activationPointY: activationPoint.y.sanitizedForJSON,
            respondsToUserInteraction: element.respondsToUserInteraction,
            customContent: {
                let valid = element.customContent.filter { !$0.label.isEmpty || !$0.value.isEmpty }
                return valid.isEmpty ? nil : valid.map {
                    HeistCustomContent(label: $0.label, value: $0.value, isImportant: $0.isImportant)
                }
            }(),
            rotors: {
                let valid = element.customRotors.filter { !$0.name.isEmpty }
                return valid.isEmpty ? nil : valid.map { HeistRotor(name: $0.name) }
            }(),
            actions: buildActions(for: element)
        )
    }

    static func buildActions(for element: AccessibilityElement) -> [ElementAction] {
        let isInteractive = Interactivity.isInteractive(element: element)
        let activate: [ElementAction] = isInteractive ? [.activate] : []
        let adjustable: [ElementAction] = (isInteractive && element.traits.contains(.adjustable))
            ? [.increment, .decrement]
            : []
        let custom = element.customActions
            .map { $0.name }
            .filter { !$0.isEmpty }
            .map(ElementAction.custom)
        return activate + adjustable + custom
    }

    // MARK: - Interface Conversion

    /// Convert a Screen into the canonical interface capture. The parser
    /// hierarchy remains the tree; Button Heist metadata is attached as
    /// annotations keyed by capture-local tree path.
    static func toInterface(from screen: Screen, timestamp: Date = Date()) -> Interface {
        Interface(
            timestamp: timestamp,
            tree: screen.liveCapture.hierarchy,
            annotations: InterfaceAnnotations(
                elements: elementAnnotations(from: screen),
                containers: containerAnnotations(from: screen)
            )
        )
    }

    /// Convert the committed semantic screen into a trace-facing interface.
    ///
    /// Exploration commits the full targetable element set into
    /// `screen.knownInterface`; the latest live capture remains viewport-local
    /// evidence for action dispatch. Post-action traces compare semantic
    /// captures, so known off-viewport elements must be present here even when
    /// they are absent from the latest live parser hierarchy.
    static func toSemanticInterface(from screen: Screen, timestamp: Date = Date()) -> Interface {
        let entries = screen.orderedElements
        let tree = entries.enumerated().map { index, entry in
            AccessibilityHierarchy.element(entry.element, traversalIndex: index)
        }
        let annotations = entries.enumerated().map { index, entry in
            InterfaceElementAnnotation(
                path: TreePath([index]),
                actions: buildActions(for: entry.element)
            )
        }
        return Interface(
            timestamp: timestamp,
            tree: tree,
            annotations: InterfaceAnnotations(elements: annotations)
        )
    }

    // MARK: - Private Helpers

    private static func elementAnnotations(from screen: Screen) -> [InterfaceElementAnnotation] {
        screen.liveCapture.hierarchy.compactMapSubtrees { node, path in
            guard case .element(let element, _) = node else { return nil }
            return InterfaceElementAnnotation(
                path: path,
                actions: buildActions(for: element)
            )
        }
    }

    private static func containerAnnotations(from screen: Screen) -> [InterfaceContainerAnnotation] {
        screen.liveCapture.hierarchy.compactMapSubtrees { node, path in
            guard case .container(let container, _) = node else { return nil }
            return InterfaceContainerAnnotation(
                path: path,
                containerName: screen.liveCapture.containerNamesByPath[path]
                    ?? screen.liveCapture.containerNames[container]
            )
        }
    }
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
