#if canImport(UIKit) && canImport(AccessibilitySnapshotParser)
import AccessibilitySnapshotParser
import CoreGraphics
import TheScore
import UIKit

// MARK: - Coarse Frame Comparison

struct CoarseFrameKey: Hashable {
    let minX: Int
    let minY: Int
    let width: Int
    let height: Int

    static let zero = CoarseFrameKey(minX: 0, minY: 0, width: 0, height: 0)

    var hashFragment: String {
        "\(minX)_\(minY)_\(width)_\(height)"
    }
}

@MainActor enum CoarseFrameComparison {
    static var currentBucket: CGFloat {
        bucket(for: UIDevice.current.userInterfaceIdiom)
    }

    static func bucket(for idiom: UIUserInterfaceIdiom) -> CGFloat {
        idiom == .pad ? 13 : 8
    }

    static func key(for frame: CGRect, bucket: CGFloat = currentBucket) -> CoarseFrameKey {
        CoarseFrameKey(
            minX: component(frame.origin.x, bucket: bucket),
            minY: component(frame.origin.y, bucket: bucket),
            width: component(frame.size.width, bucket: bucket),
            height: component(frame.size.height, bucket: bucket)
        )
    }

    static func hashFragment(for frame: CGRect, bucket: CGFloat = currentBucket) -> String {
        key(for: frame, bucket: bucket).hashFragment
    }

    private static func component(_ value: CGFloat, bucket: CGFloat) -> Int {
        let sanitized = value.isFinite ? value : 0
        guard bucket > 0, bucket.isFinite else { return safeInt(sanitized.rounded()) }
        return safeInt((sanitized / bucket).rounded())
    }
}

// MARK: - Safe Path Bounds

extension UIBezierPath {
    /// Bounds that won't trap on degenerate paths.
    ///
    /// `UIBezierPath.bounds` and `cgPath.boundingBoxOfPath` can return `.null`
    /// for empty paths and may carry non-finite coordinates when callers feed
    /// in NaN or infinity. Returns `.zero` for any non-finite result so callers
    /// can hash the rect safely.
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

#endif // canImport(UIKit) && canImport(AccessibilitySnapshotParser)
