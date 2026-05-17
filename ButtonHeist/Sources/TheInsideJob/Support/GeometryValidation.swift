#if canImport(UIKit)
#if DEBUG
import UIKit
import TheScore

@MainActor enum GeometryValidation { // swiftlint:disable:this agent_main_actor_value_type

    static func validateScreenPoint(_ point: CGPoint, field: String = "point") -> String? {
        guard point.x.isFinite, point.y.isFinite else {
            return "\(field) must contain finite coordinates"
        }
        guard ScreenMetrics.current.bounds.contains(point) else {
            return "\(field) must be inside screen bounds \(format(ScreenMetrics.current.bounds)); observed \(format(point))"
        }
        return nil
    }

    static func validateScreenPoints(_ points: [CGPoint], field: String = "points") -> String? {
        for (index, point) in points.enumerated() {
            if let error = validateScreenPoint(point, field: "\(field)[\(index)]") {
                return error
            }
        }
        return nil
    }

    static func validateUnitPoint(_ point: UnitPoint, field: String) -> String? {
        guard point.x.isFinite, point.y.isFinite else {
            return "\(field) must contain finite coordinates"
        }
        guard (0...1).contains(point.x), (0...1).contains(point.y) else {
            return "\(field) must be inside the unit rectangle 0...1"
        }
        return nil
    }

    static func validateRect(_ rect: CGRect, field: String = "frame") -> String? {
        let values = [rect.origin.x, rect.origin.y, rect.size.width, rect.size.height]
        guard values.allSatisfy(\.isFinite) else {
            return "\(field) must contain finite geometry"
        }
        guard rect.size.width > 0, rect.size.height > 0 else {
            return "\(field) must have positive width and height"
        }
        guard ScreenMetrics.current.bounds.intersects(rect) else {
            return "\(field) must intersect screen bounds \(format(ScreenMetrics.current.bounds)); observed \(format(rect))"
        }
        return nil
    }

    private static func format(_ point: CGPoint) -> String {
        "(\(format(point.x)), \(format(point.y)))"
    }

    private static func format(_ rect: CGRect) -> String {
        "(x: \(format(rect.origin.x)), y: \(format(rect.origin.y)), w: \(format(rect.width)), h: \(format(rect.height)))"
    }

    private static func format(_ value: CGFloat) -> String {
        if value.rounded(.towardZero) == value {
            return String(format: "%.0f", Double(value))
        }
        return String(format: "%.2f", Double(value))
    }
}
#endif // DEBUG
#endif // canImport(UIKit)
