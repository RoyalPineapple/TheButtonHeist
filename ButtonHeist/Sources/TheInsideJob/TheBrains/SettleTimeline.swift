#if canImport(UIKit)
#if DEBUG
import UIKit

import AccessibilitySnapshotParser
import TheScore

struct TimelineKey: Hashable, Sendable {
    let label: String?
    let identifier: String?
    let frameMinX: Int
    let frameMinY: Int
    let frameWidth: Int
    let frameHeight: Int
}

extension AccessibilityElement {
    @MainActor
    var timelineKey: TimelineKey {
        timelineKey(bucket: CoarseFrameComparison.currentBucket)
    }

    @MainActor
    func timelineKey(bucket: CGFloat) -> TimelineKey {
        let rect: CGRect
        if case .frame(let r) = shape {
            rect = r.cgRect
        } else {
            rect = .zero
        }
        let masked = traits.contains(.updatesFrequently)
        let frameKey = masked ? .zero : CoarseFrameComparison.key(for: rect, bucket: bucket)
        return TimelineKey(
            label: label,
            identifier: identifier,
            frameMinX: frameKey.minX,
            frameMinY: frameKey.minY,
            frameWidth: frameKey.width,
            frameHeight: frameKey.height
        )
    }
}

@MainActor struct SettleObservationLedger {
    private(set) var elementsByKey: [TimelineKey: AccessibilityElement] = [:]
    private(set) var currentGenerationLastObservation: SettleRecordedObservation?
    private(set) var latestChangeDescription: String?
    private let bucket: CGFloat
    private var previousElements: [AccessibilityElement]?

    init(bucket: CGFloat = CoarseFrameComparison.currentBucket) {
        self.bucket = bucket
    }

    mutating func record(_ observation: InterfaceObservation) -> SettleRecordedObservation {
        let elements = observation.liveCapture.hierarchy.sortedElements
        if let previousElements {
            latestChangeDescription = SettleTimeline.changeDescription(
                from: previousElements,
                to: elements,
                bucket: bucket
            )
        }
        previousElements = elements
        for element in elements {
            elementsByKey[element.timelineKey(bucket: bucket)] = element
        }
        let recordedObservation = SettleRecordedObservation(
            observation: observation,
            fingerprint: SettleTimeline.fingerprint(of: observation, bucket: bucket),
            elementsByKey: elementsByKey,
            instabilityDescription: latestChangeDescription
        )
        currentGenerationLastObservation = recordedObservation
        return recordedObservation
    }

    mutating func resetCurrentGeneration() {
        currentGenerationLastObservation = nil
    }
}

struct SettleRecordedObservation {
    let observation: InterfaceObservation
    let fingerprint: Int
    let elementsByKey: [TimelineKey: AccessibilityElement]
    let instabilityDescription: String?

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

        guard !element.traits.contains(.updatesFrequently) else { return }
        hasher.combine(element.value)
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

    static func transientElements(
        seenByKey: [TimelineKey: AccessibilityElement],
        baseline: [AccessibilityElement],
        final: [AccessibilityElement]
    ) -> [AccessibilityElement] {
        if seenByKey.isEmpty { return [] }
        let baselineKeys = Set(baseline.map(\.timelineKey))
        let finalKeys = Set(final.map(\.timelineKey))
        let candidates = seenByKey.compactMap { key, element -> AccessibilityElement? in
            (baselineKeys.contains(key) || finalKeys.contains(key)) ? nil : element
        }
        return candidates.sorted { lhs, rhs in
            let lhsKey = lhs.timelineKey
            let rhsKey = rhs.timelineKey
            if lhsKey.frameMinY != rhsKey.frameMinY { return lhsKey.frameMinY < rhsKey.frameMinY }
            if lhsKey.frameMinX != rhsKey.frameMinX { return lhsKey.frameMinX < rhsKey.frameMinX }
            if (lhsKey.label ?? "") != (rhsKey.label ?? "") { return (lhsKey.label ?? "") < (rhsKey.label ?? "") }
            return (lhsKey.identifier ?? "") < (rhsKey.identifier ?? "")
        }
    }

    static func changeDescription(
        from previous: [AccessibilityElement],
        to current: [AccessibilityElement],
        bucket: CGFloat = CoarseFrameComparison.currentBucket
    ) -> String? {
        var changes: [String] = []
        var truncated = false
        if previous.count != current.count {
            changes.append("count \(previous.count)->\(current.count)")
        }

        let pairedCount = min(previous.count, current.count)
        for index in 0..<pairedCount {
            let before = previous[index]
            let after = current[index]
            guard let summary = elementChangeDescription(
                before: before,
                after: after,
                index: index,
                bucket: bucket
            ) else { continue }
            changes.append(summary)
            if changes.count == 4 {
                truncated = index < pairedCount - 1
                break
            }
        }

        guard !changes.isEmpty else { return nil }
        let suffix = truncated ? "; ..." : ""
        return "unstable accessibility changes: \(changes.joined(separator: "; "))\(suffix)"
    }

    private static func elementChangeDescription(
        before: AccessibilityElement,
        after: AccessibilityElement,
        index: Int,
        bucket: CGFloat
    ) -> String? {
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

        let masked = before.traits.contains(.updatesFrequently) || after.traits.contains(.updatesFrequently)
        if !masked {
            if before.value != after.value {
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
        }

        guard !fields.isEmpty else { return nil }
        return "[\(index)] \(elementName(before, alternate: after)): \(fields.joined(separator: ", "))"
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
        return "\"\(value)\""
    }

    private static func format(_ frame: CGRect) -> String {
        "(\(format(frame.origin.x)),\(format(frame.origin.y)),\(format(frame.size.width)),\(format(frame.size.height)))"
    }

    private static func format(_ value: CGFloat) -> String {
        guard value.isFinite else { return "0" }
        let rounded = value.rounded()
        if abs(value - rounded) < 0.000_001 {
            return "\(safeInt(rounded))"
        }
        return String(format: "%.1f", Double(value))
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
