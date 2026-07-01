import ThePlans
import Foundation
import AccessibilitySnapshotModel

enum AccessibilityTraceMoveInference {

    static func suppressElementChurnFromFunctionalMoves(
        edits: ElementEdits,
        beforeElements: [HeistElement],
        afterElements: [HeistElement],
        projection: AccessibilityTrace.DeltaProjection = .geometryAware
    ) -> ElementEdits {
        suppressElementChurnFromFunctionalMoves(
            edits: edits,
            beforeRecords: beforeElements.map(ElementDiffRecord.init),
            afterRecords: afterElements.map(ElementDiffRecord.init),
            projection: projection
        )
    }

    static func suppressElementChurnFromFunctionalMoves(
        edits: ElementEdits,
        beforeRecords: [ElementDiffRecord],
        afterRecords: [ElementDiffRecord],
        projection: AccessibilityTrace.DeltaProjection = .geometryAware
    ) -> ElementEdits {
        let beforeKeys = Set(beforeRecords.map(\.diffPairingKey))
        let afterKeys = Set(afterRecords.map(\.diffPairingKey))
        let removedKeys = beforeKeys.subtracting(afterKeys)
        let addedKeys = afterKeys.subtracting(beforeKeys)
        guard !removedKeys.isEmpty, !addedKeys.isEmpty else { return edits }

        let removedByKey = Dictionary(
            grouping: beforeRecords.filter { removedKeys.contains($0.diffPairingKey) },
            by: \.diffPairingKey
        ).compactMapValues { $0.count == 1 ? $0[0] : nil }
        let addedByKey = Dictionary(
            grouping: afterRecords.filter { addedKeys.contains($0.diffPairingKey) },
            by: \.diffPairingKey
        ).compactMapValues { $0.count == 1 ? $0[0] : nil }

        let pairs = inferFunctionalHeistElementPairs(
            removedByKey: removedByKey,
            addedByKey: addedByKey
        )
        guard !pairs.isEmpty else { return edits }

        let pairedRemovedElements = Set(pairs.compactMap { removedByKey[$0.removedKey]?.element })
        let pairedAddedElements = Set(pairs.compactMap { addedByKey[$0.insertedKey]?.element })
        let added = edits.added.filter { !pairedAddedElements.contains($0) }
        let removed = edits.removed.filter { !pairedRemovedElements.contains($0) }
        let inferredUpdates = pairs.compactMap { pair -> ElementUpdate? in
            guard let old = removedByKey[pair.removedKey],
                  let new = addedByKey[pair.insertedKey] else { return nil }
            return projectElementStateChange(old: old.element, new: new.element, projection: projection)
        }

        return ElementEdits(
            added: added,
            removed: removed,
            updated: edits.updated + inferredUpdates
        )
    }

    private static func inferFunctionalHeistElementPairs(
        removedByKey: [ElementDiffPairingKey: ElementDiffRecord],
        addedByKey: [ElementDiffPairingKey: ElementDiffRecord]
    ) -> [FunctionalElementPair<ElementDiffPairingKey>] {
        let removed = removedByKey.compactMap { key, element -> ElementPairingCandidate<ElementDiffPairingKey>? in
            guard key.traceIdentity == nil else { return nil }
            return ElementPairingCandidate(key: key, signature: pairingSignature(for: element.element))
        }
        let added = addedByKey.compactMap { key, element -> ElementPairingCandidate<ElementDiffPairingKey>? in
            guard key.traceIdentity == nil else { return nil }
            return ElementPairingCandidate(key: key, signature: pairingSignature(for: element.element))
        }
        return inferFunctionalPairs(removed: removed, added: added)
    }

    private static func inferFunctionalPairs<Key: Hashable>(
        removed: [ElementPairingCandidate<Key>],
        added: [ElementPairingCandidate<Key>]
    ) -> [FunctionalElementPair<Key>] {
        let removedByIdentity = Dictionary(grouping: removed, by: { $0.signature.identity })
        let addedByIdentity = Dictionary(grouping: added, by: { $0.signature.identity })
        let identities = Set(removedByIdentity.keys).intersection(addedByIdentity.keys)
        var pairs: [FunctionalElementPair<Key>] = []

        for identity in identities {
            guard let removedMatches = removedByIdentity[identity],
                  let addedMatches = addedByIdentity[identity] else { continue }
            if removedMatches.count == 1 && addedMatches.count == 1 {
                pairs.append(FunctionalElementPair(
                    removedKey: removedMatches[0].key,
                    insertedKey: addedMatches[0].key
                ))
                continue
            }

            let removedByFullSignature = Dictionary(grouping: removedMatches, by: \.signature)
            let addedByFullSignature = Dictionary(grouping: addedMatches, by: \.signature)
            let matchingSignatures = Set(removedByFullSignature.keys)
                .intersection(addedByFullSignature.keys)
            for signature in matchingSignatures {
                guard let removedStateMatches = removedByFullSignature[signature],
                      let addedStateMatches = addedByFullSignature[signature],
                      removedStateMatches.count == 1,
                      addedStateMatches.count == 1 else { continue }
                pairs.append(FunctionalElementPair(
                    removedKey: removedStateMatches[0].key,
                    insertedKey: addedStateMatches[0].key
                ))
            }
        }
        return pairs
    }
}

private struct ElementPairingCandidate<Key: Hashable> {
    let key: Key
    let signature: ElementPairingSignature
}

private struct FunctionalElementPair<Key: Hashable> {
    let removedKey: Key
    let insertedKey: Key
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
