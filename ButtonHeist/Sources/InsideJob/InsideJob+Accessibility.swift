#if canImport(UIKit)
#if DEBUG
import UIKit
import AccessibilitySnapshotParser
import TheScore

extension InsideJob {

    // MARK: - Accessibility Data Refresh

    /// Refresh the accessibility hierarchy. Provides a visitor closure to the parser
    /// that captures weak references to interactive objects for action dispatch.
    /// Returns the hierarchy tree for callers that need it (e.g., sendInterface).
    @discardableResult
    func refreshAccessibilityData() -> [AccessibilityHierarchy]? {
        let windows = getTraversableWindows()
        guard !windows.isEmpty else { return nil }

        var allHierarchy: [AccessibilityHierarchy] = []
        var newElementObjects: [Int: WeakObject] = [:]
        var allElements: [AccessibilityElement] = []

        for (window, rootView) in windows {
            let baseIndex = allElements.count
            let windowTree = parser.parseAccessibilityHierarchy(in: rootView) { _, index, object in
                newElementObjects[baseIndex + index] = WeakObject(object: object)
            }
            let windowElements = windowTree.flattenToElements()

            // Wrap each window's tree in a container node when multiple windows are present
            if windows.count > 1 {
                let windowName = NSStringFromClass(type(of: window))
                let container = AccessibilityContainer(
                    type: .semanticGroup(
                        label: windowName,
                        value: "windowLevel: \(window.windowLevel.rawValue)",
                        identifier: nil
                    ),
                    frame: window.frame
                )
                let reindexed = windowTree.reindexed(offset: baseIndex)
                allHierarchy.append(.container(container, children: reindexed))
            } else {
                allHierarchy.append(contentsOf: windowTree)
            }

            allElements.append(contentsOf: windowElements)
        }

        elementObjects = newElementObjects
        cachedElements = allElements
        return allHierarchy
    }

    /// Returns all windows that should be included in the accessibility traversal,
    /// sorted by windowLevel descending (frontmost first).
    /// Excludes our own overlay windows (FingerprintWindow).
    func getTraversableWindows() -> [(window: UIWindow, rootView: UIView)] {
        guard let windowScene = UIApplication.shared.connectedScenes
                .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene else {
            return []
        }

        return windowScene.windows
            .filter { window in
                !(window is FingerprintWindow) &&
                !window.isHidden &&
                window.bounds.size != .zero
            }
            .sorted { $0.windowLevel > $1.windowLevel }
            .map { ($0, $0 as UIView) }
    }

    // MARK: - Element Conversion

    func convertElement(_ element: AccessibilityElement, index: Int) -> HeistElement {
        let frame = element.shape.frame
        return HeistElement(
            order: index,
            description: element.description,
            label: element.label,
            value: element.value,
            identifier: element.identifier,
            hint: element.hint,
            traits: traitNames(element.traits),
            frameX: frame.origin.x,
            frameY: frame.origin.y,
            frameWidth: frame.size.width,
            frameHeight: frame.size.height,
            activationPointX: element.activationPoint.x,
            activationPointY: element.activationPoint.y,
            respondsToUserInteraction: element.respondsToUserInteraction,
            customContent: element.customContent.isEmpty ? nil : element.customContent.map {
                HeistCustomContent(label: $0.label, value: $0.value, isImportant: $0.isImportant)
            },
            actions: buildActions(for: index, element: element)
        )
    }

    private func traitNames(_ traits: UIAccessibilityTraits) -> [String] {
        var names: [String] = []
        if traits.contains(.button) { names.append("button") }
        if traits.contains(.link) { names.append("link") }
        if traits.contains(.image) { names.append("image") }
        if traits.contains(.staticText) { names.append("staticText") }
        if traits.contains(.header) { names.append("header") }
        if traits.contains(.adjustable) { names.append("adjustable") }
        if traits.contains(.searchField) { names.append("searchField") }
        if traits.contains(.selected) { names.append("selected") }
        if traits.contains(.notEnabled) { names.append("notEnabled") }
        if traits.contains(.keyboardKey) { names.append("keyboardKey") }
        if traits.contains(.summaryElement) { names.append("summaryElement") }
        if traits.contains(.updatesFrequently) { names.append("updatesFrequently") }
        if traits.contains(.playsSound) { names.append("playsSound") }
        if traits.contains(.startsMediaSession) { names.append("startsMediaSession") }
        if traits.contains(.allowsDirectInteraction) { names.append("allowsDirectInteraction") }
        if traits.contains(.causesPageTurn) { names.append("causesPageTurn") }
        if traits.contains(.tabBar) { names.append("tabBar") }
        return names
    }

    private func buildActions(for index: Int, element: AccessibilityElement) -> [ElementAction] {
        var actions: [ElementAction] = []
        if theSafecracker.hasInteractiveObject(at: index) {
            actions.append(.activate)
        }
        if element.traits.contains(.adjustable), theSafecracker.hasInteractiveObject(at: index) {
            actions.append(.increment)
            actions.append(.decrement)
        }
        for name in theSafecracker.customActionNames(elementAt: index) {
            actions.append(.custom(name))
        }
        return actions
    }

    // MARK: - Tree Conversion

    func convertHierarchyNode(_ node: AccessibilityHierarchy) -> ElementNode {
        switch node {
        case let .element(_, traversalIndex):
            return .element(order: traversalIndex)
        case let .container(container, children):
            let containerData = convertContainer(container)
            let childNodes = children.map { convertHierarchyNode($0) }
            return .container(containerData, children: childNodes)
        }
    }

    private func convertContainer(_ container: AccessibilityContainer) -> Group {
        let (typeName, label, value, identifier): (String, String?, String?, String?)
        switch container.type {
        case let .semanticGroup(l, v, id):
            typeName = "semanticGroup"
            label = l; value = v; identifier = id
        case .list:
            typeName = "list"
            label = nil; value = nil; identifier = nil
        case .landmark:
            typeName = "landmark"
            label = nil; value = nil; identifier = nil
        case let .dataTable(rowCount: _, columnCount: _):
            typeName = "dataTable"
            label = nil; value = nil; identifier = nil
        case .tabBar:
            typeName = "tabBar"
            label = nil; value = nil; identifier = nil
        }
        return Group(
            type: typeName,
            label: label,
            value: value,
            identifier: identifier,
            frameX: container.frame.origin.x,
            frameY: container.frame.origin.y,
            frameWidth: container.frame.size.width,
            frameHeight: container.frame.size.height
        )
    }

    // MARK: - Interface Delta

    /// Convert current cachedElements to wire HeistElements for delta comparison.
    func snapshotElements() -> [HeistElement] {
        cachedElements.enumerated().map { convertElement($0.element, index: $0.offset) }
    }

    /// Compare two element snapshots and return a compact delta.
    func computeDelta(
        before: [HeistElement],
        after: [HeistElement],
        afterTree: [AccessibilityHierarchy]?
    ) -> InterfaceDelta {
        // Quick check: if hash is identical, nothing changed
        if before.hashValue == after.hashValue && before == after {
            return InterfaceDelta(kind: .noChange, elementCount: after.count)
        }

        // Build identifier sets for screen-change detection
        let oldIDs = Set(before.compactMap(\.identifier))
        let newIDs = Set(after.compactMap(\.identifier))
        let commonIDs = oldIDs.intersection(newIDs)
        let maxCount = max(oldIDs.count, newIDs.count, 1)

        // Screen change: fewer than 50% of identifiers overlap
        if commonIDs.count < maxCount / 2 {
            let tree = afterTree?.map { convertHierarchyNode($0) }
            let fullInterface = Interface(timestamp: Date(), elements: after, tree: tree)
            return InterfaceDelta(
                kind: .screenChanged,
                elementCount: after.count,
                newInterface: fullInterface
            )
        }

        // Element-level diff
        let oldByID = Dictionary(grouping: before, by: { $0.identifier ?? "" }).filter { !$0.key.isEmpty }
        let newByID = Dictionary(grouping: after, by: { $0.identifier ?? "" }).filter { !$0.key.isEmpty }

        let addedIDs = newIDs.subtracting(oldIDs)
        let added = addedIDs.flatMap { newByID[$0] ?? [] }

        let removedIDs = oldIDs.subtracting(newIDs)
        let removedOrders = removedIDs.flatMap { oldByID[$0] ?? [] }.map(\.order)

        var valueChanges: [ValueChange] = []
        // Identifier-based comparison: check value, description, and label
        for id in commonIDs {
            if let oldEl = oldByID[id]?.first, let newEl = newByID[id]?.first {
                if oldEl.value != newEl.value {
                    valueChanges.append(ValueChange(
                        order: newEl.order,
                        identifier: id,
                        oldValue: oldEl.value,
                        newValue: newEl.value
                    ))
                } else if oldEl.description != newEl.description || oldEl.label != newEl.label {
                    valueChanges.append(ValueChange(
                        order: newEl.order,
                        identifier: id,
                        oldValue: oldEl.description,
                        newValue: newEl.description
                    ))
                }
            }
        }

        // Order-based comparison for elements without identifiers
        // (catches segmented controls, unlabeled buttons, etc.)
        let minCount = min(before.count, after.count)
        for i in 0..<minCount {
            let oldEl = before[i]
            let newEl = after[i]
            if oldEl.identifier != nil && newEl.identifier != nil { continue }
            if oldEl.description != newEl.description
                || oldEl.label != newEl.label
                || oldEl.value != newEl.value {
                valueChanges.append(ValueChange(
                    order: newEl.order,
                    identifier: newEl.identifier,
                    oldValue: oldEl.description,
                    newValue: newEl.description
                ))
            }
        }

        if added.isEmpty && removedOrders.isEmpty && valueChanges.isEmpty {
            if before.count != after.count {
                return InterfaceDelta(
                    kind: .elementsChanged,
                    elementCount: after.count,
                    added: after.count > before.count ? Array(after.suffix(after.count - before.count)) : nil,
                    removedOrders: after.count < before.count ? Array(after.count..<before.count) : nil
                )
            }
            return InterfaceDelta(kind: .noChange, elementCount: after.count)
        }

        if added.isEmpty && removedOrders.isEmpty {
            return InterfaceDelta(
                kind: .valuesChanged,
                elementCount: after.count,
                valueChanges: valueChanges.isEmpty ? nil : valueChanges
            )
        }

        return InterfaceDelta(
            kind: .elementsChanged,
            elementCount: after.count,
            added: added.isEmpty ? nil : added,
            removedOrders: removedOrders.isEmpty ? nil : removedOrders,
            valueChanges: valueChanges.isEmpty ? nil : valueChanges
        )
    }
}

// MARK: - Shape Helper

private extension AccessibilityElement.Shape {
    var frame: CGRect {
        switch self {
        case let .frame(rect): return rect
        case let .path(path): return path.bounds
        }
    }
}

// MARK: - AccessibilityHierarchy Reindexing

extension Array where Element == AccessibilityHierarchy {
    func reindexed(offset: Int) -> [AccessibilityHierarchy] {
        guard offset != 0 else { return self }
        return map { node in
            switch node {
            case let .element(element, index):
                return .element(element, traversalIndex: index + offset)
            case let .container(container, children):
                return .container(container, children: children.reindexed(offset: offset))
            }
        }
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
