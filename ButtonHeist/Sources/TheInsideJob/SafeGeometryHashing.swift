#if canImport(UIKit) && canImport(AccessibilitySnapshotParser)
import AccessibilitySnapshotParser
import CoreGraphics
import ThePlans
import TheScore
import UIKit

enum CoarseFrameComparison {
    /// The smallest distance that counts as having moved: one touch target,
    /// which is the smallest thing a user could have been aiming at.
    @MainActor static var currentGeometryTolerance: CGFloat {
        geometryTolerance(for: UIDevice.current.userInterfaceIdiom)
    }

    static func geometryTolerance(for idiom: UIUserInterfaceIdiom) -> CGFloat {
        idiom == .pad ? 13 : 8
    }

    /// Whether two frames describe the same place, within the given geometryTolerance.
    ///
    /// Unreadable geometry is never in the same place as anything, including
    /// itself: we cannot claim a frame held still if we could not read where it
    /// was.
    ///
    /// The geometryTolerance is a parameter and not read from the device here, so that
    /// this stays callable off the main actor — the reducer that asks whether a
    /// tree moved is deliberately nonisolated.
    static func isInSamePlace(
        _ lhs: CGRect,
        _ rhs: CGRect,
        geometryTolerance: CGFloat
    ) -> Bool {
        guard let lhs = ScreenFrameEvidence(lhs).rect?.cgRect,
              let rhs = ScreenFrameEvidence(rhs).rect?.cgRect
        else { return false }
        return abs(lhs.minX - rhs.minX) < geometryTolerance
            && abs(lhs.minY - rhs.minY) < geometryTolerance
            && abs(lhs.width - rhs.width) < geometryTolerance
            && abs(lhs.height - rhs.height) < geometryTolerance
    }

    static func isInSamePlace(
        _ lhs: ScreenRect,
        _ rhs: ScreenRect,
        geometryTolerance: CGFloat
    ) -> Bool {
        isInSamePlace(lhs.cgRect, rhs.cgRect, geometryTolerance: geometryTolerance)
    }

    static func isInSamePlace(
        _ lhs: ViewRect,
        _ rhs: ViewRect,
        geometryTolerance: CGFloat
    ) -> Bool {
        isInSamePlace(lhs.cgRect, rhs.cgRect, geometryTolerance: geometryTolerance)
    }

    static func isInSamePlace(
        _ lhs: ScreenPoint,
        _ rhs: ScreenPoint,
        geometryTolerance: CGFloat
    ) -> Bool {
        isInSamePlace(lhs.cgPoint, rhs.cgPoint, geometryTolerance: geometryTolerance)
    }

    static func isInSamePlace(
        _ lhs: ViewPoint,
        _ rhs: ViewPoint,
        geometryTolerance: CGFloat
    ) -> Bool {
        isInSamePlace(lhs.cgPoint, rhs.cgPoint, geometryTolerance: geometryTolerance)
    }

    private static func isInSamePlace(
        _ lhs: CGPoint,
        _ rhs: CGPoint,
        geometryTolerance: CGFloat
    ) -> Bool {
        guard lhs.x.isFinite, lhs.y.isFinite, rhs.x.isFinite, rhs.y.isFinite else {
            return false
        }
        return abs(lhs.x - rhs.x) < geometryTolerance
            && abs(lhs.y - rhs.y) < geometryTolerance
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
    /// A geometryTolerance rather than a grid, deliberately. Snapping each frame to a
    /// bucket and comparing the buckets looks equivalent and is not: a frame
    /// sitting on a bucket edge — `y = 100` with an 8pt bucket — flips buckets
    /// under a third of a point of noise, so the elements most likely to be
    /// called moved are the ones that never moved at all. Comparing the
    /// distance between two frames has no edges to sit on.
    ///
    /// Exact frames stay exact everywhere else: they are what gets stored,
    /// reported, and turned into a tap point. Only the comparison is coarse.
    func isInSamePlace(as other: CGRect, geometryTolerance: CGFloat) -> Bool {
        CoarseFrameComparison.isInSamePlace(self, other, geometryTolerance: geometryTolerance)
    }
}

#endif // canImport(UIKit) && canImport(AccessibilitySnapshotParser)
