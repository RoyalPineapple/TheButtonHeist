#if canImport(UIKit) && canImport(AccessibilitySnapshotParser)
import AccessibilitySnapshotParser
import CoreGraphics

// MARK: - Page Reconciliation

/// Result of merging a new page into the accumulated element sequence.
struct PageReconciliation: Equatable {
    /// The merged element sequence after incorporating the page.
    let elements: [AccessibilityElement]

    /// The overlap region that anchored the merge.
    let overlap: OverlapResult

    /// Elements from the page that were inserted (not present in accumulated).
    let inserted: [AccessibilityElement]

    /// How many elements were in the accumulated sequence before the merge.
    let previousCount: Int
}

/// Reconcile a visible page into accumulated semantic memory.
///
/// Visible pages are physical evidence; known state is semantic memory. This
/// helper is the page-level bridge: content identity finds overlap, and
/// content-space geometry orders the merged memory when available.
///
/// When content-space origins are complete, geometry orders the union. Otherwise,
/// overlap anchors the page in semantic memory and page evidence wins inside the
/// visible overlap. See `reconcileByContentOrigin` and `reconcileByOverlap` for
/// those two merge strategies.
///
/// - Parameters:
///   - accumulated: Elements seen so far from previous pages.
///   - accumulatedOrigins: Content-space origin for each accumulated element.
///     Pass nil entries for elements not inside a scroll view.
///   - page: Elements from the current viewport.
///   - pageOrigins: Content-space origin for each page element.
///     Pass nil entries for elements not inside a scroll view.
///
/// When no overlap is found, the page is appended as entirely new content.
func reconcilePage(
    accumulated: [AccessibilityElement],
    accumulatedOrigins: [CGPoint?],
    page: [AccessibilityElement],
    pageOrigins: [CGPoint?],
    orderingAxis: ContentOrderingAxis? = nil
) -> PageReconciliation {
    guard !page.isEmpty else {
        return PageReconciliation(
            elements: accumulated,
            overlap: OverlapResult(accumulatedStart: 0, pageStart: 0, length: 0),
            inserted: [],
            previousCount: accumulated.count
        )
    }

    guard !accumulated.isEmpty else {
        return PageReconciliation(
            elements: page,
            overlap: OverlapResult(accumulatedStart: 0, pageStart: 0, length: 0),
            inserted: page,
            previousCount: 0
        )
    }

    let accumulatedFingerprints = contentFingerprints(for: accumulated, origins: accumulatedOrigins)
    let pageFingerprints = contentFingerprints(for: page, origins: pageOrigins)
    let overlap = findOverlap(
        accumulated: accumulatedFingerprints,
        page: pageFingerprints
    )

    if let ordered = reconcileByContentOrigin(
        accumulated: accumulated,
        accumulatedOrigins: accumulatedOrigins,
        accumulatedFingerprints: accumulatedFingerprints,
        page: page,
        pageOrigins: pageOrigins,
        pageFingerprints: pageFingerprints,
        overlap: overlap,
        orderingAxis: orderingAxis
    ) {
        return ordered
    }

    return reconcileByOverlap(accumulated: accumulated, page: page, overlap: overlap)
}

private func reconcileByOverlap(
    accumulated: [AccessibilityElement],
    page: [AccessibilityElement],
    overlap: OverlapResult
) -> PageReconciliation {
    guard overlap.length > 0 else {
        return PageReconciliation(
            elements: accumulated + page,
            overlap: overlap,
            inserted: page,
            previousCount: accumulated.count
        )
    }

    var result: [AccessibilityElement] = []
    result.reserveCapacity(accumulated.count + page.count - overlap.length)
    result.append(contentsOf: accumulated[..<overlap.accumulatedStart])
    result.append(contentsOf: page[..<overlap.pageStart])
    result.append(contentsOf: page[overlap.pageStart..<overlap.pageEnd])
    result.append(contentsOf: page[overlap.pageEnd..<page.endIndex])
    result.append(contentsOf: accumulated[overlap.accumulatedEnd..<accumulated.endIndex])

    let inserted = Array(page[..<overlap.pageStart])
        + Array(page[overlap.pageEnd..<page.endIndex])

    return PageReconciliation(
        elements: result,
        overlap: overlap,
        inserted: inserted,
        previousCount: accumulated.count
    )
}

/// Convenience overload using window-space frames (for non-scrollable contexts or tests).
func reconcilePage(
    accumulated: [AccessibilityElement],
    page: [AccessibilityElement]
) -> PageReconciliation {
    reconcilePage(
        accumulated: accumulated,
        accumulatedOrigins: accumulated.map { _ in nil },
        page: page,
        pageOrigins: page.map { _ in nil }
    )
}
#endif // canImport(UIKit) && canImport(AccessibilitySnapshotParser)
