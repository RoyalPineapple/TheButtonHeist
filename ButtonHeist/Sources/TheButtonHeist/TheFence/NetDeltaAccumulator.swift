import Foundation

import TheScore

// MARK: - Net Delta Accumulator

/// Merges per-step deltas into a single net delta (like git squash).
/// If any step triggered a screen change, the net delta is screenChanged
/// with the final interface. Otherwise, tracks net added/removed/updated.
internal enum NetDeltaAccumulator {
    static func merge(deltas: [InterfaceDelta]) -> InterfaceDelta? {
        let meaningful = deltas.filter { $0.kind != .noChange }
        guard !meaningful.isEmpty else { return nil }

        // If any step was a screen change, the net is screenChanged with the last one's interface
        if let lastScreenChange = meaningful.last(where: { $0.kind == .screenChanged }) {
            return mergeAfterScreenChange(screenChange: lastScreenChange, deltas: deltas)
        }

        // All steps are elementsChanged — accumulate net adds/removes/updates
        return mergeElementDeltas(meaningful)
    }

    private static func mergeAfterScreenChange(
        screenChange: InterfaceDelta, deltas: [InterfaceDelta]
    ) -> InterfaceDelta {
        // Find steps after the last screen change and fold their element changes
        // into the screen change's interface
        guard let screenIndex = deltas.lastIndex(where: { $0.kind == .screenChanged }) else {
            return screenChange
        }
        let afterScreen = Array(deltas[(screenIndex + 1)...])
        let postDeltas = afterScreen.filter { $0.kind == .elementsChanged }
        if postDeltas.isEmpty {
            return screenChange
        }
        // Merge the post-screen element changes into one
        guard let postMerge = mergeElementDeltas(postDeltas) else { return screenChange }
        let finalInterface = screenChange.newInterface.map {
            apply(postMerge, to: $0)
        }
        return InterfaceDelta(
            kind: .screenChanged,
            elementCount: finalInterface?.elements.count ?? postMerge.elementCount,
            added: postMerge.added,
            removed: postMerge.removed,
            updated: postMerge.updated,
            newInterface: finalInterface
        )
    }

    private static func apply(_ delta: InterfaceDelta, to interface: Interface) -> Interface {
        var elementsById = Dictionary(uniqueKeysWithValues: interface.elements.map { ($0.heistId, $0) })
        for heistId in delta.removed ?? [] {
            elementsById.removeValue(forKey: heistId)
        }
        for element in delta.added ?? [] {
            elementsById[element.heistId] = element
        }
        for update in delta.updated ?? [] {
            guard var element = elementsById[update.heistId] else { continue }
            for change in update.changes {
                apply(change, to: &element)
            }
            elementsById[update.heistId] = element
        }
        let elements = interface.elements
            .filter { elementsById[$0.heistId] != nil }
            .map { elementsById[$0.heistId] ?? $0 }
            + (delta.added ?? []).filter { original in
                !interface.elements.contains { $0.heistId == original.heistId }
            }
        return Interface(timestamp: interface.timestamp, elements: elements, tree: interface.tree)
    }

    private static func apply(_ change: PropertyChange, to element: inout HeistElement) {
        switch change.property {
        case .label:
            element.label = change.new
        case .value:
            element.value = change.new
        case .hint:
            element.hint = change.new
        default:
            break
        }
    }

    private static func mergeElementDeltas(_ deltas: [InterfaceDelta]) -> InterfaceDelta? {
        guard !deltas.isEmpty else { return nil }

        var netAdded: [String: HeistElement] = [:]  // heistId → element
        var netRemoved: Set<String> = []
        var netUpdated: [String: [PropertyChange]] = [:]  // heistId → latest changes

        for delta in deltas {
            for element in delta.added ?? [] {
                if netRemoved.contains(element.heistId) {
                    // Was removed earlier, now re-added → treat as net add
                    netRemoved.remove(element.heistId)
                    netAdded[element.heistId] = element
                } else {
                    netAdded[element.heistId] = element
                }
            }
            for heistId in delta.removed ?? [] {
                if netAdded.removeValue(forKey: heistId) != nil {
                    // Was added earlier in this batch, now removed → nets to nothing
                } else {
                    netRemoved.insert(heistId)
                    netUpdated.removeValue(forKey: heistId)
                }
            }
            for update in delta.updated ?? [] {
                // Keep latest property values per heistId
                var existing = netUpdated[update.heistId] ?? []
                for change in update.changes {
                    if let index = existing.firstIndex(where: { $0.property == change.property }) {
                        // Same property updated again — keep original old, use new new
                        existing[index] = PropertyChange(
                            property: change.property, old: existing[index].old, new: change.new
                        )
                    } else {
                        existing.append(change)
                    }
                }
                netUpdated[update.heistId] = existing
            }
        }

        // Filter out updates where old == new (property changed and changed back)
        netUpdated = netUpdated.compactMapValues { changes in
            let meaningful = changes.filter { $0.old != $0.new }
            return meaningful.isEmpty ? nil : meaningful
        }

        let addedList = netAdded.values.sorted { $0.heistId < $1.heistId }
        let removedList = netRemoved.sorted()
        let updatedList = netUpdated.map { ElementUpdate(heistId: $0.key, changes: $0.value) }
            .sorted { $0.heistId < $1.heistId }

        if addedList.isEmpty && removedList.isEmpty && updatedList.isEmpty { return nil }

        let lastCount = deltas.last?.elementCount ?? 0
        return InterfaceDelta(
            kind: .elementsChanged,
            elementCount: lastCount,
            added: addedList.isEmpty ? nil : addedList,
            removed: removedList.isEmpty ? nil : removedList,
            updated: updatedList.isEmpty ? nil : updatedList
        )
    }
}
