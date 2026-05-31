#if canImport(UIKit) && canImport(AccessibilitySnapshotParser)
import Foundation

// MARK: - Overlap Detection

/// Result of sliding two fingerprint sequences to find their overlap region.
struct OverlapResult: Equatable {
    /// Index into the accumulated sequence where the overlap begins.
    let accumulatedStart: Int

    /// Index into the page sequence where the overlap begins.
    let pageStart: Int

    /// Number of consecutive matching fingerprints in the overlap.
    let length: Int

    /// True when no overlap was found and the page is entirely new content.
    var isEmpty: Bool { length == 0 }

    var accumulatedEnd: Int { accumulatedStart + length }

    var pageEnd: Int { pageStart + length }
}

/// Slide two fingerprint sequences over each other to find the longest
/// contiguous overlap.
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

    let minOffset = -(page.count - 1)
    let maxOffset = accumulated.count - 1

    for offset in minOffset...maxOffset {
        let accStart = max(0, offset)
        let pageStart = max(0, -offset)
        let overlapLength = min(accumulated.count - accStart, page.count - pageStart)

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
#endif // canImport(UIKit) && canImport(AccessibilitySnapshotParser)
