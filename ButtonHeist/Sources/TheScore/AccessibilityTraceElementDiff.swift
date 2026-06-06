import ThePlans
import Foundation
import AccessibilitySnapshotModel

enum AccessibilityTraceElementDiff {

    static func projectElementEdits(
        beforeElements: [HeistElement],
        afterElements: [HeistElement],
        includeGeometry: Bool = true
    ) -> ElementEdits {
        let oldByKey = Dictionary(grouping: beforeElements, by: \.diffPairingKey)
        let newByKey = Dictionary(grouping: afterElements, by: \.diffPairingKey)
        let allKeys = Set(oldByKey.keys).union(newByKey.keys)

        var updated: [ElementUpdate] = []
        var added: [HeistElement] = []
        var removed: [HeistElement] = []

        for key in allKeys {
            let oldEls = oldByKey[key] ?? []
            let newEls = newByKey[key] ?? []
            let pairCount = min(oldEls.count, newEls.count)
            updated += zip(oldEls.prefix(pairCount), newEls.prefix(pairCount))
                .compactMap { projectElementStateChange(old: $0, new: $1, includeGeometry: includeGeometry) }
            removed += Array(oldEls.suffix(from: pairCount))
            added += newEls.suffix(from: pairCount)
        }

        return AccessibilityTraceMoveInference.suppressElementChurnFromFunctionalMoves(
            edits: ElementEdits(added: added, removed: removed, updated: updated),
            beforeElements: beforeElements,
            afterElements: afterElements
        )
    }
}

func projectElementStateChange(
    old: HeistElement,
    new: HeistElement,
    element: HeistElement? = nil,
    includeGeometry: Bool = true
) -> ElementUpdate? {
    var changes: [PropertyChange] = []

    // label is identity (pairing key), not an update property — paired elements
    // share it by construction, so no label PropertyChange is emitted.
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
    if old.respondsToUserInteraction != new.respondsToUserInteraction {
        changes.append(PropertyChange(
            property: .respondsToUserInteraction,
            old: String(old.respondsToUserInteraction),
            new: String(new.respondsToUserInteraction)
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
    return ElementUpdate(element: element ?? new, changes: changes)
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
    return rotors.map { $0.name }.joined(separator: ", ")
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
