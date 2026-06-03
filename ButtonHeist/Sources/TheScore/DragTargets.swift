public enum DragGestureSelection: Sendable, Equatable, CustomStringConvertible {
    case elementToPoint(ElementTarget, end: ScreenPoint)
    case pointToPoint(start: ScreenPoint, end: ScreenPoint)

    public var description: String {
        switch self {
        case .elementToPoint(let target, let end):
            return ScoreDescription.call("elementToPointDrag", [
                target.description,
                "end=\(end)",
            ])
        case .pointToPoint(let start, let end):
            return ScoreDescription.call("pointToPointDrag", [
                "start=\(start)",
                "end=\(end)",
            ])
        }
    }
}

private enum DragTargetCodingKeys: String, CodingKey, CaseIterable {
    case duration
    case elementToPoint
    case pointToPoint
}

private struct DragElementToPointPayload: Codable, Sendable, Equatable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case element
        case end
    }

    let element: ElementTarget
    let end: ScreenPoint

    init(element: ElementTarget, end: ScreenPoint) {
        self.element = element
        self.end = end
    }

    init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "element-to-point drag")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            element: try container.decode(ElementTarget.self, forKey: .element),
            end: try container.decode(ScreenPoint.self, forKey: .end)
        )
    }
}

private struct DragPointToPointPayload: Codable, Sendable, Equatable {
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
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "point-to-point drag")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            start: try container.decode(ScreenPoint.self, forKey: .start),
            end: try container.decode(ScreenPoint.self, forKey: .end)
        )
    }
}

public struct DragTarget: Codable, Sendable, Equatable {
    public static let defaultDuration = GestureDuration.dragDefault

    public let selection: DragGestureSelection
    /// Duration in seconds (default 0.5).
    public let duration: GestureDuration?

    public init(start: GesturePointSelection, end: ScreenPoint, duration: GestureDuration? = nil) {
        switch start {
        case .element(let target):
            self.selection = .elementToPoint(target, end: end)
        case .coordinate(let point):
            self.selection = .pointToPoint(start: point, end: end)
        }
        self.duration = duration
    }

    public init(selection: DragGestureSelection, duration: GestureDuration? = nil) {
        self.selection = selection
        self.duration = duration
    }

    public var start: GesturePointSelection {
        switch selection {
        case .elementToPoint(let target, _):
            return .element(target)
        case .pointToPoint(let start, _):
            return .coordinate(start)
        }
    }

    public var end: ScreenPoint {
        switch selection {
        case .elementToPoint(_, let end), .pointToPoint(_, let end):
            return end
        }
    }

    public var resolvedDuration: GestureDuration { duration ?? Self.defaultDuration }

    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: DragTargetCodingKeys.self, typeName: "drag target")
        let container = try decoder.container(keyedBy: DragTargetCodingKeys.self)
        let elementToPoint = try container.decodeIfPresent(DragElementToPointPayload.self, forKey: .elementToPoint)
        let pointToPoint = try container.decodeIfPresent(DragPointToPointPayload.self, forKey: .pointToPoint)
        let intentCount = [elementToPoint != nil, pointToPoint != nil].filter { $0 }.count
        guard intentCount > 0 else {
            throw GestureProjectionError.missingGesturePoint(field: "drag intent")
        }
        guard intentCount == 1 else {
            throw GestureProjectionError.mixedGestureIntent(kind: "drag")
        }
        if let elementToPoint {
            self.selection = .elementToPoint(elementToPoint.element, end: elementToPoint.end)
        } else if let pointToPoint {
            self.selection = .pointToPoint(start: pointToPoint.start, end: pointToPoint.end)
        } else {
            throw GestureProjectionError.missingGesturePoint(field: "drag intent")
        }
        self.duration = try container.decodeIfPresent(GestureDuration.self, forKey: .duration)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: DragTargetCodingKeys.self)
        switch selection {
        case .elementToPoint(let target, let end):
            try container.encode(DragElementToPointPayload(element: target, end: end), forKey: .elementToPoint)
        case .pointToPoint(let start, let end):
            try container.encode(DragPointToPointPayload(start: start, end: end), forKey: .pointToPoint)
        }
        try container.encodeIfPresent(duration, forKey: .duration)
    }
}

extension DragTarget: CustomStringConvertible {
    public var description: String {
        ScoreDescription.call("drag", [
            selection.description,
            duration.map { "duration=\($0)" },
        ].compactMap { $0 })
    }
}
