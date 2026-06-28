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
            return "\(field) accepts element, element with unitPoint, or ScreenPoint, not mixed shapes"
        case .missingGesturePoint(let field):
            return "\(field) requires element, element with unitPoint, or ScreenPoint"
        case .mixedGestureIntent(let kind):
            return "\(kind) accepts exactly one gesture intent"
        case .missingSwipeIntent:
            return "swipe requires a start target or point and an end point or direction"
        case .invalidDuration(let observed, let expected):
            return "duration must be \(expected) (observed \(ScoreDescription.decimal(observed)))"
        }
    }
}

struct GesturePayloadCandidate<Key: CodingKey, Selection> {
    private let decodePayload: (KeyedDecodingContainer<Key>) throws -> Selection?

    init<Payload: Decodable>(
        _ key: Key,
        as _: Payload.Type,
        map: @escaping (Payload) -> Selection
    ) {
        self.decodePayload = { container in
            try container.decodeIfPresent(Payload.self, forKey: key).map(map)
        }
    }

    func decode(from container: KeyedDecodingContainer<Key>) throws -> Selection? {
        try decodePayload(container)
    }
}

extension KeyedDecodingContainer {
    func decodeExactlyOneGesturePayload<Selection>(
        kind: String,
        missing missingError: @autoclosure () -> Error,
        candidates: [GesturePayloadCandidate<Key, Selection>]
    ) throws -> Selection {
        let selections = try candidates.compactMap { candidate in
            try candidate.decode(from: self)
        }

        switch selections.count {
        case 0:
            throw missingError()
        case 1:
            return selections[0]
        default:
            throw GestureProjectionError.mixedGestureIntent(kind: kind)
        }
    }
}

public enum GesturePointSelection: Codable, Sendable, Equatable, CustomStringConvertible {
    case element(ElementTarget)
    case elementUnitPoint(ElementTarget, UnitPoint)
    case coordinate(ScreenPoint)

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case element
        case unitPoint
        case point
    }

    public init(element: ElementTarget?, unitPoint: UnitPoint?, point: ScreenPoint?) throws {
        switch (element, unitPoint, point) {
        case (.some(let element), nil, nil):
            self = .element(element)
        case (.some(let element), .some(let unitPoint), nil):
            self = .elementUnitPoint(element, unitPoint)
        case (nil, nil, .some(let point)):
            self = .coordinate(point)
        case (.some, _, .some), (nil, .some, .some):
            throw GestureProjectionError.mixedCoordinateAndElement(field: "point")
        case (nil, .some, nil), (nil, nil, nil):
            throw GestureProjectionError.missingGesturePoint(field: "point")
        }
    }

    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "gesture point selection")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            element: try container.decodeIfPresent(ElementTarget.self, forKey: .element),
            unitPoint: try container.decodeIfPresent(UnitPoint.self, forKey: .unitPoint),
            point: try container.decodeIfPresent(ScreenPoint.self, forKey: .point)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .element(let target):
            try container.encode(target, forKey: .element)
        case .elementUnitPoint(let target, let unitPoint):
            try container.encode(target, forKey: .element)
            try container.encode(unitPoint, forKey: .unitPoint)
        case .coordinate(let point):
            try container.encode(point, forKey: .point)
        }
    }

    public var description: String {
        switch self {
        case .element(let target):
            return target.description
        case .elementUnitPoint(let target, let unitPoint):
            return ScoreDescription.call("unitPoint", [
                target.description,
                "at=\(unitPoint)",
            ])
        case .coordinate(let point):
            return point.description
        }
    }
}
