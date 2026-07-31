#if canImport(UIKit)
#if DEBUG
import UIKit

import TheScore
import ThePlans

import AccessibilitySnapshotParser

// MARK: - Wire Conversion

extension TheVault {

    /// Convert internal accessibility types (`AccessibilityElement`,
    /// `AccessibilityHierarchy`, `InterfaceObservation`) to their wire-facing projections.
    /// Pure transform — no stored state. Delta projection is capture-backed in
    /// TheScore.
    enum WireConversion {

    // MARK: - Element Conversion

    static func convert(
        _ element: AccessibilityElement,
        geometry: HeistElement.Geometry
    ) -> HeistElement {
        HeistElement(
            semantics: semantics(element),
            geometry: geometry
        )
    }

    static func semantics(_ element: AccessibilityElement) -> HeistElement.Semantics {
        let customContent = element.customContent.compactMap(HeistCustomContent.init(projecting:))
        let rotors = element.customRotors.filter { !$0.name.isEmpty }
        return HeistElement.Semantics(
            spokenDescription: element.description,
            assertable: HeistElement.Semantics.AssertableProperties(
                label: element.label,
                value: element.value,
                identifier: element.identifier,
                hint: element.hint,
                traits: Set(element.traits.heistTraits),
                customContent: customContent,
                rotors: Set(rotors.map { HeistRotor(name: $0.name) }),
                actions: element.projectedActionSet.actions
            ),
            respondsToUserInteraction: element.respondsToUserInteraction
        )
    }

    // MARK: - Interface Conversion

    static func discoveryProjection(
        from tree: InterfaceTree,
        timestamp: Date = Date()
    ) -> DiscoveryProjection {
        DiscoveryProjection(
            interface: tree.semanticInterface(timestamp: timestamp),
            containerPathBySourcePath: tree.projectedContainerPathBySourcePath
        )
    }

    }
}

extension TheVault.WireConversion {
    struct DiscoveryProjection {
        let interface: Interface
        let containerPathBySourcePath: [TreePath: TreePath]
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
