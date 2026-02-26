import Foundation
import CoreGraphics

// MARK: - Server -> Client Messages

public enum ServerMessage: Codable {
    /// Server requires authentication (sent immediately on connection)
    case authRequired

    /// Authentication failed (sent before disconnect)
    case authFailed(String)

    /// Authentication approved via on-device UI — includes token for future reconnections
    case authApproved(AuthApprovedPayload)

    /// Server info on connection
    case info(ServerInfo)

    /// Interface (UI element hierarchy) response/update
    case interface(Interface)

    /// Pong response
    case pong

    /// Error message
    case error(String)

    /// Result of an action command
    case actionResult(ActionResult)

    /// Screen capture response with PNG data
    case screen(ScreenPayload)

    /// Session is locked by another driver (sent before disconnect)
    case sessionLocked(SessionLockedPayload)

    // MARK: - Recording Responses

    /// Recording has started
    case recordingStarted

    /// Recording stop acknowledged — payload arrives via broadcast
    case recordingStopped

    /// Recording complete with video data
    case recording(RecordingPayload)

    /// Recording failed or was not active
    case recordingError(String)
}

// MARK: - Action Results

public struct ActionResult: Codable, Sendable {
    public let success: Bool
    public let method: ActionMethod
    public let message: String?
    /// Current text field value after a typeText operation
    public let value: String?
    /// Compact delta describing what changed in the hierarchy after the action
    public let interfaceDelta: InterfaceDelta?
    /// Whether the UI was still animating when this result was produced.
    /// nil means idle (no animations detected).
    public let animating: Bool?

    public init(
        success: Bool,
        method: ActionMethod,
        message: String? = nil,
        value: String? = nil,
        interfaceDelta: InterfaceDelta? = nil,
        animating: Bool? = nil
    ) {
        self.success = success
        self.method = method
        self.message = message
        self.value = value
        self.interfaceDelta = interfaceDelta
        self.animating = animating
    }
}

// MARK: - Interface Delta

/// Compact description of what changed in the accessibility hierarchy after an action.
public struct InterfaceDelta: Codable, Sendable {
    /// What kind of change occurred
    public let kind: DeltaKind

    /// Total element count after the action
    public let elementCount: Int

    /// Elements that were added (present for .elementsChanged)
    public let added: [HeistElement]?

    /// Orders of elements that were removed (present for .elementsChanged)
    public let removedOrders: [Int]?

    /// Value changes on existing elements (present for .valuesChanged or .elementsChanged)
    public let valueChanges: [ValueChange]?

    /// Full new interface (present only for .screenChanged)
    public let newInterface: Interface?

    public init(
        kind: DeltaKind,
        elementCount: Int,
        added: [HeistElement]? = nil,
        removedOrders: [Int]? = nil,
        valueChanges: [ValueChange]? = nil,
        newInterface: Interface? = nil
    ) {
        self.kind = kind
        self.elementCount = elementCount
        self.added = added
        self.removedOrders = removedOrders
        self.valueChanges = valueChanges
        self.newInterface = newInterface
    }

    public enum DeltaKind: String, Codable, Sendable {
        case noChange
        case valuesChanged
        case elementsChanged
        case screenChanged
    }
}

/// A single value change on an element
public struct ValueChange: Codable, Sendable {
    public let order: Int
    public let identifier: String?
    public let oldValue: String?
    public let newValue: String?

    public init(order: Int, identifier: String?, oldValue: String?, newValue: String?) {
        self.order = order
        self.identifier = identifier
        self.oldValue = oldValue
        self.newValue = newValue
    }
}

/// Payload containing screen capture data
public struct ScreenPayload: Codable, Sendable {
    /// Base64-encoded PNG data
    public let pngData: String
    /// Screen width in points
    public let width: Double
    /// Screen height in points
    public let height: Double
    /// Timestamp when screen was captured
    public let timestamp: Date

    public init(pngData: String, width: Double, height: Double, timestamp: Date = Date()) {
        self.pngData = pngData
        self.width = width
        self.height = height
        self.timestamp = timestamp
    }
}

/// Payload containing screen recording video data
public struct RecordingPayload: Codable, Sendable {
    /// Base64-encoded MP4 video data (H.264)
    public let videoData: String
    /// Video width in pixels
    public let width: Int
    /// Video height in pixels
    public let height: Int
    /// Recording duration in seconds
    public let duration: Double
    /// Number of frames captured
    public let frameCount: Int
    /// Frames per second used during recording
    public let fps: Int
    /// Timestamp when recording started
    public let startTime: Date
    /// Timestamp when recording ended
    public let endTime: Date
    /// Reason recording stopped
    public let stopReason: StopReason

    public enum StopReason: String, Codable, Sendable {
        case manual
        case inactivity
        case maxDuration
        case fileSizeLimit
    }

    /// Ordered log of interactions recorded during this session (nil if no interactions occurred)
    public let interactionLog: [InteractionEvent]?

    public init(
        videoData: String,
        width: Int,
        height: Int,
        duration: Double,
        frameCount: Int,
        fps: Int,
        startTime: Date,
        endTime: Date,
        stopReason: StopReason,
        interactionLog: [InteractionEvent]? = nil
    ) {
        self.videoData = videoData
        self.width = width
        self.height = height
        self.duration = duration
        self.frameCount = frameCount
        self.fps = fps
        self.startTime = startTime
        self.endTime = endTime
        self.stopReason = stopReason
        self.interactionLog = interactionLog
    }
}

/// A single recorded interaction event captured during a TheStakeout recording.
/// Uses `InterfaceDelta` instead of full before/after `Interface` snapshots to minimize payload size.
public struct InteractionEvent: Codable, Sendable {
    /// Time offset from recording start in seconds
    public let timestamp: Double
    /// The command that triggered this interaction
    public let command: ClientMessage
    /// The result returned to the client
    public let result: ActionResult
    /// Compact delta describing what changed in the hierarchy (from result.interfaceDelta)
    public let interfaceDelta: InterfaceDelta?

    public init(
        timestamp: Double,
        command: ClientMessage,
        result: ActionResult,
        interfaceDelta: InterfaceDelta? = nil
    ) {
        self.timestamp = timestamp
        self.command = command
        self.result = result
        self.interfaceDelta = interfaceDelta
    }
}

public enum ActionMethod: String, Codable, Sendable {
    case activate
    case increment
    case decrement
    case syntheticTap
    case syntheticLongPress
    case syntheticSwipe
    case syntheticDrag
    case syntheticPinch
    case syntheticRotate
    case syntheticTwoFingerTap
    case syntheticDrawPath
    case typeText
    case customAction
    case editAction
    case resignFirstResponder
    case waitForIdle
    case scroll
    case scrollToVisible
    case scrollToEdge
    case elementNotFound
    case elementDeallocated
}

/// Payload sent when a connection is approved via the on-device UI
public struct AuthApprovedPayload: Codable, Sendable {
    public let token: String
    public init(token: String) { self.token = token }
}

public struct ServerInfo: Codable, Sendable {
    public let protocolVersion: String
    public let appName: String
    public let bundleIdentifier: String
    public let deviceName: String
    public let systemVersion: String
    public let screenWidth: Double
    public let screenHeight: Double
    /// Per-launch session identifier (nil for servers < v2.1)
    public let instanceId: String?
    /// Human-readable instance identifier (from INSIDEJOB_ID env var, or shortId fallback)
    public let instanceIdentifier: String?
    /// Port the server is listening on (nil for servers < v2.1)
    public let listeningPort: UInt16?
    /// Simulator UDID when running on iOS Simulator (nil on physical devices)
    public let simulatorUDID: String?
    /// Vendor identifier from UIDevice.identifierForVendor (stable per app install per device)
    public let vendorIdentifier: String?

    public init(
        protocolVersion: String,
        appName: String,
        bundleIdentifier: String,
        deviceName: String,
        systemVersion: String,
        screenWidth: Double,
        screenHeight: Double,
        instanceId: String? = nil,
        instanceIdentifier: String? = nil,
        listeningPort: UInt16? = nil,
        simulatorUDID: String? = nil,
        vendorIdentifier: String? = nil
    ) {
        self.protocolVersion = protocolVersion
        self.appName = appName
        self.bundleIdentifier = bundleIdentifier
        self.deviceName = deviceName
        self.systemVersion = systemVersion
        self.screenWidth = screenWidth
        self.screenHeight = screenHeight
        self.instanceId = instanceId
        self.instanceIdentifier = instanceIdentifier
        self.listeningPort = listeningPort
        self.simulatorUDID = simulatorUDID
        self.vendorIdentifier = vendorIdentifier
    }
}

extension ServerInfo {
    /// Computed screen size as CGSize
    public var screenSize: CGSize {
        CGSize(width: screenWidth, height: screenHeight)
    }
}
