import Foundation
import CoreGraphics

// MARK: - Request Envelope

/// Wraps a client message with an optional request ID for response correlation.
/// When `requestId` is present, the server echoes it in the corresponding response
/// so the client can match request-response pairs. Push broadcasts have no requestId.
public struct RequestEnvelope: Codable, Sendable {
    public let protocolVersion: String
    public let requestId: String?
    public let message: ClientMessage

    public init(requestId: String? = nil, message: ClientMessage) {
        self.init(wireProtocolVersion: TheScore.protocolVersion, requestId: requestId, message: message)
    }

    public init(wireProtocolVersion: String, requestId: String? = nil, message: ClientMessage) {
        self.protocolVersion = wireProtocolVersion
        self.requestId = requestId
        self.message = message
    }
}

// MARK: - Client -> Server Messages

public enum ClientMessage: Codable, Sendable {
    /// Version-negotiation hello sent immediately after receiving serverHello.
    case clientHello

    /// Authenticate with a token (sent after clientHello handshake completes)
    case authenticate(AuthenticatePayload)

    /// Request current interface (UI element hierarchy)
    case requestInterface

    /// Subscribe to automatic updates
    case subscribe

    /// Unsubscribe from automatic updates
    case unsubscribe

    /// Ping for keepalive
    case ping

    /// Lightweight status probe (identity + availability, no session claim)
    case status

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

    /// Scroll via accessibility scroll action (bubbles up to nearest scroll view)
    case scroll(ScrollTarget)

    /// Scroll the nearest scroll view ancestor until an element matching the predicate is visible
    case scrollToVisible(ScrollToVisibleTarget)

    /// Scroll the nearest scroll view ancestor to an edge (top, bottom, left, right)
    case scrollToEdge(ScrollToEdgeTarget)

    /// Resign first responder (dismiss keyboard)
    case resignFirstResponder

    /// Write text to the general pasteboard (in-app, avoids paste dialog for subsequent reads)
    case setPasteboard(SetPasteboardTarget)

    /// Read text from the general pasteboard
    case getPasteboard

    /// Wait for all animations to complete, then return the settled interface
    case waitForIdle(WaitForIdleTarget)

    /// Request a capture of the current screen
    case requestScreen

    // MARK: - Recording Commands

    /// Start recording the screen
    case startRecording(RecordingConfig)

    /// Stop an in-progress recording
    case stopRecording

    // MARK: - Watch (Observer) Commands

    /// Connect as a read-only observer (no session lock)
    case watch(WatchPayload)

    /// Extract the element target from any action command, if present.
    public var actionTarget: ActionTarget? {
        switch self {
        case .activate(let t), .increment(let t), .decrement(let t):
            return t
        case .scrollToVisible:
            return nil
        case .performCustomAction(let t):
            return t.elementTarget
        case .editAction:
            return nil
        case .touchTap(let t):
            return t.elementTarget
        case .touchLongPress(let t):
            return t.elementTarget
        case .touchSwipe(let t):
            return t.elementTarget
        case .touchDrag(let t):
            return t.elementTarget
        case .touchPinch(let t):
            return t.elementTarget
        case .touchRotate(let t):
            return t.elementTarget
        case .touchTwoFingerTap(let t):
            return t.elementTarget
        case .touchDrawPath:
            return nil
        case .touchDrawBezier:
            return nil
        case .typeText(let t):
            return t.elementTarget
        case .scroll(let t):
            return t.elementTarget
        case .scrollToEdge(let t):
            return t.elementTarget
        default:
            return nil
        }
    }
}

// MARK: - Action Targets

/// Target for element actions
public struct ActionTarget: Codable, Sendable {
    /// Developer-provided accessibility identifier (most stable)
    public let identifier: String?
    /// Synthesized stable ID from traits + label (stable across reorders)
    public let heistId: String?
    /// Element order in current snapshot (positional, fragile)
    public let order: Int?

    public init(identifier: String? = nil, heistId: String? = nil, order: Int? = nil) {
        self.identifier = identifier
        self.heistId = heistId
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
    /// Clear all existing text before typing. Uses UITextInput select-all + delete
    /// for a clean replacement without needing to know the current field length.
    public let clearFirst: Bool?
    /// Optional element to tap first to bring up keyboard (text field).
    /// Also used to read back the current value after typing.
    public let elementTarget: ActionTarget?

    public init(text: String? = nil, deleteCount: Int? = nil, clearFirst: Bool? = nil, elementTarget: ActionTarget? = nil) {
        self.text = text
        self.deleteCount = deleteCount
        self.clearFirst = clearFirst
        self.elementTarget = elementTarget
    }
}

/// Standard edit actions that can be dispatched via the responder chain.
public enum EditAction: String, Codable, Sendable, CaseIterable {
    case copy, paste, cut, select, selectAll
}

/// Target for writing text to the general pasteboard.
public struct SetPasteboardTarget: Codable, Sendable {
    /// Text to write to the pasteboard
    public let text: String

    public init(text: String) {
        self.text = text
    }
}

/// Target for edit actions dispatched via the responder chain
public struct EditActionTarget: Codable, Sendable {
    /// The edit action to perform
    public let action: EditAction

    public init(action: EditAction) {
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
    /// Unique driver identity for session locking. When set, the server uses this
    /// (instead of the auth token) to distinguish drivers. Set via BUTTONHEIST_DRIVER_ID.
    public let driverId: String?
    public init(token: String, driverId: String? = nil) {
        self.token = token
        self.driverId = driverId
    }
}

/// Information about the active session that is blocking this connection
public struct SessionLockedPayload: Codable, Sendable {
    public let message: String
    public let activeConnections: Int

    public init(message: String, activeConnections: Int) {
        self.message = message
        self.activeConnections = activeConnections
    }
}

/// Payload for watch (observer) connections
public struct WatchPayload: Codable, Sendable {
    /// Optional auth token. When empty and server allows open watch, auto-approved.
    /// When empty and server restricts watch, triggers UI approval prompt.
    public let token: String
    public init(token: String = "") {
        self.token = token
    }
}

/// Configuration for screen recording
public struct RecordingConfig: Codable, Sendable {
    /// Frames per second (default: 8, range: 1-15)
    public let fps: Int?
    /// Resolution scale relative to native pixels (0.25-1.0).
    /// Default: nil — uses 1x point resolution (native pixels / screen scale).
    /// 1.0 = full native resolution (no reduction).
    public let scale: Double?
    /// Inactivity timeout in seconds — auto-stop when no screen changes
    /// and no commands received for this duration (default: 5.0)
    public let inactivityTimeout: Double?
    /// Maximum recording duration in seconds as a hard safety cap (default: 60.0)
    public let maxDuration: Double?

    public init(
        fps: Int? = nil,
        scale: Double? = nil,
        inactivityTimeout: Double? = nil,
        maxDuration: Double? = nil
    ) {
        self.fps = fps
        self.scale = scale
        self.inactivityTimeout = inactivityTimeout
        self.maxDuration = maxDuration
    }
}

/// Direction for swipe gestures
public enum SwipeDirection: String, Codable, Sendable {
    case up, down, left, right
}

/// Direction for scroll actions
public enum ScrollDirection: String, Codable, Sendable {
    case up, down, left, right, next, previous
}

/// Target for scroll command
public struct ScrollTarget: Codable, Sendable {
    /// Element to scroll from (bubbles up to nearest scroll view ancestor)
    public let elementTarget: ActionTarget?
    /// Scroll direction
    public let direction: ScrollDirection

    public init(elementTarget: ActionTarget? = nil, direction: ScrollDirection) {
        self.elementTarget = elementTarget
        self.direction = direction
    }
}

/// Direction for scroll-to-visible search
public enum ScrollSearchDirection: String, Codable, Sendable, CaseIterable {
    case down, up, left, right
}

/// Target for scroll-to-visible search with element matching
public struct ScrollToVisibleTarget: Codable, Sendable {
    /// Predicate describing the element to find
    public let match: ElementMatcher
    /// Maximum scroll attempts before giving up (default: 20)
    public let maxScrolls: Int?
    /// Starting scroll direction (default: .down)
    public let direction: ScrollSearchDirection?

    public init(
        match: ElementMatcher,
        maxScrolls: Int? = nil,
        direction: ScrollSearchDirection? = nil
    ) {
        self.match = match
        self.maxScrolls = maxScrolls
        self.direction = direction
    }

    public var resolvedMaxScrolls: Int { max(maxScrolls ?? 20, 1) }
    public var resolvedDirection: ScrollSearchDirection { direction ?? .down }
}

/// Edge for scroll-to-edge commands
public enum ScrollEdge: String, Codable, Sendable {
    case top, bottom, left, right
}

/// Target for scroll-to-edge command
public struct ScrollToEdgeTarget: Codable, Sendable {
    /// Element whose nearest scroll view ancestor to scroll
    public let elementTarget: ActionTarget?
    /// Which edge to scroll to
    public let edge: ScrollEdge

    public init(elementTarget: ActionTarget? = nil, edge: ScrollEdge) {
        self.elementTarget = elementTarget
        self.edge = edge
    }
}
