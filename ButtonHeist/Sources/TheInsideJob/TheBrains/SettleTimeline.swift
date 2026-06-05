#if canImport(UIKit)
#if DEBUG
import UIKit

import AccessibilitySnapshotParser

struct TimelineKey: Hashable {
    let label: String?
    let identifier: String?
    let frameMinX: Double
    let frameMinY: Double
    let frameWidth: Double
    let frameHeight: Double
}

extension AccessibilityElement {
    var timelineKey: TimelineKey {
        let rect: CGRect
        if case .frame(let r) = shape {
            rect = r.cgRect
        } else {
            rect = .zero
        }
        let masked = traits.contains(.updatesFrequently)
        return TimelineKey(
            label: label,
            identifier: identifier,
            frameMinX: masked ? 0 : Double(rect.origin.x),
            frameMinY: masked ? 0 : Double(rect.origin.y),
            frameWidth: masked ? 0 : Double(rect.size.width),
            frameHeight: masked ? 0 : Double(rect.size.height)
        )
    }
}

struct SettleObservationLedger {
    private(set) var elementsByKey: [TimelineKey: AccessibilityElement] = [:]

    mutating func record(_ screen: Screen) -> Int {
        let elements = screen.liveCapture.hierarchy.sortedElements
        for element in elements {
            elementsByKey[element.timelineKey] = element
        }
        return SettleTimeline.fingerprint(of: elements)
    }
}

enum SettleTimeline {
    static func fingerprint(of elements: [AccessibilityElement]) -> Int {
        var hasher = Hasher()
        hasher.combine(elements.count)
        for element in elements {
            hasher.combine(element.label)
            hasher.combine(element.identifier)
            hasher.combine(element.traits.rawValue)
            let masked = element.traits.contains(.updatesFrequently)
            if case .frame(let rect) = element.shape, !masked {
                hasher.combine(rect.origin.x)
                hasher.combine(rect.origin.y)
                hasher.combine(rect.size.width)
                hasher.combine(rect.size.height)
            }
            if !masked {
                hasher.combine(element.value)
            }
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
}

#endif // DEBUG
#endif // canImport(UIKit)
