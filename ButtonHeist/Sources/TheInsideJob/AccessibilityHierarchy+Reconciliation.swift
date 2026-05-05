#if canImport(UIKit) && canImport(AccessibilitySnapshotParser)
import AccessibilitySnapshotParser
import CoreGraphics
import UIKit

// MARK: - Safe Path Bounds

extension UIBezierPath {
    /// Bounds that won't trap on degenerate paths.
    ///
    /// `UIBezierPath.bounds` (and `cgPath.boundingBoxOfPath`) can return `.null`
    /// — whose origin is `.infinity` — when the path is empty, and may carry
    /// non-finite coordinates when callers feed in `.nan`/`.infinity`. Passing
    /// those values to `Int(_:)` traps with a Swift runtime SIGTRAP. Returns
    /// `.zero` for any non-finite result so callers can hash the rect safely.
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
    public func fingerprint(contentSpaceOrigin: CGPoint?) -> Int {
        var hasher = Hasher()
        hasher.combine(label)
        hasher.combine(identifier)
        hasher.combine(value)
        hasher.combine(traits)
        if let origin = contentSpaceOrigin {
            // Content-space: stable across scroll positions
            hasher.combine(Int(origin.x))
            hasher.combine(Int(origin.y))
        } else {
            // Not in a scroll view — window-space frame is fine
            switch shape {
            case let .frame(rect):
                hasher.combine(Int(rect.origin.x))
                hasher.combine(Int(rect.origin.y))
            case let .path(path):
                let bounds = path.safeBounds
                hasher.combine(Int(bounds.origin.x))
                hasher.combine(Int(bounds.origin.y))
            }
        }
        // Size is scroll-invariant — always include it
        switch shape {
        case let .frame(rect):
            hasher.combine(Int(rect.size.width))
            hasher.combine(Int(rect.size.height))
        case let .path(path):
            let bounds = path.safeBounds
            hasher.combine(Int(bounds.size.width))
            hasher.combine(Int(bounds.size.height))
        }
        return hasher.finalize()
    }

    /// Convenience: fingerprint using the window-space frame (for non-scrollable contexts).
    public var contentFingerprint: Int {
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
    public var contentFingerprint: Int {
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
public struct OverlapResult: Equatable {
    /// Index into the accumulated sequence where the overlap begins.
    public let accumulatedStart: Int

    /// Index into the page sequence where the overlap begins.
    public let pageStart: Int

    /// Number of consecutive matching fingerprints in the overlap.
    public let length: Int

    /// True when no overlap was found — the page is entirely new content.
    public var isEmpty: Bool { length == 0 }
}

/// Slide two fingerprint sequences over each other to find the longest contiguous overlap.
///
/// This is the "rotating polarized lenses" step. We slide the page sequence across every
/// possible alignment with the accumulated sequence, scoring each offset by the number of
/// consecutive matching fingerprints. The highest-scoring offset is where the page locks in.
///
/// O(n·m) where n = accumulated length, m = page length. For typical screen-sized pages
/// (20–50 elements) against accumulated histories (100–500 elements), this is sub-millisecond.
public func findOverlap(
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

        for i in 0..<overlapLength {
            if accumulated[accStart + i] == page[pageStart + i] {
                if currentRunLength == 0 {
                    currentRunStart = i
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

// MARK: - Page Stitching

/// Content-space axis used when stitching scroll pages with stable origins.
public enum StitchOrderingAxis: Sendable {
    case horizontal
    case vertical
}

/// Result of merging a new page into the accumulated element sequence.
public struct StitchResult: Equatable {
    /// The merged element sequence after incorporating the page.
    public let elements: [AccessibilityElement]

    /// The overlap region that anchored the merge.
    public let overlap: OverlapResult

    /// Elements from the page that were inserted (not present in accumulated).
    public let inserted: [AccessibilityElement]

    /// How many elements were in the accumulated sequence before the merge.
    public let previousCount: Int
}

/// Stitch a new page of elements into the accumulated sequence.
///
/// The algorithm:
/// 1. Fingerprint both sequences using content-space origins (scroll-invariant).
/// 2. Slide page fingerprints over accumulated fingerprints to find the overlap.
/// 3. Use the overlap as an anchor to position the page within the full sequence.
/// 4. Elements before the overlap in the page → prepend (scrolled backward).
/// 5. Elements in the overlap → update from page (fresher data).
/// 6. Elements after the overlap in the page → append (scrolled forward).
/// 7. Accumulated elements outside the page's range are preserved as-is.
/// 8. When a scroll axis and complete content-space origins are provided, the
///    merged result is ordered by content-space position so retained off-screen
///    elements cannot drift behind newer page content.
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
public func stitchPage(
    accumulated: [AccessibilityElement],
    accumulatedOrigins: [CGPoint?],
    page: [AccessibilityElement],
    pageOrigins: [CGPoint?],
    orderingAxis: StitchOrderingAxis? = nil
) -> StitchResult {
    guard !page.isEmpty else {
        return StitchResult(
            elements: accumulated,
            overlap: OverlapResult(accumulatedStart: 0, pageStart: 0, length: 0),
            inserted: [],
            previousCount: accumulated.count
        )
    }

    guard !accumulated.isEmpty else {
        return StitchResult(
            elements: page,
            overlap: OverlapResult(accumulatedStart: 0, pageStart: 0, length: 0),
            inserted: page,
            previousCount: 0
        )
    }

    let accFingerprints = zip(accumulated, accumulatedOrigins).map { element, origin in
        element.fingerprint(contentSpaceOrigin: origin)
    }
    let pageFingerprints = zip(page, pageOrigins).map { element, origin in
        element.fingerprint(contentSpaceOrigin: origin)
    }

    let overlap = findOverlap(accumulated: accFingerprints, page: pageFingerprints)

    if let ordered = stitchByContentOrigin(
        accumulated: accumulated,
        accumulatedOrigins: accumulatedOrigins,
        accumulatedFingerprints: accFingerprints,
        page: page,
        pageOrigins: pageOrigins,
        pageFingerprints: pageFingerprints,
        overlap: overlap,
        orderingAxis: orderingAxis
    ) {
        return ordered
    }

    guard overlap.length > 0 else {
        return StitchResult(
            elements: accumulated + page,
            overlap: overlap,
            inserted: page,
            previousCount: accumulated.count
        )
    }

    // Build the merged sequence:
    //
    //   [accumulated before overlap] + [page before overlap] + [overlap from page] + [page after overlap] + [accumulated after overlap]
    //
    // Visualized with a scroll view that scrolled forward:
    //
    //   accumulated: [A B C D E F G]
    //                        ^^^       ← overlap (D E F)
    //   page:            [X D E F H I]
    //                     ^       ^^^  ← new content
    //   result:      [A B C X D E F H I G]
    //                       ^       ^^   ← inserted

    var result: [AccessibilityElement] = []
    var inserted: [AccessibilityElement] = []

    // 1. Accumulated elements before the overlap region
    let accBeforeEnd = overlap.accumulatedStart
    result.append(contentsOf: accumulated[0..<accBeforeEnd])

    // 2. Page elements before its overlap region (scrolled backward / new at top)
    let pageBeforeEnd = overlap.pageStart
    if pageBeforeEnd > 0 {
        let newElements = Array(page[0..<pageBeforeEnd])
        result.append(contentsOf: newElements)
        inserted.append(contentsOf: newElements)
    }

    // 3. Overlap region — take from page (fresher data, may have updated values)
    let overlapEnd = overlap.pageStart + overlap.length
    result.append(contentsOf: page[overlap.pageStart..<overlapEnd])

    // 4. Page elements after its overlap region (scrolled forward / new at bottom)
    if overlapEnd < page.count {
        let newElements = Array(page[overlapEnd..<page.count])
        result.append(contentsOf: newElements)
        inserted.append(contentsOf: newElements)
    }

    // 5. Accumulated elements after the overlap region that aren't in the page
    let accAfterStart = overlap.accumulatedStart + overlap.length
    if accAfterStart < accumulated.count {
        result.append(contentsOf: accumulated[accAfterStart..<accumulated.count])
    }

    return StitchResult(
        elements: result,
        overlap: overlap,
        inserted: inserted,
        previousCount: accumulated.count
    )
}

private struct OriginStitchEntry {
    let element: AccessibilityElement
    let origin: CGPoint
    let order: Int
}

private func stitchByContentOrigin(
    accumulated: [AccessibilityElement],
    accumulatedOrigins: [CGPoint?],
    accumulatedFingerprints: [Int],
    page: [AccessibilityElement],
    pageOrigins: [CGPoint?],
    pageFingerprints: [Int],
    overlap: OverlapResult,
    orderingAxis: StitchOrderingAxis?
) -> StitchResult? {
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
    var entriesByFingerprint: [Int: OriginStitchEntry] = [:]
    for index in accumulated.indices {
        entriesByFingerprint[accumulatedFingerprints[index]] = OriginStitchEntry(
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
        entriesByFingerprint[fingerprint] = OriginStitchEntry(
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

    return StitchResult(
        elements: orderedEntries.map(\.element),
        overlap: overlap,
        inserted: inserted,
        previousCount: accumulated.count
    )
}

/// Convenience overload using window-space frames (for non-scrollable contexts or tests).
public func stitchPage(
    accumulated: [AccessibilityElement],
    page: [AccessibilityElement]
) -> StitchResult {
    stitchPage(
        accumulated: accumulated,
        accumulatedOrigins: accumulated.map { _ in nil },
        page: page,
        pageOrigins: page.map { _ in nil }
    )
}

// MARK: - Hierarchy Stitching

extension Array where Element == AccessibilityHierarchy {
    /// Flatten to elements, stitch, and report what happened.
    /// This is the convenience entry point for merging a page of hierarchy nodes
    /// into an accumulated hierarchy.
    public func stitchPage(
        from page: [AccessibilityHierarchy]
    ) -> StitchResult {
        let accElements = self.sortedElements
        let pageElements = page.sortedElements
        return buttonHeistStitchPage(accumulated: accElements, page: pageElements)
    }
}

// Module-level function to avoid ambiguity with the extension method
private func buttonHeistStitchPage(
    accumulated: [AccessibilityElement],
    page: [AccessibilityElement]
) -> StitchResult {
    stitchPage(accumulated: accumulated, page: page)
}
#endif // canImport(UIKit) && canImport(AccessibilitySnapshotParser)
