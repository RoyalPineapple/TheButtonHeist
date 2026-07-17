#if canImport(UIKit)
#if DEBUG
import UIKit

@MainActor enum GeometryValidation {

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
