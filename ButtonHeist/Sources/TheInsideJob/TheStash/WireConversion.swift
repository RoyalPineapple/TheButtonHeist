#if canImport(UIKit)
#if DEBUG
import UIKit

import TheScore

import AccessibilitySnapshotParser

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

    /// Converts internal accessibility types to wire format (HeistElement,
    /// InterfaceNode, ContainerInfo) and computes interface deltas.
    /// Pure transformations — no mutable state.
    @MainActor enum WireConversion {

    // MARK: - Trait Names

    /// Trait-to-name conversion delegated to AccessibilitySnapshotParser.
    /// The parser's `UIAccessibilityTraits.knownTraits` is the single source of truth
    /// for trait naming (22 traits including private traits like textEntry, switchButton).
    /// Strings are mapped to HeistTrait; unknown names are preserved via .unknown().
    static func traitNames(_ traits: UIAccessibilityTraits) -> [HeistTrait] {
        traits.traitNames.map { HeistTrait(rawValue: $0) ?? .unknown($0) }
    }

    // MARK: - Element Conversion

    static func convert(_ element: AccessibilityElement) -> HeistElement {
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
            actions: buildActions(for: element)
        )
    }

    static func buildActions(for element: AccessibilityElement) -> [ElementAction] {
        let isInteractive = Interactivity.isInteractive(element: element)
        let activate: [ElementAction] = isInteractive ? [.activate] : []
        let adjustable: [ElementAction] = (isInteractive && element.traits.contains(.adjustable))
            ? [.increment, .decrement]
            : []
        let custom = element.customActions.map { ElementAction.custom($0.name) }
        return activate + adjustable + custom
    }

    // MARK: - Wire Output

    /// Convert a ScreenElement to its wire representation.
    static func toWire(_ entry: ScreenElement) -> HeistElement {
        var wire = convert(entry.element)
        wire.heistId = entry.heistId
        return wire
    }

    /// Convert a snapshot to wire format. Use at serialization boundaries.
    static func toWire(_ entries: [ScreenElement]) -> [HeistElement] {
        entries.map { toWire($0) }
    }

    // MARK: - Tree Conversion (registry → wire)

    /// Convert the persistent registry tree to its canonical wire form.
    /// Every element in the registry — visible, scrolled out, or otherwise
    /// off-live-parse — appears at its tree position.
    static func toWireTree(_ roots: [RegistryNode]) -> [InterfaceNode] {
        roots.map { toWireNode($0) }
    }

    private static func toWireNode(_ node: RegistryNode) -> InterfaceNode {
        switch node {
        case .element(let element):
            return .element(toWire(element))
        case .container(let entry, let children):
            return .container(toContainerInfo(entry.container), children: children.map(toWireNode))
        }
    }

    private static func toContainerInfo(_ container: AccessibilityContainer) -> ContainerInfo {
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
            frameX: Double(container.frame.origin.x.sanitizedForJSON),
            frameY: Double(container.frame.origin.y.sanitizedForJSON),
            frameWidth: Double(container.frame.size.width.sanitizedForJSON),
            frameHeight: Double(container.frame.size.height.sanitizedForJSON)
        )
    }

    // MARK: - Interface Delta

    /// Compare two element snapshots and return a compact delta.
    ///
    /// Screen change detection is done by the caller via view controller identity —
    /// `isScreenChange` is true when the screen changed. This function handles
    /// the response payloads:
    /// - screen_changed → full new interface tree
    /// - elements_changed → added/removed/updated diff
    /// - no_change → element count only
    static func computeDelta(
        before: [ScreenElement],
        after: [ScreenElement],
        afterTree: [RegistryNode],
        isScreenChange: Bool
    ) -> InterfaceDelta {
        // Screen changed: VC identity differs → return full new interface
        if isScreenChange {
            let fullInterface = Interface(timestamp: Date(), tree: toWireTree(afterTree))
            return InterfaceDelta(
                kind: .screenChanged,
                elementCount: after.count,
                newInterface: fullInterface
            )
        }

        // Fast no-change check on internal types — compares heistId + AccessibilityElement
        // (both Hashable) without wire conversion. This is the hot path for Pulse polling
        // where most cycles produce no change.
        if before.count == after.count {
            var unchanged = true
            for index in before.indices {
                if before[index].heistId != after[index].heistId
                    || before[index].element != after[index].element {
                    unchanged = false
                    break
                }
            }
            if unchanged {
                return InterfaceDelta(kind: .noChange, elementCount: after.count)
            }
        }

        // Something changed — convert to wire for property-level diff.
        let beforeWire = toWire(before)
        let afterWire = toWire(after)

        return computeElementDelta(beforeEls: beforeWire, afterEls: afterWire)
    }

    /// Semantic element diff — heistId is the sole matching key.
    ///
    /// heistId encodes developer identifiers or synthesized trait+label (value excluded).
    /// For identifier-matched elements, label changes surface as property updates.
    /// For synthesized IDs, label changes produce different heistIds and appear as remove + add.
    ///
    /// Returns added/removed/updated categories. Updated elements carry per-property diffs.
    private static func computeElementDelta(
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
            updated += zip(oldEls.prefix(pairCount), newEls.prefix(pairCount))
                .compactMap { buildElementUpdate(old: $0, new: $1) }
            removed += oldEls.suffix(from: pairCount).map(\.heistId)
            added += newEls.suffix(from: pairCount)
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
    private static func buildElementUpdate(old: HeistElement, new: HeistElement) -> ElementUpdate? {
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
        if old.customContent != new.customContent {
            let formatContent: ([HeistCustomContent]?) -> String? = { content in
                let formatted = content?.compactMap { item -> String? in
                    switch (item.label.isEmpty, item.value.isEmpty) {
                    case (false, false): return "\(item.label): \(item.value)"
                    case (false, true): return item.label
                    case (true, false): return item.value
                    case (true, true): return nil
                    }
                }
                guard let formatted, !formatted.isEmpty else { return nil }
                return formatted.joined(separator: "; ")
            }
            changes.append(PropertyChange(
                property: .customContent,
                old: formatContent(old.customContent),
                new: formatContent(new.customContent)
            ))
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
} // extension TheStash

#endif // DEBUG
#endif // canImport(UIKit)
