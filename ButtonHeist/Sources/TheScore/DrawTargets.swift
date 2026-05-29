import CoreGraphics

public struct PathPoint: Codable, Sendable, Equatable {
    public let x: Double
    public let y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case x
        case y
    }

    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "draw path point")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            x: try container.decode(Double.self, forKey: .x),
            y: try container.decode(Double.self, forKey: .y)
        )
    }

    public var cgPoint: CGPoint {
        CGPoint(x: x, y: y)
    }
}

extension PathPoint: CustomStringConvertible {
    public var description: String {
        "point(\(ScoreDescription.decimal(x)),\(ScoreDescription.decimal(y)))"
    }
}

public struct DrawPathTarget: Codable, Sendable {
    /// Ordered array of waypoints to trace through.
    public let points: [PathPoint]
    /// Total duration in seconds (mutually exclusive with velocity).
    public let duration: Double?
    /// Speed in points-per-second (mutually exclusive with duration).
    public let velocity: Double?

    public init(points: [PathPoint], duration: Double? = nil, velocity: Double? = nil) {
        self.points = points
        self.duration = duration
        self.velocity = velocity
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case points
        case duration
        case velocity
    }

    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "draw path target")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let duration = try container.decodeIfPresent(Double.self, forKey: .duration)
        let velocity = try container.decodeIfPresent(Double.self, forKey: .velocity)
        try Self.validateTiming(duration: duration, velocity: velocity, codingPath: decoder.codingPath)
        self.init(
            points: try container.decode([PathPoint].self, forKey: .points),
            duration: duration,
            velocity: velocity
        )
    }

    public func encode(to encoder: Encoder) throws {
        try Self.validateTiming(duration: duration, velocity: velocity, codingPath: encoder.codingPath)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(points, forKey: .points)
        try container.encodeIfPresent(duration, forKey: .duration)
        try container.encodeIfPresent(velocity, forKey: .velocity)
    }

    private static func validateTiming(
        duration: Double?,
        velocity: Double?,
        codingPath: [CodingKey]
    ) throws {
        guard duration == nil || velocity == nil else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: codingPath,
                debugDescription: "Draw timing accepts duration or velocity, not both"
            ))
        }
    }
}

extension DrawPathTarget: CustomStringConvertible {
    public var description: String {
        ScoreDescription.call("drawPath", [
            "points=\(points.count)",
            points.first.map { "first=\($0)" },
            points.last.map { "last=\($0)" },
            duration.map { "duration=\(ScoreDescription.decimal($0))" },
            velocity.map { "velocity=\(ScoreDescription.decimal($0))" },
        ].compactMap { $0 })
    }
}

public struct BezierSegment: Codable, Sendable {
    public let cp1X: Double
    public let cp1Y: Double
    public let cp2X: Double
    public let cp2Y: Double
    public let endX: Double
    public let endY: Double

    public init(cp1X: Double, cp1Y: Double, cp2X: Double, cp2Y: Double, endX: Double, endY: Double) {
        self.cp1X = cp1X
        self.cp1Y = cp1Y
        self.cp2X = cp2X
        self.cp2Y = cp2Y
        self.endX = endX
        self.endY = endY
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case cp1X
        case cp1Y
        case cp2X
        case cp2Y
        case endX
        case endY
    }

    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "bezier segment")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            cp1X: try container.decode(Double.self, forKey: .cp1X),
            cp1Y: try container.decode(Double.self, forKey: .cp1Y),
            cp2X: try container.decode(Double.self, forKey: .cp2X),
            cp2Y: try container.decode(Double.self, forKey: .cp2Y),
            endX: try container.decode(Double.self, forKey: .endX),
            endY: try container.decode(Double.self, forKey: .endY)
        )
    }

    public var cp1: CGPoint { CGPoint(x: cp1X, y: cp1Y) }
    public var cp2: CGPoint { CGPoint(x: cp2X, y: cp2Y) }
    public var end: CGPoint { CGPoint(x: endX, y: endY) }
}

extension BezierSegment: CustomStringConvertible {
    public var description: String {
        ScoreDescription.call("bezierSegment", [
            "cp1=(\(ScoreDescription.decimal(cp1X)),\(ScoreDescription.decimal(cp1Y)))",
            "cp2=(\(ScoreDescription.decimal(cp2X)),\(ScoreDescription.decimal(cp2Y)))",
            "end=(\(ScoreDescription.decimal(endX)),\(ScoreDescription.decimal(endY)))",
        ])
    }
}

public struct DrawBezierTarget: Codable, Sendable {
    public static let defaultSamplesPerSegment = 20
    public static let maxSamplesPerSegment = 1_000

    /// Starting point of the bezier path.
    public let startX: Double
    public let startY: Double
    /// Array of cubic bezier segments.
    public let segments: [BezierSegment]
    /// Samples per bezier segment (default 20).
    public let samplesPerSegment: Int?
    /// Total duration in seconds (mutually exclusive with velocity).
    public let duration: Double?
    /// Speed in points-per-second (mutually exclusive with duration).
    public let velocity: Double?

    public init(
        startX: Double, startY: Double,
        segments: [BezierSegment],
        samplesPerSegment: Int? = nil,
        duration: Double? = nil, velocity: Double? = nil
    ) {
        self.startX = startX
        self.startY = startY
        self.segments = segments
        self.samplesPerSegment = samplesPerSegment
        self.duration = duration
        self.velocity = velocity
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case startX
        case startY
        case segments
        case samplesPerSegment
        case duration
        case velocity
    }

    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "draw bezier target")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let duration = try container.decodeIfPresent(Double.self, forKey: .duration)
        let velocity = try container.decodeIfPresent(Double.self, forKey: .velocity)
        try Self.validateTiming(duration: duration, velocity: velocity, codingPath: decoder.codingPath)
        self.init(
            startX: try container.decode(Double.self, forKey: .startX),
            startY: try container.decode(Double.self, forKey: .startY),
            segments: try container.decode([BezierSegment].self, forKey: .segments),
            samplesPerSegment: try container.decodeIfPresent(Int.self, forKey: .samplesPerSegment),
            duration: duration,
            velocity: velocity
        )
    }

    public func encode(to encoder: Encoder) throws {
        try Self.validateTiming(duration: duration, velocity: velocity, codingPath: encoder.codingPath)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(startX, forKey: .startX)
        try container.encode(startY, forKey: .startY)
        try container.encode(segments, forKey: .segments)
        try container.encodeIfPresent(samplesPerSegment, forKey: .samplesPerSegment)
        try container.encodeIfPresent(duration, forKey: .duration)
        try container.encodeIfPresent(velocity, forKey: .velocity)
    }

    private static func validateTiming(
        duration: Double?,
        velocity: Double?,
        codingPath: [CodingKey]
    ) throws {
        guard duration == nil || velocity == nil else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: codingPath,
                debugDescription: "Draw timing accepts duration or velocity, not both"
            ))
        }
    }

    public var startPoint: CGPoint {
        CGPoint(x: startX, y: startY)
    }

    public var resolvedSamplesPerSegment: Int {
        min(samplesPerSegment ?? Self.defaultSamplesPerSegment, Self.maxSamplesPerSegment)
    }
}

private struct DrawTargetUnknownKey: CodingKey {
    var stringValue: String
    var intValue: Int?

    init(stringValue: String) {
        self.stringValue = stringValue
        intValue = nil
    }

    init?(intValue: Int) {
        stringValue = "\(intValue)"
        self.intValue = intValue
    }
}

private extension Decoder {
    func rejectUnknownKeys<K>(
        allowed keyType: K.Type,
        typeName: String
    ) throws where K: CodingKey & CaseIterable {
        let knownKeys = Set(keyType.allCases.map(\.stringValue))
        let dynamicContainer = try container(keyedBy: DrawTargetUnknownKey.self)
        guard let unknownKey = dynamicContainer.allKeys.first(where: { !knownKeys.contains($0.stringValue) }) else {
            return
        }
        throw DecodingError.dataCorrupted(.init(
            codingPath: codingPath + [unknownKey],
            debugDescription: "Unknown \(typeName) field \"\(unknownKey.stringValue)\""
        ))
    }
}

extension DrawBezierTarget: CustomStringConvertible {
    public var description: String {
        ScoreDescription.call("drawBezier", [
            "start=(\(ScoreDescription.decimal(startX)),\(ScoreDescription.decimal(startY)))",
            "segments=\(segments.count)",
            segments.first.map { "first=\($0)" },
            segments.last.map { "last=\($0)" },
            ScoreDescription.valueField("samplesPerSegment", samplesPerSegment),
            duration.map { "duration=\(ScoreDescription.decimal($0))" },
            velocity.map { "velocity=\(ScoreDescription.decimal($0))" },
        ].compactMap { $0 })
    }
}
