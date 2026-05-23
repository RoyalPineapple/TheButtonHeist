#if canImport(UIKit)
#if DEBUG
import UIKit

import TheScore

import AccessibilitySnapshotParser

// MARK: - Array Helpers

extension Array where Element == HeistElement {
    /// Label of the topmost header-traited element (screen name hint).
    var screenName: String? {
        enumerated()
            .compactMap { index, element -> (index: Int, element: HeistElement)? in
                guard element.traits.contains(.header), element.label != nil else { return nil }
                return (index, element)
            }
            .min { left, right in
                if left.element.frameY != right.element.frameY { return left.element.frameY < right.element.frameY }
                if left.element.frameX != right.element.frameX { return left.element.frameX < right.element.frameX }
                return left.index < right.index
            }?
            .element
            .label
    }

    /// Slugified screen name for machine use (e.g. "controls_demo").
    var screenId: String? {
        screenName.flatMap { slugify($0) }
    }
}

extension Array where Element == Screen.ScreenElement {
    /// Label of the topmost header-traited element (screen name hint).
    var screenName: String? {
        enumerated()
            .compactMap { index, entry -> (index: Int, entry: Screen.ScreenElement)? in
                guard entry.element.traits.contains(.header), entry.element.label != nil else { return nil }
                return (index, entry)
            }
            .min { left, right in
                let leftFrame = left.entry.element.shape.frame
                let rightFrame = right.entry.element.shape.frame
                if leftFrame.minY != rightFrame.minY { return leftFrame.minY < rightFrame.minY }
                if leftFrame.minX != rightFrame.minX { return leftFrame.minX < rightFrame.minX }
                return left.index < right.index
            }?
            .entry
            .element
            .label
    }

    /// Slugified screen name for machine use (e.g. "controls_demo").
    var screenId: String? {
        screenName.flatMap { slugify($0) }
    }
}

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
