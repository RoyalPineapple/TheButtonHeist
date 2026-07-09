import Foundation

/// Direction for swipe gestures
public enum SwipeDirection: String, Codable, Sendable, CaseIterable {
    case up, down, left, right

    /// Default unit-point start for this cardinal direction
    public var defaultStart: UnitPoint {
        switch self {
        case .left:  UnitPoint(x: 0.8, y: 0.5)
        case .right: UnitPoint(x: 0.2, y: 0.5)
        case .up:    UnitPoint(x: 0.5, y: 0.8)
        case .down:  UnitPoint(x: 0.5, y: 0.2)
        }
    }

    /// Default unit-point end for this cardinal direction
    public var defaultEnd: UnitPoint {
        switch self {
        case .left:  UnitPoint(x: 0.2, y: 0.5)
        case .right: UnitPoint(x: 0.8, y: 0.5)
        case .up:    UnitPoint(x: 0.5, y: 0.2)
        case .down:  UnitPoint(x: 0.5, y: 0.8)
        }
    }
}
