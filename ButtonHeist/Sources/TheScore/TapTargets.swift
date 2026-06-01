public struct TapTarget: Codable, Sendable, Equatable {
    public let selection: GesturePointSelection

    public init(selection: GesturePointSelection) {
        self.selection = selection
    }

    public func gesturePointSelection() -> GesturePointSelection {
        selection
    }

    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(
            allowed: gesturePointFieldNames.union(ElementTarget.inlineFieldNames),
            typeName: "tap target"
        )
        self.selection = try decodeRequiredGesturePointSelection(from: decoder)
    }

    public func encode(to encoder: Encoder) throws {
        try encodeGesturePointSelection(selection, to: encoder)
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
        case duration
    }

    public let selection: GesturePointSelection
    /// Duration in seconds.
    public let duration: GestureDuration

    public init(selection: GesturePointSelection, duration: GestureDuration = .longPressDefault) {
        self.selection = selection
        self.duration = duration
    }

    public func gesturePointSelection() -> GesturePointSelection {
        selection
    }

    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(
            allowed: CodingKeys.self,
            additional: gesturePointFieldNames.union(ElementTarget.inlineFieldNames),
            typeName: "long press target"
        )
        self.selection = try decodeRequiredGesturePointSelection(from: decoder)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.duration = try container.decodeIfPresent(GestureDuration.self, forKey: .duration) ?? .longPressDefault
    }

    public func encode(to encoder: Encoder) throws {
        try encodeGesturePointSelection(selection, to: encoder)
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
