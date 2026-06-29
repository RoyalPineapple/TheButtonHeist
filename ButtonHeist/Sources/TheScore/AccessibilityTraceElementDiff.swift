import ThePlans
import Foundation
import AccessibilitySnapshotModel

enum AccessibilityTraceElementDiff {

    static func projectElementEdits(
        beforeElements: [HeistElement],
        afterElements: [HeistElement]
    ) -> ElementEdits {
        projectElementEdits(
            beforeRecords: beforeElements.map(ElementDiffRecord.init),
            afterRecords: afterElements.map(ElementDiffRecord.init)
        )
    }

    static func projectElementEdits(
        beforeRecords: [ElementDiffRecord],
        afterRecords: [ElementDiffRecord]
    ) -> ElementEdits {
        let edits = projectElementEditsWithoutMoveSuppression(
            beforeRecords: beforeRecords,
            afterRecords: afterRecords
        )
        return AccessibilityTraceMoveInference.suppressElementChurnFromFunctionalMoves(
            edits: edits,
            beforeRecords: beforeRecords,
            afterRecords: afterRecords
        )
    }

    static func projectElementEditsWithoutMoveSuppression(
        beforeElements: [HeistElement],
        afterElements: [HeistElement]
    ) -> ElementEdits {
        projectElementEditsWithoutMoveSuppression(
            beforeRecords: beforeElements.map(ElementDiffRecord.init),
            afterRecords: afterElements.map(ElementDiffRecord.init)
        )
    }

    static func projectElementEditsWithoutMoveSuppression(
        beforeRecords: [ElementDiffRecord],
        afterRecords: [ElementDiffRecord]
    ) -> ElementEdits {
        let oldByKey = Dictionary(grouping: beforeRecords, by: \.diffPairingKey)
        let newByKey = Dictionary(grouping: afterRecords, by: \.diffPairingKey)
        let allKeys = Set(oldByKey.keys).union(newByKey.keys).sorted()

        var updated: [ElementUpdate] = []
        var added: [HeistElement] = []
        var removed: [HeistElement] = []

        for key in allKeys {
            let oldEls = oldByKey[key] ?? []
            let newEls = newByKey[key] ?? []
            let pairCount = min(oldEls.count, newEls.count)
            updated += zip(oldEls.prefix(pairCount), newEls.prefix(pairCount))
                .compactMap { projectElementStateChange(old: $0.element, new: $1.element) }
            removed += oldEls.suffix(from: pairCount).map(\.element)
            added += newEls.suffix(from: pairCount).map(\.element)
        }

        return ElementEdits(added: added, removed: removed, updated: updated)
    }

    static func pairingKeyMultisetDiffers(
        beforeElements: [HeistElement],
        afterElements: [HeistElement]
    ) -> Bool {
        pairingKeyMultisetDiffers(
            beforeRecords: beforeElements.map(ElementDiffRecord.init),
            afterRecords: afterElements.map(ElementDiffRecord.init)
        )
    }

    static func pairingKeyMultisetDiffers(
        beforeRecords: [ElementDiffRecord],
        afterRecords: [ElementDiffRecord]
    ) -> Bool {
        pairingKeyCounts(beforeRecords) != pairingKeyCounts(afterRecords)
    }

    private static func pairingKeyCounts(_ elements: [ElementDiffRecord]) -> [ElementDiffPairingKey: Int] {
        var counts: [ElementDiffPairingKey: Int] = [:]
        for element in elements {
            counts[element.diffPairingKey, default: 0] += 1
        }
        return counts
    }
}

struct ElementDiffRecord: Equatable, Sendable {
    let element: HeistElement
    let traceIdentity: TraceElementIdentity?

    init(element: HeistElement, traceIdentity: TraceElementIdentity? = nil) {
        self.element = element
        self.traceIdentity = traceIdentity
    }

    init(_ element: HeistElement) {
        self.init(element: element)
    }

    init(_ record: InterfaceElementRecord) {
        self.init(element: record.element, traceIdentity: record.traceIdentity)
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
    appendSemanticChanges(old: old, new: new, to: &changes)

    if includeGeometry {
        appendGeometryChanges(old: old, new: new, to: &changes)
    }

    guard !changes.isEmpty else { return nil }
    return ElementUpdate(before: old, after: new, changes: changes)
}

private func appendSemanticChanges(
    old: HeistElement,
    new: HeistElement,
    to changes: inout [PropertyChange]
) {
    appendChangeIfNeeded(ValueProperty.self, old: old, new: new, to: &changes)
    appendChangeIfNeeded(TraitsProperty.self, old: old, new: new, to: &changes)
    appendChangeIfNeeded(HintProperty.self, old: old, new: new, to: &changes)
    appendChangeIfNeeded(ActionsProperty.self, old: old, new: new, to: &changes)
    appendChangeIfNeeded(CustomContentProperty.self, old: old, new: new, to: &changes)
    appendChangeIfNeeded(RotorsProperty.self, old: old, new: new, to: &changes)
}

private func appendGeometryChanges(
    old: HeistElement,
    new: HeistElement,
    to changes: inout [PropertyChange]
) {
    appendChangeIfNeeded(FrameProperty.self, old: old, new: new, to: &changes)
    appendChangeIfNeeded(ActivationPointProperty.self, old: old, new: new, to: &changes)
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

// MARK: - Diff Pairing Key

struct ElementDiffPairingKey: Hashable, Sendable, Comparable {
    let traceIdentity: TraceElementIdentity?
    let text: String
    let identityTraits: Set<HeistTrait>

    init(element: HeistElement) {
        self.init(record: ElementDiffRecord(element))
    }

    init(record: ElementDiffRecord) {
        traceIdentity = record.traceIdentity
        let element = record.element
        text = Self.identityText(for: element)
        identityTraits = Set(element.traits.filter {
            !AccessibilityPolicy.transientTraits.contains($0)
        })
    }

    static func == (lhs: ElementDiffPairingKey, rhs: ElementDiffPairingKey) -> Bool {
        switch (lhs.traceIdentity, rhs.traceIdentity) {
        case let (left?, right?):
            return left == right
        case (nil, nil):
            return lhs.text == rhs.text && lhs.identityTraits == rhs.identityTraits
        case (.some, nil), (nil, .some):
            return false
        }
    }

    func hash(into hasher: inout Hasher) {
        if let traceIdentity {
            hasher.combine(0)
            hasher.combine(traceIdentity)
        } else {
            hasher.combine(1)
            hasher.combine(text)
            hasher.combine(identityTraits)
        }
    }

    static func < (lhs: ElementDiffPairingKey, rhs: ElementDiffPairingKey) -> Bool {
        switch (lhs.traceIdentity, rhs.traceIdentity) {
        case let (left?, right?):
            return left < right
        case (.some, nil):
            return true
        case (nil, .some):
            return false
        case (nil, nil):
            break
        }
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

extension ElementDiffRecord {
    var diffPairingKey: ElementDiffPairingKey {
        ElementDiffPairingKey(record: self)
    }
}
