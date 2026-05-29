public struct TapTarget: Codable, Sendable {
    public let selection: GesturePointSelection

    public init(selection: GesturePointSelection) {
        self.selection = selection
    }

    public func gesturePointSelection() -> GesturePointSelection {
        selection
    }

    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(
            allowed: gesturePointFieldNames.union(ElementTargetGrammar.inlineFieldNames),
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

public struct LongPressTarget: Codable, Sendable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case duration
    }

    public let selection: GesturePointSelection
    /// Duration in seconds.
    public let duration: Double

    public init(selection: GesturePointSelection, duration: Double = 0.5) {
        self.selection = selection
        self.duration = duration
    }

    public func gesturePointSelection() -> GesturePointSelection {
        selection
    }

    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(
            allowed: CodingKeys.self,
            additional: gesturePointFieldNames.union(ElementTargetGrammar.inlineFieldNames),
            typeName: "long press target"
        )
        self.selection = try decodeRequiredGesturePointSelection(from: decoder)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.duration = try container.decodeIfPresent(Double.self, forKey: .duration) ?? 0.5
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
            "duration=\(ScoreDescription.decimal(duration))",
        ])
    }
}
