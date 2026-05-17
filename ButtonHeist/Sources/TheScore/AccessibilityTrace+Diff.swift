import Foundation

// MARK: - Accessibility Trace Diff

private struct WireTreeRecord {
    let ref: TreeNodeRef
    let location: TreeLocation
    let node: InterfaceNode
    let ancestors: [String]
}

private struct ElementIdentitySignature: Hashable {
    let text: String?
    let identifier: String?
    let hint: String?
    let stableTraits: [HeistTrait]
}

private struct ElementStateSignature: Hashable {
    let label: String?
    let value: String?
    let transientTraits: [HeistTrait]
    let respondsToUserInteraction: Bool
    let customContent: [HeistCustomContent]?
    let rotors: [HeistRotor]?
    let actions: [ElementAction]?
}

private struct ElementPairingSignature: Hashable {
    let identity: ElementIdentitySignature
    let state: ElementStateSignature
}

private let stableDiffTimestamp = Date(timeIntervalSince1970: 0)

public extension AccessibilityTrace {
    /// Raw compact projection between this trace's first and final capture.
    ///
    /// This is the canonical delta projection for an action receipt: the
    /// captures remain the durable source, while the delta is just the compact
    /// view callers use for expectations and formatting. Unlike background
    /// projections, a no-change action is still meaningful and is returned.
    var captureEndpointDelta: AccessibilityTrace.Delta? {
        guard captures.count >= 2,
              let first = captures.first,
              let last = captures.last
        else { return nil }
        return .between(first, last)
    }

    /// Background/summary projection between this trace's endpoints.
    ///
    /// Silent no-change edges are omitted because they do not carry useful
    /// background evidence. Transient-bearing no-change edges are preserved.
    var meaningfulCaptureEndpointDelta: AccessibilityTrace.Delta? {
        guard let delta = captureEndpointDelta else { return nil }
        return Self.meaningfulCaptureEndpointDelta(delta)
    }

    /// Build one source trace from per-step action traces.
    ///
    /// Adjacent duplicate captures are collapsed so a batch `[A→B, B→C]`
    /// becomes `[A, B, C]`. Parent links are normalized by
    /// `AccessibilityTrace(captures:)`; capture hashes still describe the
    /// captured interface/context content.
    static func captureEndpointTrace(from traces: [AccessibilityTrace]) -> AccessibilityTrace? {
        var captures: [AccessibilityTrace.Capture] = []
        for trace in traces {
            for capture in trace.captures {
                guard captures.last?.hash != capture.hash else { continue }
                captures.append(capture)
            }
        }
        guard captures.count >= 2 else { return nil }
        return AccessibilityTrace(captures: captures)
    }

    /// Raw compact projection across a set of per-step traces.
    static func captureEndpointDelta(from traces: [AccessibilityTrace]) -> AccessibilityTrace.Delta? {
        captureEndpointTrace(from: traces)?.captureEndpointDelta
    }

    /// Background/summary projection across a set of per-step traces.
    static func meaningfulCaptureEndpointDelta(from traces: [AccessibilityTrace]) -> AccessibilityTrace.Delta? {
        captureEndpointTrace(from: traces)?.meaningfulCaptureEndpointDelta
    }

    private static func meaningfulCaptureEndpointDelta(
        _ delta: AccessibilityTrace.Delta
    ) -> AccessibilityTrace.Delta? {
        switch delta {
        case .noChange(let payload) where payload.transient.isEmpty:
            return nil
        case .noChange, .elementsChanged, .screenChanged:
            return delta
        }
    }
}

public extension AccessibilityTrace.Delta {

    /// Compare two full accessibility captures and emit the compact delta.
    ///
    /// This is the pure capture-first diff path. Higher layers decide whether
    /// a transition is a screen change by passing `isScreenChange` or by
    /// writing `after.transition.screenChangeReason`. When the transition
    /// reason is present it is authoritative, so `isScreenChange: false` can
    /// still produce `.screenChanged`. The diff then carries exactly the
    /// evidence needed for expectations, replay diagnostics, and future repair.
    static func between(
        _ before: AccessibilityTrace.Capture,
        _ after: AccessibilityTrace.Capture,
        isScreenChange: Bool = false
    ) -> AccessibilityTrace.Delta {
        let edge = AccessibilityTrace.CaptureEdge(before: before, after: after)
        let screenChanged = isScreenChange
            || before.context.screenId != after.context.screenId
            || after.transition.screenChangeReason != nil
        if !screenChanged, before.hash == after.hash {
            return .noChange(AccessibilityTrace.NoChange(
                elementCount: after.interface.elements.count,
                captureEdge: edge,
                transient: after.transition.transient
            ))
        }

        let interfaceDelta = between(before.interface, after.interface, isScreenChange: screenChanged)
            .withCaptureEdge(edge)
            .withTransient(after.transition.transient)

        guard before.context != after.context else { return interfaceDelta }
        if case .noChange = interfaceDelta {
            return .elementsChanged(AccessibilityTrace.ElementsChanged(
                elementCount: after.interface.elements.count,
                edits: ElementEdits(),
                captureEdge: edge,
                transient: after.transition.transient
            ))
        }
        return interfaceDelta
    }

    /// Compatibility projection for callers that only have interfaces. New
    /// production emission should prefer the capture overload so the delta
    /// carries the source capture edge.
    static func between(
        _ before: Interface,
        _ after: Interface,
        isScreenChange: Bool = false
    ) -> AccessibilityTrace.Delta {
        let afterElements = after.elements

        if isScreenChange {
            return .screenChanged(AccessibilityTrace.ScreenChanged(
                elementCount: afterElements.count,
                newInterface: after
            ))
        }

        if AccessibilityTrace.Capture.hash(before) == AccessibilityTrace.Capture.hash(after) {
            return .noChange(AccessibilityTrace.NoChange(elementCount: afterElements.count))
        }

        return makeDelta(edits: ElementEdits.between(before, after), elementCount: afterElements.count)
    }

    /// Compatibility/test projection for callers that only have elements.
    /// New production emission should prefer the capture overload.
    static func between(
        _ before: HeistElement,
        _ after: HeistElement,
        isScreenChange: Bool = false
    ) -> AccessibilityTrace.Delta {
        between(singleElementInterface(before), singleElementInterface(after), isScreenChange: isScreenChange)
    }

    /// Compatibility/test projection for callers that only have nodes. New
    /// production emission should prefer the capture overload.
    static func between(
        _ before: InterfaceNode,
        _ after: InterfaceNode,
        isScreenChange: Bool = false
    ) -> AccessibilityTrace.Delta {
        between([before], [after], isScreenChange: isScreenChange)
    }

    /// Compatibility/test projection for callers that only have root-node
    /// lists. New production emission should prefer the capture overload.
    static func between(
        _ beforeTree: [InterfaceNode],
        _ afterTree: [InterfaceNode],
        isScreenChange: Bool = false
    ) -> AccessibilityTrace.Delta {
        between(
            Interface(timestamp: stableDiffTimestamp, tree: beforeTree),
            Interface(timestamp: stableDiffTimestamp, tree: afterTree),
            isScreenChange: isScreenChange
        )
    }

    private static func makeDelta(edits: ElementEdits, elementCount: Int) -> AccessibilityTrace.Delta {
        if edits.isEmpty {
            return .noChange(AccessibilityTrace.NoChange(elementCount: elementCount))
        }
        return .elementsChanged(AccessibilityTrace.ElementsChanged(elementCount: elementCount, edits: edits))
    }
}

private func singleElementInterface(_ element: HeistElement) -> Interface {
    Interface(timestamp: stableDiffTimestamp, tree: [.element(element)])
}

public extension ElementEdits {

    /// Compare two single-element hierarchies.
    static func between(_ before: HeistElement, _ after: HeistElement) -> ElementEdits {
        between(InterfaceNode.element(before), InterfaceNode.element(after))
    }

    /// Compare two flat root element lists.
    static func between(_ before: [HeistElement], _ after: [HeistElement]) -> ElementEdits {
        between(before.map(InterfaceNode.element), after.map(InterfaceNode.element))
    }

    /// Compare two single-node hierarchies.
    static func between(_ before: InterfaceNode, _ after: InterfaceNode) -> ElementEdits {
        between([before], [after])
    }

    /// Compare two interface root-node lists.
    static func between(_ beforeTree: [InterfaceNode], _ afterTree: [InterfaceNode]) -> ElementEdits {
        let elementEdits = between(beforeElements: beforeTree.flatten(), afterElements: afterTree.flatten())
        let treeEdits = between(beforeTree: beforeTree, afterTree: afterTree)
        return ElementEdits(
            added: elementEdits.added,
            removed: elementEdits.removed,
            updated: elementEdits.updated,
            treeInserted: treeEdits.treeInserted,
            treeRemoved: treeEdits.treeRemoved,
            treeMoved: treeEdits.treeMoved
        )
    }

    /// Compare two full interfaces.
    static func between(_ before: Interface, _ after: Interface) -> ElementEdits {
        between(before.tree, after.tree)
    }

    static func between(
        beforeElements: [HeistElement],
        afterElements: [HeistElement]
    ) -> ElementEdits {
        let oldByHeistId = Dictionary(grouping: beforeElements, by: \.heistId)
        let newByHeistId = Dictionary(grouping: afterElements, by: \.heistId)
        let allHeistIds = Set(oldByHeistId.keys).union(newByHeistId.keys)

        var updated: [ElementUpdate] = []
        var added: [HeistElement] = []
        var removed: [String] = []

        for heistId in allHeistIds {
            let oldEls = oldByHeistId[heistId] ?? []
            let newEls = newByHeistId[heistId] ?? []
            let pairCount = min(oldEls.count, newEls.count)
            updated += zip(oldEls.prefix(pairCount), newEls.prefix(pairCount))
                .compactMap { buildElementUpdate(old: $0, new: $1) }
            removed += oldEls.suffix(from: pairCount).map(\.heistId)
            added += newEls.suffix(from: pairCount)
        }

        return suppressFunctionalMoveElementChurn(
            edits: ElementEdits(added: added, removed: removed, updated: updated),
            beforeElements: beforeElements,
            afterElements: afterElements
        )
    }

    static func between(
        beforeTree: [InterfaceNode],
        afterTree: [InterfaceNode]
    ) -> ElementEdits {
        let oldRecords = indexTree(beforeTree)
        let newRecords = indexTree(afterTree)
        let oldIds = Set(oldRecords.keys)
        let newIds = Set(newRecords.keys)

        let insertedIds = newIds.subtracting(oldIds)
        let removedIds = oldIds.subtracting(newIds)
        let inferredPairs = inferFunctionalTreePairs(
            oldRecords: oldRecords,
            newRecords: newRecords,
            removedIds: removedIds,
            insertedIds: insertedIds
        )
        let inferredInsertedIds = Set(inferredPairs.map(\.insertedId))
        let inferredRemovedIds = Set(inferredPairs.map(\.removedId))

        let inserted = insertedIds.subtracting(inferredInsertedIds)
            .filter { identifier in
                guard let record = newRecords[identifier] else { return false }
                return !record.ancestors.contains(where: insertedIds.contains)
            }
            .compactMap { identifier -> TreeInsertion? in
                guard let record = newRecords[identifier] else { return nil }
                return TreeInsertion(location: record.location, node: record.node)
            }
            .sorted(by: treeInsertionOrder)

        let removed = removedIds.subtracting(inferredRemovedIds)
            .filter { identifier in
                guard let record = oldRecords[identifier] else { return false }
                return !record.ancestors.contains(where: removedIds.contains)
            }
            .compactMap { identifier -> TreeRemoval? in
                guard let record = oldRecords[identifier] else { return nil }
                return TreeRemoval(ref: record.ref, location: record.location)
            }
            .sorted(by: treeRemovalOrder)

        let inferredMoves = inferredPairs.compactMap { pair -> TreeMove? in
            guard let old = oldRecords[pair.removedId],
                  let new = newRecords[pair.insertedId] else { return nil }
            guard old.location != new.location else { return nil }
            return TreeMove(ref: old.ref, from: old.location, to: new.location)
        }
        let rawMoved = oldIds.intersection(newIds).compactMap { identifier -> TreeMove? in
            guard let old = oldRecords[identifier], let new = newRecords[identifier] else { return nil }
            guard old.location != new.location else { return nil }
            return TreeMove(ref: new.ref, from: old.location, to: new.location)
        } + inferredMoves
        let movedIds = Set(rawMoved.map(\.ref.id))
        let moved = rawMoved
            .filter { move in
                let ancestors = newRecords[move.ref.id]?.ancestors ?? []
                return !ancestors.contains(where: movedIds.contains)
            }
            .sorted(by: treeMoveOrder)

        return ElementEdits(treeInserted: inserted, treeRemoved: removed, treeMoved: moved)
    }
}

private func suppressFunctionalMoveElementChurn(
    edits: ElementEdits,
    beforeElements: [HeistElement],
    afterElements: [HeistElement]
) -> ElementEdits {
    let beforeIds = Set(beforeElements.map(\.heistId))
    let afterIds = Set(afterElements.map(\.heistId))
    let removedIds = beforeIds.subtracting(afterIds)
    let addedIds = afterIds.subtracting(beforeIds)
    guard !removedIds.isEmpty, !addedIds.isEmpty else { return edits }

    let removedById = Dictionary(grouping: beforeElements.filter { removedIds.contains($0.heistId) }, by: \.heistId)
        .compactMapValues { $0.count == 1 ? $0[0] : nil }
    let addedById = Dictionary(grouping: afterElements.filter { addedIds.contains($0.heistId) }, by: \.heistId)
        .compactMapValues { $0.count == 1 ? $0[0] : nil }

    let pairs = inferFunctionalHeistElementPairs(removedById: removedById, addedById: addedById)
    guard !pairs.isEmpty else { return edits }

    let pairedRemoved = Set(pairs.map(\.removedId))
    let pairedAdded = Set(pairs.map(\.insertedId))
    let added = edits.added.filter { !pairedAdded.contains($0.heistId) }
    let removed = edits.removed.filter { !pairedRemoved.contains($0) }
    let inferredUpdates = pairs.compactMap { pair -> ElementUpdate? in
        guard let old = removedById[pair.removedId],
              let new = addedById[pair.insertedId] else { return nil }
        return buildElementUpdate(old: old, new: new, heistId: pair.removedId, includeGeometry: false)
    }

    return ElementEdits(
        added: added,
        removed: removed,
        updated: edits.updated + inferredUpdates,
        treeInserted: edits.treeInserted,
        treeRemoved: edits.treeRemoved,
        treeMoved: edits.treeMoved
    )
}

// MARK: - Functional-Move Pairing

private func inferFunctionalTreePairs(
    oldRecords: [String: WireTreeRecord],
    newRecords: [String: WireTreeRecord],
    removedIds: Set<String>,
    insertedIds: Set<String>
) -> [(removedId: String, insertedId: String)] {
    let removedById = Dictionary(uniqueKeysWithValues: removedIds.compactMap { identifier in
        oldRecords[identifier].map { (identifier, $0) }
    })
    let insertedById = Dictionary(uniqueKeysWithValues: insertedIds.compactMap { identifier in
        newRecords[identifier].map { (identifier, $0) }
    })

    return inferFunctionalTreeRecordPairs(removedById: removedById, addedById: insertedById)
}

private func inferFunctionalHeistElementPairs(
    removedById: [String: HeistElement],
    addedById: [String: HeistElement]
) -> [(removedId: String, insertedId: String)] {
    let removed = removedById.map { identifier, element in
        (identifier, pairingSignature(for: element))
    }
    let added = addedById.map { identifier, element in
        (identifier, pairingSignature(for: element))
    }
    return inferFunctionalPairs(removed: removed, added: added)
}

private func inferFunctionalTreeRecordPairs(
    removedById: [String: WireTreeRecord],
    addedById: [String: WireTreeRecord]
) -> [(removedId: String, insertedId: String)] {
    let removed = removedById.compactMap { identifier, record -> (String, ElementPairingSignature)? in
        pairingSignature(for: record).map { (identifier, $0) }
    }
    let added = addedById.compactMap { identifier, record -> (String, ElementPairingSignature)? in
        pairingSignature(for: record).map { (identifier, $0) }
    }
    return inferFunctionalPairs(removed: removed, added: added)
}

private func inferFunctionalPairs(
    removed: [(String, ElementPairingSignature)],
    added: [(String, ElementPairingSignature)]
) -> [(removedId: String, insertedId: String)] {
    let removedByIdentity = Dictionary(grouping: removed, by: { $0.1.identity })
    let addedByIdentity = Dictionary(grouping: added, by: { $0.1.identity })
    let identities = Set(removedByIdentity.keys).intersection(addedByIdentity.keys)
    var pairs: [(removedId: String, insertedId: String)] = []

    for identity in identities {
        guard let removedMatches = removedByIdentity[identity],
              let addedMatches = addedByIdentity[identity] else { continue }
        if removedMatches.count == 1 && addedMatches.count == 1 {
            pairs.append((removedId: removedMatches[0].0, insertedId: addedMatches[0].0))
            continue
        }

        let removedByFullSignature = Dictionary(grouping: removedMatches, by: \.1)
        let addedByFullSignature = Dictionary(grouping: addedMatches, by: \.1)
        for signature in Set(removedByFullSignature.keys).intersection(addedByFullSignature.keys) {
            guard let removedStateMatches = removedByFullSignature[signature],
                  let addedStateMatches = addedByFullSignature[signature],
                  removedStateMatches.count == 1,
                  addedStateMatches.count == 1 else { continue }
            pairs.append((removedId: removedStateMatches[0].0, insertedId: addedStateMatches[0].0))
        }
    }
    return pairs
}

// MARK: - Signatures

private func pairingSignature(for record: WireTreeRecord) -> ElementPairingSignature? {
    guard case .element(let element) = record.node else { return nil }
    return pairingSignature(for: element)
}

private func pairingSignature(for element: HeistElement) -> ElementPairingSignature {
    ElementPairingSignature(identity: identitySignature(for: element), state: stateSignature(for: element))
}

private func identitySignature(for element: HeistElement) -> ElementIdentitySignature {
    let text = firstNonEmpty(element.identifier, element.label, element.description)
    return ElementIdentitySignature(
        text: text,
        identifier: element.identifier,
        hint: element.hint,
        stableTraits: normalizedTraits(element.traits.filter { !AccessibilityPolicy.transientTraits.contains($0) })
    )
}

private func stateSignature(for element: HeistElement) -> ElementStateSignature {
    ElementStateSignature(
        label: element.label,
        value: element.value,
        transientTraits: normalizedTraits(element.traits.filter(AccessibilityPolicy.transientTraits.contains)),
        respondsToUserInteraction: element.respondsToUserInteraction,
        customContent: element.customContent,
        rotors: element.rotors,
        actions: element.actions
    )
}

private func firstNonEmpty(_ values: String?...) -> String? {
    for value in values {
        if let value, !value.isEmpty {
            return value
        }
    }
    return nil
}

private func normalizedTraits(_ traits: [HeistTrait]) -> [HeistTrait] {
    traits.sorted { $0.rawValue < $1.rawValue }
}

// MARK: - Tree Indexing

private func indexTree(_ roots: [InterfaceNode]) -> [String: WireTreeRecord] {
    var result: [String: WireTreeRecord] = [:]
    for (index, node) in roots.enumerated() {
        collectTreeRecords(
            node,
            parentId: nil,
            index: index,
            ancestors: [],
            into: &result
        )
    }
    return result
}

private func collectTreeRecords(
    _ node: InterfaceNode,
    parentId: String?,
    index: Int,
    ancestors: [String],
    into result: inout [String: WireTreeRecord]
) {
    guard let ref = treeRef(for: node) else { return }
    let location = TreeLocation(parentId: parentId, index: index)
    result[ref.id] = WireTreeRecord(ref: ref, location: location, node: node, ancestors: ancestors)

    guard case .container(_, let children) = node else { return }
    let childAncestors = ancestors + [ref.id]
    for (childIndex, child) in children.enumerated() {
        collectTreeRecords(
            child,
            parentId: ref.id,
            index: childIndex,
            ancestors: childAncestors,
            into: &result
        )
    }
}

private func treeRef(for node: InterfaceNode) -> TreeNodeRef? {
    switch node {
    case .element(let element):
        return TreeNodeRef(id: element.heistId, kind: .element)
    case .container(let info, _):
        guard let stableId = info.stableId else { return nil }
        return TreeNodeRef(id: stableId, kind: .container)
    }
}

// MARK: - Tree-Order Helpers

private func treeInsertionOrder(_ lhs: TreeInsertion, _ rhs: TreeInsertion) -> Bool {
    compare(lhs.location, rhs.location)
}

private func treeRemovalOrder(_ lhs: TreeRemoval, _ rhs: TreeRemoval) -> Bool {
    compare(lhs.location, rhs.location)
}

private func treeMoveOrder(_ lhs: TreeMove, _ rhs: TreeMove) -> Bool {
    compare(lhs.to, rhs.to)
}

private func compare(_ lhs: TreeLocation, _ rhs: TreeLocation) -> Bool {
    switch (lhs.parentId, rhs.parentId) {
    case let (left?, right?) where left != right:
        return left < right
    case (nil, _?):
        return true
    case (_?, nil):
        return false
    default:
        return lhs.index < rhs.index
    }
}

// MARK: - Element Update

private func buildElementUpdate(
    old: HeistElement,
    new: HeistElement,
    heistId: String? = nil,
    includeGeometry: Bool = true
) -> ElementUpdate? {
    var changes: [PropertyChange] = []

    if old.label != new.label {
        changes.append(PropertyChange(property: .label, old: old.label, new: new.label))
    }
    if old.value != new.value {
        changes.append(PropertyChange(property: .value, old: old.value, new: new.value))
    }
    if old.traits != new.traits {
        changes.append(PropertyChange(
            property: .traits,
            old: old.traits.map(\.rawValue).joined(separator: ", "),
            new: new.traits.map(\.rawValue).joined(separator: ", ")
        ))
    }
    if old.hint != new.hint {
        changes.append(PropertyChange(property: .hint, old: old.hint, new: new.hint))
    }
    if old.actions != new.actions {
        changes.append(PropertyChange(
            property: .actions,
            old: old.actions.map(\.description).joined(separator: ", "),
            new: new.actions.map(\.description).joined(separator: ", ")
        ))
    }
    if old.customContent != new.customContent {
        changes.append(PropertyChange(
            property: .customContent,
            old: formatCustomContent(old.customContent),
            new: formatCustomContent(new.customContent)
        ))
    }
    if old.rotors != new.rotors {
        changes.append(PropertyChange(
            property: .rotors,
            old: formatRotors(old.rotors),
            new: formatRotors(new.rotors)
        ))
    }
    let oldFrame = "\(Int(old.frameX)),\(Int(old.frameY)),\(Int(old.frameWidth)),\(Int(old.frameHeight))"
    let newFrame = "\(Int(new.frameX)),\(Int(new.frameY)),\(Int(new.frameWidth)),\(Int(new.frameHeight))"
    if includeGeometry && oldFrame != newFrame {
        changes.append(PropertyChange(property: .frame, old: oldFrame, new: newFrame))
    }
    let oldActivationPoint = "\(Int(old.activationPointX)),\(Int(old.activationPointY))"
    let newActivationPoint = "\(Int(new.activationPointX)),\(Int(new.activationPointY))"
    if includeGeometry && oldActivationPoint != newActivationPoint {
        changes.append(PropertyChange(property: .activationPoint, old: oldActivationPoint, new: newActivationPoint))
    }

    guard !changes.isEmpty else { return nil }
    return ElementUpdate(heistId: heistId ?? new.heistId, changes: changes)
}

private func formatCustomContent(_ content: [HeistCustomContent]?) -> String? {
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

private func formatRotors(_ rotors: [HeistRotor]?) -> String? {
    guard let rotors, !rotors.isEmpty else { return nil }
    return rotors.map(\.name).joined(separator: ", ")
}
