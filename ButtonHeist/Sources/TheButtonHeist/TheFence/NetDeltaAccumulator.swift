import Foundation

import TheScore

// MARK: - Net Delta Accumulator

/// Merges per-step deltas into a single net delta (like git squash).
/// If any step triggered a screen change, the net delta is screenChanged
/// with the final interface. Otherwise, tracks net added/removed/updated.
internal enum NetDeltaAccumulator {
    static func merge(deltas: [InterfaceDelta]) -> InterfaceDelta? {
        let meaningful = deltas.filter { $0.kind != .noChange || hasTransient($0) }
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
        let postDeltas = afterScreen.filter { $0.kind == .elementsChanged || hasTransient($0) }
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
            treeInserted: postMerge.treeInserted,
            treeRemoved: postMerge.treeRemoved,
            treeMoved: postMerge.treeMoved,
            transient: mergeTransients(screenChange.transient, postMerge.transient),
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
            var fullyApplied = true
            for change in update.changes where !apply(change, to: &element) {
                fullyApplied = false
            }
            if fullyApplied {
                elementsById[update.heistId] = element
            } else {
                // We couldn't apply every property delta in-place (e.g. actions/customContent
                // are lossy strings on the wire). Drop the element from `newInterface` so the
                // snapshot stays internally consistent — callers should read `delta.updated`
                // for the authoritative change list.
                elementsById.removeValue(forKey: update.heistId)
            }
        }

        // Walk the tree, swapping each leaf with its updated counterpart and
        // dropping leaves whose heistId was removed/dropped from elementsById.
        // Containers with no surviving children are pruned.
        let originalHeistIds = Set(interface.elements.map(\.heistId))
        let updatedTree = mapTree(interface.tree, elementsById: elementsById)

        // Append any "added" element that wasn't already in the original tree
        // at the root level — we don't know its tree position from the delta.
        let novelAdds = (delta.added ?? []).filter { !originalHeistIds.contains($0.heistId) }
        let finalTree = updatedTree + novelAdds.map { InterfaceNode.element($0) }

        return Interface(timestamp: interface.timestamp, tree: finalTree)
    }

    /// Walk the tree, replacing each leaf with its updated counterpart from
    /// `elementsById` (or dropping the leaf if absent). Containers with no
    /// surviving descendants are pruned.
    private static func mapTree(
        _ nodes: [InterfaceNode], elementsById: [String: HeistElement]
    ) -> [InterfaceNode] {
        nodes.compactMap { node in
            switch node {
            case .element(let element):
                guard let updated = elementsById[element.heistId] else { return nil }
                return .element(updated)
            case .container(let info, let children):
                let newChildren = mapTree(children, elementsById: elementsById)
                return newChildren.isEmpty ? nil : .container(info, children: newChildren)
            }
        }
    }

    /// Apply a property change to `element`. Returns `false` when the property cannot be
    /// reconstructed from the wire string (the caller should drop the element from
    /// `newInterface` to avoid leaving stale fields behind).
    private static func apply(_ change: PropertyChange, to element: inout HeistElement) -> Bool {
        switch change.property {
        case .label:
            element.label = change.new
            return true
        case .value:
            element.value = change.new
            return true
        case .hint:
            element.hint = change.new
            return true
        case .traits:
            guard let traits = parseTraits(change.new) else { return false }
            element.traits = traits
            return true
        case .frame:
            guard let frame = parseFrame(change.new) else { return false }
            element.frameX = frame.x
            element.frameY = frame.y
            element.frameWidth = frame.width
            element.frameHeight = frame.height
            return true
        case .activationPoint:
            guard let point = parsePoint(change.new) else { return false }
            element.activationPointX = point.x
            element.activationPointY = point.y
            return true
        case .actions, .customContent:
            return false
        }
    }

    private static func parseTraits(_ value: String?) -> [HeistTrait]? {
        guard let value, !value.isEmpty else { return [] }
        let names = value.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        return names.compactMap { name -> HeistTrait? in
            guard !name.isEmpty else { return nil }
            return HeistTrait(rawValue: name) ?? .unknown(name)
        }
    }

    private static func parseFrame(_ value: String?) -> (x: Double, y: Double, width: Double, height: Double)? {
        guard let value else { return nil }
        let parts = value.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
        guard parts.count == 4 else { return nil }
        return (parts[0], parts[1], parts[2], parts[3])
    }

    private static func parsePoint(_ value: String?) -> (x: Double, y: Double)? {
        guard let value else { return nil }
        let parts = value.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
        guard parts.count == 2 else { return nil }
        return (parts[0], parts[1])
    }

    private static func mergeElementDeltas(_ deltas: [InterfaceDelta]) -> InterfaceDelta? {
        guard !deltas.isEmpty else { return nil }

        var netAdded: [String: HeistElement] = [:]  // heistId → element
        var netRemoved: Set<String> = []
        var netUpdated: [String: [PropertyChange]] = [:]  // heistId → latest changes
        var treeInserted: [TreeInsertion] = []
        var treeRemoved: [TreeRemoval] = []
        var treeMoved: [TreeMove] = []
        var transient: [HeistElement] = []
        var transientIds: Set<String> = []

        for delta in deltas {
            treeInserted.append(contentsOf: delta.treeInserted ?? [])
            treeRemoved.append(contentsOf: delta.treeRemoved ?? [])
            treeMoved.append(contentsOf: delta.treeMoved ?? [])
            appendUniqueTransients(delta.transient, to: &transient, seenIds: &transientIds)

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
                    netUpdated.removeValue(forKey: heistId)
                } else {
                    netRemoved.insert(heistId)
                    netUpdated.removeValue(forKey: heistId)
                }
            }
            for update in delta.updated ?? [] {
                var changesToRecord = update.changes
                if var added = netAdded[update.heistId] {
                    var unappliedChanges: [PropertyChange] = []
                    for change in update.changes {
                        if !apply(change, to: &added) {
                            unappliedChanges.append(change)
                        }
                    }
                    netAdded[update.heistId] = added
                    changesToRecord = unappliedChanges
                    guard !changesToRecord.isEmpty else { continue }
                }
                guard !netRemoved.contains(update.heistId) else { continue }

                // Keep latest property values per heistId
                var existing = netUpdated[update.heistId] ?? []
                for change in changesToRecord {
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

        if addedList.isEmpty && removedList.isEmpty && updatedList.isEmpty
            && treeInserted.isEmpty && treeRemoved.isEmpty && treeMoved.isEmpty
            && transient.isEmpty {
            return nil
        }

        let lastCount = deltas.last?.elementCount ?? 0
        return InterfaceDelta(
            kind: addedList.isEmpty && removedList.isEmpty && updatedList.isEmpty
                && treeInserted.isEmpty && treeRemoved.isEmpty && treeMoved.isEmpty
                ? .noChange
                : .elementsChanged,
            elementCount: lastCount,
            added: addedList.isEmpty ? nil : addedList,
            removed: removedList.isEmpty ? nil : removedList,
            updated: updatedList.isEmpty ? nil : updatedList,
            treeInserted: treeInserted.isEmpty ? nil : treeInserted,
            treeRemoved: treeRemoved.isEmpty ? nil : treeRemoved,
            treeMoved: treeMoved.isEmpty ? nil : treeMoved,
            transient: transient.isEmpty ? nil : transient
        )
    }

    private static func hasTransient(_ delta: InterfaceDelta) -> Bool {
        delta.transient?.isEmpty == false
    }

    private static func mergeTransients(
        _ lhs: [HeistElement]?, _ rhs: [HeistElement]?
    ) -> [HeistElement]? {
        var merged: [HeistElement] = []
        var seenIds = Set<String>()
        appendUniqueTransients(lhs, to: &merged, seenIds: &seenIds)
        appendUniqueTransients(rhs, to: &merged, seenIds: &seenIds)
        return merged.isEmpty ? nil : merged
    }

    private static func appendUniqueTransients(
        _ elements: [HeistElement]?,
        to output: inout [HeistElement],
        seenIds: inout Set<String>
    ) {
        for element in elements ?? [] where !seenIds.contains(element.heistId) {
            seenIds.insert(element.heistId)
            output.append(element)
        }
    }
}
