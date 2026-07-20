#if canImport(UIKit) && canImport(AccessibilitySnapshotParser)
import AccessibilitySnapshotParser
import CoreGraphics
import TheScore
import UIKit

// MARK: - Coarse Frame Comparison

enum CoarseFrameKey: Hashable {
    case available(minX: Int, minY: Int, width: Int, height: Int)
    case masked
    case unavailable

    var hashFragment: String {
        switch self {
        case .available(let minX, let minY, let width, let height):
            "\(minX)_\(minY)_\(width)_\(height)"
        case .masked:
            "masked"
        case .unavailable:
            "unavailable"
        }
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
        guard let frame = ScreenFrameEvidence(frame).rect?.cgRect else { return .unavailable }
        return .available(
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
        let scaled = bucket > 0 && bucket.isFinite ? (value / bucket).rounded() : value.rounded()
        if scaled >= CGFloat(Int.max) { return Int.max }
        if scaled <= CGFloat(Int.min) { return Int.min }
        return Int(scaled)
    }
}

#endif // canImport(UIKit) && canImport(AccessibilitySnapshotParser)
