import Foundation
import CoreGraphics

// MARK: - Client -> Server Messages

public enum ClientMessage: Codable {
    /// Authenticate with a token (must be first message sent)
    case authenticate(AuthenticatePayload)

    /// Request current interface (UI element hierarchy)
    case requestInterface

    /// Subscribe to automatic updates
    case subscribe

    /// Unsubscribe from automatic updates
    case unsubscribe

    /// Ping for keepalive
    case ping

    // MARK: - Action Commands

    /// Activate an element
    case activate(ActionTarget)

    /// Increment an adjustable element (e.g., slider)
    case increment(ActionTarget)

    /// Decrement an adjustable element
    case decrement(ActionTarget)

    /// Perform a custom action on an element
    case performCustomAction(CustomActionTarget)

    // MARK: - Touch Gesture Commands

    /// Tap at a point or element
    case touchTap(TouchTapTarget)

    /// Long press at a point or element
    case touchLongPress(LongPressTarget)

    /// Swipe from one point to another
    case touchSwipe(SwipeTarget)

    /// Drag from one point to another
    case touchDrag(DragTarget)

    /// Pinch/zoom gesture
    case touchPinch(PinchTarget)

    /// Rotation gesture
    case touchRotate(RotateTarget)

    /// Two-finger tap
    case touchTwoFingerTap(TwoFingerTapTarget)

    /// Draw along a path (sequence of points)
    case touchDrawPath(DrawPathTarget)

    /// Draw along a bezier curve (sampled to polyline server-side)
    case touchDrawBezier(DrawBezierTarget)

    /// Type text character-by-character by tapping keyboard keys
    case typeText(TypeTextTarget)

    /// Perform a standard edit action (copy, paste, cut, select, selectAll) on the first responder
    case editAction(EditActionTarget)

    /// Resign first responder (dismiss keyboard)
    case resignFirstResponder

    /// Wait for all animations to complete, then return the settled interface
    case waitForIdle(WaitForIdleTarget)

    /// Request a capture of the current screen
    case requestScreen
}

// MARK: - Action Targets

/// Target for element actions
public struct ActionTarget: Codable, Sendable {
    /// Element identifier
    public let identifier: String?
    /// Element order (alternative to identifier)
    public let order: Int?

    public init(identifier: String? = nil, order: Int? = nil) {
        self.identifier = identifier
        self.order = order
    }
}

/// Target for custom actions
public struct CustomActionTarget: Codable, Sendable {
    public let elementTarget: ActionTarget
    public let actionName: String

    public init(elementTarget: ActionTarget, actionName: String) {
        self.elementTarget = elementTarget
        self.actionName = actionName
    }
}

// MARK: - Touch Gesture Targets

/// Target for tap gesture
public struct TouchTapTarget: Codable, Sendable {
    /// Use element's interaction point
    public let elementTarget: ActionTarget?
    /// Or specify exact screen coordinates
    public let pointX: Double?
    public let pointY: Double?

    public init(elementTarget: ActionTarget? = nil, pointX: Double? = nil, pointY: Double? = nil) {
        self.elementTarget = elementTarget
        self.pointX = pointX
        self.pointY = pointY
    }

    public var point: CGPoint? {
        guard let x = pointX, let y = pointY else { return nil }
        return CGPoint(x: x, y: y)
    }
}

/// Target for long press gesture
public struct LongPressTarget: Codable, Sendable {
    public let elementTarget: ActionTarget?
    public let pointX: Double?
    public let pointY: Double?
    /// Duration in seconds
    public let duration: Double

    public init(elementTarget: ActionTarget? = nil, pointX: Double? = nil, pointY: Double? = nil, duration: Double = 0.5) {
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

/// Target for swipe gesture
public struct SwipeTarget: Codable, Sendable {
    /// Start from element's interaction point
    public let elementTarget: ActionTarget?
    /// Or start from explicit coordinates
    public let startX: Double?
    public let startY: Double?
    /// End coordinates (required if not using direction)
    public let endX: Double?
    public let endY: Double?
    /// Or use direction + distance from start point
    public let direction: SwipeDirection?
    public let distance: Double?
    /// Duration in seconds (default 0.15)
    public let duration: Double?

    public init(
        elementTarget: ActionTarget? = nil,
        startX: Double? = nil, startY: Double? = nil,
        endX: Double? = nil, endY: Double? = nil,
        direction: SwipeDirection? = nil, distance: Double? = nil,
        duration: Double? = nil
    ) {
        self.elementTarget = elementTarget
        self.startX = startX; self.startY = startY
        self.endX = endX; self.endY = endY
        self.direction = direction; self.distance = distance
        self.duration = duration
    }

    public var startPoint: CGPoint? {
        guard let x = startX, let y = startY else { return nil }
        return CGPoint(x: x, y: y)
    }
}

/// Target for drag gesture
public struct DragTarget: Codable, Sendable {
    public let elementTarget: ActionTarget?
    public let startX: Double?
    public let startY: Double?
    public let endX: Double
    public let endY: Double
    /// Duration in seconds (default 0.5)
    public let duration: Double?

    public init(
        elementTarget: ActionTarget? = nil,
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

/// Target for pinch/zoom gesture
public struct PinchTarget: Codable, Sendable {
    public let elementTarget: ActionTarget?
    public let centerX: Double?
    public let centerY: Double?
    /// Scale factor: >1.0 zooms in (spread), <1.0 zooms out (pinch)
    public let scale: Double
    /// Initial distance from center to each finger in points
    public let spread: Double?
    /// Duration in seconds (default 0.5)
    public let duration: Double?

    public init(
        elementTarget: ActionTarget? = nil,
        centerX: Double? = nil, centerY: Double? = nil,
        scale: Double, spread: Double? = nil, duration: Double? = nil
    ) {
        self.elementTarget = elementTarget
        self.centerX = centerX; self.centerY = centerY
        self.scale = scale; self.spread = spread
        self.duration = duration
    }
}

/// Target for rotation gesture
public struct RotateTarget: Codable, Sendable {
    public let elementTarget: ActionTarget?
    public let centerX: Double?
    public let centerY: Double?
    /// Rotation angle in radians (positive = counter-clockwise)
    public let angle: Double
    /// Distance from center to each finger in points
    public let radius: Double?
    /// Duration in seconds (default 0.5)
    public let duration: Double?

    public init(
        elementTarget: ActionTarget? = nil,
        centerX: Double? = nil, centerY: Double? = nil,
        angle: Double, radius: Double? = nil, duration: Double? = nil
    ) {
        self.elementTarget = elementTarget
        self.centerX = centerX; self.centerY = centerY
        self.angle = angle; self.radius = radius
        self.duration = duration
    }
}

/// Target for two-finger tap gesture
public struct TwoFingerTapTarget: Codable, Sendable {
    public let elementTarget: ActionTarget?
    public let centerX: Double?
    public let centerY: Double?
    /// Distance between the two fingers in points
    public let spread: Double?

    public init(
        elementTarget: ActionTarget? = nil,
        centerX: Double? = nil, centerY: Double? = nil,
        spread: Double? = nil
    ) {
        self.elementTarget = elementTarget
        self.centerX = centerX; self.centerY = centerY
        self.spread = spread
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

/// Target for typing text character-by-character via keyboard key taps
public struct TypeTextTarget: Codable, Sendable {
    /// Text to type (each character is tapped individually). Can be nil if only deleting.
    public let text: String?
    /// Number of times to tap the delete key before typing. Used for corrections.
    public let deleteCount: Int?
    /// Optional element to tap first to bring up keyboard (text field).
    /// Also used to read back the current value after typing.
    public let elementTarget: ActionTarget?

    public init(text: String? = nil, deleteCount: Int? = nil, elementTarget: ActionTarget? = nil) {
        self.text = text
        self.deleteCount = deleteCount
        self.elementTarget = elementTarget
    }
}

/// Target for edit actions dispatched via the responder chain
public struct EditActionTarget: Codable, Sendable {
    /// The edit action to perform: "copy", "paste", "cut", "select", "selectAll"
    public let action: String

    public init(action: String) {
        self.action = action
    }
}

/// Target for waitForIdle command
public struct WaitForIdleTarget: Codable, Sendable {
    /// Maximum time to wait in seconds (default 5.0)
    public let timeout: Double?

    public init(timeout: Double? = nil) {
        self.timeout = timeout
    }
}

/// Payload for authenticate message
public struct AuthenticatePayload: Codable, Sendable {
    public let token: String
    public init(token: String) { self.token = token }
}

/// Direction for swipe gestures
public enum SwipeDirection: String, Codable, Sendable {
    case up, down, left, right
}
