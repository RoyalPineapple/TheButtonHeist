import AccessibilitySnapshotModel

// MARK: - Page Reconciliation

/// Result of merging a new page into the accumulated element sequence.
package struct PageReconciliation: Equatable {
    /// The merged element sequence after incorporating the page.
    package let elements: [AccessibilityElement]

    /// The overlap region that anchored the merge.
    package let overlap: OverlapResult

    /// Elements from the page that were inserted (not present in accumulated).
    package let inserted: [AccessibilityElement]

    /// How many elements were in the accumulated sequence before the merge.
    package let previousCount: Int
}

/// Reconcile a visible page into accumulated semantic memory.
///
/// Visible pages are physical evidence; known state is semantic memory. This
/// helper is the page-level bridge: content identity finds overlap, and page
/// evidence wins inside the visible overlap.
///
/// - Parameters:
///   - accumulated: Elements seen so far from previous pages.
///   - page: Elements from the current viewport.
///
/// When no overlap is found, the page is appended as entirely new content.
package func reconcilePage(
    accumulated: [AccessibilityElement],
    page: [AccessibilityElement]
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

    let accumulatedFingerprints = contentFingerprints(for: accumulated)
    let pageFingerprints = contentFingerprints(for: page)
    let overlap = findOverlap(
        accumulated: accumulatedFingerprints,
        page: pageFingerprints
    )

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
