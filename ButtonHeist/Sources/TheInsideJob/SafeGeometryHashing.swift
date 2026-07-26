#if canImport(UIKit) && canImport(AccessibilitySnapshotParser)
import AccessibilitySnapshotParser
import CoreGraphics
import TheScore
import UIKit

// MARK: - Frame Placement

enum FramePlacement: Hashable {
    case at(minX: Int, minY: Int, width: Int, height: Int)
    case masked
    case unavailable

    var hashFragment: String {
        switch self {
        case .at(let minX, let minY, let width, let height):
            "\(minX)_\(minY)_\(width)_\(height)"
        case .masked:
            "masked"
        case .unavailable:
            "unavailable"
        }
    }
}

enum CoarseFrameComparison {
    /// The smallest distance that counts as having moved: one touch target,
    /// which is the smallest thing a user could have been aiming at.
    @MainActor static var currentTolerance: CGFloat {
        tolerance(for: UIDevice.current.userInterfaceIdiom)
    }

    static func tolerance(for idiom: UIUserInterfaceIdiom) -> CGFloat {
        idiom == .pad ? 13 : 8
    }

    @MainActor static func placement(of frame: CGRect, bucket: CGFloat = currentTolerance) -> FramePlacement {
        guard let frame = ScreenFrameEvidence(frame).rect?.cgRect else { return .unavailable }
        return .at(
            minX: component(frame.origin.x, bucket: bucket),
            minY: component(frame.origin.y, bucket: bucket),
            width: component(frame.size.width, bucket: bucket),
            height: component(frame.size.height, bucket: bucket)
        )
    }

    @MainActor static func hashFragment(for frame: CGRect, bucket: CGFloat = currentTolerance) -> String {
        placement(of: frame, bucket: bucket).hashFragment
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

    private static func component(_ value: CGFloat, bucket: CGFloat) -> Int {
        let scaled = bucket > 0 && bucket.isFinite ? (value / bucket).rounded() : value.rounded()
        if scaled >= CGFloat(Int.max) { return Int.max }
        if scaled <= CGFloat(Int.min) { return Int.min }
        return Int(scaled)
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
