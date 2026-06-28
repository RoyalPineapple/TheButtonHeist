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

    private static func pairingKeyCounts(_ elements: [HeistElement]) -> [String: Int] {
        var counts: [String: Int] = [:]
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
    let oldValue = ElementPropertyValue.value(for: property, in: old)
    let newValue = ElementPropertyValue.value(for: property, in: new)
    guard oldValue != newValue else { return }
    changes.append(PropertyChange(property: property, oldValue: oldValue, newValue: newValue))
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

extension HeistElement {
    /// Content-derived key used to pair before/after elements across a
    /// transition. Replaces the removed internal element id: the diff has no
    /// notion of element identity beyond what the wire-visible content implies.
    /// Mirrors the old identity synthesis — the first non-empty of
    /// `identifier`/`label`/`description`, plus non-transient (identity) traits —
    /// so transient state changes (selected, focused) don't break pairing.
    var diffPairingKey: String {
        let base = [identifier, label].compactMap { value in
            (value?.isEmpty == false) ? value : nil
        }.first ?? description
        let identityTraits = traits
            .filter { !AccessibilityPolicy.transientTraits.contains($0) }
            .map(\.rawValue)
            .sorted()
            .joined(separator: ",")
        return base + "\u{1F}" + identityTraits
    }
}
