import CoreGraphics

public enum SwipeDestinationSelection: Sendable, Equatable, CustomStringConvertible {
    case coordinate(ScreenPoint)
    case direction(SwipeDirection)
    case unspecified

    public var isSpecified: Bool {
        if case .unspecified = self {
            return false
        }
        return true
    }

    public var description: String {
        switch self {
        case .coordinate(let point):
            return point.description
        case .direction(let direction):
            return "\(direction)"
        case .unspecified:
            return "unspecified"
        }
    }
}

public enum SwipeGestureSelection: Sendable, Equatable, CustomStringConvertible {
    case unitElement(ElementTarget, start: UnitPoint, end: UnitPoint, direction: SwipeDirection?)
    case point(start: GesturePointSelection, destination: SwipeDestinationSelection)

    public var description: String {
        switch self {
        case .unitElement(let target, let start, let end, let direction):
            return ScoreDescription.call("unitSwipe", ([
                target.description,
                "start=\(start)",
                "end=\(end)",
                ScoreDescription.valueField("direction", direction),
            ] as [String?]).compactMap { $0 })
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
    public let x: Double
    public let y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

extension UnitPoint: CustomStringConvertible {
    public var description: String {
        "unitPoint(\(ScoreDescription.decimal(x)),\(ScoreDescription.decimal(y)))"
    }
}

private enum SwipePointCodingKeys: String, CodingKey {
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
) throws -> SwipeDestinationSelection {
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
    return .unspecified
}

public struct SwipeTarget: Codable, Sendable {
    public static let defaultDuration = 0.15

    public let selection: SwipeGestureSelection
    /// Duration in seconds (default 0.15).
    public let duration: Double?

    public init(selection: SwipeGestureSelection, duration: Double? = nil) {
        self.selection = selection
        self.duration = duration
    }

    public var elementTarget: ElementTarget? {
        switch selection {
        case .unitElement(let target, _, _, _):
            return target
        case .point(let start, _):
            return start.elementTarget
        }
    }

    public var startX: Double? {
        guard case .point(let start, _) = selection else { return nil }
        return start.pointX
    }

    public var startY: Double? {
        guard case .point(let start, _) = selection else { return nil }
        return start.pointY
    }

    public var endX: Double? {
        guard case .point(_, .coordinate(let point)) = selection else { return nil }
        return point.x
    }

    public var endY: Double? {
        guard case .point(_, .coordinate(let point)) = selection else { return nil }
        return point.y
    }

    public var direction: SwipeDirection? {
        switch selection {
        case .unitElement(_, _, _, let direction):
            return direction
        case .point(_, .direction(let direction)):
            return direction
        case .point:
            return nil
        }
    }

    /// Direction-based swipes derive their own start/end at dispatch time.
    public var start: UnitPoint? {
        guard case .unitElement(_, let start, _, let direction) = selection, direction == nil else { return nil }
        return start
    }

    /// Direction-based swipes derive their own start/end at dispatch time.
    public var end: UnitPoint? {
        guard case .unitElement(_, _, let end, let direction) = selection, direction == nil else { return nil }
        return end
    }

    public var startPoint: CGPoint? {
        guard let x = startX, let y = startY else { return nil }
        return CGPoint(x: x, y: y)
    }

    public var resolvedDuration: Double { duration ?? Self.defaultDuration }

    public func gestureSelection() -> SwipeGestureSelection {
        selection
    }

    public init(from decoder: Decoder) throws {
        let elementTarget = try ElementTarget.decodeInlineIfPresent(from: decoder)
        let pointContainer = try decoder.container(keyedBy: SwipePointCodingKeys.self)
        let startX = try pointContainer.decodeIfPresent(Double.self, forKey: .startX)
        let startY = try pointContainer.decodeIfPresent(Double.self, forKey: .startY)
        let endX = try pointContainer.decodeIfPresent(Double.self, forKey: .endX)
        let endY = try pointContainer.decodeIfPresent(Double.self, forKey: .endY)
        let direction = try pointContainer.decodeIfPresent(SwipeDirection.self, forKey: .direction)
        let start = try pointContainer.decodeIfPresent(UnitPoint.self, forKey: .start)
        let end = try pointContainer.decodeIfPresent(UnitPoint.self, forKey: .end)
        self.duration = try pointContainer.decodeIfPresent(Double.self, forKey: .duration)
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
            self.selection = .unitElement(elementTarget, start: start, end: end, direction: nil)
            return
        }
        if let direction, let elementTarget, startX == nil, startY == nil, endX == nil, endY == nil {
            self.selection = .unitElement(
                elementTarget,
                start: direction.defaultStart,
                end: direction.defaultEnd,
                direction: direction
            )
            return
        }
        let startSelection = try makeGesturePointSelection(
            elementTarget: elementTarget,
            x: startX,
            y: startY,
            field: "startPoint"
        )
        let destination = try swipeDestinationSelection(x: endX, y: endY, direction: direction)
        guard startSelection.isSpecified, destination.isSpecified else {
            throw GestureProjectionError.missingSwipeIntent
        }
        self.selection = .point(start: startSelection, destination: destination)
    }

    public func encode(to encoder: Encoder) throws {
        switch selection {
        case .unitElement(let target, let start, let end, let direction):
            try target.encode(to: encoder)
            var container = encoder.container(keyedBy: SwipePointCodingKeys.self)
            if let direction {
                guard start == direction.defaultStart, end == direction.defaultEnd else {
                    throw EncodingError.invalidValue(self, .init(
                        codingPath: encoder.codingPath,
                        debugDescription: "direction swipe must use the direction default start/end; omit direction for explicit unit points"
                    ))
                }
                try container.encode(direction, forKey: .direction)
            } else {
                try container.encode(start, forKey: .start)
                try container.encode(end, forKey: .end)
            }
            try container.encodeIfPresent(duration, forKey: .duration)
        case .point(let start, let destination):
            var container = encoder.container(keyedBy: SwipePointCodingKeys.self)
            switch start {
            case .element(let target):
                try target.encode(to: encoder)
            case .coordinate(let point):
                try container.encode(point.x, forKey: .startX)
                try container.encode(point.y, forKey: .startY)
            case .unspecified:
                break
            }
            switch destination {
            case .coordinate(let point):
                try container.encode(point.x, forKey: .endX)
                try container.encode(point.y, forKey: .endY)
            case .direction(let direction):
                try container.encode(direction, forKey: .direction)
            case .unspecified:
                break
            }
            try container.encodeIfPresent(duration, forKey: .duration)
        }
    }
}

extension SwipeTarget: CustomStringConvertible {
    public var description: String {
        ScoreDescription.call("swipe", [
            elementTarget?.description,
            startX.map { "startX=\(ScoreDescription.decimal($0))" },
            startY.map { "startY=\(ScoreDescription.decimal($0))" },
            endX.map { "endX=\(ScoreDescription.decimal($0))" },
            endY.map { "endY=\(ScoreDescription.decimal($0))" },
            ScoreDescription.valueField("direction", direction),
            duration.map { "duration=\(ScoreDescription.decimal($0))" },
            start.map { "start=\($0)" },
            end.map { "end=\($0)" },
        ].compactMap { $0 })
    }
}
