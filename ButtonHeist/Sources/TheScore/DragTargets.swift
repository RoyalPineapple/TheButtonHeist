public struct DragTarget: Codable, Sendable {
    public static let defaultDuration = 0.5

    public let start: GesturePointSelection
    public let end: ScreenPoint
    /// Duration in seconds (default 0.5).
    public let duration: Double?

    public init(start: GesturePointSelection, end: ScreenPoint, duration: Double? = nil) {
        self.start = start
        self.end = end
        self.duration = duration
    }

    public var resolvedDuration: Double { duration ?? Self.defaultDuration }

    public func startSelection() -> GesturePointSelection {
        start
    }

    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(
            allowed: DragPointCodingKeys.self,
            additional: Set(ElementTarget.inlineFieldNames),
            typeName: "drag target"
        )
        let elementTarget = try ElementTarget.decodeInlineIfPresent(from: decoder)
        let container = try decoder.container(keyedBy: DragPointCodingKeys.self)
        let startX = try container.decodeIfPresent(Double.self, forKey: .startX)
        let startY = try container.decodeIfPresent(Double.self, forKey: .startY)
        guard let startSelection = try makeGesturePointSelection(
            elementTarget: elementTarget,
            x: startX,
            y: startY,
            field: "startPoint"
        ) else {
            throw GestureProjectionError.missingGesturePoint(field: "startPoint")
        }
        self.start = startSelection
        self.end = ScreenPoint(
            x: try container.decode(Double.self, forKey: .endX),
            y: try container.decode(Double.self, forKey: .endY)
        )
        self.duration = try container.decodeIfPresent(Double.self, forKey: .duration)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: DragPointCodingKeys.self)
        switch start {
        case .element(let target):
            try target.encode(to: encoder)
        case .coordinate(let point):
            try container.encode(point.x, forKey: .startX)
            try container.encode(point.y, forKey: .startY)
        }
        try container.encode(end.x, forKey: .endX)
        try container.encode(end.y, forKey: .endY)
        try container.encodeIfPresent(duration, forKey: .duration)
    }
}

private enum DragPointCodingKeys: String, CodingKey, CaseIterable {
    case startX
    case startY
    case endX
    case endY
    case duration
}

extension DragTarget: CustomStringConvertible {
    public var description: String {
        ScoreDescription.call("drag", [
            "start=\(start)",
            "end=\(end)",
            duration.map { "duration=\(ScoreDescription.decimal($0))" },
        ].compactMap { $0 })
    }
}
