#if canImport(UIKit) && canImport(AccessibilitySnapshotParser)
import AccessibilitySnapshotParser
import CoreGraphics
import UIKit

// MARK: - Safe Numeric Conversions

/// Convert a `CGFloat` to `Int` without trapping on pathological inputs.
///
/// `Int(_:)` traps with a Swift runtime SIGTRAP when the input is non-finite
/// (NaN, +/-infinity) or finite-but-out-of-range (e.g. `1e100`,
/// `CGFloat.greatestFiniteMagnitude`). Accessibility geometry can contain
/// those values, and fingerprinting must not let one poisoned frame crash parse.
///
/// For any finite value where `Int(cgFloat)` already succeeds, this returns the
/// same value. Only inputs that would trap are clamped to `Int.min`, `Int.max`,
/// or `0`.
func safeInt(_ cgFloat: CGFloat) -> Int {
    guard cgFloat.isFinite else { return 0 }
    if cgFloat >= CGFloat(Int.max) { return Int.max }
    if cgFloat <= CGFloat(Int.min) { return Int.min }
    return Int(cgFloat)
}

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

@MainActor enum CoarseFrameComparison { // swiftlint:disable:this agent_main_actor_value_type
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

// MARK: - Content Fingerprint

extension AccessibilityElement {
    /// Identity hash based on content only: no traversal index.
    func fingerprint() -> Int {
        var hasher = Hasher()
        hasher.combine(label)
        hasher.combine(identifier)
        hasher.combine(value)
        hasher.combine(traits)
        switch shape {
        case let .frame(rect):
            hasher.combine(safeInt(rect.origin.x))
            hasher.combine(safeInt(rect.origin.y))
        case let .path(path):
            let bounds = safePathBounds(path)
            hasher.combine(safeInt(bounds.origin.x))
            hasher.combine(safeInt(bounds.origin.y))
        }
        switch shape {
        case let .frame(rect):
            hasher.combine(safeInt(rect.size.width))
            hasher.combine(safeInt(rect.size.height))
        case let .path(path):
            let bounds = safePathBounds(path)
            hasher.combine(safeInt(bounds.size.width))
            hasher.combine(safeInt(bounds.size.height))
        }
        return hasher.finalize()
    }

    /// Convenience fingerprint using window-space geometry.
    var contentFingerprint: Int {
        fingerprint()
    }
}

extension AccessibilityHierarchy {
    /// Content-only fingerprint for a hierarchy node. Ignores traversal indices.
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

func contentFingerprints(
    for elements: [AccessibilityElement]
) -> [Int] {
    elements.map { $0.fingerprint() }
}

private func safePathBounds(_ pathElements: [AccessibilityPathElement]) -> CGRect {
    let path = UIBezierPath()
    for element in pathElements {
        element.apply(to: path)
    }
    return path.safeBounds
}
#endif // canImport(UIKit) && canImport(AccessibilitySnapshotParser)
