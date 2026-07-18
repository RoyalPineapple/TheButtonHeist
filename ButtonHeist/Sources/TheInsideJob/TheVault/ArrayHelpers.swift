#if canImport(UIKit)
#if DEBUG
import UIKit

import AccessibilitySnapshotParser

// MARK: - Array Helpers

// MARK: - Shape Helper

extension AccessibilityShape {
    var frame: CGRect {
        switch self {
        case let .frame(rect): return rect.cgRect
        case let .path(path): return path.safeBounds
        }
    }
}

private extension Array where Element == AccessibilityPathElement {
    var safeBounds: CGRect {
        let bezierPath = UIBezierPath()
        for element in self {
            element.apply(to: bezierPath)
        }
        guard !bezierPath.isEmpty else { return .zero }
        let bounds = bezierPath.cgPath.boundingBoxOfPath
        guard !bounds.isNull,
              bounds.origin.x.isFinite,
              bounds.origin.y.isFinite,
              bounds.size.width.isFinite,
              bounds.size.height.isFinite else {
            return .zero
        }
        return bounds
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
