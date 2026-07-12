public struct TapTarget: Codable, Sendable, Equatable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case element
        case unitPoint
        case point
    }

    public let selection: GesturePointSelection

    public init(selection: GesturePointSelection) {
        self.selection = selection
    }

    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "tap target")
        self.selection = try GesturePointSelection(from: decoder)
    }

    public func encode(to encoder: Encoder) throws {
        try selection.encode(to: encoder)
    }
}

extension TapTarget: CustomStringConvertible {
    public var description: String {
        ScoreDescription.call("tap", [
            selection.description,
        ])
    }
}

public struct LongPressTarget: Codable, Sendable, Equatable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case element
        case unitPoint
        case point
        case duration
    }

    public let selection: GesturePointSelection
    /// Duration in seconds.
    public let duration: GestureDuration

    public init(selection: GesturePointSelection, duration: GestureDuration = .longPressDefault) {
        self.selection = selection
        self.duration = duration
    }

    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "long press target")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.selection = try GesturePointSelection(
            element: try container.decodeIfPresent(AccessibilityTarget.self, forKey: .element),
            unitPoint: try container.decodeIfPresent(UnitPoint.self, forKey: .unitPoint),
            point: try container.decodeIfPresent(ScreenPoint.self, forKey: .point)
        )
        self.duration = try container.decodeIfPresent(GestureDuration.self, forKey: .duration) ?? .longPressDefault
    }

    public func encode(to encoder: Encoder) throws {
        try selection.encode(to: encoder)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(duration, forKey: .duration)
    }
}

extension LongPressTarget: CustomStringConvertible {
    public var description: String {
        ScoreDescription.call("longPress", [
            selection.description,
            "duration=\(duration)",
        ])
    }
}
