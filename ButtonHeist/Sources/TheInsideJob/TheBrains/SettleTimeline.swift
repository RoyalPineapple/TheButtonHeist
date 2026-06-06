#if canImport(UIKit)
#if DEBUG
import UIKit

import AccessibilitySnapshotParser

struct TimelineKey: Hashable {
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

@MainActor struct SettleObservationLedger { // swiftlint:disable:this agent_main_actor_value_type
    private(set) var elementsByKey: [TimelineKey: AccessibilityElement] = [:]
    private(set) var latestChangeDescription: String?
    private let bucket: CGFloat
    private var previousElements: [AccessibilityElement]?

    init(bucket: CGFloat = CoarseFrameComparison.currentBucket) {
        self.bucket = bucket
    }

    mutating func record(_ screen: Screen) -> Int {
        let elements = screen.liveCapture.hierarchy.sortedElements
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
        return SettleTimeline.fingerprint(of: elements, bucket: bucket)
    }
}

@MainActor enum SettleTimeline { // swiftlint:disable:this agent_main_actor_value_type
    static func fingerprint(
        of elements: [AccessibilityElement],
        bucket _: CGFloat = CoarseFrameComparison.currentBucket
    ) -> Int {
        var hasher = Hasher()
        hasher.combine(elements.count)
        for element in elements {
            let masked = element.traits.contains(.updatesFrequently)
            hasher.combine(element.description)
            hasher.combine(element.label)
            hasher.combine(element.identifier)
            hasher.combine(element.traits.rawValue)
            if !masked {
                hasher.combine(element.value)
            }
            hasher.combine(element.hint)
            hasher.combine(element.userInputLabels)
            hasher.combine(element.customActions.map(\.name).filter { !$0.isEmpty })
            hasher.combine(normalizedCustomContent(element))
            hasher.combine(element.customRotors.map(\.name).filter { !$0.isEmpty })
            hasher.combine(element.accessibilityLanguage)
            hasher.combine(element.respondsToUserInteraction)
        }
        return hasher.finalize()
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
        bucket _: CGFloat = CoarseFrameComparison.currentBucket
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
                index: index
            ) else { continue }
            changes.append(summary)
            if changes.count == 4 {
                truncated = index < pairedCount - 1
                break
            }
        }

        guard !changes.isEmpty else { return nil }
        let suffix = truncated ? "; ..." : ""
        return "unstable semantic changes: \(changes.joined(separator: "; "))\(suffix)"
    }

    private static func elementChangeDescription(
        before: AccessibilityElement,
        after: AccessibilityElement,
        index: Int
    ) -> String? {
        var fields: [String] = []
        if before.description != after.description {
            fields.append("description \(quoted(before.description))->\(quoted(after.description))")
        }
        if before.label != after.label {
            fields.append("label \(quoted(before.label))->\(quoted(after.label))")
        }
        if before.identifier != after.identifier {
            fields.append("id \(quoted(before.identifier))->\(quoted(after.identifier))")
        }
        if before.traits.rawValue != after.traits.rawValue {
            fields.append("traits \(before.traits.rawValue)->\(after.traits.rawValue)")
        }

        let masked = before.traits.contains(.updatesFrequently) || after.traits.contains(.updatesFrequently)
        if !masked {
            if before.value != after.value {
                fields.append("value \(quoted(before.value))->\(quoted(after.value))")
            }
        }
        if before.hint != after.hint {
            fields.append("hint \(quoted(before.hint))->\(quoted(after.hint))")
        }
        if before.userInputLabels != after.userInputLabels {
            fields.append("userInputLabels \(quotedList(before.userInputLabels))->\(quotedList(after.userInputLabels))")
        }
        let beforeActions = before.customActions.map(\.name).filter { !$0.isEmpty }
        let afterActions = after.customActions.map(\.name).filter { !$0.isEmpty }
        if beforeActions != afterActions {
            fields.append("actions \(quotedList(beforeActions))->\(quotedList(afterActions))")
        }
        let beforeContent = normalizedCustomContent(before)
        let afterContent = normalizedCustomContent(after)
        if beforeContent != afterContent {
            fields.append("customContent \(format(beforeContent))->\(format(afterContent))")
        }
        let beforeRotors = before.customRotors.map(\.name).filter { !$0.isEmpty }
        let afterRotors = after.customRotors.map(\.name).filter { !$0.isEmpty }
        if beforeRotors != afterRotors {
            fields.append("rotors \(quotedList(beforeRotors))->\(quotedList(afterRotors))")
        }
        if before.accessibilityLanguage != after.accessibilityLanguage {
            fields.append("language \(quoted(before.accessibilityLanguage))->\(quoted(after.accessibilityLanguage))")
        }
        if before.respondsToUserInteraction != after.respondsToUserInteraction {
            fields.append(
                "respondsToUserInteraction \(before.respondsToUserInteraction)->\(after.respondsToUserInteraction)"
            )
        }

        guard !fields.isEmpty else { return nil }
        return "[\(index)] \(elementName(before, alternate: after)): \(fields.joined(separator: ", "))"
    }

    private struct CustomContentFingerprint: Hashable {
        let label: String
        let value: String
        let isImportant: Bool
    }

    private static func normalizedCustomContent(_ element: AccessibilityElement) -> [CustomContentFingerprint] {
        element.customContent
            .filter { !$0.label.isEmpty || !$0.value.isEmpty }
            .map {
                CustomContentFingerprint(
                    label: $0.label,
                    value: $0.value,
                    isImportant: $0.isImportant
                )
            }
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

    private static func quotedList(_ value: [String]?) -> String {
        guard let value else { return "nil" }
        return "[\(value.map { quoted($0) }.joined(separator: ", "))]"
    }

    private static func format(_ content: [CustomContentFingerprint]) -> String {
        "[\(content.map { format($0) }.joined(separator: ", "))]"
    }

    private static func format(_ content: CustomContentFingerprint) -> String {
        let importance = content.isImportant ? ", important" : ""
        return "\(quoted(content.label)):\(quoted(content.value))\(importance)"
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
