import ThePlans
import Foundation
import AccessibilitySnapshotModel

enum AccessibilityTraceMoveInference {

    static func suppressElementChurnFromFunctionalMoves(
        edits: ElementEdits,
        beforeElements: [HeistElement],
        afterElements: [HeistElement]
    ) -> ElementEdits {
        let beforeKeys = Set(beforeElements.map(\.diffPairingKey))
        let afterKeys = Set(afterElements.map(\.diffPairingKey))
        let removedKeys = beforeKeys.subtracting(afterKeys)
        let addedKeys = afterKeys.subtracting(beforeKeys)
        guard !removedKeys.isEmpty, !addedKeys.isEmpty else { return edits }

        let removedByKey = Dictionary(
            grouping: beforeElements.filter { removedKeys.contains($0.diffPairingKey) },
            by: \.diffPairingKey
        ).compactMapValues { $0.count == 1 ? $0[0] : nil }
        let addedByKey = Dictionary(
            grouping: afterElements.filter { addedKeys.contains($0.diffPairingKey) },
            by: \.diffPairingKey
        ).compactMapValues { $0.count == 1 ? $0[0] : nil }

        let pairs = inferFunctionalHeistElementPairs(
            removedByKey: removedByKey,
            addedByKey: addedByKey
        )
        guard !pairs.isEmpty else { return edits }

        let pairedRemoved = Set(pairs.map(\.removedKey))
        let pairedAdded = Set(pairs.map(\.insertedKey))
        let added = edits.added.filter { !pairedAdded.contains($0.diffPairingKey) }
        let removed = edits.removed.filter { !pairedRemoved.contains($0.diffPairingKey) }
        let inferredUpdates = pairs.compactMap { pair -> ElementUpdate? in
            guard let old = removedByKey[pair.removedKey],
                  let new = addedByKey[pair.insertedKey] else { return nil }
            return projectElementStateChange(old: old, new: new, includeGeometry: false)
        }

        return ElementEdits(
            added: added,
            removed: removed,
            updated: edits.updated + inferredUpdates
        )
    }

    private static func inferFunctionalHeistElementPairs(
        removedByKey: [ElementDiffPairingKey: HeistElement],
        addedByKey: [ElementDiffPairingKey: HeistElement]
    ) -> [(removedKey: ElementDiffPairingKey, insertedKey: ElementDiffPairingKey)] {
        let removed = removedByKey.map { key, element in
            (key, pairingSignature(for: element))
        }
        let added = addedByKey.map { key, element in
            (key, pairingSignature(for: element))
        }
        return inferFunctionalPairs(removed: removed, added: added)
    }

    private static func inferFunctionalPairs<Key: Hashable>(
        removed: [(Key, ElementPairingSignature)],
        added: [(Key, ElementPairingSignature)]
    ) -> [(removedKey: Key, insertedKey: Key)] {
        let removedByIdentity = Dictionary(grouping: removed, by: { $0.1.identity })
        let addedByIdentity = Dictionary(grouping: added, by: { $0.1.identity })
        let identities = Set(removedByIdentity.keys).intersection(addedByIdentity.keys)
        var pairs: [(removedKey: Key, insertedKey: Key)] = []

        for identity in identities {
            guard let removedMatches = removedByIdentity[identity],
                  let addedMatches = addedByIdentity[identity] else { continue }
            if removedMatches.count == 1 && addedMatches.count == 1 {
                pairs.append((removedKey: removedMatches[0].0, insertedKey: addedMatches[0].0))
                continue
            }

            let removedByFullSignature = Dictionary(grouping: removedMatches, by: \.1)
            let addedByFullSignature = Dictionary(grouping: addedMatches, by: \.1)
            let matchingSignatures = Set(removedByFullSignature.keys)
                .intersection(addedByFullSignature.keys)
            for signature in matchingSignatures {
                guard let removedStateMatches = removedByFullSignature[signature],
                      let addedStateMatches = addedByFullSignature[signature],
                      removedStateMatches.count == 1,
                      addedStateMatches.count == 1 else { continue }
                pairs.append((
                    removedKey: removedStateMatches[0].0,
                    insertedKey: addedStateMatches[0].0
                ))
            }
        }
        return pairs
    }
}

private struct ElementIdentitySignature: Hashable {
    let text: String?
    let identifier: String?
    let hint: String?
    let stableTraits: Set<HeistTrait>
}

private struct ElementStateSignature: Hashable {
    let label: String?
    let value: String?
    let transientTraits: Set<HeistTrait>
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
    ElementPairingSignature(
        identity: identitySignature(for: element),
        state: stateSignature(for: element)
    )
}

private func identitySignature(for element: HeistElement) -> ElementIdentitySignature {
    let text = firstNonEmpty(element.identifier, element.label, element.description)
    return ElementIdentitySignature(
        text: text,
        identifier: element.identifier,
        hint: element.hint,
        stableTraits: Set(element.traits.filter {
            !AccessibilityPolicy.transientTraits.contains($0)
        })
    )
}

private func stateSignature(for element: HeistElement) -> ElementStateSignature {
    ElementStateSignature(
        label: element.label,
        value: element.value,
        transientTraits: Set(element.traits.filter(AccessibilityPolicy.transientTraits.contains)),
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
