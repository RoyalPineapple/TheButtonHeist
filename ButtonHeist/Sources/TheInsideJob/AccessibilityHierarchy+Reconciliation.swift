#if canImport(UIKit) && canImport(AccessibilitySnapshotParser)
import AccessibilitySnapshotParser
import CoreGraphics
import UIKit

// MARK: - Safe Numeric Conversions

/// Convert a `CGFloat` to `Int` without trapping on pathological inputs.
///
/// `Int(_:)` traps with a Swift runtime SIGTRAP when the input is non-finite
/// (NaN, ±∞) or finite-but-out-of-range (e.g. `1e100`, `CGFloat.greatestFiniteMagnitude`).
/// These values can flow in from accessibility geometry — UIKit occasionally produces
/// `.infinity` origins on `.null` rects, and pathological callers can poison frames
/// with values past `Int.max`. The fingerprint hot path hashes thousands of these
/// values per refresh; one bad input takes down the parse.
///
/// Used by two classes of caller, with different stakes:
///
/// - **Fingerprint hashes** (`AccessibilityElement.fingerprint`) feed `Hasher`,
///   so the only contract is "don't trap".
/// - **heistId synthesis fragments** (TheBurglar's `coarseFrameHash`,
///   `contentPositionHeistId`) feed directly into the wire-format heistId string.
///   Per CLAUDE.md heistId synthesis is wire format and is locked by
///   `SynthesisDeterminismTests`. The no-change-for-previously-working-inputs
///   invariant is therefore load-bearing: for any `cgFloat` where `Int(cgFloat)`
///   already succeeded (finite, in `[Int.min, Int.max]`), `safeInt(cgFloat)` must
///   return the same value bit-for-bit. Only pathological inputs that would have
///   trapped get clamped to `Int.min`/`Int.max`/`0`.
///
/// - Returns: `0` for non-finite inputs, the clamped value for out-of-range finite
///   inputs, and `Int(cgFloat)` otherwise.
func safeInt(_ cgFloat: CGFloat) -> Int {
    guard cgFloat.isFinite else { return 0 }
    if cgFloat >= CGFloat(Int.max) { return Int.max }
    if cgFloat <= CGFloat(Int.min) { return Int.min }
    return Int(cgFloat)
}

// MARK: - Safe Path Bounds

extension UIBezierPath {
    /// Bounds that won't trap on degenerate paths.
    ///
    /// `UIBezierPath.bounds` (and `cgPath.boundingBoxOfPath`) can return `.null`
    /// — whose origin is `.infinity` — when the path is empty, and may carry
    /// non-finite coordinates when callers feed in `.nan`/`.infinity`. Passing
    /// those values to `Int(_:)` traps with a Swift runtime SIGTRAP. Returns
    /// `.zero` for any non-finite result so callers can hash the rect safely.
    ///
    /// Note: `safeBounds` filters non-finite values, but very large finite
    /// coordinates (`1e100`) still flow through. Callers must use `safeInt`
    /// for the conversion to `Int`.
    var safeBounds: CGRect {
        guard !isEmpty else { return .zero }
        let rect = cgPath.boundingBoxOfPath
        guard !rect.isNull,
              rect.origin.x.isFinite,
              rect.origin.y.isFinite,
              rect.size.width.isFinite,
              rect.size.height.isFinite
        else { return .zero }
        return rect
    }
}

// MARK: - Content Fingerprint

extension AccessibilityElement {
    /// Identity hash based on content only — no traversal index, no window-space frame.
    ///
    /// Two elements with the same label, identifier, value, traits, and content-space origin
    /// are the same element regardless of scroll position or traversal order.
    ///
    /// - Parameter contentSpaceOrigin: Position in the scroll view's content coordinate space.
    ///   Stable across scroll positions — the same row always has the same content-space origin
    ///   even when the viewport moves. When nil (element is not inside a scroll view), the
    ///   window-space frame origin is used as fallback.
    func fingerprint(contentSpaceOrigin: CGPoint?) -> Int {
        var hasher = Hasher()
        hasher.combine(label)
        hasher.combine(identifier)
        hasher.combine(value)
        hasher.combine(traits)
        if let origin = contentSpaceOrigin {
            // Content-space: stable across scroll positions
            hasher.combine(safeInt(origin.x))
            hasher.combine(safeInt(origin.y))
        } else {
            // Not in a scroll view — window-space frame is fine
            switch shape {
            case let .frame(rect):
                hasher.combine(safeInt(rect.origin.x))
                hasher.combine(safeInt(rect.origin.y))
            case let .path(path):
                let bounds = AccessibilityShape.path(path).frame
                hasher.combine(safeInt(bounds.origin.x))
                hasher.combine(safeInt(bounds.origin.y))
            }
        }
        // Size is scroll-invariant — always include it
        switch shape {
        case let .frame(rect):
            hasher.combine(safeInt(rect.size.width))
            hasher.combine(safeInt(rect.size.height))
        case let .path(path):
            let bounds = AccessibilityShape.path(path).frame
            hasher.combine(safeInt(bounds.size.width))
            hasher.combine(safeInt(bounds.size.height))
        }
        return hasher.finalize()
    }

    /// Convenience: fingerprint using the window-space frame (for non-scrollable contexts).
    var contentFingerprint: Int {
        fingerprint(contentSpaceOrigin: nil)
    }
}

extension AccessibilityHierarchy {
    /// Content-only fingerprint for a hierarchy node. Ignores traversal indices entirely.
    ///
    /// For elements: hashes the element content (label, identifier, traits, frame).
    /// For containers: hashes the container metadata + ordered child fingerprints (Merkle-style).
    ///
    /// This is the identity used for sliding alignment — two nodes with the same
    /// content fingerprint represent the same UI element regardless of position.
    var contentFingerprint: Int {
        folded(
            onElement: { element, _ in
                var hasher = Hasher()
                hasher.combine(0)
                hasher.combine(element.contentFingerprint)
                return hasher.finalize()
            },
            onContainer: { container, childFingerprints in
                var hasher = Hasher()
                hasher.combine(1)
                hasher.combine(container)
                for childFingerprint in childFingerprints {
                    hasher.combine(childFingerprint)
                }
                return hasher.finalize()
            }
        )
    }
}

// MARK: - Overlap Detection

/// Result of sliding two fingerprint sequences to find their overlap region.
struct OverlapResult: Equatable {
    /// Index into the accumulated sequence where the overlap begins.
    let accumulatedStart: Int

    /// Index into the page sequence where the overlap begins.
    let pageStart: Int

    /// Number of consecutive matching fingerprints in the overlap.
    let length: Int

    /// True when no overlap was found — the page is entirely new content.
    var isEmpty: Bool { length == 0 }
}

/// Slide two fingerprint sequences over each other to find the longest contiguous overlap.
///
/// This is the "rotating polarized lenses" step. We slide the page sequence across every
/// possible alignment with the accumulated sequence, scoring each offset by the number of
/// consecutive matching fingerprints. The highest-scoring offset is where the page locks in.
///
/// O(n·m) where n = accumulated length, m = page length. For typical screen-sized pages
/// (20–50 elements) against accumulated histories (100–500 elements), this is sub-millisecond.
func findOverlap(
    accumulated: [Int],
    page: [Int]
) -> OverlapResult {
    guard !accumulated.isEmpty, !page.isEmpty else {
        return OverlapResult(accumulatedStart: 0, pageStart: 0, length: 0)
    }

    var bestAccumulatedStart = 0
    var bestPageStart = 0
    var bestLength = 0

    // Try every possible offset where the page could align with the accumulated sequence.
    // Offset = (start of page in accumulated space) - (start of accumulated).
    // Negative offsets mean the page starts before the accumulated sequence.
    let minOffset = -(page.count - 1)
    let maxOffset = accumulated.count - 1

    for offset in minOffset...maxOffset {
        // Compute the overlapping range in both sequences
        let accStart = max(0, offset)
        let pageStart = max(0, -offset)
        let overlapLength = min(accumulated.count - accStart, page.count - pageStart)

        // Count the longest run of consecutive matches starting from the beginning
        // of the overlap region. We want the longest *contiguous* run, not just
        // the total count of matches.
        var runStart = -1
        var runLength = 0
        var currentRunStart = -1
        var currentRunLength = 0

        for index in 0..<overlapLength {
            if accumulated[accStart + index] == page[pageStart + index] {
                if currentRunLength == 0 {
                    currentRunStart = index
                }
                currentRunLength += 1
                if currentRunLength > runLength {
                    runStart = currentRunStart
                    runLength = currentRunLength
                }
            } else {
                currentRunLength = 0
            }
        }

        if runLength > bestLength {
            bestLength = runLength
            bestAccumulatedStart = accStart + (runStart >= 0 ? runStart : 0)
            bestPageStart = pageStart + (runStart >= 0 ? runStart : 0)
        }
    }

    return OverlapResult(
        accumulatedStart: bestAccumulatedStart,
        pageStart: bestPageStart,
        length: bestLength
    )
}

// MARK: - Page Reconciliation

/// Content-space axis used when reconciling scroll pages with stable origins.
enum ContentOrderingAxis: Sendable {
    case horizontal
    case vertical
}

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

    let accumulatedFingerprints = fingerprints(for: accumulated, origins: accumulatedOrigins)
    let pageFingerprints = fingerprints(for: page, origins: pageOrigins)
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

private func fingerprints(
    for elements: [AccessibilityElement],
    origins: [CGPoint?]
) -> [Int] {
    zip(elements, origins).map { element, origin in
        element.fingerprint(contentSpaceOrigin: origin)
    }
}

private extension OverlapResult {
    var accumulatedEnd: Int { accumulatedStart + length }
    var pageEnd: Int { pageStart + length }
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

private struct ContentOriginEntry {
    let element: AccessibilityElement
    let origin: CGPoint
    let order: Int
}

private func reconcileByContentOrigin(
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

// MARK: - Hierarchy Reconciliation

extension Array where Element == AccessibilityHierarchy {
    /// Flatten to elements, reconcile, and report what happened.
    /// This is the convenience entry point for merging a page of hierarchy nodes
    /// into an accumulated hierarchy.
    func reconcilePage(
        from page: [AccessibilityHierarchy]
    ) -> PageReconciliation {
        let accElements = self.sortedElements
        let pageElements = page.sortedElements
        return buttonHeistReconcilePage(accumulated: accElements, page: pageElements)
    }
}

// Module-level function to avoid ambiguity with the extension method
private func buttonHeistReconcilePage(
    accumulated: [AccessibilityElement],
    page: [AccessibilityElement]
) -> PageReconciliation {
    reconcilePage(accumulated: accumulated, page: page)
}
#endif // canImport(UIKit) && canImport(AccessibilitySnapshotParser)
