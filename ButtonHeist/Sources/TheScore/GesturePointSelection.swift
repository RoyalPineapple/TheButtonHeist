import CoreGraphics

public struct ScreenPoint: Codable, Sendable, Equatable, CustomStringConvertible {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case x
        case y
    }

    public let x: Double
    public let y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "screen point")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            x: try container.decode(Double.self, forKey: .x),
            y: try container.decode(Double.self, forKey: .y)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(x, forKey: .x)
        try container.encode(y, forKey: .y)
    }

    public var cgPoint: CGPoint {
        CGPoint(x: x, y: y)
    }

    public var description: String {
        "point(\(ScoreDescription.decimal(x)),\(ScoreDescription.decimal(y)))"
    }
}

public enum GestureProjectionError: Error, Sendable, Equatable, CustomStringConvertible {
    case mixedCoordinateAndElement(field: String)
    case missingGesturePoint(field: String)
    case mixedGestureIntent(kind: String)
    case missingSwipeIntent
    case invalidDuration(observed: Double, expected: String)

    public var description: String {
        switch self {
        case .mixedCoordinateAndElement(let field):
            return "\(field) accepts either a semantic target or coordinates, not both"
        case .missingGesturePoint(let field):
            return "\(field) requires a semantic target or coordinates"
        case .mixedGestureIntent(let kind):
            return "\(kind) accepts exactly one gesture intent"
        case .missingSwipeIntent:
            return "swipe requires a start target or point and an end point or direction"
        case .invalidDuration(let observed, let expected):
            return "duration must be \(expected) (observed \(ScoreDescription.decimal(observed)))"
        }
    }
}

public enum GesturePointSelection: Codable, Sendable, Equatable, CustomStringConvertible {
    case element(ElementTarget)
    case coordinate(ScreenPoint)

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case element
        case point
    }

    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "gesture point selection")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let element = try container.decodeIfPresent(ElementTarget.self, forKey: .element)
        let point = try container.decodeIfPresent(ScreenPoint.self, forKey: .point)
        switch (element, point) {
        case (.some(let element), nil):
            self = .element(element)
        case (nil, .some(let point)):
            self = .coordinate(point)
        case (.some, .some):
            throw GestureProjectionError.mixedCoordinateAndElement(field: "point")
        case (nil, nil):
            throw GestureProjectionError.missingGesturePoint(field: "point")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .element(let target):
            try container.encode(target, forKey: .element)
        case .coordinate(let point):
            try container.encode(point, forKey: .point)
        }
    }

    public var description: String {
        switch self {
        case .element(let target):
            return target.description
        case .coordinate(let point):
            return point.description
        }
    }
}
