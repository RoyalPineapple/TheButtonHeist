import Foundation

import TheScore

// MARK: - Net Delta Accumulator

/// Merges per-step deltas into a single net delta (like git squash).
/// If any step triggered a screen change, the net delta is screenChanged
/// with the final interface. Otherwise, tracks net added/removed/updated.
enum NetDeltaAccumulator {
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
        guard let screenIdx = deltas.lastIndex(where: { $0.kind == .screenChanged }) else {
            return screenChange
        }
        let afterScreen = Array(deltas[(screenIdx + 1)...])
        let postDeltas = afterScreen.filter { $0.kind == .elementsChanged }
        if postDeltas.isEmpty {
            return screenChange
        }
        // Merge the post-screen element changes into one
        guard let postMerge = mergeElementDeltas(postDeltas) else { return screenChange }
        // Return screenChanged but with the merged updates appended
        return InterfaceDelta(
            kind: .screenChanged,
            elementCount: postMerge.elementCount,
            added: postMerge.added,
            removed: postMerge.removed,
            updated: postMerge.updated,
            newInterface: screenChange.newInterface
        )
    }

    private static func mergeElementDeltas(_ deltas: [InterfaceDelta]) -> InterfaceDelta? {
        guard !deltas.isEmpty else { return nil }

        var netAdded: [String: HeistElement] = [:]  // heistId → element
        var netRemoved: Set<String> = []
        var netUpdated: [String: [PropertyChange]] = [:]  // heistId → latest changes

        for delta in deltas {
            for el in delta.added ?? [] {
                if netRemoved.contains(el.heistId) {
                    // Was removed earlier, now re-added → treat as net add
                    netRemoved.remove(el.heistId)
                    netAdded[el.heistId] = el
                } else {
                    netAdded[el.heistId] = el
                }
            }
            for hid in delta.removed ?? [] {
                if netAdded.removeValue(forKey: hid) != nil {
                    // Was added earlier in this batch, now removed → nets to nothing
                } else {
                    netRemoved.insert(hid)
                    netUpdated.removeValue(forKey: hid)
                }
            }
            for update in delta.updated ?? [] {
                // Keep latest property values per heistId
                var existing = netUpdated[update.heistId] ?? []
                for change in update.changes {
                    if let idx = existing.firstIndex(where: { $0.property == change.property }) {
                        // Same property updated again — keep original old, use new new
                        existing[idx] = PropertyChange(
                            property: change.property, old: existing[idx].old, new: change.new
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
