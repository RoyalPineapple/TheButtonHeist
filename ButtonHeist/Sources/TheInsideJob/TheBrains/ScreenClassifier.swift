#if canImport(UIKit)
#if DEBUG
import UIKit

import AccessibilitySnapshotParser
import TheScore

/// Classifies parsed accessibility snapshots.
///
/// Tripwire triggers parsing; this type is the single place that decides
/// whether the parsed result should be treated as a new screen. Same-screen
/// element and tree changes are left to `InterfaceDiff`.
@MainActor enum ScreenClassifier { // swiftlint:disable:this agent_main_actor_value_type

    struct Snapshot: Equatable {
        let signature: ScreenSignature
        let firstResponderHeistId: String?
    }

    struct ScreenSignature: Equatable {
        let modalMarkers: [Marker]
        let primaryHeader: String?
        let backButton: Marker?
        let selectedTab: Marker?
        let rootShape: [RootShapeToken]
    }

    struct Marker: Equatable, Hashable {
        let label: String?
        let value: String?
        let identifier: String?
    }

    struct RootShapeToken: Equatable, Hashable {
        let kind: RootShapeKind
        let depth: Int
        let stableIdentifier: String?
        let state: RootShapeState
    }

    enum RootShapeKind: Equatable, Hashable {
        case container(ContainerRootShapeRole)
        case element(ElementRootShapeRole)
    }

    enum ContainerRootShapeRole: Equatable, Hashable {
        case semanticGroup
        case list
        case landmark
        case dataTable
        case tabBar
        case scrollable
    }

    enum ElementRootShapeRole: Equatable, Hashable {
        case backButton
        case header
        case tabBarItem
        case searchField
        case textEntry
        case button
        case link
        case adjustable
    }

    struct RootShapeState: Equatable, Hashable {
        let isSelected: Bool
        let isModal: Bool
    }

    enum Reason: String, Equatable {
        case modalBoundaryChanged
        case selectedTabChanged
        case navigationMarkerChanged
        case primaryHeaderChanged
        case rootShapeChanged
    }

    struct Classification: Equatable {
        let isScreenChange: Bool
        let reason: Reason?

        static let sameScreen = Classification(isScreenChange: false, reason: nil)
        static func screenChanged(_ reason: Reason) -> Classification {
            Classification(isScreenChange: true, reason: reason)
        }
    }

    static func snapshot(of screen: Screen) -> Snapshot {
        Snapshot(
            signature: signature(
                hierarchy: screen.hierarchy,
                elements: screen.hierarchy.sortedElements
            ),
            firstResponderHeistId: screen.firstResponderHeistId
        )
    }

    static func classify(before: Snapshot, after: Snapshot) -> Classification {
        let beforeSignature = before.signature
        let afterSignature = after.signature

        if beforeSignature.modalMarkers != afterSignature.modalMarkers {
            return .screenChanged(.modalBoundaryChanged)
        }
        if beforeSignature.selectedTab != afterSignature.selectedTab {
            return .screenChanged(.selectedTabChanged)
        }
        if beforeSignature.backButton != afterSignature.backButton {
            return .screenChanged(.navigationMarkerChanged)
        }
        if beforeSignature.primaryHeader != afterSignature.primaryHeader {
            return .screenChanged(.primaryHeaderChanged)
        }
        if beforeSignature.rootShape != afterSignature.rootShape,
           !hasStableInteractionContext(before: before, after: after),
           isRootShapeReplacement(before: beforeSignature.rootShape, after: afterSignature.rootShape) {
            return .screenChanged(.rootShapeChanged)
        }
        return .sameScreen
    }

    static func signature(
        hierarchy: [AccessibilityHierarchy],
        elements: [AccessibilityElement]
    ) -> ScreenSignature {
        ScreenSignature(
            modalMarkers: modalMarkers(in: hierarchy),
            primaryHeader: elements.first { $0.traits.contains(.header) }?.label,
            backButton: elements.first(where: isBackButton).map(marker(for:)),
            selectedTab: selectedTabMarker(in: hierarchy),
            rootShape: rootShapeTokens(in: hierarchy)
        )
    }

    private static func hasStableInteractionContext(before: Snapshot, after: Snapshot) -> Bool {
        guard let beforeResponder = before.firstResponderHeistId,
              let afterResponder = after.firstResponderHeistId else { return false }
        return beforeResponder == afterResponder
    }

    private static func marker(for element: AccessibilityElement) -> Marker {
        Marker(
            label: element.label,
            value: element.value,
            identifier: stableIdentifier(element.identifier)
        )
    }

    private static func marker(for container: AccessibilityContainer) -> Marker {
        switch container.type {
        case .semanticGroup(let label, let value, let identifier):
            return Marker(label: label, value: value, identifier: stableIdentifier(identifier))
        case .list:
            return Marker(label: "list", value: nil, identifier: nil)
        case .landmark:
            return Marker(label: "landmark", value: nil, identifier: nil)
        case .dataTable(let rowCount, let columnCount):
            return Marker(label: "dataTable", value: "\(rowCount)x\(columnCount)", identifier: nil)
        case .tabBar:
            return Marker(label: "tabBar", value: nil, identifier: nil)
        case .scrollable:
            return Marker(label: "scrollable", value: nil, identifier: nil)
        }
    }

    private static func stableIdentifier(_ identifier: String?) -> String? {
        guard let identifier, isStableIdentifier(identifier) else { return nil }
        return identifier
    }

    private static func modalMarkers(in hierarchy: [AccessibilityHierarchy]) -> [Marker] {
        hierarchy.containers.compactMap { container in
            container.isModalBoundary ? marker(for: container) : nil
        }
    }

    private static func selectedTabMarker(in hierarchy: [AccessibilityHierarchy]) -> Marker? {
        let markers: [Marker] = hierarchy.compactMap(
            first: 1,
            context: false,
            container: { isInTabBar, container in
                if case .tabBar = container.type { return true }
                return isInTabBar
            },
            element: { element, _, isInTabBar in
                guard isInTabBar, element.traits.contains(.selected) else { return nil }
                return marker(for: element)
            }
        )
        return markers.first
    }

    private static func rootShapeTokens(in hierarchy: [AccessibilityHierarchy]) -> [RootShapeToken] {
        var tokens: [RootShapeToken] = []
        let hasMultipleRootNodes = hierarchy.count > 1
        for node in hierarchy {
            appendShapeTokens(
                from: node,
                depth: 0,
                hasMultipleRootNodes: hasMultipleRootNodes,
                into: &tokens
            )
        }
        return Array(tokens.prefix(80))
    }

    private static func appendShapeTokens(
        from node: AccessibilityHierarchy,
        depth: Int,
        hasMultipleRootNodes: Bool,
        into tokens: inout [RootShapeToken]
    ) {
        switch node {
        case .element(let element, _):
            guard let role = structuralRole(of: element) else { return }
            tokens.append(
                RootShapeToken(
                    kind: .element(role),
                    depth: depth,
                    stableIdentifier: stableIdentifier(element.identifier),
                    state: RootShapeState(
                        isSelected: element.traits.contains(.selected),
                        isModal: false
                    )
                )
            )
        case .container(let container, let children):
            if isTransparentTopLevelWrapper(container, depth: depth, hasMultipleRootNodes: hasMultipleRootNodes) {
                for child in children {
                    appendShapeTokens(
                        from: child,
                        depth: depth,
                        hasMultipleRootNodes: hasMultipleRootNodes,
                        into: &tokens
                    )
                }
                return
            }
            tokens.append(
                RootShapeToken(
                    kind: .container(containerRole(of: container)),
                    depth: depth,
                    stableIdentifier: stableIdentifier(containerIdentifier(of: container)),
                    state: RootShapeState(
                        isSelected: false,
                        isModal: container.isModalBoundary
                    )
                )
            )
            for child in children {
                appendShapeTokens(
                    from: child,
                    depth: depth + 1,
                    hasMultipleRootNodes: hasMultipleRootNodes,
                    into: &tokens
                )
            }
        }
    }

    private static func containerRole(of container: AccessibilityContainer) -> ContainerRootShapeRole {
        switch container.type {
        case .semanticGroup:
            return .semanticGroup
        case .list:
            return .list
        case .landmark:
            return .landmark
        case .dataTable:
            return .dataTable
        case .tabBar:
            return .tabBar
        case .scrollable:
            return .scrollable
        }
    }

    private static func containerIdentifier(of container: AccessibilityContainer) -> String? {
        guard case .semanticGroup(_, _, let identifier) = container.type else { return nil }
        return identifier
    }

    private static func structuralRole(of element: AccessibilityElement) -> ElementRootShapeRole? {
        if isBackButton(element) { return .backButton }
        if element.traits.contains(.header) { return .header }
        if element.traits.contains(.tabBarItem) { return .tabBarItem }
        if element.traits.contains(.searchField) { return .searchField }
        if element.traits.contains(.textEntry) { return .textEntry }
        if element.traits.contains(.button) { return .button }
        if element.traits.contains(.link) { return .link }
        if element.traits.contains(.adjustable) { return .adjustable }
        return nil
    }

    private static func isBackButton(_ element: AccessibilityElement) -> Bool {
        element.traits.contains(.backButton)
    }

    private static func isTransparentTopLevelWrapper(
        _ container: AccessibilityContainer,
        depth: Int,
        hasMultipleRootNodes: Bool
    ) -> Bool {
        guard depth == 0, hasMultipleRootNodes, !container.isModalBoundary else { return false }
        guard case .semanticGroup = container.type else { return false }
        return stableIdentifier(containerIdentifier(of: container)) == nil
    }

    private static func isRootShapeReplacement(before: [RootShapeToken], after: [RootShapeToken]) -> Bool {
        guard !before.isEmpty || !after.isEmpty else { return false }
        var afterCounts = after.reduce(into: [RootShapeToken: Int]()) { counts, token in
            counts[token, default: 0] += 1
        }
        var matchedCount = 0
        for token in before {
            guard let count = afterCounts[token], count > 0 else { continue }
            matchedCount += 1
            afterCounts[token] = count - 1
        }
        let maxCount = max(before.count, after.count)
        let persistRatio = Double(matchedCount) / Double(maxCount)
        return persistRatio < AccessibilityPolicy.tabSwitchPersistThreshold
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
