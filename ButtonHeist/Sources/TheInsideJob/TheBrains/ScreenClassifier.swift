#if canImport(UIKit)
#if DEBUG
import UIKit

import ThePlans
import TheScore

import AccessibilitySnapshotParser

/// Classifies parsed accessibility snapshots.
///
/// Tripwire triggers parsing; this type is the single place that decides
/// whether the parsed result should be treated as a new screen. Same-screen
/// element and tree changes are derived from accessibility trace captures.
@MainActor enum ScreenClassifier { // swiftlint:disable:this agent_main_actor_value_type

    struct Snapshot: Equatable {
        let signature: ScreenSignature
        let firstResponderHeistId: HeistId?
    }

    struct ScreenSignature: Equatable {
        let modalMarkers: [Marker]
        let primaryHeader: String?
        let backButton: Marker?
        let selectedTabs: Set<Marker>
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
        case container(AccessibilityContainerKind)
        case element(ElementRootShapeRole)
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
        let isScrollable: Bool
    }

    enum Classification: Equatable {
        case sameGeneration
        case inferredScreenChange(reason: AccessibilityObservationFallbackReason)
    }

    static func snapshot(of tree: InterfaceTree) -> Snapshot {
        Snapshot(
            signature: signature(
                hierarchy: tree.viewportCapture.hierarchy,
                elements: tree.viewportCapture.hierarchy.sortedElements
            ),
            firstResponderHeistId: tree.firstResponderHeistId
        )
    }

    static func snapshot(of stash: TheStash) -> Snapshot {
        snapshot(of: stash.interfaceTree)
    }

    static func classify(before: Snapshot, after: Snapshot) -> Classification {
        let beforeSignature = before.signature
        let afterSignature = after.signature

        if beforeSignature.modalMarkers != afterSignature.modalMarkers {
            return .inferredScreenChange(reason: .modalBoundaryChanged)
        }
        if beforeSignature.selectedTabs != afterSignature.selectedTabs {
            return .inferredScreenChange(reason: .selectedTabChanged)
        }
        if beforeSignature.backButton != afterSignature.backButton {
            return .inferredScreenChange(reason: .navigationMarkerChanged)
        }
        if beforeSignature.primaryHeader != afterSignature.primaryHeader {
            return .inferredScreenChange(reason: .primaryHeaderChanged)
        }
        if beforeSignature.rootShape != afterSignature.rootShape,
           !hasStableInteractionContext(before: before, after: after),
           isRootShapeReplacement(before: beforeSignature.rootShape, after: afterSignature.rootShape) {
            return .inferredScreenChange(reason: .rootShapeChanged)
        }
        return .sameGeneration
    }

    static func signature(
        hierarchy: [AccessibilityHierarchy],
        elements: [AccessibilityElement]
    ) -> ScreenSignature {
        ScreenSignature(
            modalMarkers: modalMarkers(in: hierarchy),
            primaryHeader: summaryElement(in: elements)?.label,
            backButton: elements.first(where: isBackButton).map(marker(for:)),
            selectedTabs: selectedTabMarkers(in: hierarchy),
            rootShape: rootShapeTokens(in: hierarchy)
        )
    }

    private static func summaryElement(in elements: [AccessibilityElement]) -> AccessibilityElement? {
        if let explicit = elements.first(where: { $0.traits.contains(.summaryElement) }) {
            return explicit
        }
        return elements
            .enumerated()
            .compactMap { index, element -> (index: Int, element: AccessibilityElement)? in
                guard element.traits.contains(.header), element.label != nil else { return nil }
                return (index, element)
            }
            .min { left, right in
                let leftFrame = left.element.shape.frame
                let rightFrame = right.element.shape.frame
                if leftFrame.minY != rightFrame.minY { return leftFrame.minY < rightFrame.minY }
                if leftFrame.minX != rightFrame.minX { return leftFrame.minX < rightFrame.minX }
                return left.index < right.index
            }?
            .element
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
        let facts = container.containerPredicateFacts
        let identifier = stableIdentifier(facts.identifier)
        switch facts.role {
        case .none:
            return Marker(
                label: facts.isScrollable ? "scrollable" : "container",
                value: nil,
                identifier: identifier
            )
        case .semanticGroup(let label, let value):
            return Marker(label: label, value: value, identifier: identifier)
        case .list:
            return Marker(label: "list", value: nil, identifier: identifier)
        case .landmark:
            return Marker(label: "landmark", value: nil, identifier: identifier)
        case .dataTable(let rowCount, let columnCount):
            return Marker(label: "dataTable", value: "\(rowCount)x\(columnCount)", identifier: identifier)
        case .tabBar:
            return Marker(label: "tabBar", value: nil, identifier: identifier)
        case .series:
            return Marker(label: "series", value: nil, identifier: identifier)
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

    private static func selectedTabMarkers(in hierarchy: [AccessibilityHierarchy]) -> Set<Marker> {
        Set(hierarchy.compactMap(
            context: false,
            container: { isInTabBar, container in
                if case .tabBar = container.type { return true }
                return isInTabBar
            },
            element: { element, _, isInTabBar in
                guard isInTabBar, element.traits.contains(.selected) else { return nil }
                return marker(for: element)
            }
        ))
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
        return tokens
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
                        isModal: false,
                        isScrollable: false
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
            let facts = container.containerPredicateFacts
            tokens.append(
                RootShapeToken(
                    kind: .container(facts.role.kind),
                    depth: depth,
                    stableIdentifier: stableIdentifier(facts.identifier),
                    state: RootShapeState(
                        isSelected: false,
                        isModal: facts.isModalBoundary,
                        isScrollable: facts.isScrollable
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
        return stableIdentifier(container.containerPredicateFacts.identifier) == nil
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
