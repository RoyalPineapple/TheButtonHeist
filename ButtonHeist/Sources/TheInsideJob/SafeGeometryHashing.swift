#if canImport(UIKit) && canImport(AccessibilitySnapshotParser)
import AccessibilitySnapshotParser
import CoreGraphics
import TheScore
import UIKit

enum CoarseFrameComparison {
    /// The smallest distance that counts as having moved: one touch target,
    /// which is the smallest thing a user could have been aiming at.
    @MainActor static var currentTolerance: CGFloat {
        tolerance(for: UIDevice.current.userInterfaceIdiom)
    }

    static func tolerance(for idiom: UIUserInterfaceIdiom) -> CGFloat {
        idiom == .pad ? 13 : 8
    }

    /// Whether two frames describe the same place, within the given tolerance.
    ///
    /// Unreadable geometry is never in the same place as anything, including
    /// itself: we cannot claim a frame held still if we could not read where it
    /// was.
    ///
    /// The tolerance is a parameter and not read from the device here, so that
    /// this stays callable off the main actor — the reducer that asks whether a
    /// tree moved is deliberately nonisolated.
    static func isInSamePlace(
        _ lhs: CGRect,
        _ rhs: CGRect,
        tolerance: CGFloat
    ) -> Bool {
        guard let lhs = ScreenFrameEvidence(lhs).rect?.cgRect,
              let rhs = ScreenFrameEvidence(rhs).rect?.cgRect
        else { return false }
        return abs(lhs.minX - rhs.minX) < tolerance
            && abs(lhs.minY - rhs.minY) < tolerance
            && abs(lhs.width - rhs.width) < tolerance
            && abs(lhs.height - rhs.height) < tolerance
    }
}

extension CGRect {
    /// Whether this frame is in the same place as another.
    ///
    /// Raw `CGRect` equality is never that question: a layout pass re-runs the
    /// same arithmetic and lands a fraction of a point away, so exact
    /// comparison reports motion no user could see and no accessibility client
    /// cares about.
    ///
    /// A tolerance rather than a grid, deliberately. Snapping each frame to a
    /// bucket and comparing the buckets looks equivalent and is not: a frame
    /// sitting on a bucket edge — `y = 100` with an 8pt bucket — flips buckets
    /// under a third of a point of noise, so the elements most likely to be
    /// called moved are the ones that never moved at all. Comparing the
    /// distance between two frames has no edges to sit on.
    ///
    /// Exact frames stay exact everywhere else: they are what gets stored,
    /// reported, and turned into a tap point. Only the comparison is coarse.
    func isInSamePlace(as other: CGRect, tolerance: CGFloat) -> Bool {
        CoarseFrameComparison.isInSamePlace(self, other, tolerance: tolerance)
    }
}

#endif // canImport(UIKit) && canImport(AccessibilitySnapshotParser)
