#if canImport(UIKit)
#if DEBUG
import UIKit

import AccessibilitySnapshotParser
import ThePlans
import TheScore

/// A derived change projection over two ordered accessibility observations.
///
/// This is the settle loop's evidence: `unchanged` is the only shape that can
/// prove stability, and the field list explains exactly what falsified it
/// otherwise. It never owns source truth — the ledger holds that.
struct SettleDelta: Equatable, Sendable {
    /// One paired element's changed fields, in traversal order.
    struct ElementChange: Equatable, Sendable {
        let index: Int
        let name: String
        let fields: [String]
    }

    /// The element counts on either side, when they differ.
    struct CountChange: Equatable, Sendable {
        let previous: Int
        let current: Int
    }

    /// No prior observation exists to compare against, so the delta carries no
    /// verdict. Distinct from `unchanged`: a first reading is not evidence.
    static let baseline = SettleDelta(isBaseline: true)

    /// A comparison ran and found nothing. This is the only settlement
    /// evidence the loop recognises.
    static let unchanged = SettleDelta(countChange: nil, elementChanges: [], truncated: false)

    let countChange: CountChange?
    let elementChanges: [ElementChange]
    /// True when the paired scan stopped early at the reporting cap.
    let truncated: Bool
    private let isBaseline: Bool

    init(
        countChange: CountChange?,
        elementChanges: [ElementChange],
        truncated: Bool
    ) {
        self.countChange = countChange
        self.elementChanges = elementChanges
        self.truncated = truncated
        self.isBaseline = false
    }

    private init(isBaseline: Bool) {
        self.countChange = nil
        self.elementChanges = []
        self.truncated = false
        self.isBaseline = isBaseline
    }

    /// True when a comparison ran and found nothing — the settle loop's only
    /// stability evidence.
    var isUnchanged: Bool {
        !isBaseline && countChange == nil && elementChanges.isEmpty
    }

    /// Compact explanation of the change, or `nil` when nothing changed.
    var changeDescription: String? {
        guard !isUnchanged, !isBaseline else { return nil }
        let counts = countChange.map { ["count \($0.previous)->\($0.current)"] } ?? []
        let elements = elementChanges.map { "[\($0.index)] \($0.name): \($0.fields.joined(separator: ", "))" }
        let suffix = truncated ? "; ..." : ""
        return "unstable accessibility changes: \((counts + elements).joined(separator: "; "))\(suffix)"
    }
}

@MainActor struct SettleObservationLedger {
    private(set) var currentGenerationLastObservation: SettleRecordedObservation?
    private(set) var latestDelta: SettleDelta = .baseline
    private let bucket: CGFloat
    private var previousElements: [AccessibilityElement]?

    init(bucket: CGFloat = CoarseFrameComparison.currentBucket) {
        self.bucket = bucket
    }

    mutating func record(_ observation: InterfaceObservation) -> SettleRecordedObservation {
        let elements = observation.liveCapture.hierarchy.sortedElements
        if let previousElements {
            latestDelta = SettleTimeline.delta(
                from: previousElements,
                to: elements,
                bucket: bucket
            )
        }
        previousElements = elements
        let recordedObservation = SettleRecordedObservation(
            observation: observation,
            fingerprint: SettleTimeline.fingerprint(of: observation, bucket: bucket)
        )
        currentGenerationLastObservation = recordedObservation
        return recordedObservation
    }

    mutating func resetCurrentGeneration() {
        currentGenerationLastObservation = nil
        previousElements = nil
        latestDelta = .baseline
    }
}

struct SettleRecordedObservation {
    let observation: InterfaceObservation
    let fingerprint: Int

    var sample: SettleObservationSample {
        SettleObservationSample(fingerprint: fingerprint)
    }
}

@MainActor enum SettleTimeline {
    static func fingerprint(
        of observation: InterfaceObservation,
        bucket: CGFloat = CoarseFrameComparison.currentBucket
    ) -> Int {
        var hasher = Hasher()
        let hierarchy = observation.liveCapture.hierarchy
        let indexedElements = hierarchy.pathIndexedElements
        hasher.combine(indexedElements.count)
        for indexed in indexedElements {
            hasher.combine(indexed.path)
            hasher.combine(indexed.traversalIndex)
            combine(indexed.element, into: &hasher, bucket: bucket)
        }
        let indexedContainers = hierarchy.pathIndexedContainers
        hasher.combine(indexedContainers.count)
        for indexed in indexedContainers {
            hasher.combine(indexed.path)
            hasher.combine(indexed.container)
        }
        for (path, heistId) in observation.liveCapture.snapshot.heistIdsByPath.sorted(by: { $0.key < $1.key }) {
            hasher.combine(path)
            hasher.combine(heistId)
        }
        hasher.combine(observation.liveCapture.firstResponderHeistId)
        return hasher.finalize()
    }

    private static func combine(
        _ element: AccessibilityElement,
        into hasher: inout Hasher,
        bucket: CGFloat
    ) {
        hasher.combine(element.description)
        hasher.combine(element.label)
        hasher.combine(element.identifier)
        hasher.combine(element.traits)
        hasher.combine(element.hint)
        hasher.combine(element.userInputLabels)
        hasher.combine(element.usesDefaultActivationPoint)
        hasher.combine(element.customActions)
        hasher.combine(element.customContent)
        hasher.combine(element.customRotors)
        hasher.combine(element.accessibilityLanguage)
        hasher.combine(element.respondsToUserInteraction)
        hasher.combine(element.visibility)

        // `updatesFrequently` declares that the *value* churns (a timer, a
        // progress readout). It says nothing about position, so geometry stays
        // in the fingerprint: an element carrying the trait that moves is still
        // unstable.
        if !element.traits.contains(.updatesFrequently) {
            hasher.combine(element.value)
        }
        switch element.shape {
        case .frame(let rect):
            hasher.combine(CoarseFrameComparison.key(for: rect.cgRect, bucket: bucket))
        case .path:
            hasher.combine(element.shape)
        }
        guard !element.usesDefaultActivationPoint else { return }
        hasher.combine(CoarseFrameComparison.key(
            for: CGRect(x: element.activationPoint.x, y: element.activationPoint.y, width: 0, height: 0),
            bucket: bucket
        ))
    }

    /// The typed change projection between two ordered element scans.
    ///
    /// Element changes are capped at the reporting limit; `truncated` records
    /// that the paired scan stopped early so callers do not read an empty tail
    /// as stability.
    static func delta(
        from previous: [AccessibilityElement],
        to current: [AccessibilityElement],
        bucket: CGFloat = CoarseFrameComparison.currentBucket
    ) -> SettleDelta {
        let countChange = previous.count == current.count
            ? nil
            : SettleDelta.CountChange(previous: previous.count, current: current.count)
        let reportedChangeLimit = 4
        var elementChanges: [SettleDelta.ElementChange] = []
        var truncated = false

        let pairedCount = min(previous.count, current.count)
        for index in 0..<pairedCount {
            guard let change = elementChange(
                before: previous[index],
                after: current[index],
                index: index,
                bucket: bucket
            ) else { continue }
            elementChanges.append(change)
            if elementChanges.count + (countChange == nil ? 0 : 1) == reportedChangeLimit {
                truncated = index < pairedCount - 1
                break
            }
        }

        return SettleDelta(
            countChange: countChange,
            elementChanges: elementChanges,
            truncated: truncated
        )
    }

    private static func elementChange(
        before: AccessibilityElement,
        after: AccessibilityElement,
        index: Int,
        bucket: CGFloat
    ) -> SettleDelta.ElementChange? {
        var fields: [String] = []
        if before.label != after.label {
            fields.append("label \(quoted(before.label))->\(quoted(after.label))")
        }
        if before.identifier != after.identifier {
            fields.append("identifier \(quoted(before.identifier))->\(quoted(after.identifier))")
        }
        if before.traits.rawValue != after.traits.rawValue {
            fields.append("traits \(before.traits.rawValue)->\(after.traits.rawValue)")
        }

        // Mirrors `combine`: the value is masked for `updatesFrequently`
        // elements, geometry never is.
        let valueMasked = before.traits.contains(.updatesFrequently) || after.traits.contains(.updatesFrequently)
        if !valueMasked, before.value != after.value {
            fields.append("value \(quoted(before.value))->\(quoted(after.value))")
        }
        let beforeFrame = before.shape.frame
        let afterFrame = after.shape.frame
        let beforeKey = CoarseFrameComparison.key(for: beforeFrame, bucket: bucket)
        let afterKey = CoarseFrameComparison.key(for: afterFrame, bucket: bucket)
        if beforeKey != afterKey {
            fields.append(
                "frame bucket \(beforeKey.hashFragment)->\(afterKey.hashFragment) " +
                    "frame \(format(beforeFrame))->\(format(afterFrame))"
            )
        }

        guard !fields.isEmpty else { return nil }
        return SettleDelta.ElementChange(
            index: index,
            name: elementName(before, alternate: after),
            fields: fields
        )
    }

    private static func elementName(_ element: AccessibilityElement, alternate: AccessibilityElement) -> String {
        if let label = element.label, !label.isEmpty { return "label=\(quoted(label))" }
        if let identifier = element.identifier, !identifier.isEmpty { return "id=\(quoted(identifier))" }
        if let label = alternate.label, !label.isEmpty { return "label=\(quoted(label))" }
        if let identifier = alternate.identifier, !identifier.isEmpty { return "id=\(quoted(identifier))" }
        return "anonymous"
    }

    private static func quoted(_ value: String?) -> String {
        guard let value else { return "nil" }
        return CanonicalValueDescription.quoted(value)
    }

    private static func format(_ frame: CGRect) -> String {
        "(\(format(frame.origin.x)),\(format(frame.origin.y)),\(format(frame.size.width)),\(format(frame.size.height)))"
    }

    private static func format(_ value: CGFloat) -> String {
        guard value.isFinite else { return "unavailable" }
        let rounded = value.rounded()
        if abs(value - rounded) < 0.000_001 {
            return String(format: "%.0f", Double(rounded))
        }
        return String(format: "%.1f", Double(value))
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
