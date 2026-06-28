import ThePlans
import Foundation
import AccessibilitySnapshotModel

enum AccessibilityTraceElementDiff {

    static func projectElementEdits(
        beforeElements: [HeistElement],
        afterElements: [HeistElement]
    ) -> ElementEdits {
        let edits = projectElementEditsWithoutMoveSuppression(
            beforeElements: beforeElements,
            afterElements: afterElements
        )
        return AccessibilityTraceMoveInference.suppressElementChurnFromFunctionalMoves(
            edits: edits,
            beforeElements: beforeElements,
            afterElements: afterElements
        )
    }

    static func projectElementEditsWithoutMoveSuppression(
        beforeElements: [HeistElement],
        afterElements: [HeistElement]
    ) -> ElementEdits {
        let oldByKey = Dictionary(grouping: beforeElements, by: \.diffPairingKey)
        let newByKey = Dictionary(grouping: afterElements, by: \.diffPairingKey)
        let allKeys = Set(oldByKey.keys).union(newByKey.keys).sorted()

        var updated: [ElementUpdate] = []
        var added: [HeistElement] = []
        var removed: [HeistElement] = []

        for key in allKeys {
            let oldEls = oldByKey[key] ?? []
            let newEls = newByKey[key] ?? []
            let pairCount = min(oldEls.count, newEls.count)
            updated += zip(oldEls.prefix(pairCount), newEls.prefix(pairCount))
                .compactMap { projectElementStateChange(old: $0, new: $1) }
            removed += Array(oldEls.suffix(from: pairCount))
            added += newEls.suffix(from: pairCount)
        }

        return ElementEdits(added: added, removed: removed, updated: updated)
    }

    static func pairingKeyMultisetDiffers(
        beforeElements: [HeistElement],
        afterElements: [HeistElement]
    ) -> Bool {
        pairingKeyCounts(beforeElements) != pairingKeyCounts(afterElements)
    }

    private static func pairingKeyCounts(_ elements: [HeistElement]) -> [ElementDiffPairingKey: Int] {
        var counts: [ElementDiffPairingKey: Int] = [:]
        for element in elements {
            counts[element.diffPairingKey, default: 0] += 1
        }
        return counts
    }
}

func projectElementStateChange(
    old: HeistElement,
    new: HeistElement,
    includeGeometry: Bool = true
) -> ElementUpdate? {
    var changes: [PropertyChange] = []

    // label is identity (pairing key), not an update property — paired elements
    // share it by construction, so no label PropertyChange is emitted.
    for property in ElementProperty.semanticDiffProperties {
        appendChangeIfNeeded(property, old: old, new: new, to: &changes)
    }

    if includeGeometry {
        for property in ElementProperty.geometryDiffProperties {
            appendChangeIfNeeded(property, old: old, new: new, to: &changes)
        }
    }

    guard !changes.isEmpty else { return nil }
    return ElementUpdate(before: old, after: new, changes: changes)
}

private func appendChangeIfNeeded(
    _ property: ElementProperty,
    old: HeistElement,
    new: HeistElement,
    to changes: inout [PropertyChange]
) {
    switch property {
    case .value:
        appendChangeIfNeeded(ValueProperty.self, old: old, new: new, to: &changes)
    case .traits:
        appendChangeIfNeeded(TraitsProperty.self, old: old, new: new, to: &changes)
    case .hint:
        appendChangeIfNeeded(HintProperty.self, old: old, new: new, to: &changes)
    case .actions:
        appendChangeIfNeeded(ActionsProperty.self, old: old, new: new, to: &changes)
    case .frame:
        appendChangeIfNeeded(FrameProperty.self, old: old, new: new, to: &changes)
    case .activationPoint:
        appendChangeIfNeeded(ActivationPointProperty.self, old: old, new: new, to: &changes)
    case .customContent:
        appendChangeIfNeeded(CustomContentProperty.self, old: old, new: new, to: &changes)
    case .rotors:
        appendChangeIfNeeded(RotorsProperty.self, old: old, new: new, to: &changes)
    }
}

private func appendChangeIfNeeded<P: ElementPropertyValueKind>(
    _ property: P.Type,
    old: HeistElement,
    new: HeistElement,
    to changes: inout [PropertyChange]
) {
    let oldValue = P.value(in: old)
    let newValue = P.value(in: new)
    guard !P.valuesEqual(oldValue, newValue) else { return }
    changes.append(P.change(old: oldValue, new: newValue))
}

private extension ElementProperty {
    static let semanticDiffProperties: [ElementProperty] = [
        .value,
        .traits,
        .hint,
        .actions,
        .customContent,
        .rotors,
    ]

    static let geometryDiffProperties: [ElementProperty] = [
        .frame,
        .activationPoint,
    ]
}

// MARK: - Diff Pairing Key

struct ElementDiffPairingKey: Hashable, Sendable, Comparable {
    let text: String
    let identityTraits: Set<HeistTrait>

    init(element: HeistElement) {
        text = Self.identityText(for: element)
        identityTraits = Set(element.traits.filter {
            !AccessibilityPolicy.transientTraits.contains($0)
        })
    }

    static func < (lhs: ElementDiffPairingKey, rhs: ElementDiffPairingKey) -> Bool {
        guard lhs.text == rhs.text else { return lhs.text < rhs.text }
        return lhs.orderedIdentityTraitRawValues
            .lexicographicallyPrecedes(rhs.orderedIdentityTraitRawValues)
    }

    private var orderedIdentityTraitRawValues: [String] {
        identityTraits.map(\.rawValue).sorted()
    }

    private static func identityText(for element: HeistElement) -> String {
        [element.identifier, element.label]
            .compactMap { value in
                (value?.isEmpty == false) ? value : nil
            }
            .first ?? element.description
    }
}

extension HeistElement {
    /// Content-derived key used to pair before/after elements across a
    /// transition. Replaces the removed internal element id: the diff has no
    /// notion of element identity beyond what the wire-visible content implies.
    /// Mirrors the old identity synthesis — the first non-empty of
    /// `identifier`/`label`/`description`, plus non-transient (identity) traits —
    /// so transient state changes (selected, focused) don't break pairing.
    var diffPairingKey: ElementDiffPairingKey {
        ElementDiffPairingKey(element: self)
    }
}
