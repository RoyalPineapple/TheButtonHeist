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

// MARK: - Wire Conversion

extension TheStash {

    /// Convert internal accessibility types (`AccessibilityElement`,
    /// `AccessibilityHierarchy`, `Screen`) to their wire representations
    /// (`HeistElement`, `InterfaceNode`, `ContainerInfo`). Pure transform —
    /// no stored state. Sibling `InterfaceDiff` consumes the wire forms.
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

    static func convert(_ element: AccessibilityElement, object: NSObject? = nil) -> HeistElement {
        let frame = element.shape.frame
        return HeistElement(
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
            activationPointX: element.activationPoint.x.sanitizedForJSON,
            activationPointY: element.activationPoint.y.sanitizedForJSON,
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
            actions: buildActions(for: element, object: object)
        )
    }

    static func buildActions(for element: AccessibilityElement, object: NSObject? = nil) -> [ElementAction] {
        let isInteractive = Interactivity.isInteractive(element: element, object: object)
        let activate: [ElementAction] = isInteractive ? [.activate] : []
        let adjustable: [ElementAction] = (isInteractive && element.traits.contains(.adjustable))
            ? [.increment, .decrement]
            : []
        let custom = element.customActions.map { ElementAction.custom($0.name) }
        return activate + adjustable + custom
    }

    // MARK: - Wire Output

    static func toWire(_ entry: ScreenElement) -> HeistElement {
        var wire = convert(entry.element, object: entry.object)
        wire.heistId = entry.heistId
        return wire
    }

    /// Convert a snapshot to wire format. Use at serialization boundaries.
    static func toWire(_ entries: [ScreenElement]) -> [HeistElement] {
        entries.map { toWire($0) }
    }

    // MARK: - Tree Conversion (Screen → wire)

    /// Convert a Screen's hierarchy to canonical wire form. Elements are
    /// looked up by their assigned heistId; containers carry the stable id
    /// computed once during parse.
    static func toWireTree(from screen: Screen) -> [InterfaceNode] {
        screen.hierarchy.map { node in
            convertNode(node, screen: screen)
        }
    }

    // MARK: - Private Helpers

    private static func convertNode(_ node: AccessibilityHierarchy, screen: Screen) -> InterfaceNode {
        switch node {
        case .element(let element, _):
            if let heistId = screen.heistIdByElement[element],
               let entry = screen.elements[heistId] {
                return .element(toWire(entry))
            }
            // Construction invariant: every leaf in `screen.hierarchy` also
            // appears in `screen.heistIdByElement`/`screen.elements` because
            // both maps are built from the same parse pass (TheBurglar zips
            // `hierarchy.sortedElements` with `resolvedHeistIds`). Log and fall back to
            // an id-less wire node so we'd notice if the invariant ever broke.
            wireConversionLogger.error("Hierarchy leaf with no heistId in screen; emitting wire node without id")
            return .element(convert(element))
        case .container(let container, let children):
            let stableId = screen.containerStableIds[container]
            let info = toContainerInfo(container, stableId: stableId)
            return .container(info, children: children.map { convertNode($0, screen: screen) })
        }
    }

    private static func toContainerInfo(_ container: AccessibilityContainer, stableId: String?) -> ContainerInfo {
        let type: ContainerInfo.ContainerType
        switch container.type {
        case let .semanticGroup(label, value, identifier):
            type = .semanticGroup(label: label, value: value, identifier: identifier)
        case .list:
            type = .list
        case .landmark:
            type = .landmark
        case let .dataTable(rowCount, columnCount):
            type = .dataTable(rowCount: rowCount, columnCount: columnCount)
        case .tabBar:
            type = .tabBar
        case .scrollable(let contentSize):
            type = .scrollable(
                contentWidth: Double(contentSize.width.sanitizedForJSON),
                contentHeight: Double(contentSize.height.sanitizedForJSON)
            )
        }
        return ContainerInfo(
            type: type,
            stableId: stableId,
            isModalBoundary: container.isModalBoundary,
            frameX: Double(container.frame.origin.x.sanitizedForJSON),
            frameY: Double(container.frame.origin.y.sanitizedForJSON),
            frameWidth: Double(container.frame.size.width.sanitizedForJSON),
            frameHeight: Double(container.frame.size.height.sanitizedForJSON)
        )
    }
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
