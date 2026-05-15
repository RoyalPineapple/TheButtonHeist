import Foundation

import TheScore

// MARK: - Non-Screen-Change Delta

/// A subset of `InterfaceDelta` that structurally excludes `.screenChanged`.
/// Built at the boundary where the caller has already pinned to the last
/// screen-change step, so any subsequent slice is guaranteed not to contain
/// another. Carrying that proof in the type lets every downstream consumer
/// exhaust the cases without a `preconditionFailure` for the impossible
/// branch.
internal enum NonScreenChangeDelta {
    case noChange(InterfaceDelta.NoChange)
    case elementsChanged(InterfaceDelta.ElementsChanged)

    /// Narrow an `InterfaceDelta` to `NonScreenChangeDelta`, dropping
    /// `.screenChanged` (the caller has already proven the slice contains
    /// none).
    init?(_ delta: InterfaceDelta) {
        switch delta {
        case .noChange(let payload): self = .noChange(payload)
        case .elementsChanged(let payload): self = .elementsChanged(payload)
        case .screenChanged: return nil
        }
    }

    var isMeaningful: Bool {
        switch self {
        case .noChange(let payload): return !payload.transient.isEmpty
        case .elementsChanged: return true
        }
    }

    var asInterfaceDelta: InterfaceDelta {
        switch self {
        case .noChange(let payload): return .noChange(payload)
        case .elementsChanged(let payload): return .elementsChanged(payload)
        }
    }
}

// MARK: - Net Delta Accumulator

/// Merges per-step deltas into a single net delta (like git squash).
/// If any step triggered a screen change, the net delta is screenChanged
/// with the final interface. Otherwise, tracks net added/removed/updated.
internal enum NetDeltaAccumulator {
    static func merge(deltas: [InterfaceDelta]) -> InterfaceDelta? {
        let meaningful = deltas.filter { delta in
            switch delta {
            case .noChange(let payload): return !payload.transient.isEmpty
            case .elementsChanged, .screenChanged: return true
            }
        }
        guard !meaningful.isEmpty else { return nil }

        // If any step was a screen change, the net is screenChanged with the last one's interface
        if let screenIndex = deltas.lastIndex(where: \.isScreenChanged),
           case .screenChanged(let screenPayload) = deltas[screenIndex] {
            let postDeltas = deltas[(screenIndex + 1)...].compactMap(NonScreenChangeDelta.init)
            return mergeAfterScreenChange(
                screenChange: screenPayload,
                postDeltas: postDeltas
            )
        }

        // All steps are elementsChanged or transient-bearing noChange —
        // accumulate net adds/removes/updates.
        return mergeElementDeltas(meaningful)
    }

    /// Fold element-level edits that happened after `screenChange` into a
    /// single `.screenChanged` result, applying them to the new interface.
    /// `postDeltas` is the slice of the original sequence strictly after the
    /// screen-change step, narrowed to `NonScreenChangeDelta` at the
    /// boundary so the "no further screen change" invariant is enforced by
    /// the type system rather than a runtime precondition.
    private static func mergeAfterScreenChange(
        screenChange: InterfaceDelta.ScreenChanged, postDeltas: [NonScreenChangeDelta]
    ) -> InterfaceDelta {
        let filteredPostDeltas: [NonScreenChangeDelta] = postDeltas.filter(\.isMeaningful)
        if filteredPostDeltas.isEmpty {
            return .screenChanged(screenChange)
        }
        // Merge the post-screen element changes into one
        guard let postMerged = mergeElementDeltas(filteredPostDeltas.map(\.asInterfaceDelta)) else {
            return .screenChanged(screenChange)
        }
        let postEdits: ElementEdits
        let postTransients: [HeistElement]
        switch postMerged {
        case .noChange(let payload):
            postEdits = ElementEdits()
            postTransients = payload.transient
        case .elementsChanged(let payload):
            postEdits = payload.edits
            postTransients = payload.transient
        case .screenChanged:
            // mergeElementDeltas never returns a screenChanged
            return .screenChanged(screenChange)
        }
        let finalInterface = apply(postEdits, to: screenChange.newInterface)
        let mergedTransients = mergeTransients(screenChange.transient, postTransients)
        return .screenChanged(InterfaceDelta.ScreenChanged(
            elementCount: finalInterface.elements.count,
            newInterface: finalInterface,
            postEdits: postEdits.isEmpty ? nil : postEdits,
            transient: mergedTransients
        ))
    }

    /// Apply element-level edits (`added`/`removed`/`updated`) to `interface`,
    /// producing a best-effort `newInterface` for `.screenChanged.newInterface`.
    ///
    /// Tree-level edits (`treeInserted`/`treeRemoved`/`treeMoved`) are *not*
    /// applied here — they are descriptive metadata produced by diffing two
    /// snapshots, not instructions for reconstructing the tree. Consumers who
    /// need the structural truth should read `postEdits` directly; the
    /// `newInterface.tree` returned here reflects the leaf-level swaps and
    /// adds, with novel adds appended at the root forest.
    ///
    /// `heistId` collisions in `interface.elements` are tolerated with
    /// last-write-wins semantics — uniqueness is a best-effort property of the
    /// snapshot, not an invariant (e.g. sibling `staticText` with identical
    /// labels can synthesize the same id).
    private static func apply(_ edits: ElementEdits, to interface: Interface) -> Interface {
        var elementsById: [String: HeistElement] = [:]
        for element in interface.elements {
            elementsById[element.heistId] = element
        }
        for heistId in edits.removed {
            elementsById.removeValue(forKey: heistId)
        }
        for element in edits.added {
            elementsById[element.heistId] = element
        }
        for update in edits.updated {
            guard var element = elementsById[update.heistId] else { continue }
            var fullyApplied = true
            for change in update.changes where !apply(change, to: &element) {
                fullyApplied = false
            }
            if fullyApplied {
                elementsById[update.heistId] = element
            } else {
                // We couldn't apply every property delta in-place (e.g. actions/customContent/rotors
                // are lossy strings on the wire). Drop the element from `newInterface` so the
                // snapshot stays internally consistent — callers should read the authoritative
                // edits.updated list.
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
        let novelAdds = edits.added.filter { !originalHeistIds.contains($0.heistId) }
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
        case .actions, .customContent, .rotors:
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
            let edits: ElementEdits
            switch delta {
            case .noChange(let payload):
                edits = ElementEdits()
                appendUniqueTransients(payload.transient, to: &transient, seenIds: &transientIds)
                continue
            case .elementsChanged(let payload):
                edits = payload.edits
                appendUniqueTransients(payload.transient, to: &transient, seenIds: &transientIds)
            case .screenChanged:
                // Caller filters screen changes out before reaching this loop.
                continue
            }

            treeInserted.append(contentsOf: edits.treeInserted)
            treeRemoved.append(contentsOf: edits.treeRemoved)
            treeMoved.append(contentsOf: edits.treeMoved)

            for element in edits.added {
                if netRemoved.contains(element.heistId) {
                    // Was removed earlier, now re-added → treat as net add
                    netRemoved.remove(element.heistId)
                    netAdded[element.heistId] = element
                } else {
                    netAdded[element.heistId] = element
                }
            }
            for heistId in edits.removed {
                if netAdded.removeValue(forKey: heistId) != nil {
                    // Was added earlier in this batch, now removed → nets to nothing
                    netUpdated.removeValue(forKey: heistId)
                } else {
                    netRemoved.insert(heistId)
                    netUpdated.removeValue(forKey: heistId)
                }
            }
            for update in edits.updated {
                var changesToRecord = update.changes
                if var added = netAdded[update.heistId] {
                    var unappliedChanges: [PropertyChange] = []
                    for change in update.changes where !apply(change, to: &added) {
                        unappliedChanges.append(change)
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

        let mergedEdits = ElementEdits(
            added: addedList,
            removed: removedList,
            updated: updatedList,
            treeInserted: treeInserted,
            treeRemoved: treeRemoved,
            treeMoved: treeMoved
        )

        if mergedEdits.isEmpty && transient.isEmpty {
            return nil
        }

        let lastCount = deltas.last?.elementCount ?? 0
        if mergedEdits.isEmpty {
            return .noChange(InterfaceDelta.NoChange(elementCount: lastCount, transient: transient))
        }
        return .elementsChanged(InterfaceDelta.ElementsChanged(
            elementCount: lastCount,
            edits: mergedEdits,
            transient: transient
        ))
    }

    private static func mergeTransients(
        _ lhs: [HeistElement], _ rhs: [HeistElement]
    ) -> [HeistElement] {
        var merged: [HeistElement] = []
        var seenIds = Set<String>()
        appendUniqueTransients(lhs, to: &merged, seenIds: &seenIds)
        appendUniqueTransients(rhs, to: &merged, seenIds: &seenIds)
        return merged
    }

    private static func appendUniqueTransients(
        _ elements: [HeistElement],
        to output: inout [HeistElement],
        seenIds: inout Set<String>
    ) {
        for element in elements where !seenIds.contains(element.heistId) {
            seenIds.insert(element.heistId)
            output.append(element)
        }
    }
}
