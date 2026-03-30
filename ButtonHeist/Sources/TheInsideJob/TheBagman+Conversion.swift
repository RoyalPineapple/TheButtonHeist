#if canImport(UIKit)
#if DEBUG
import UIKit
import AccessibilitySnapshotParser
import TheScore

// MARK: - Trait Names

extension TheBagman {

    /// Trait-to-name conversion delegated to AccessibilitySnapshotParser.
    /// The parser's `UIAccessibilityTraits.knownTraits` is the single source of truth
    /// for trait naming (22 traits including private traits like textEntry, switchButton).
    /// Strings are mapped to HeistTrait; unknown names are preserved via .unknown().
    func traitNames(_ traits: UIAccessibilityTraits) -> [HeistTrait] {
        traits.traitNames.map { HeistTrait(rawValue: $0) ?? .unknown($0) }
    }
}

// MARK: - Element Conversion

extension TheBagman {

    func convertElement(_ element: AccessibilityElement, index: Int) -> HeistElement {
        let frame = element.shape.frame
        return HeistElement(
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
        let (groupType, label, value, identifier): (GroupType, String?, String?, String?)
        switch container.type {
        case let .semanticGroup(l, v, id):
            groupType = .semanticGroup
            label = l; value = v; identifier = id
        case .list:
            groupType = .list
            label = nil; value = nil; identifier = nil
        case .landmark:
            groupType = .landmark
            label = nil; value = nil; identifier = nil
        case .dataTable:
            groupType = .dataTable
            label = nil; value = nil; identifier = nil
        case .tabBar:
            groupType = .tabBar
            label = nil; value = nil; identifier = nil
        case .scrollable(let contentSize):
            groupType = .scrollable
            label = nil; value = "\(Int(contentSize.width))x\(Int(contentSize.height))"; identifier = nil
        }
        return Group(
            type: groupType,
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

// MARK: - Single Element Conversion

extension TheBagman {

    /// Convert a single AccessibilityElement to a wire HeistElement with heistId assigned.
    /// Used when we've matched at the hierarchy level and need to project one result for the wire.
    func convertAndAssignId(_ element: AccessibilityElement, index: Int) -> HeistElement {
        var wire = convertElement(element, index: index)
        if let identifier = element.identifier, !identifier.isEmpty {
            wire.heistId = identifier
        } else {
            wire.heistId = synthesizeBaseId(wire)
        }
        return wire
    }
}

// MARK: - Interface Delta

extension TheBagman {

    /// Return wire elements for the currently visible set and mark them as presented.
    /// The screen element registry is updated during refreshAccessibilityData() —
    /// this method is a cheap read that extracts the visible subset.
    func snapshotElements() -> [HeistElement] {
        var result: [(Int, HeistElement)] = []
        for heistId in onScreen {
            guard var entry = screenElements[heistId] else { continue }
            if !entry.presented {
                entry.presented = true
                screenElements[heistId] = entry
            }
            result.append((entry.lastTraversalIndex, entry.wire))
        }
        return result.sorted { $0.0 < $1.0 }.map(\.1)
    }

    /// Return wire elements for ALL known elements — visible and off-screen.
    /// Used by get_interface --full to return the complete screen census.
    func snapshotAllElements() -> [HeistElement] {
        screenElements.values
            .sorted { $0.lastTraversalIndex < $1.lastTraversalIndex }
            .map(\.wire)
    }

    // MARK: - Stable ID Synthesis

    /// Trait priority for heistId prefix — most descriptive wins.
    /// Names come from AccessibilitySnapshotParser's knownTraits.
    private static let traitPriority: [HeistTrait] = [
        .backButton, .searchField, .textEntry, .switchButton, .adjustable,
        .button, .link, .image, .header, .tabBar,
    ]

    /// Assign deterministic `heistId` to each element.
    /// Developer-provided identifiers take priority — they become the heistId directly.
    /// Synthesized IDs use `{trait}_{slug}` with label for the slug (value excluded for stability).
    /// Duplicates get `_1`, `_2` suffixes in traversal order — all instances, not just the second.
    func assignHeistIds(_ elements: inout [HeistElement]) {
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

    func synthesizeBaseId(_ element: HeistElement) -> String {
        let traitPrefix = Self.traitPriority.first { element.traits.contains($0) }?.rawValue
            ?? (element.label != nil ? HeistTrait.staticText.rawValue : "element")

        // Value is intentionally excluded — it changes on interaction (toggles,
        // sliders, checkboxes) and must not affect element identity.
        let slug = slugify(element.label)
            ?? slugify(element.description)

        if let slug {
            return "\(traitPrefix)_\(slug)"
        }
        return traitPrefix
    }

    func slugify(_ text: String?) -> String? {
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
    /// - elements_changed → added/removed/updated diff
    /// - no_change → element count only
    func computeDelta(
        before: [HeistElement],
        after: [HeistElement],
        afterTree: [AccessibilityHierarchy]?,
        isScreenChange: Bool
    ) -> InterfaceDelta {
        // Screen changed: VC identity differs → return full new interface
        if isScreenChange {
            let tree = afterTree?.map { convertHierarchyNode($0) }
            let fullInterface = Interface(timestamp: Date(), elements: after, tree: tree)
            return InterfaceDelta(
                kind: .screenChanged,
                elementCount: after.count,
                newInterface: fullInterface
            )
        }

        // Same screen — quick check: if identical, nothing changed
        if before.hashValue == after.hashValue && before == after {
            return InterfaceDelta(kind: .noChange, elementCount: after.count)
        }

        // Same screen, something changed — element-level diff
        return computeElementDelta(beforeEls: before, afterEls: after)
    }

    /// Semantic element diff — heistId is the sole matching key.
    ///
    /// heistId encodes developer identifiers or synthesized trait+label (value excluded).
    /// For identifier-matched elements, label changes surface as property updates.
    /// For synthesized IDs, label changes produce different heistIds and appear as remove + add.
    ///
    /// Returns added/removed/updated categories. Updated elements carry per-property diffs.
    private func computeElementDelta(
        beforeEls: [HeistElement],
        afterEls: [HeistElement]
    ) -> InterfaceDelta {
        let oldByHeistId = Dictionary(grouping: beforeEls, by: \.heistId)
        let newByHeistId = Dictionary(grouping: afterEls, by: \.heistId)
        let allHeistIds = Set(oldByHeistId.keys).union(newByHeistId.keys)

        var updated: [ElementUpdate] = []
        var added: [HeistElement] = []
        var removed: [String] = []

        for hid in allHeistIds {
            let oldEls = oldByHeistId[hid] ?? []
            let newEls = newByHeistId[hid] ?? []
            let pairCount = min(oldEls.count, newEls.count)
            for i in 0..<pairCount {
                if let update = buildElementUpdate(old: oldEls[i], new: newEls[i]) {
                    updated.append(update)
                }
            }
            for i in pairCount..<oldEls.count {
                removed.append(oldEls[i].heistId)
            }
            for i in pairCount..<newEls.count {
                added.append(newEls[i])
            }
        }

        if added.isEmpty && removed.isEmpty && updated.isEmpty {
            return InterfaceDelta(kind: .noChange, elementCount: afterEls.count)
        }

        return InterfaceDelta(
            kind: .elementsChanged,
            elementCount: afterEls.count,
            added: added.isEmpty ? nil : added,
            removed: removed.isEmpty ? nil : removed,
            updated: updated.isEmpty ? nil : updated
        )
    }

    /// Build an ElementUpdate if any mutable property differs.
    private func buildElementUpdate(old: HeistElement, new: HeistElement) -> ElementUpdate? {
        var changes: [PropertyChange] = []

        if old.label != new.label {
            changes.append(PropertyChange(property: .label, old: old.label, new: new.label))
        }
        if old.value != new.value {
            changes.append(PropertyChange(property: .value, old: old.value, new: new.value))
        }
        if old.traits != new.traits {
            let oldTraits = old.traits.map(\.rawValue).joined(separator: ", ")
            let newTraits = new.traits.map(\.rawValue).joined(separator: ", ")
            changes.append(PropertyChange(property: .traits, old: oldTraits, new: newTraits))
        }
        if old.hint != new.hint {
            changes.append(PropertyChange(property: .hint, old: old.hint, new: new.hint))
        }
        if old.actions != new.actions {
            let oldActions = old.actions.map(\.description).joined(separator: ", ")
            let newActions = new.actions.map(\.description).joined(separator: ", ")
            changes.append(PropertyChange(property: .actions, old: oldActions, new: newActions))
        }
        let oldFrame = "\(Int(old.frameX)),\(Int(old.frameY)),\(Int(old.frameWidth)),\(Int(old.frameHeight))"
        let newFrame = "\(Int(new.frameX)),\(Int(new.frameY)),\(Int(new.frameWidth)),\(Int(new.frameHeight))"
        if oldFrame != newFrame {
            changes.append(PropertyChange(property: .frame, old: oldFrame, new: newFrame))
        }
        let oldAP = "\(Int(old.activationPointX)),\(Int(old.activationPointY))"
        let newAP = "\(Int(new.activationPointX)),\(Int(new.activationPointY))"
        if oldAP != newAP {
            changes.append(PropertyChange(property: .activationPoint, old: oldAP, new: newAP))
        }

        guard !changes.isEmpty else { return nil }
        return ElementUpdate(heistId: new.heistId, changes: changes)
    }

}

// MARK: - HeistElement Array Helpers

extension Array where Element == HeistElement {
    /// Label of the first header-traited element (screen name hint).
    var screenName: String? {
        first { $0.traits.contains(.header) }?.label
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
