#if canImport(UIKit)
#if DEBUG
import UIKit
import AccessibilitySnapshotParser
import TheScore

// MARK: - Array Helpers

extension Array where Element == HeistElement {
    /// Label of the first header-traited element (screen name hint).
    var screenName: String? {
        first { $0.traits.contains(.header) }?.label
    }

    /// Slugified screen name for machine use (e.g. "controls_demo").
    var screenId: String? {
        screenName.flatMap { slugify($0) }
    }
}

extension Array where Element == TheStash.ScreenElement {
    /// Label of the first header-traited element (screen name hint).
    var screenName: String? {
        first { $0.element.traits.contains(.header) }?.element.label
    }

    /// Slugified screen name for machine use (e.g. "controls_demo").
    var screenId: String? {
        screenName.flatMap { slugify($0) }
    }
}

// MARK: - Shape Helper

extension AccessibilityElement.Shape {
    var frame: CGRect {
        switch self {
        case let .frame(rect): return rect
        case let .path(path): return path.bounds
        }
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
