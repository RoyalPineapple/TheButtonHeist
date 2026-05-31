#if canImport(UIKit) && canImport(AccessibilitySnapshotParser)
import AccessibilitySnapshotParser
import CoreGraphics

// MARK: - Content-Origin Ordering

/// Content-space axis used when reconciling scroll pages with stable origins.
enum ContentOrderingAxis: Sendable {
    case horizontal
    case vertical
}

private struct ContentOriginEntry {
    let element: AccessibilityElement
    let origin: CGPoint
    let order: Int
}

/// Geometry-ordered reconciliation when every element has stable content-space
/// origin evidence.
func reconcileByContentOrigin(
    accumulated: [AccessibilityElement],
    accumulatedOrigins: [CGPoint?],
    accumulatedFingerprints: [Int],
    page: [AccessibilityElement],
    pageOrigins: [CGPoint?],
    pageFingerprints: [Int],
    overlap: OverlapResult,
    orderingAxis: ContentOrderingAxis?
) -> PageReconciliation? {
    guard let orderingAxis,
          accumulated.count == accumulatedOrigins.count,
          page.count == pageOrigins.count,
          accumulated.count == accumulatedFingerprints.count,
          page.count == pageFingerprints.count
    else { return nil }

    let accumulatedResolvedOrigins = accumulatedOrigins.compactMap { $0 }
    let pageResolvedOrigins = pageOrigins.compactMap { $0 }
    guard accumulatedResolvedOrigins.count == accumulated.count,
          pageResolvedOrigins.count == page.count
    else { return nil }

    let accumulatedFingerprintSet = Set(accumulatedFingerprints)
    var entriesByFingerprint: [Int: ContentOriginEntry] = [:]
    for index in accumulated.indices {
        entriesByFingerprint[accumulatedFingerprints[index]] = ContentOriginEntry(
            element: accumulated[index],
            origin: accumulatedResolvedOrigins[index],
            order: index
        )
    }

    var inserted: [AccessibilityElement] = []
    for index in page.indices {
        let fingerprint = pageFingerprints[index]
        if !accumulatedFingerprintSet.contains(fingerprint) {
            inserted.append(page[index])
        }
        entriesByFingerprint[fingerprint] = ContentOriginEntry(
            element: page[index],
            origin: pageResolvedOrigins[index],
            order: accumulated.count + index
        )
    }

    let orderedEntries = entriesByFingerprint.values.sorted { lhs, rhs in
        switch orderingAxis {
        case .horizontal:
            if lhs.origin.x != rhs.origin.x { return lhs.origin.x < rhs.origin.x }
            if lhs.origin.y != rhs.origin.y { return lhs.origin.y < rhs.origin.y }
        case .vertical:
            if lhs.origin.y != rhs.origin.y { return lhs.origin.y < rhs.origin.y }
            if lhs.origin.x != rhs.origin.x { return lhs.origin.x < rhs.origin.x }
        }
        return lhs.order < rhs.order
    }

    return PageReconciliation(
        elements: orderedEntries.map(\.element),
        overlap: overlap,
        inserted: inserted,
        previousCount: accumulated.count
    )
}
#endif // canImport(UIKit) && canImport(AccessibilitySnapshotParser)
