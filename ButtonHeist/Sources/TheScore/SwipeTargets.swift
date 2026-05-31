public enum SwipeDestinationSelection: Sendable, Equatable, CustomStringConvertible {
    case coordinate(ScreenPoint)
    case direction(SwipeDirection)

    public var description: String {
        switch self {
        case .coordinate(let point):
            return point.description
        case .direction(let direction):
            return "\(direction)"
        }
    }
}

public enum SwipeGestureSelection: Sendable, Equatable, CustomStringConvertible {
    case unitElement(ElementTarget, start: UnitPoint, end: UnitPoint)
    case elementDirection(ElementTarget, SwipeDirection)
    case point(start: GesturePointSelection, destination: SwipeDestinationSelection)

    public var description: String {
        switch self {
        case .unitElement(let target, let start, let end):
            return ScoreDescription.call("unitSwipe", [
                target.description,
                "start=\(start)",
                "end=\(end)",
            ])
        case .elementDirection(let target, let direction):
            return ScoreDescription.call("elementDirectionSwipe", [
                target.description,
                "direction=\(direction)",
            ])
        case .point(let start, let destination):
            return ScoreDescription.call("pointSwipe", [
                "start=\(start)",
                "destination=\(destination)",
            ])
        }
    }
}

/// A point in unit coordinates (0-1) relative to an element's accessibility frame.
/// `(0, 0)` is top-left, `(1, 1)` is bottom-right, `(0.5, 0.5)` is center.
/// Values outside 0-1 extend beyond the element's frame.
public struct UnitPoint: Codable, Sendable, Equatable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case x
        case y
    }

    public static var fieldNames: Set<String> {
        Set(CodingKeys.allCases.map(\.stringValue))
    }

    public let x: Double
    public let y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "unit point")
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
}

extension UnitPoint: CustomStringConvertible {
    public var description: String {
        "unitPoint(\(ScoreDescription.decimal(x)),\(ScoreDescription.decimal(y)))"
    }
}

private enum SwipePointCodingKeys: String, CodingKey, CaseIterable {
    case startX
    case startY
    case endX
    case endY
    case direction
    case duration
    case start
    case end
}

private func swipeDestinationSelection(
    x: Double?,
    y: Double?,
    direction: SwipeDirection?
) throws -> SwipeDestinationSelection? {
    if direction != nil, x != nil || y != nil {
        throw GestureProjectionError.mixedCoordinateAndDirection(field: "endPoint")
    }
    if let x, let y {
        return .coordinate(ScreenPoint(x: x, y: y))
    }
    if x != nil || y != nil {
        throw GestureProjectionError.partialCoordinate(field: "endPoint", xPresent: x != nil, yPresent: y != nil)
    }
    if let direction {
        return .direction(direction)
    }
    return nil
}

public struct SwipeTarget: Codable, Sendable {
    public static let defaultDuration = GestureDuration.swipeDefault

    public let selection: SwipeGestureSelection
    /// Duration in seconds (default 0.15).
    public let duration: GestureDuration?

    public init(selection: SwipeGestureSelection, duration: GestureDuration? = nil) {
        self.selection = selection
        self.duration = duration
    }

    public var direction: SwipeDirection? {
        switch selection {
        case .elementDirection(_, let direction):
            return direction
        case .point(_, .direction(let direction)):
            return direction
        case .unitElement, .point:
            return nil
        }
    }

    public var start: UnitPoint? {
        guard case .unitElement(_, let start, _) = selection else { return nil }
        return start
    }

    public var end: UnitPoint? {
        guard case .unitElement(_, _, let end) = selection else { return nil }
        return end
    }

    public var resolvedDuration: GestureDuration { duration ?? Self.defaultDuration }

    public func gestureSelection() -> SwipeGestureSelection {
        selection
    }

    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(
            allowed: SwipePointCodingKeys.self,
            additional: Set(ElementTarget.inlineFieldNames),
            typeName: "swipe target"
        )
        let elementTarget = try ElementTarget.decodeInlineIfPresent(from: decoder)
        let pointContainer = try decoder.container(keyedBy: SwipePointCodingKeys.self)
        let startX = try pointContainer.decodeIfPresent(Double.self, forKey: .startX)
        let startY = try pointContainer.decodeIfPresent(Double.self, forKey: .startY)
        let endX = try pointContainer.decodeIfPresent(Double.self, forKey: .endX)
        let endY = try pointContainer.decodeIfPresent(Double.self, forKey: .endY)
        let direction = try pointContainer.decodeIfPresent(SwipeDirection.self, forKey: .direction)
        let start = try pointContainer.decodeIfPresent(UnitPoint.self, forKey: .start)
        let end = try pointContainer.decodeIfPresent(UnitPoint.self, forKey: .end)
        self.duration = try pointContainer.decodeIfPresent(GestureDuration.self, forKey: .duration)
        if start != nil || end != nil {
            guard let start, let end else {
                throw GestureProjectionError.partialUnitPoints
            }
            guard let elementTarget else {
                throw GestureProjectionError.unitPointsRequireElementTarget
            }
            guard direction == nil else {
                throw GestureProjectionError.mixedCoordinateAndDirection(field: "unitPoints")
            }
            self.selection = .unitElement(elementTarget, start: start, end: end)
            return
        }
        if let direction, let elementTarget, startX == nil, startY == nil, endX == nil, endY == nil {
            self.selection = .elementDirection(elementTarget, direction)
            return
        }
        let startSelection = try makeGesturePointSelection(
            elementTarget: elementTarget,
            x: startX,
            y: startY,
            field: "startPoint"
        )
        let destination = try swipeDestinationSelection(x: endX, y: endY, direction: direction)
        guard let startSelection, let destination else {
            throw GestureProjectionError.missingSwipeIntent
        }
        self.selection = .point(start: startSelection, destination: destination)
    }

    public func encode(to encoder: Encoder) throws {
        switch selection {
        case .unitElement(let target, let start, let end):
            try target.encode(to: encoder)
            var container = encoder.container(keyedBy: SwipePointCodingKeys.self)
            try container.encode(start, forKey: .start)
            try container.encode(end, forKey: .end)
            try container.encodeIfPresent(duration, forKey: .duration)
        case .elementDirection(let target, let direction):
            try target.encode(to: encoder)
            var container = encoder.container(keyedBy: SwipePointCodingKeys.self)
            try container.encode(direction, forKey: .direction)
            try container.encodeIfPresent(duration, forKey: .duration)
        case .point(let start, let destination):
            var container = encoder.container(keyedBy: SwipePointCodingKeys.self)
            switch start {
            case .element(let target):
                try target.encode(to: encoder)
            case .coordinate(let point):
                try container.encode(point.x, forKey: .startX)
                try container.encode(point.y, forKey: .startY)
            }
            switch destination {
            case .coordinate(let point):
                try container.encode(point.x, forKey: .endX)
                try container.encode(point.y, forKey: .endY)
            case .direction(let direction):
                try container.encode(direction, forKey: .direction)
            }
            try container.encodeIfPresent(duration, forKey: .duration)
        }
    }
}

extension SwipeTarget: CustomStringConvertible {
    public var description: String {
        ScoreDescription.call("swipe", [
            selection.description,
            duration.map { "duration=\($0)" },
        ].compactMap { $0 })
    }
}
