import Foundation
import CoreGraphics

// MARK: - Touch Gesture Targets

/// Target for a tap gesture — either an `ElementTarget` (tap at its activation
/// point) or explicit screen coordinates. Exactly one form should be set.
public struct TouchTapTarget: Codable, Sendable {
    public let elementTarget: ElementTarget?
    public let pointX: Double?
    public let pointY: Double?

    public init(elementTarget: ElementTarget? = nil, pointX: Double? = nil, pointY: Double? = nil) {
        self.elementTarget = elementTarget
        self.pointX = pointX
        self.pointY = pointY
    }

    public var point: CGPoint? {
        guard let x = pointX, let y = pointY else { return nil }
        return CGPoint(x: x, y: y)
    }
}

extension TouchTapTarget: CustomStringConvertible {
    public var description: String {
        ScoreDescription.call("tap", [
            elementTarget?.description,
            pointX.map { "x=\(ScoreDescription.decimal($0))" },
            pointY.map { "y=\(ScoreDescription.decimal($0))" },
        ].compactMap { $0 })
    }
}

/// Target for long press gesture
public struct LongPressTarget: Codable, Sendable {
    public let elementTarget: ElementTarget?
    public let pointX: Double?
    public let pointY: Double?
    /// Duration in seconds
    public let duration: Double

    public init(elementTarget: ElementTarget? = nil, pointX: Double? = nil, pointY: Double? = nil, duration: Double = 0.5) {
        self.elementTarget = elementTarget
        self.pointX = pointX
        self.pointY = pointY
        self.duration = duration
    }

    public var point: CGPoint? {
        guard let x = pointX, let y = pointY else { return nil }
        return CGPoint(x: x, y: y)
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

/// A point in unit coordinates (0-1) relative to an element's accessibility frame.
/// `(0, 0)` is top-left, `(1, 1)` is bottom-right, `(0.5, 0.5)` is center.
/// Values outside 0-1 extend beyond the element's frame.
public struct UnitPoint: Codable, Sendable, Equatable {
    public let x: Double
    public let y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

extension UnitPoint: CustomStringConvertible {
    public var description: String {
        "unitPoint(\(ScoreDescription.decimal(x)),\(ScoreDescription.decimal(y)))"
    }
}

/// Target for swipe gesture
public struct SwipeTarget: Codable, Sendable {
    /// Start from element's interaction point
    public let elementTarget: ElementTarget?
    /// Or start from explicit coordinates
    public let startX: Double?
    public let startY: Double?
    /// End coordinates (required if not using direction)
    public let endX: Double?
    public let endY: Double?
    /// Or use direction from start point
    public let direction: SwipeDirection?
    /// Duration in seconds (default 0.15)
    public let duration: Double?
    /// Unit-point start relative to element frame (0-1)
    public let start: UnitPoint?
    /// Unit-point end relative to element frame (0-1)
    public let end: UnitPoint?

    public init(
        elementTarget: ElementTarget? = nil,
        startX: Double? = nil, startY: Double? = nil,
        endX: Double? = nil, endY: Double? = nil,
        direction: SwipeDirection? = nil,
        duration: Double? = nil,
        start: UnitPoint? = nil, end: UnitPoint? = nil
    ) {
        self.elementTarget = elementTarget
        self.startX = startX; self.startY = startY
        self.endX = endX; self.endY = endY
        self.direction = direction
        self.duration = duration
        self.start = start; self.end = end
    }

    public var startPoint: CGPoint? {
        guard let x = startX, let y = startY else { return nil }
        return CGPoint(x: x, y: y)
    }
}

extension SwipeTarget: CustomStringConvertible {
    public var description: String {
        ScoreDescription.call("swipe", [
            elementTarget?.description,
            startX.map { "startX=\(ScoreDescription.decimal($0))" },
            startY.map { "startY=\(ScoreDescription.decimal($0))" },
            endX.map { "endX=\(ScoreDescription.decimal($0))" },
            endY.map { "endY=\(ScoreDescription.decimal($0))" },
            ScoreDescription.valueField("direction", direction),
            duration.map { "duration=\(ScoreDescription.decimal($0))" },
            start.map { "start=\($0)" },
            end.map { "end=\($0)" },
        ].compactMap { $0 })
    }
}

/// Target for drag gesture
public struct DragTarget: Codable, Sendable {
    public let elementTarget: ElementTarget?
    public let startX: Double?
    public let startY: Double?
    public let endX: Double
    public let endY: Double
    /// Duration in seconds (default 0.5)
    public let duration: Double?

    public init(
        elementTarget: ElementTarget? = nil,
        startX: Double? = nil, startY: Double? = nil,
        endX: Double, endY: Double,
        duration: Double? = nil
    ) {
        self.elementTarget = elementTarget
        self.startX = startX; self.startY = startY
        self.endX = endX; self.endY = endY
        self.duration = duration
    }

    public var startPoint: CGPoint? {
        guard let x = startX, let y = startY else { return nil }
        return CGPoint(x: x, y: y)
    }

    public var endPoint: CGPoint {
        CGPoint(x: endX, y: endY)
    }
}

extension DragTarget: CustomStringConvertible {
    public var description: String {
        ScoreDescription.call("drag", [
            elementTarget?.description,
            startX.map { "startX=\(ScoreDescription.decimal($0))" },
            startY.map { "startY=\(ScoreDescription.decimal($0))" },
            "endX=\(ScoreDescription.decimal(endX))",
            "endY=\(ScoreDescription.decimal(endY))",
            duration.map { "duration=\(ScoreDescription.decimal($0))" },
        ].compactMap { $0 })
    }
}

/// Target for pinch/zoom gesture
public struct PinchTarget: Codable, Sendable {
    public let elementTarget: ElementTarget?
    public let centerX: Double?
    public let centerY: Double?
    /// Scale factor: >1.0 zooms in (spread), <1.0 zooms out (pinch)
    public let scale: Double
    /// Initial distance from center to each finger in points
    public let spread: Double?
    /// Duration in seconds (default 0.5)
    public let duration: Double?

    public init(
        elementTarget: ElementTarget? = nil,
        centerX: Double? = nil, centerY: Double? = nil,
        scale: Double, spread: Double? = nil, duration: Double? = nil
    ) {
        self.elementTarget = elementTarget
        self.centerX = centerX; self.centerY = centerY
        self.scale = scale; self.spread = spread
        self.duration = duration
    }
}

extension PinchTarget: CustomStringConvertible {
    public var description: String {
        ScoreDescription.call("pinch", [
            elementTarget?.description,
            centerX.map { "centerX=\(ScoreDescription.decimal($0))" },
            centerY.map { "centerY=\(ScoreDescription.decimal($0))" },
            "scale=\(ScoreDescription.decimal(scale))",
            spread.map { "spread=\(ScoreDescription.decimal($0))" },
            duration.map { "duration=\(ScoreDescription.decimal($0))" },
        ].compactMap { $0 })
    }
}

/// Target for rotation gesture
public struct RotateTarget: Codable, Sendable {
    public let elementTarget: ElementTarget?
    public let centerX: Double?
    public let centerY: Double?
    /// Rotation angle in radians (positive = counter-clockwise)
    public let angle: Double
    /// Distance from center to each finger in points
    public let radius: Double?
    /// Duration in seconds (default 0.5)
    public let duration: Double?

    public init(
        elementTarget: ElementTarget? = nil,
        centerX: Double? = nil, centerY: Double? = nil,
        angle: Double, radius: Double? = nil, duration: Double? = nil
    ) {
        self.elementTarget = elementTarget
        self.centerX = centerX; self.centerY = centerY
        self.angle = angle; self.radius = radius
        self.duration = duration
    }
}

extension RotateTarget: CustomStringConvertible {
    public var description: String {
        ScoreDescription.call("rotate", [
            elementTarget?.description,
            centerX.map { "centerX=\(ScoreDescription.decimal($0))" },
            centerY.map { "centerY=\(ScoreDescription.decimal($0))" },
            "angle=\(ScoreDescription.decimal(angle))",
            radius.map { "radius=\(ScoreDescription.decimal($0))" },
            duration.map { "duration=\(ScoreDescription.decimal($0))" },
        ].compactMap { $0 })
    }
}

/// Target for two-finger tap gesture
public struct TwoFingerTapTarget: Codable, Sendable {
    public let elementTarget: ElementTarget?
    public let centerX: Double?
    public let centerY: Double?
    /// Distance between the two fingers in points
    public let spread: Double?

    public init(
        elementTarget: ElementTarget? = nil,
        centerX: Double? = nil, centerY: Double? = nil,
        spread: Double? = nil
    ) {
        self.elementTarget = elementTarget
        self.centerX = centerX; self.centerY = centerY
        self.spread = spread
    }
}

extension TwoFingerTapTarget: CustomStringConvertible {
    public var description: String {
        ScoreDescription.call("twoFingerTap", [
            elementTarget?.description,
            centerX.map { "centerX=\(ScoreDescription.decimal($0))" },
            centerY.map { "centerY=\(ScoreDescription.decimal($0))" },
            spread.map { "spread=\(ScoreDescription.decimal($0))" },
        ].compactMap { $0 })
    }
}

/// A point in a draw path
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

/// Target for draw-path gesture (polyline trace)
public struct DrawPathTarget: Codable, Sendable {
    /// Ordered array of waypoints to trace through
    public let points: [PathPoint]
    /// Total duration in seconds (mutually exclusive with velocity)
    public let duration: Double?
    /// Speed in points-per-second (mutually exclusive with duration)
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

/// A cubic bezier segment: two control points and an endpoint.
/// The start point is implicit (the end of the previous segment, or the path's startPoint).
public struct BezierSegment: Codable, Sendable {
    public let cp1X: Double
    public let cp1Y: Double
    public let cp2X: Double
    public let cp2Y: Double
    public let endX: Double
    public let endY: Double

    public init(cp1X: Double, cp1Y: Double, cp2X: Double, cp2Y: Double, endX: Double, endY: Double) {
        self.cp1X = cp1X; self.cp1Y = cp1Y
        self.cp2X = cp2X; self.cp2Y = cp2Y
        self.endX = endX; self.endY = endY
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

/// Target for draw-bezier gesture (cubic bezier curves sampled to polyline)
public struct DrawBezierTarget: Codable, Sendable {
    /// Starting point of the bezier path
    public let startX: Double
    public let startY: Double
    /// Array of cubic bezier segments
    public let segments: [BezierSegment]
    /// Samples per bezier segment (default 20)
    public let samplesPerSegment: Int?
    /// Total duration in seconds (mutually exclusive with velocity)
    public let duration: Double?
    /// Speed in points-per-second (mutually exclusive with duration)
    public let velocity: Double?

    public init(
        startX: Double, startY: Double,
        segments: [BezierSegment],
        samplesPerSegment: Int? = nil,
        duration: Double? = nil, velocity: Double? = nil
    ) {
        self.startX = startX; self.startY = startY
        self.segments = segments
        self.samplesPerSegment = samplesPerSegment
        self.duration = duration; self.velocity = velocity
    }

    public var startPoint: CGPoint {
        CGPoint(x: startX, y: startY)
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
