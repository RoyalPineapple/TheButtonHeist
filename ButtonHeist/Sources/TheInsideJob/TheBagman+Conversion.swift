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
        (UIAccessibilityTraits(rawValue: 0x8000000), "backButton"),
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
    struct ElementSnapshot {
        let elements: [HeistElement]
    }

    func snapshotElements() -> ElementSnapshot {
        var elements = cachedElements.enumerated().map { convertElement($0.element, index: $0.offset) }
        assignHeistIds(&elements)
        lastSnapshot = elements
        return ElementSnapshot(elements: elements)
    }

    // MARK: - Stable ID Synthesis

    /// Trait priority for heistId prefix — most descriptive wins.
    private static let traitPriority: [String] = [
        "backButton", "searchField", "textField", "adjustable",
        "button", "link", "image", "header", "tabBar",
    ]

    /// Assign deterministic `heistId` to each element.
    /// Developer-provided identifiers take priority. Synthesized IDs use
    /// `{trait}_{slug}` with label (or value as fallback) for the slug.
    /// Duplicates get `_1`, `_2` suffixes — all instances, not just the second.
    private func assignHeistIds(_ elements: inout [HeistElement]) {
        // Phase 1: generate base IDs
        for i in elements.indices {
            if let identifier = elements[i].identifier, !identifier.isEmpty {
                elements[i].heistId = identifier
            } else {
                elements[i].heistId = synthesizeBaseId(elements[i])
            }
        }

        // Phase 2: disambiguate duplicates
        var counts: [String: Int] = [:]
        for element in elements {
            counts[element.heistId, default: 0] += 1
        }

        var seen: [String: Int] = [:]
        for i in elements.indices {
            let base = elements[i].heistId
            if let count = counts[base], count > 1 {
                let index = seen[base, default: 0] + 1
                seen[base] = index
                elements[i].heistId = "\(base)_\(index)"
            }
        }
    }

    private func synthesizeBaseId(_ element: HeistElement) -> String {
        let traitPrefix = Self.traitPriority.first { element.traits.contains($0) }
            ?? (element.label != nil ? "staticText" : "element")

        let slug = slugify(element.label)
            ?? slugify(element.value)
            ?? slugify(element.description)

        if let slug {
            return "\(traitPrefix)_\(slug)"
        }
        return traitPrefix
    }

    private func slugify(_ text: String?) -> String? {
        guard let text, !text.isEmpty else { return nil }
        let slug = text.lowercased()
            .replacing(/[^a-z0-9]+/, with: "_")
            .trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        guard !slug.isEmpty else { return nil }
        return String(slug.prefix(24))
    }

    /// Compare two element snapshots and return a compact delta.
    ///
    /// Screen change detection is done by the caller via view controller identity —
    /// `isScreenChange` is true when the screen changed (VC identity or topology). This function handles
    /// the response payloads:
    /// - screen_changed → full new interface
    /// - layout_changed → elementsAdded/elementsRemoved diff
    /// - values_changed → valueChanges diff
    /// - no_change → element count only
    func computeDelta(
        before: ElementSnapshot,
        after: ElementSnapshot,
        afterTree: [AccessibilityHierarchy]?,
        isScreenChange: Bool
    ) -> InterfaceDelta {
        let beforeEls = before.elements
        let afterEls = after.elements

        // Screen changed: VC identity differs → return full new interface
        if isScreenChange {
            let tree = afterTree?.map { convertHierarchyNode($0) }
            let fullInterface = Interface(timestamp: Date(), elements: afterEls, tree: tree)
            return InterfaceDelta(
                kind: .screenChanged,
                elementCount: afterEls.count,
                newInterface: fullInterface
            )
        }

        // Same screen — quick check: if identical, nothing changed
        if beforeEls.hashValue == afterEls.hashValue && beforeEls == afterEls {
            return InterfaceDelta(kind: .noChange, elementCount: afterEls.count)
        }

        // Same screen, something changed — element-level diff
        return computeElementDelta(beforeEls: beforeEls, afterEls: afterEls)
    }

    private func computeElementDelta(
        beforeEls: [HeistElement],
        afterEls: [HeistElement]
    ) -> InterfaceDelta {
        let allOldIDs = Set(beforeEls.compactMap(\.identifier))
        let allNewIDs = Set(afterEls.compactMap(\.identifier))
        let allCommonIDs = allOldIDs.intersection(allNewIDs)

        let oldByID = Dictionary(grouping: beforeEls, by: { $0.identifier ?? "" })
            .filter { !$0.key.isEmpty }
        let newByID = Dictionary(grouping: afterEls, by: { $0.identifier ?? "" })
            .filter { !$0.key.isEmpty }

        let addedIDs = allNewIDs.subtracting(allOldIDs)
        let added = addedIDs.flatMap { newByID[$0] ?? [] }

        let removedIDs = allOldIDs.subtracting(allNewIDs)
        let removedElements = removedIDs.flatMap { oldByID[$0] ?? [] }
        let removedOrders = removedElements.map(\.order)
        let removedHeistIds = removedElements.map(\.heistId)

        var valueChanges: [ValueChange] = []
        for id in allCommonIDs {
            if let oldEl = oldByID[id]?.first, let newEl = newByID[id]?.first {
                if oldEl.value != newEl.value {
                    valueChanges.append(ValueChange(
                        order: newEl.order, heistId: newEl.heistId, identifier: id,
                        oldValue: oldEl.value, newValue: newEl.value
                    ))
                } else if oldEl.description != newEl.description || oldEl.label != newEl.label {
                    valueChanges.append(ValueChange(
                        order: newEl.order, heistId: newEl.heistId, identifier: id,
                        oldValue: oldEl.description, newValue: newEl.description
                    ))
                }
            }
        }

        let minCount = min(beforeEls.count, afterEls.count)
        for i in 0..<minCount {
            let oldEl = beforeEls[i]
            let newEl = afterEls[i]
            if oldEl.identifier != nil && newEl.identifier != nil { continue }
            if oldEl.description != newEl.description
                || oldEl.label != newEl.label
                || oldEl.value != newEl.value {
                valueChanges.append(ValueChange(
                    order: newEl.order, heistId: newEl.heistId, identifier: newEl.identifier,
                    oldValue: oldEl.description, newValue: newEl.description
                ))
            }
        }

        if added.isEmpty && removedOrders.isEmpty && valueChanges.isEmpty {
            if beforeEls.count != afterEls.count {
                return InterfaceDelta(
                    kind: .elementsChanged,
                    elementCount: afterEls.count,
                    added: afterEls.count > beforeEls.count
                        ? Array(afterEls.suffix(afterEls.count - beforeEls.count)) : nil,
                    removedOrders: afterEls.count < beforeEls.count
                        ? Array(afterEls.count..<beforeEls.count) : nil
                )
            }
            return InterfaceDelta(kind: .noChange, elementCount: afterEls.count)
        }

        if added.isEmpty && removedOrders.isEmpty {
            return InterfaceDelta(
                kind: .valuesChanged,
                elementCount: afterEls.count,
                valueChanges: valueChanges.isEmpty ? nil : valueChanges
            )
        }

        return InterfaceDelta(
            kind: .elementsChanged,
            elementCount: afterEls.count,
            added: added.isEmpty ? nil : added,
            removedOrders: removedOrders.isEmpty ? nil : removedOrders,
            removedHeistIds: removedHeistIds.isEmpty ? nil : removedHeistIds,
            valueChanges: valueChanges.isEmpty ? nil : valueChanges
        )
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
