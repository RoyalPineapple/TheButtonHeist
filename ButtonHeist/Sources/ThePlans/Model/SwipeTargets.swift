public enum SwipeGestureSelection: Sendable, Equatable, CustomStringConvertible {
    case unitElement(AccessibilityTarget, start: UnitPoint, end: UnitPoint)
    case elementDirection(AccessibilityTarget, SwipeDirection)
    case pointToPoint(start: ScreenPoint, end: ScreenPoint)
    case pointDirection(start: ScreenPoint, direction: SwipeDirection)

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
        case .pointToPoint(let start, let end):
            return ScoreDescription.call("pointToPointSwipe", [
                "start=\(start)",
                "end=\(end)",
            ])
        case .pointDirection(let start, let direction):
            return ScoreDescription.call("pointDirectionSwipe", [
                "start=\(start)",
                "direction=\(direction)",
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

    private let finiteX: FiniteCoordinate
    private let finiteY: FiniteCoordinate

    public var x: Double { finiteX.value }
    public var y: Double { finiteY.value }

    public init(x: FiniteCoordinate, y: FiniteCoordinate) {
        finiteX = x
        finiteY = y
    }

    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "unit point")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            x: try container.decode(FiniteCoordinate.self, forKey: .x),
            y: try container.decode(FiniteCoordinate.self, forKey: .y)
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

private enum SwipeTargetCodingKeys: String, CodingKey, CaseIterable {
    case duration
    case elementDirection
    case elementUnitPoints
    case pointToPoint
    case pointDirection
}

private struct SwipeElementDirectionPayload: Codable, Sendable, Equatable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case element
        case direction
    }

    let element: AccessibilityTarget
    let direction: SwipeDirection

    init(element: AccessibilityTarget, direction: SwipeDirection) {
        self.element = element
        self.direction = direction
    }

    init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "element direction swipe")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            element: try container.decode(AccessibilityTarget.self, forKey: .element),
            direction: try container.decode(SwipeDirection.self, forKey: .direction)
        )
    }
}

private struct SwipeElementUnitPointsPayload: Codable, Sendable, Equatable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case element
        case start
        case end
    }

    let element: AccessibilityTarget
    let start: UnitPoint
    let end: UnitPoint

    init(element: AccessibilityTarget, start: UnitPoint, end: UnitPoint) {
        self.element = element
        self.start = start
        self.end = end
    }

    init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "element unit-points swipe")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            element: try container.decode(AccessibilityTarget.self, forKey: .element),
            start: try container.decode(UnitPoint.self, forKey: .start),
            end: try container.decode(UnitPoint.self, forKey: .end)
        )
    }
}

private struct SwipePointToPointPayload: Codable, Sendable, Equatable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case start
        case end
    }

    let start: ScreenPoint
    let end: ScreenPoint

    init(start: ScreenPoint, end: ScreenPoint) {
        self.start = start
        self.end = end
    }

    init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "point-to-point swipe")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            start: try container.decode(ScreenPoint.self, forKey: .start),
            end: try container.decode(ScreenPoint.self, forKey: .end)
        )
    }
}

private struct SwipePointDirectionPayload: Codable, Sendable, Equatable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case start
        case direction
    }

    let start: ScreenPoint
    let direction: SwipeDirection

    init(start: ScreenPoint, direction: SwipeDirection) {
        self.start = start
        self.direction = direction
    }

    init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "point direction swipe")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            start: try container.decode(ScreenPoint.self, forKey: .start),
            direction: try container.decode(SwipeDirection.self, forKey: .direction)
        )
    }
}

public struct SwipeTarget: Codable, Sendable, Equatable {
    public static let defaultDuration = GestureDuration.swipeDefault

    public let selection: SwipeGestureSelection
    /// Duration in seconds (default 0.15).
    public let duration: GestureDuration?

    public init(selection: SwipeGestureSelection, duration: GestureDuration? = nil) {
        self.selection = selection
        self.duration = duration
    }

    public var resolvedDuration: GestureDuration { duration ?? Self.defaultDuration }

    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: SwipeTargetCodingKeys.self, typeName: "swipe target")
        let container = try decoder.container(keyedBy: SwipeTargetCodingKeys.self)
        self.duration = try container.decodeIfPresent(GestureDuration.self, forKey: .duration)
        let selectionPayloads: [GesturePayloadCandidate<SwipeTargetCodingKeys, SwipeGestureSelection>] = [
            GesturePayloadCandidate(.elementDirection, as: SwipeElementDirectionPayload.self) {
                .elementDirection($0.element, $0.direction)
            },
            GesturePayloadCandidate(.elementUnitPoints, as: SwipeElementUnitPointsPayload.self) {
                .unitElement($0.element, start: $0.start, end: $0.end)
            },
            GesturePayloadCandidate(.pointToPoint, as: SwipePointToPointPayload.self) {
                .pointToPoint(start: $0.start, end: $0.end)
            },
            GesturePayloadCandidate(.pointDirection, as: SwipePointDirectionPayload.self) {
                .pointDirection(start: $0.start, direction: $0.direction)
            },
        ]
        self.selection = try container.decodeExactlyOneGesturePayload(
            kind: "swipe",
            missing: GestureProjectionError.missingSwipeIntent,
            candidates: selectionPayloads
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: SwipeTargetCodingKeys.self)
        switch selection {
        case .unitElement(let target, let start, let end):
            try container.encode(
                SwipeElementUnitPointsPayload(element: target, start: start, end: end),
                forKey: .elementUnitPoints
            )
        case .elementDirection(let target, let direction):
            try container.encode(
                SwipeElementDirectionPayload(element: target, direction: direction),
                forKey: .elementDirection
            )
        case .pointToPoint(let start, let end):
            try container.encode(SwipePointToPointPayload(start: start, end: end), forKey: .pointToPoint)
        case .pointDirection(let start, let direction):
            try container.encode(
                SwipePointDirectionPayload(start: start, direction: direction),
                forKey: .pointDirection
            )
        }
        try container.encodeIfPresent(duration, forKey: .duration)
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
