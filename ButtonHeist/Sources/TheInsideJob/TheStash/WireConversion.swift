#if canImport(UIKit)
#if DEBUG
import UIKit
import os.log

import TheScore

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

    // MARK: - Trait Names

    /// Trait-to-name conversion delegated to AccessibilitySnapshotParser.
    static func traitNames(_ traits: UIAccessibilityTraits) -> [HeistTrait] {
        traitNames(AccessibilityTraits(traits))
    }

    static func traitNames(_ traits: AccessibilityTraits) -> [HeistTrait] {
        traits.namesIncludingUnknownBits.map { HeistTrait(rawValue: $0) ?? .unknown($0) }
    }

    // MARK: - Element Conversion

    static func convert(_ element: AccessibilityElement, heistId: HeistId = "") -> HeistElement {
        let frame = element.bhFrame
        let activationPoint = element.bhResolvedActivationPoint
        return HeistElement(
            heistId: heistId,
            description: element.description,
            label: element.label,
            value: element.value,
            identifier: element.identifier,
            hint: element.hint,
            traits: traitNames(element.traits),
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

    static func buildActions(for container: AccessibilityContainer) -> [ElementAction] {
        let names = container.customActions
            .map { $0.name }
            .filter { !$0.isEmpty }
        return names.map(ElementAction.custom)
    }

    // MARK: - Wire Output

    static func toWire(_ entry: ScreenElement) -> HeistElement {
        convert(entry.element, heistId: entry.heistId)
    }

    /// Convert a snapshot to wire format. Use at serialization boundaries.
    static func toWire(_ entries: [ScreenElement]) -> [HeistElement] {
        entries.map { toWire($0) }
    }

    // MARK: - Interface Conversion

    /// Convert a Screen into the canonical interface capture. The parser
    /// hierarchy remains the tree; Button Heist metadata is attached as
    /// annotations keyed by capture-local tree path.
    static func toInterface(from screen: Screen, timestamp: Date = Date()) -> Interface {
        Interface(
            timestamp: timestamp,
            tree: screen.liveInterface.hierarchy,
            annotations: InterfaceAnnotations(
                elements: elementAnnotations(from: screen),
                containers: containerAnnotations(from: screen)
            )
        )
    }

    // MARK: - Private Helpers

    private static func elementAnnotations(from screen: Screen) -> [InterfaceElementAnnotation] {
        screen.liveInterface.hierarchy.compactMapSubtrees { node, path in
            guard case .element(let element, _) = node else { return nil }
            guard let heistId = screen.liveInterface.heistId(forPath: path)
                ?? screen.liveInterface.heistIdByElement[element] else {
                wireConversionLogger.error("Hierarchy leaf with no heistId in screen; annotating without id")
                return InterfaceElementAnnotation(
                    path: path,
                    heistId: "",
                    actions: buildActions(for: element)
                )
            }

            return InterfaceElementAnnotation(
                path: path,
                heistId: heistId,
                actions: buildActions(for: element)
            )
        }
    }

    private static func containerAnnotations(from screen: Screen) -> [InterfaceContainerAnnotation] {
        screen.liveInterface.hierarchy.compactMapSubtrees { node, path in
            guard case .container(let container, _) = node else { return nil }
            return InterfaceContainerAnnotation(
                path: path,
                stableId: screen.liveInterface.containerStableIdsByPath[path]
                    ?? screen.liveInterface.containerStableIds[container],
                actions: buildActions(for: container)
            )
        }
    }
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
