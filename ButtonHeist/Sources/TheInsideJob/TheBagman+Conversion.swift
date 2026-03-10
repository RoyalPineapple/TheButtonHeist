#if canImport(UIKit)
#if DEBUG
import UIKit
import AccessibilitySnapshotParser
import TheScore

// MARK: - Trait Names

extension TheBagman {

    /// All known trait-to-name mappings, evaluated in declaration order.
    private static let traitMapping: [(UIAccessibilityTraits, String)] = [
        (.button, "button"),
        (.link, "link"),
        (.image, "image"),
        (.staticText, "staticText"),
        (.header, "header"),
        (.adjustable, "adjustable"),
        (.searchField, "searchField"),
        (.selected, "selected"),
        (.notEnabled, "notEnabled"),
        (.keyboardKey, "keyboardKey"),
        (.summaryElement, "summaryElement"),
        (.updatesFrequently, "updatesFrequently"),
        (.playsSound, "playsSound"),
        (.startsMediaSession, "startsMediaSession"),
        (.allowsDirectInteraction, "allowsDirectInteraction"),
        (.causesPageTurn, "causesPageTurn"),
        (.tabBar, "tabBar"),
    ]

    func traitNames(_ traits: UIAccessibilityTraits) -> [String] {
        Self.traitMapping.compactMap { traits.contains($0.0) ? $0.1 : nil }
    }
}

// MARK: - Element Conversion

extension TheBagman {

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

    func buildActions(for index: Int, element: AccessibilityElement) -> [ElementAction] {
        var actions: [ElementAction] = []
        if hasInteractiveObject(at: index) {
            actions.append(.activate)
        }
        if element.traits.contains(.adjustable), hasInteractiveObject(at: index) {
            actions.append(.increment)
            actions.append(.decrement)
        }
        for name in customActionNames(elementAt: index) {
            actions.append(.custom(name))
        }
        return actions
    }
}

// MARK: - Tree Conversion

extension TheBagman {

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
        case .dataTable:
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
}

// MARK: - Interface Delta

extension TheBagman {

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

    func hierarchySignature(_ elements: [HeistElement]) -> Int {
        var hasher = Hasher()
        hasher.combine(elements.count)
        for element in elements {
            hasher.combine(element)
        }
        return hasher.finalize()
    }
}

// MARK: - Shape Helper

extension AccessibilityElement.Shape {
    var frame: CGRect {
        switch self {
        case let .frame(rect): return rect
        case let .path(path): return path.bounds
        }
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
