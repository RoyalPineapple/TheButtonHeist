import CoreGraphics

public struct TapTarget: Codable, Sendable {
    public let selection: GesturePointSelection

    public init(selection: GesturePointSelection) {
        self.selection = selection
    }

    public var elementTarget: ElementTarget? {
        selection.elementTarget
    }

    public var pointX: Double? {
        selection.pointX
    }

    public var pointY: Double? {
        selection.pointY
    }

    public var point: CGPoint? {
        guard let x = selection.pointX, let y = selection.pointY else { return nil }
        return CGPoint(x: x, y: y)
    }

    public func gesturePointSelection() -> GesturePointSelection {
        selection
    }

    public init(from decoder: Decoder) throws {
        self.selection = try decodeRequiredGesturePointSelection(from: decoder)
    }

    public func encode(to encoder: Encoder) throws {
        try encodeGesturePointSelection(selection, to: encoder)
    }
}

extension TapTarget: CustomStringConvertible {
    public var description: String {
        ScoreDescription.call("tap", [
            elementTarget?.description,
            pointX.map { "x=\(ScoreDescription.decimal($0))" },
            pointY.map { "y=\(ScoreDescription.decimal($0))" },
        ].compactMap { $0 })
    }
}

public struct LongPressTarget: Codable, Sendable {
    private enum CodingKeys: String, CodingKey {
        case duration
    }

    public let selection: GesturePointSelection
    /// Duration in seconds.
    public let duration: Double

    public init(selection: GesturePointSelection, duration: Double = 0.5) {
        self.selection = selection
        self.duration = duration
    }

    public var elementTarget: ElementTarget? {
        selection.elementTarget
    }

    public var pointX: Double? {
        selection.pointX
    }

    public var pointY: Double? {
        selection.pointY
    }

    public var point: CGPoint? {
        guard let x = selection.pointX, let y = selection.pointY else { return nil }
        return CGPoint(x: x, y: y)
    }

    public func gesturePointSelection() -> GesturePointSelection {
        selection
    }

    public init(from decoder: Decoder) throws {
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
            elementTarget?.description,
            pointX.map { "x=\(ScoreDescription.decimal($0))" },
            pointY.map { "y=\(ScoreDescription.decimal($0))" },
            "duration=\(ScoreDescription.decimal(duration))",
        ].compactMap { $0 })
    }
}
