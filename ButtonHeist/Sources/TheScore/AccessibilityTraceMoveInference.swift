import ThePlans
import Foundation
import AccessibilitySnapshotModel

enum AccessibilityTraceMoveInference {

    static func suppressElementChurnFromFunctionalMoves(
        edits: ElementEdits,
        beforeElements: [HeistElement],
        afterElements: [HeistElement]
    ) -> ElementEdits {
        let beforeIds = Set(beforeElements.map(\.diffPairingKey))
        let afterIds = Set(afterElements.map(\.diffPairingKey))
        let removedIds = beforeIds.subtracting(afterIds)
        let addedIds = afterIds.subtracting(beforeIds)
        guard !removedIds.isEmpty, !addedIds.isEmpty else { return edits }

        let removedById = Dictionary(grouping: beforeElements.filter { removedIds.contains($0.diffPairingKey) }, by: \.diffPairingKey)
            .compactMapValues { $0.count == 1 ? $0[0] : nil }
        let addedById = Dictionary(grouping: afterElements.filter { addedIds.contains($0.diffPairingKey) }, by: \.diffPairingKey)
            .compactMapValues { $0.count == 1 ? $0[0] : nil }

        let pairs = inferFunctionalHeistElementPairs(removedById: removedById, addedById: addedById)
        guard !pairs.isEmpty else { return edits }

        let pairedRemoved = Set(pairs.map(\.removedId))
        let pairedAdded = Set(pairs.map(\.insertedId))
        let added = edits.added.filter { !pairedAdded.contains($0.diffPairingKey) }
        let removed = edits.removed.filter { !pairedRemoved.contains($0.diffPairingKey) }
        let inferredUpdates = pairs.compactMap { pair -> ElementUpdate? in
            guard let old = removedById[pair.removedId],
                  let new = addedById[pair.insertedId] else { return nil }
            return projectElementStateChange(old: old, new: new, includeGeometry: false)
        }

        return ElementEdits(
            added: added,
            removed: removed,
            updated: edits.updated + inferredUpdates
        )
    }

    private static func inferFunctionalHeistElementPairs(
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

    private static func inferFunctionalPairs<Identifier: Hashable>(
        removed: [(Identifier, ElementPairingSignature)],
        added: [(Identifier, ElementPairingSignature)]
    ) -> [(removedId: Identifier, insertedId: Identifier)] {
        let removedByIdentity = Dictionary(grouping: removed, by: { $0.1.identity })
        let addedByIdentity = Dictionary(grouping: added, by: { $0.1.identity })
        let identities = Set(removedByIdentity.keys).intersection(addedByIdentity.keys)
        var pairs: [(removedId: Identifier, insertedId: Identifier)] = []

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
    for value in values where value?.isEmpty == false {
        return value
    }
    return nil
}

private func normalizedTraits(_ traits: [HeistTrait]) -> [HeistTrait] {
    traits.sorted { $0.rawValue < $1.rawValue }
}
