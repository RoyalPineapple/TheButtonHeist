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
        let rootShape: [String]
    }

    struct Marker: Equatable, Hashable {
        let label: String?
        let value: String?
        let identifier: String?
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

    private static func rootShapeTokens(in hierarchy: [AccessibilityHierarchy]) -> [String] {
        var tokens: [String] = []
        for node in hierarchy {
            appendShapeTokens(from: node, depth: 0, into: &tokens)
        }
        return Array(tokens.prefix(80))
    }

    private static func appendShapeTokens(
        from node: AccessibilityHierarchy,
        depth: Int,
        into tokens: inout [String]
    ) {
        switch node {
        case .element(let element, _):
            guard let role = structuralRole(of: element) else { return }
            var token = "e\(depth):\(role)"
            if let identifier = stableIdentifier(element.identifier) {
                token += "#\(identifier)"
            }
            if element.traits.contains(.selected) {
                token += ":selected"
            }
            tokens.append(token)
        case .container(let container, let children):
            if isWindowMarker(container) {
                for child in children {
                    appendShapeTokens(from: child, depth: depth, into: &tokens)
                }
                return
            }
            tokens.append("c\(depth):\(containerRole(of: container))")
            for child in children {
                appendShapeTokens(from: child, depth: depth + 1, into: &tokens)
            }
        }
    }

    private static func containerRole(of container: AccessibilityContainer) -> String {
        let suffix = container.isModalBoundary ? ":modal" : ""
        switch container.type {
        case .semanticGroup(_, _, let identifier):
            if let identifier = stableIdentifier(identifier) { return "group#\(identifier)\(suffix)" }
            return "group\(suffix)"
        case .list:
            return "list\(suffix)"
        case .landmark:
            return "landmark\(suffix)"
        case .dataTable:
            return "dataTable\(suffix)"
        case .tabBar:
            return "tabBar\(suffix)"
        case .scrollable:
            return "scrollable\(suffix)"
        }
    }

    private static func structuralRole(of element: AccessibilityElement) -> String? {
        if isBackButton(element) { return "backButton" }
        if element.traits.contains(.header) { return "header" }
        if element.traits.contains(UIAccessibilityTraits.fromNames(["tabBarItem"])) { return "tabBarItem" }
        if element.traits.contains(.searchField) { return "searchField" }
        if element.traits.contains(UIAccessibilityTraits.fromNames(["textEntry"])) { return "textEntry" }
        if element.traits.contains(.button) { return "button" }
        if element.traits.contains(.link) { return "link" }
        if element.traits.contains(.adjustable) { return "adjustable" }
        return nil
    }

    private static func isBackButton(_ element: AccessibilityElement) -> Bool {
        element.traits.contains(UIAccessibilityTraits.fromNames(["backButton"]))
    }

    private static func isWindowMarker(_ container: AccessibilityContainer) -> Bool {
        guard case .semanticGroup(_, let value, _) = container.type else { return false }
        return value?.hasPrefix("windowLevel:") == true
    }

    private static func isRootShapeReplacement(before: [String], after: [String]) -> Bool {
        guard !before.isEmpty || !after.isEmpty else { return false }
        var afterCounts = after.reduce(into: [String: Int]()) { counts, token in
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
