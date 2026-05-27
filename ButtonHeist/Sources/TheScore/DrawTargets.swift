import CoreGraphics


public struct PathPoint: Codable, Sendable, Equatable {
    public let x: Double
    public let y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
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

    public var startPoint: CGPoint {
        CGPoint(x: startX, y: startY)
    }

    public var resolvedSamplesPerSegment: Int {
        min(samplesPerSegment ?? Self.defaultSamplesPerSegment, Self.maxSamplesPerSegment)
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
