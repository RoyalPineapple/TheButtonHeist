#if canImport(UIKit)
#if DEBUG
import Foundation
import UIKit

import TheScore
import AccessibilitySnapshotParser

// MARK: - TimelineKey

/// A stable identity for an `AccessibilityElement` across snapshot cycles
/// that is *not* perturbed by value churn. Two snapshots of the same
/// spinner — with the same label, identifier, and frame but a changing
/// `value` — produce the same key. This is the right shape for the
/// timeline because we want value-cycling elements to dedupe across cycles
/// (so they don't appear as repeated transients).
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
            rect = r
        } else {
            rect = .zero
        }
        return TimelineKey(
            label: label,
            identifier: identifier,
            frameMinX: Double(rect.origin.x),
            frameMinY: Double(rect.origin.y),
            frameWidth: Double(rect.size.width),
            frameHeight: Double(rect.size.height)
        )
    }
}

// MARK: - TimelineClassification

/// Result of walking baseline → intermediate snapshots → final and bucketing
/// elements into add / remove / transient / flicker categories.
struct TimelineClassification {

    /// Element stableKeys present in `final` but not in `baseline`.
    let addedKeys: Set<TimelineKey>

    /// Element stableKeys present in `baseline` but not in `final`.
    let removedKeys: Set<TimelineKey>

    /// Elements that appeared in at least one intermediate snapshot but are
    /// absent from both `baseline` and `final` — i.e. they came and went
    /// during the observation window. Represented by the `AccessibilityElement`
    /// captured from the snapshot in which they were last seen.
    let transientElements: [AccessibilityElement]

    /// Elements present in both `baseline` and `final` but absent from at
    /// least one intermediate snapshot — i.e. they flickered. Represented
    /// by the `AccessibilityElement` from `baseline`.
    let flickerElements: [AccessibilityElement]

    var hasAnyTransientOrFlicker: Bool {
        !transientElements.isEmpty || !flickerElements.isEmpty
    }
}

// MARK: - SnapshotTimeline

/// A bounded ring buffer of intermediate accessibility-tree snapshots, used
/// to surface "transient" UI states that came and went during a settle
/// window or while the driver was idle.
///
/// Each snapshot stores only the set of `TimelineKey`s present at that
/// instant, plus a sparse element map so labels and traits can be recovered
/// for transient reporting. Memory is bounded: at the default cap of 100
/// snapshots × ~200 keys, the timeline holds well under 1 MB even on
/// element-heavy screens.
@MainActor
final class SnapshotTimeline {

    struct Snapshot {
        let timestamp: CFAbsoluteTime
        let keys: Set<TimelineKey>
        let elementsByKey: [TimelineKey: AccessibilityElement]
    }

    /// Hard cap on retained snapshots. ~100 snapshots × 100ms cadence =
    /// 10 seconds of history, which is plenty for any auto-dismissing flow.
    static let defaultCap: Int = 100

    private(set) var snapshots: [Snapshot] = []
    let cap: Int

    init(cap: Int = SnapshotTimeline.defaultCap) {
        self.cap = cap
    }

    /// Append the parsed elements at the current instant. Evicts oldest
    /// snapshots if the buffer is full.
    @discardableResult
    func append(_ elements: [AccessibilityElement]) -> Snapshot {
        var byKey: [TimelineKey: AccessibilityElement] = [:]
        byKey.reserveCapacity(elements.count)
        for element in elements {
            byKey[element.timelineKey] = element
        }
        let snapshot = Snapshot(
            timestamp: CFAbsoluteTimeGetCurrent(),
            keys: Set(byKey.keys),
            elementsByKey: byKey
        )
        snapshots.append(snapshot)
        if snapshots.count > cap {
            snapshots.removeFirst(snapshots.count - cap)
        }
        return snapshot
    }

    /// Drop every snapshot. Used when the brain's caches are reset.
    func clear() {
        snapshots.removeAll()
    }

    /// Trim snapshots strictly older than the given timestamp. Used after
    /// a baseline is consumed so the next classify() doesn't double-count.
    func trim(before timestamp: CFAbsoluteTime) {
        snapshots.removeAll { $0.timestamp < timestamp }
    }

    /// Classify the elements seen across the timeline against the supplied
    /// baseline and final element arrays.
    ///
    /// Definitions:
    ///  - **transient**: present in some intermediate snapshot, absent from
    ///    both baseline and final.
    ///  - **flicker**: present in baseline AND final, absent from at least
    ///    one intermediate snapshot.
    ///
    /// Spinner-style oscillation (same stable key, value churn only) does
    /// NOT show up as transient or flicker because the stable key dedupes
    /// across cycles.
    func classify(
        baseline: [AccessibilityElement],
        final: [AccessibilityElement]
    ) -> TimelineClassification {
        let baselineByKey = Self.keyMap(baseline)
        let finalByKey = Self.keyMap(final)

        let baselineKeys = Set(baselineByKey.keys)
        let finalKeys = Set(finalByKey.keys)
        let addedKeys = finalKeys.subtracting(baselineKeys)
        let removedKeys = baselineKeys.subtracting(finalKeys)
        let bothKeys = baselineKeys.intersection(finalKeys)

        var transientByKey: [TimelineKey: AccessibilityElement] = [:]
        var flickerByKey: [TimelineKey: AccessibilityElement] = [:]

        for snapshot in snapshots {
            // Transient: keys present here, absent from both endpoints.
            for key in snapshot.keys
            where !baselineKeys.contains(key) && !finalKeys.contains(key) {
                transientByKey[key] = snapshot.elementsByKey[key]
            }
            // Flicker: keys in bothKeys but missing from this snapshot.
            for key in bothKeys where !snapshot.keys.contains(key) {
                flickerByKey[key] = baselineByKey[key]
            }
        }

        return TimelineClassification(
            addedKeys: addedKeys,
            removedKeys: removedKeys,
            transientElements: Array(transientByKey.values),
            flickerElements: Array(flickerByKey.values)
        )
    }

    private static func keyMap(_ elements: [AccessibilityElement]) -> [TimelineKey: AccessibilityElement] {
        var byKey: [TimelineKey: AccessibilityElement] = [:]
        byKey.reserveCapacity(elements.count)
        for element in elements {
            byKey[element.timelineKey] = element
        }
        return byKey
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
