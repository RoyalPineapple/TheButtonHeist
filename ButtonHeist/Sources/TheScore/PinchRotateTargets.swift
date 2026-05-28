public struct PinchTarget: Codable, Sendable {
    public static let defaultSpread = 100.0
    public static let defaultDuration = 0.5

    private enum CodingKeys: String, CodingKey {
        case scale
        case spread
        case duration
    }

    public let center: GesturePointSelection
    /// Scale factor: >1.0 zooms in (spread), <1.0 zooms out (pinch).
    public let scale: Double
    /// Initial distance from center to each finger in points.
    public let spread: Double?
    /// Duration in seconds (default 0.5).
    public let duration: Double?

    public init(
        center: GesturePointSelection,
        scale: Double, spread: Double? = nil, duration: Double? = nil
    ) {
        self.center = center
        self.scale = scale
        self.spread = spread
        self.duration = duration
    }

    public var resolvedSpread: Double { spread ?? Self.defaultSpread }
    public var resolvedDuration: Double { duration ?? Self.defaultDuration }

    public func centerSelection() -> GesturePointSelection {
        center
    }

    public init(from decoder: Decoder) throws {
        self.center = try decodeRequiredGestureCenterSelection(from: decoder)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.scale = try container.decode(Double.self, forKey: .scale)
        self.spread = try container.decodeIfPresent(Double.self, forKey: .spread)
        self.duration = try container.decodeIfPresent(Double.self, forKey: .duration)
    }

    public func encode(to encoder: Encoder) throws {
        try encodeGestureCenterSelection(center, to: encoder)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(scale, forKey: .scale)
        try container.encodeIfPresent(spread, forKey: .spread)
        try container.encodeIfPresent(duration, forKey: .duration)
    }
}

extension PinchTarget: CustomStringConvertible {
    public var description: String {
        ScoreDescription.call("pinch", [
            center.description,
            "scale=\(ScoreDescription.decimal(scale))",
            spread.map { "spread=\(ScoreDescription.decimal($0))" },
            duration.map { "duration=\(ScoreDescription.decimal($0))" },
        ].compactMap { $0 })
    }
}

public struct RotateTarget: Codable, Sendable {
    public static let defaultRadius = 100.0
    public static let defaultDuration = 0.5

    private enum CodingKeys: String, CodingKey {
        case angle
        case radius
        case duration
    }

    public let center: GesturePointSelection
    /// Rotation angle in radians (positive = counter-clockwise).
    public let angle: Double
    /// Distance from center to each finger in points.
    public let radius: Double?
    /// Duration in seconds (default 0.5).
    public let duration: Double?

    public init(
        center: GesturePointSelection,
        angle: Double, radius: Double? = nil, duration: Double? = nil
    ) {
        self.center = center
        self.angle = angle
        self.radius = radius
        self.duration = duration
    }

    public var resolvedRadius: Double { radius ?? Self.defaultRadius }
    public var resolvedDuration: Double { duration ?? Self.defaultDuration }

    public func centerSelection() -> GesturePointSelection {
        center
    }

    public init(from decoder: Decoder) throws {
        self.center = try decodeRequiredGestureCenterSelection(from: decoder)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.angle = try container.decode(Double.self, forKey: .angle)
        self.radius = try container.decodeIfPresent(Double.self, forKey: .radius)
        self.duration = try container.decodeIfPresent(Double.self, forKey: .duration)
    }

    public func encode(to encoder: Encoder) throws {
        try encodeGestureCenterSelection(center, to: encoder)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(angle, forKey: .angle)
        try container.encodeIfPresent(radius, forKey: .radius)
        try container.encodeIfPresent(duration, forKey: .duration)
    }
}

extension RotateTarget: CustomStringConvertible {
    public var description: String {
        ScoreDescription.call("rotate", [
            center.description,
            "angle=\(ScoreDescription.decimal(angle))",
            radius.map { "radius=\(ScoreDescription.decimal($0))" },
            duration.map { "duration=\(ScoreDescription.decimal($0))" },
        ].compactMap { $0 })
    }
}

public struct TwoFingerTapTarget: Codable, Sendable {
    public static let defaultSpread = 40.0

    private enum CodingKeys: String, CodingKey {
        case spread
    }

    public let center: GesturePointSelection
    /// Distance between the two fingers in points.
    public let spread: Double?

    public init(center: GesturePointSelection, spread: Double? = nil) {
        self.center = center
        self.spread = spread
    }

    public var resolvedSpread: Double { spread ?? Self.defaultSpread }

    public func centerSelection() -> GesturePointSelection {
        center
    }

    public init(from decoder: Decoder) throws {
        self.center = try decodeRequiredGestureCenterSelection(from: decoder)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.spread = try container.decodeIfPresent(Double.self, forKey: .spread)
    }

    public func encode(to encoder: Encoder) throws {
        try encodeGestureCenterSelection(center, to: encoder)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(spread, forKey: .spread)
    }
}

extension TwoFingerTapTarget: CustomStringConvertible {
    public var description: String {
        ScoreDescription.call("twoFingerTap", [
            center.description,
            spread.map { "spread=\(ScoreDescription.decimal($0))" },
        ].compactMap { $0 })
    }
}

private func decodeRequiredGestureCenterSelection(from decoder: Decoder) throws -> GesturePointSelection {
    let center = try decodeGestureCenterSelection(from: decoder)
    guard center.isSpecified else {
        throw DecodingError.dataCorrupted(.init(
            codingPath: decoder.codingPath,
            debugDescription: "center requires an element target or center coordinates"
        ))
    }
    return center
}
