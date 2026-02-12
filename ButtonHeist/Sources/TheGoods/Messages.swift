import Foundation
import CoreGraphics

/// Bonjour service type for discovery
public let buttonHeistServiceType = "_buttonheist._tcp"

/// Protocol version for compatibility checking
public let protocolVersion = "2.0"

// MARK: - Client -> Server Messages

public enum ClientMessage: Codable {
    /// Request current accessibility hierarchy
    case requestHierarchy

    /// Subscribe to automatic updates
    case subscribe

    /// Unsubscribe from automatic updates
    case unsubscribe

    /// Ping for keepalive
    case ping

    // MARK: - Action Commands

    /// Activate an element (equivalent to VoiceOver double-tap)
    case activate(ActionTarget)

    /// Increment an adjustable element (e.g., slider)
    case increment(ActionTarget)

    /// Decrement an adjustable element
    case decrement(ActionTarget)

    /// Perform a custom action on an element
    case performCustomAction(CustomActionTarget)

    // MARK: - Touch Gesture Commands

    /// Tap at a point or element's activation point
    case touchTap(TouchTapTarget)

    /// Long press at a point or element's activation point
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

    /// Request a screenshot of the current screen
    case requestScreenshot
}

// MARK: - Action Targets

/// Target for accessibility actions
public struct ActionTarget: Codable, Sendable {
    /// Element identifier (accessibilityIdentifier)
    public let identifier: String?
    /// Traversal index (alternative to identifier)
    public let traversalIndex: Int?

    public init(identifier: String? = nil, traversalIndex: Int? = nil) {
        self.identifier = identifier
        self.traversalIndex = traversalIndex
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
    /// Use element's activation point
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
    /// Start from element's activation point
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

/// Direction for swipe gestures
public enum SwipeDirection: String, Codable, Sendable {
    case up, down, left, right
}

// MARK: - Server -> Client Messages

public enum ServerMessage: Codable {
    /// Server info on connection
    case info(ServerInfo)

    /// Accessibility hierarchy response/update
    case hierarchy(HierarchyPayload)

    /// Pong response
    case pong

    /// Error message
    case error(String)

    /// Result of an action command
    case actionResult(ActionResult)

    /// Screenshot response with PNG data
    case screenshot(ScreenshotPayload)
}

// MARK: - Action Results

public struct ActionResult: Codable, Sendable {
    public let success: Bool
    public let method: ActionMethod
    public let message: String?

    public init(success: Bool, method: ActionMethod, message: String? = nil) {
        self.success = success
        self.method = method
        self.message = message
    }
}

/// Payload containing screenshot data
public struct ScreenshotPayload: Codable, Sendable {
    /// Base64-encoded PNG data
    public let pngData: String
    /// Screen width in points
    public let width: Double
    /// Screen height in points
    public let height: Double
    /// Timestamp when screenshot was taken
    public let timestamp: Date

    public init(pngData: String, width: Double, height: Double, timestamp: Date = Date()) {
        self.pngData = pngData
        self.width = width
        self.height = height
        self.timestamp = timestamp
    }
}

public enum ActionMethod: String, Codable, Sendable {
    case accessibilityActivate
    case accessibilityIncrement
    case accessibilityDecrement
    case syntheticTap
    case syntheticLongPress
    case syntheticSwipe
    case syntheticDrag
    case syntheticPinch
    case syntheticRotate
    case syntheticTwoFingerTap
    case customAction
    case elementNotFound
    case elementDeallocated
}

public struct ServerInfo: Codable, Sendable {
    public let protocolVersion: String
    public let appName: String
    public let bundleIdentifier: String
    public let deviceName: String
    public let systemVersion: String
    public let screenWidth: Double
    public let screenHeight: Double

    public init(
        protocolVersion: String,
        appName: String,
        bundleIdentifier: String,
        deviceName: String,
        systemVersion: String,
        screenWidth: Double,
        screenHeight: Double
    ) {
        self.protocolVersion = protocolVersion
        self.appName = appName
        self.bundleIdentifier = bundleIdentifier
        self.deviceName = deviceName
        self.systemVersion = systemVersion
        self.screenWidth = screenWidth
        self.screenHeight = screenHeight
    }
}

public struct HierarchyPayload: Codable, Sendable {
    public let timestamp: Date
    public let elements: [AccessibilityElementData]
    /// Optional tree structure for hierarchy display (nil for backwards compatibility)
    public let tree: [AccessibilityHierarchyNode]?

    public init(timestamp: Date, elements: [AccessibilityElementData], tree: [AccessibilityHierarchyNode]? = nil) {
        self.timestamp = timestamp
        self.elements = elements
        self.tree = tree
    }
}

// MARK: - Hierarchy Tree Types

/// Cross-platform container data for accessibility containers
public struct AccessibilityContainerData: Codable, Equatable, Hashable, Sendable {
    /// Container type: "none", "dataTable", "list", "landmark", "semanticGroup"
    public let containerType: String
    /// Container's accessibility label (if any)
    public let label: String?
    /// Container's accessibility value (if any)
    public let value: String?
    /// Container's accessibility identifier (if any)
    public let identifier: String?
    /// Frame coordinates
    public let frameX: Double
    public let frameY: Double
    public let frameWidth: Double
    public let frameHeight: Double
    /// Trait names (e.g., ["tabBar"])
    public let traits: [String]

    public init(
        containerType: String,
        label: String?,
        value: String?,
        identifier: String?,
        frameX: Double,
        frameY: Double,
        frameWidth: Double,
        frameHeight: Double,
        traits: [String]
    ) {
        self.containerType = containerType
        self.label = label
        self.value = value
        self.identifier = identifier
        self.frameX = frameX
        self.frameY = frameY
        self.frameWidth = frameWidth
        self.frameHeight = frameHeight
        self.traits = traits
    }
}

/// A node in the accessibility hierarchy tree (cross-platform)
public indirect enum AccessibilityHierarchyNode: Codable, Equatable, Sendable {
    /// A leaf node representing an accessibility element by its traversal index
    case element(traversalIndex: Int)
    /// A container node grouping children
    case container(AccessibilityContainerData, children: [AccessibilityHierarchyNode])
}

// MARK: - Cross-Platform Element Type

/// Platform-agnostic element data - represents an accessibility element in VoiceOver traversal order
public struct AccessibilityElementData: Codable, Equatable, Hashable, Sendable {
    /// VoiceOver traversal index (0-based)
    public var traversalIndex: Int
    /// The description that VoiceOver will read
    public var description: String
    public var label: String?
    public var value: String?
    public var traits: [String]  // Human-readable trait names
    public var identifier: String?
    public var hint: String?
    public var frameX: Double
    public var frameY: Double
    public var frameWidth: Double
    public var frameHeight: Double
    public var activationPointX: Double
    public var activationPointY: Double
    public var customActions: [String]  // Action names

    public init(
        traversalIndex: Int,
        description: String,
        label: String?,
        value: String?,
        traits: [String],
        identifier: String?,
        hint: String?,
        frameX: Double,
        frameY: Double,
        frameWidth: Double,
        frameHeight: Double,
        activationPointX: Double,
        activationPointY: Double,
        customActions: [String]
    ) {
        self.traversalIndex = traversalIndex
        self.description = description
        self.label = label
        self.value = value
        self.traits = traits
        self.identifier = identifier
        self.hint = hint
        self.frameX = frameX
        self.frameY = frameY
        self.frameWidth = frameWidth
        self.frameHeight = frameHeight
        self.activationPointX = activationPointX
        self.activationPointY = activationPointY
        self.customActions = customActions
    }
}

// MARK: - Convenience Extensions

extension AccessibilityElementData {
    /// Computed frame as CGRect (available on both platforms)
    public var frame: CGRect {
        CGRect(x: frameX, y: frameY, width: frameWidth, height: frameHeight)
    }

    /// Computed activation point as CGPoint
    public var activationPoint: CGPoint {
        CGPoint(x: activationPointX, y: activationPointY)
    }
}

extension ServerInfo {
    /// Computed screen size as CGSize
    public var screenSize: CGSize {
        CGSize(width: screenWidth, height: screenHeight)
    }
}
