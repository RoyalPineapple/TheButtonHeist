import Foundation
import CoreGraphics

// MARK: - Touch Gesture Targets

public struct ScreenPoint: Sendable, Equatable, CustomStringConvertible {
    public let x: Double
    public let y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    public var cgPoint: CGPoint {
        CGPoint(x: x, y: y)
    }

    public var description: String {
        "point(\(ScoreDescription.decimal(x)),\(ScoreDescription.decimal(y)))"
    }
}

public enum GestureProjectionError: Error, Sendable, Equatable, CustomStringConvertible {
    case partialCoordinate(field: String, xPresent: Bool, yPresent: Bool)
    case mixedCoordinateAndElement(field: String)
    case partialUnitPoints
    case unitPointsRequireElementTarget

    public var description: String {
        switch self {
        case .partialCoordinate(let field, let xPresent, let yPresent):
            return "\(field) requires both x and y coordinates (xPresent=\(xPresent), yPresent=\(yPresent))"
        case .mixedCoordinateAndElement(let field):
            return "\(field) accepts either an element target or coordinates, not both"
        case .partialUnitPoints:
            return "unit-point swipe requires both start and end unit points"
        case .unitPointsRequireElementTarget:
            return "unit-point swipe requires elementTarget"
        }
    }
}

public enum GesturePointSelection: Sendable, Equatable, CustomStringConvertible {
    case element(ElementTarget)
    case coordinate(ScreenPoint)
    case unspecified

    public var elementTarget: ElementTarget? {
        guard case .element(let target) = self else { return nil }
        return target
    }

    public var screenPoint: ScreenPoint? {
        guard case .coordinate(let point) = self else { return nil }
        return point
    }

    public var pointX: Double? {
        screenPoint?.x
    }

    public var pointY: Double? {
        screenPoint?.y
    }

    public var description: String {
        switch self {
        case .element(let target):
            return target.description
        case .coordinate(let point):
            return point.description
        case .unspecified:
            return "unspecified"
        }
    }
}

public enum SwipeDestinationSelection: Sendable, Equatable, CustomStringConvertible {
    case coordinate(ScreenPoint)
    case direction(SwipeDirection)
    case unspecified

    public var description: String {
        switch self {
        case .coordinate(let point):
            return point.description
        case .direction(let direction):
            return "\(direction)"
        case .unspecified:
            return "unspecified"
        }
    }
}

public enum SwipeGestureSelection: Sendable, Equatable, CustomStringConvertible {
    case unitElement(ElementTarget, start: UnitPoint, end: UnitPoint)
    case point(start: GesturePointSelection, destination: SwipeDestinationSelection)

    public var description: String {
        switch self {
        case .unitElement(let target, let start, let end):
            return ScoreDescription.call("unitSwipe", [
                target.description,
                "start=\(start)",
                "end=\(end)",
            ])
        case .point(let start, let destination):
            return ScoreDescription.call("pointSwipe", [
                "start=\(start)",
                "destination=\(destination)",
            ])
        }
    }
}

private func makeGesturePointSelection(
    elementTarget: ElementTarget?,
    x: Double?,
    y: Double?,
    field: String
) throws -> GesturePointSelection {
    if let elementTarget {
        return .element(elementTarget)
    }
    if let x, let y {
        return .coordinate(ScreenPoint(x: x, y: y))
    }
    if x != nil || y != nil {
        throw GestureProjectionError.partialCoordinate(field: field, xPresent: x != nil, yPresent: y != nil)
    }
    return .unspecified
}

private enum GesturePointCodingKeys: String, CodingKey {
    case pointX
    case pointY
}

private enum GestureCenterCodingKeys: String, CodingKey {
    case centerX
    case centerY
}

private func decodeGesturePointSelection(from decoder: Decoder) throws -> GesturePointSelection {
    let elementTarget = try ElementTarget.decodeInlineIfPresent(from: decoder)
    let container = try decoder.container(keyedBy: GesturePointCodingKeys.self)
    let pointX = try container.decodeIfPresent(Double.self, forKey: .pointX)
    let pointY = try container.decodeIfPresent(Double.self, forKey: .pointY)
    if elementTarget != nil, pointX != nil || pointY != nil {
        throw GestureProjectionError.mixedCoordinateAndElement(field: "point")
    }
    return try makeGesturePointSelection(elementTarget: elementTarget, x: pointX, y: pointY, field: "point")
}

private func encodeGesturePointSelection(_ selection: GesturePointSelection, to encoder: Encoder) throws {
    switch selection {
    case .element(let target):
        try target.encode(to: encoder)
    case .coordinate(let point):
        var container = encoder.container(keyedBy: GesturePointCodingKeys.self)
        try container.encode(point.x, forKey: .pointX)
        try container.encode(point.y, forKey: .pointY)
    case .unspecified:
        break
    }
}

private func decodeGestureCenterSelection(from decoder: Decoder) throws -> GesturePointSelection {
    let elementTarget = try ElementTarget.decodeInlineIfPresent(from: decoder)
    let container = try decoder.container(keyedBy: GestureCenterCodingKeys.self)
    let centerX = try container.decodeIfPresent(Double.self, forKey: .centerX)
    let centerY = try container.decodeIfPresent(Double.self, forKey: .centerY)
    if elementTarget != nil, centerX != nil || centerY != nil {
        throw GestureProjectionError.mixedCoordinateAndElement(field: "center")
    }
    return try makeGesturePointSelection(elementTarget: elementTarget, x: centerX, y: centerY, field: "center")
}

private func encodeGestureCenterSelection(_ selection: GesturePointSelection, to encoder: Encoder) throws {
    switch selection {
    case .element(let target):
        try target.encode(to: encoder)
    case .coordinate(let point):
        var container = encoder.container(keyedBy: GestureCenterCodingKeys.self)
        try container.encode(point.x, forKey: .centerX)
        try container.encode(point.y, forKey: .centerY)
    case .unspecified:
        break
    }
}

private func uncheckedGesturePointSelection(
    elementTarget: ElementTarget?,
    x: Double?,
    y: Double?
) -> GesturePointSelection {
    if let elementTarget {
        return .element(elementTarget)
    }
    if let x, let y {
        return .coordinate(ScreenPoint(x: x, y: y))
    }
    return .unspecified
}

private func swipeDestinationSelection(
    x: Double?,
    y: Double?,
    direction: SwipeDirection?
) throws -> SwipeDestinationSelection {
    if let x, let y {
        return .coordinate(ScreenPoint(x: x, y: y))
    }
    if x != nil || y != nil {
        throw GestureProjectionError.partialCoordinate(field: "endPoint", xPresent: x != nil, yPresent: y != nil)
    }
    if let direction {
        return .direction(direction)
    }
    return .unspecified
}

/// Target for a tap gesture — either an `ElementTarget` (tap at its activation
/// point) or explicit screen coordinates.
public struct TouchTapTarget: Codable, Sendable {
    public let selection: GesturePointSelection

    public init(selection: GesturePointSelection = .unspecified) {
        self.selection = selection
    }

    public init(elementTarget: ElementTarget? = nil, pointX: Double? = nil, pointY: Double? = nil) {
        self.selection = uncheckedGesturePointSelection(elementTarget: elementTarget, x: pointX, y: pointY)
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

    public func gesturePointSelection() throws -> GesturePointSelection {
        selection
    }

    public init(from decoder: Decoder) throws {
        self.selection = try decodeGesturePointSelection(from: decoder)
    }

    public func encode(to encoder: Encoder) throws {
        try encodeGesturePointSelection(selection, to: encoder)
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
    private enum CodingKeys: String, CodingKey {
        case duration
    }

    public let selection: GesturePointSelection
    /// Duration in seconds
    public let duration: Double

    public init(selection: GesturePointSelection = .unspecified, duration: Double = 0.5) {
        self.selection = selection
        self.duration = duration
    }

    public init(elementTarget: ElementTarget? = nil, pointX: Double? = nil, pointY: Double? = nil, duration: Double = 0.5) {
        self.selection = uncheckedGesturePointSelection(elementTarget: elementTarget, x: pointX, y: pointY)
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

    public func gesturePointSelection() throws -> GesturePointSelection {
        selection
    }

    public init(from decoder: Decoder) throws {
        self.selection = try decodeGesturePointSelection(from: decoder)
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
    public static let defaultDuration = 0.15

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

    public var resolvedDuration: Double { duration ?? Self.defaultDuration }

    public func gestureSelection() throws -> SwipeGestureSelection {
        if start != nil || end != nil {
            guard let start, let end else {
                throw GestureProjectionError.partialUnitPoints
            }
            guard let elementTarget else {
                throw GestureProjectionError.unitPointsRequireElementTarget
            }
            return .unitElement(elementTarget, start: start, end: end)
        }
        if let direction, let elementTarget, startX == nil, startY == nil, endX == nil, endY == nil {
            return .unitElement(elementTarget, start: direction.defaultStart, end: direction.defaultEnd)
        }
        return .point(
            start: try makeGesturePointSelection(
                elementTarget: elementTarget,
                x: startX,
                y: startY,
                field: "startPoint"
            ),
            destination: try swipeDestinationSelection(x: endX, y: endY, direction: direction)
        )
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
    public static let defaultDuration = 0.5

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

    public var resolvedDuration: Double { duration ?? Self.defaultDuration }

    public func startSelection() throws -> GesturePointSelection {
        try makeGesturePointSelection(
            elementTarget: elementTarget,
            x: startX,
            y: startY,
            field: "startPoint"
        )
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
    public static let defaultSpread = 100.0
    public static let defaultDuration = 0.5

    private enum CodingKeys: String, CodingKey {
        case scale
        case spread
        case duration
    }

    public let center: GesturePointSelection
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
        self.center = uncheckedGesturePointSelection(elementTarget: elementTarget, x: centerX, y: centerY)
        self.scale = scale; self.spread = spread
        self.duration = duration
    }

    public init(
        center: GesturePointSelection = .unspecified,
        scale: Double, spread: Double? = nil, duration: Double? = nil
    ) {
        self.center = center
        self.scale = scale; self.spread = spread
        self.duration = duration
    }

    public var elementTarget: ElementTarget? {
        center.elementTarget
    }

    public var centerX: Double? {
        center.pointX
    }

    public var centerY: Double? {
        center.pointY
    }

    public var resolvedSpread: Double { spread ?? Self.defaultSpread }
    public var resolvedDuration: Double { duration ?? Self.defaultDuration }

    public func centerSelection() throws -> GesturePointSelection {
        center
    }

    public init(from decoder: Decoder) throws {
        self.center = try decodeGestureCenterSelection(from: decoder)
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
    public static let defaultRadius = 100.0
    public static let defaultDuration = 0.5

    private enum CodingKeys: String, CodingKey {
        case angle
        case radius
        case duration
    }

    public let center: GesturePointSelection
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
        self.center = uncheckedGesturePointSelection(elementTarget: elementTarget, x: centerX, y: centerY)
        self.angle = angle; self.radius = radius
        self.duration = duration
    }

    public init(
        center: GesturePointSelection = .unspecified,
        angle: Double, radius: Double? = nil, duration: Double? = nil
    ) {
        self.center = center
        self.angle = angle; self.radius = radius
        self.duration = duration
    }

    public var elementTarget: ElementTarget? {
        center.elementTarget
    }

    public var centerX: Double? {
        center.pointX
    }

    public var centerY: Double? {
        center.pointY
    }

    public var resolvedRadius: Double { radius ?? Self.defaultRadius }
    public var resolvedDuration: Double { duration ?? Self.defaultDuration }

    public func centerSelection() throws -> GesturePointSelection {
        center
    }

    public init(from decoder: Decoder) throws {
        self.center = try decodeGestureCenterSelection(from: decoder)
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
    public static let defaultSpread = 40.0

    private enum CodingKeys: String, CodingKey {
        case spread
    }

    public let center: GesturePointSelection
    /// Distance between the two fingers in points
    public let spread: Double?

    public init(
        elementTarget: ElementTarget? = nil,
        centerX: Double? = nil, centerY: Double? = nil,
        spread: Double? = nil
    ) {
        self.center = uncheckedGesturePointSelection(elementTarget: elementTarget, x: centerX, y: centerY)
        self.spread = spread
    }

    public init(center: GesturePointSelection = .unspecified, spread: Double? = nil) {
        self.center = center
        self.spread = spread
    }

    public var elementTarget: ElementTarget? {
        center.elementTarget
    }

    public var centerX: Double? {
        center.pointX
    }

    public var centerY: Double? {
        center.pointY
    }

    public var resolvedSpread: Double { spread ?? Self.defaultSpread }

    public func centerSelection() throws -> GesturePointSelection {
        center
    }

    public init(from decoder: Decoder) throws {
        self.center = try decodeGestureCenterSelection(from: decoder)
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
    public static let defaultSamplesPerSegment = 20
    public static let maxSamplesPerSegment = 1_000

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
