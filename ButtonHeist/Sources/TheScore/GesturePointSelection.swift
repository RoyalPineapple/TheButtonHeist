import CoreGraphics

public struct ScreenPoint: Sendable, Equatable, CustomStringConvertible {
    public let x: Double
    public let y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    public var cgPoint: CGPoint {
        CGPoint(x: x, y: y)
    }

    public var description: String {
        "point(\(ScoreDescription.decimal(x)),\(ScoreDescription.decimal(y)))"
    }
}

public enum GestureProjectionError: Error, Sendable, Equatable, CustomStringConvertible {
    case partialCoordinate(field: String, xPresent: Bool, yPresent: Bool)
    case mixedCoordinateAndElement(field: String)
    case mixedCoordinateAndDirection(field: String)
    case missingGesturePoint(field: String)
    case missingSwipeIntent
    case partialUnitPoints
    case unitPointsRequireElementTarget

    public var description: String {
        switch self {
        case .partialCoordinate(let field, let xPresent, let yPresent):
            return "\(field) requires both x and y coordinates (xPresent=\(xPresent), yPresent=\(yPresent))"
        case .mixedCoordinateAndElement(let field):
            return "\(field) accepts either a semantic target or coordinates, not both"
        case .mixedCoordinateAndDirection(let field):
            return "\(field) accepts either coordinates or direction, not both"
        case .missingGesturePoint(let field):
            return "\(field) requires a semantic target or coordinates"
        case .missingSwipeIntent:
            return "swipe requires a start target or point and an end point or direction"
        case .partialUnitPoints:
            return "unit-point swipe requires both start and end unit points"
        case .unitPointsRequireElementTarget:
            return "unit-point swipe requires a semantic target"
        }
    }
}

public enum GesturePointSelection: Sendable, Equatable, CustomStringConvertible {
    case element(ElementTarget)
    case coordinate(ScreenPoint)
    case unspecified

    public var elementTarget: ElementTarget? {
        guard case .element(let target) = self else { return nil }
        return target
    }

    public var screenPoint: ScreenPoint? {
        guard case .coordinate(let point) = self else { return nil }
        return point
    }

    public var pointX: Double? {
        screenPoint?.x
    }

    public var pointY: Double? {
        screenPoint?.y
    }

    public var isSpecified: Bool {
        if case .unspecified = self {
            return false
        }
        return true
    }

    public var description: String {
        switch self {
        case .element(let target):
            return target.description
        case .coordinate(let point):
            return point.description
        case .unspecified:
            return "unspecified"
        }
    }
}

private enum GesturePointCodingKeys: String, CodingKey {
    case pointX
    case pointY
}

private enum GestureCenterCodingKeys: String, CodingKey {
    case centerX
    case centerY
}

func makeGesturePointSelection(
    elementTarget: ElementTarget?,
    x: Double?,
    y: Double?,
    field: String
) throws -> GesturePointSelection {
    if elementTarget != nil, x != nil || y != nil {
        throw GestureProjectionError.mixedCoordinateAndElement(field: field)
    }
    if let elementTarget {
        return .element(elementTarget)
    }
    if let x, let y {
        return .coordinate(ScreenPoint(x: x, y: y))
    }
    if x != nil || y != nil {
        throw GestureProjectionError.partialCoordinate(field: field, xPresent: x != nil, yPresent: y != nil)
    }
    return .unspecified
}

func decodeGesturePointSelection(from decoder: Decoder) throws -> GesturePointSelection {
    let elementTarget = try ElementTarget.decodeInlineIfPresent(from: decoder)
    let container = try decoder.container(keyedBy: GesturePointCodingKeys.self)
    let pointX = try container.decodeIfPresent(Double.self, forKey: .pointX)
    let pointY = try container.decodeIfPresent(Double.self, forKey: .pointY)
    if elementTarget != nil, pointX != nil || pointY != nil {
        throw GestureProjectionError.mixedCoordinateAndElement(field: "point")
    }
    return try makeGesturePointSelection(elementTarget: elementTarget, x: pointX, y: pointY, field: "point")
}

func decodeRequiredGesturePointSelection(from decoder: Decoder, field: String = "point") throws -> GesturePointSelection {
    let selection = try decodeGesturePointSelection(from: decoder)
    guard selection.isSpecified else {
        throw GestureProjectionError.missingGesturePoint(field: field)
    }
    return selection
}

func encodeGesturePointSelection(_ selection: GesturePointSelection, to encoder: Encoder) throws {
    switch selection {
    case .element(let target):
        try target.encode(to: encoder)
    case .coordinate(let point):
        var container = encoder.container(keyedBy: GesturePointCodingKeys.self)
        try container.encode(point.x, forKey: .pointX)
        try container.encode(point.y, forKey: .pointY)
    case .unspecified:
        break
    }
}

func decodeGestureCenterSelection(from decoder: Decoder) throws -> GesturePointSelection {
    let elementTarget = try ElementTarget.decodeInlineIfPresent(from: decoder)
    let container = try decoder.container(keyedBy: GestureCenterCodingKeys.self)
    let centerX = try container.decodeIfPresent(Double.self, forKey: .centerX)
    let centerY = try container.decodeIfPresent(Double.self, forKey: .centerY)
    if elementTarget != nil, centerX != nil || centerY != nil {
        throw GestureProjectionError.mixedCoordinateAndElement(field: "center")
    }
    return try makeGesturePointSelection(elementTarget: elementTarget, x: centerX, y: centerY, field: "center")
}

func decodeRequiredGestureCenterSelection(from decoder: Decoder, field: String = "center") throws -> GesturePointSelection {
    let selection = try decodeGestureCenterSelection(from: decoder)
    guard selection.isSpecified else {
        throw GestureProjectionError.missingGesturePoint(field: field)
    }
    return selection
}

func encodeGestureCenterSelection(_ selection: GesturePointSelection, to encoder: Encoder) throws {
    switch selection {
    case .element(let target):
        try target.encode(to: encoder)
    case .coordinate(let point):
        var container = encoder.container(keyedBy: GestureCenterCodingKeys.self)
        try container.encode(point.x, forKey: .centerX)
        try container.encode(point.y, forKey: .centerY)
    case .unspecified:
        break
    }
}
