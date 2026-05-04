import Foundation
import CoreGraphics

// MARK: - Response Envelope

/// Wraps a server message with the echoed requestId for response correlation.
/// Push broadcasts (subscription updates) use requestId = nil.
public struct ResponseEnvelope: Codable, Sendable {
    public let protocolVersion: String
    public let requestId: String?
    public let message: ServerMessage

    /// Changes that occurred between the previous response and this one — while
    /// the agent was thinking. nil means nothing changed in the background.
    /// Lives on the envelope (not the message) because it's a session-level
    /// concern: any response type can carry it.
    public let backgroundDelta: InterfaceDelta?

    public init(requestId: String? = nil, message: ServerMessage, backgroundDelta: InterfaceDelta? = nil) {
        self.init(wireProtocolVersion: TheScore.protocolVersion, requestId: requestId,
                  message: message, backgroundDelta: backgroundDelta)
    }

    public init(
        wireProtocolVersion: String, requestId: String? = nil,
        message: ServerMessage, backgroundDelta: InterfaceDelta? = nil
    ) {
        self.protocolVersion = wireProtocolVersion
        self.requestId = requestId
        self.message = message
        self.backgroundDelta = backgroundDelta
    }

    /// Encode this envelope to JSON data. Returns nil on encode failure.
    public func encoded() throws -> Data {
        try JSONEncoder().encode(self)
    }
}

// MARK: - Server -> Client Messages

/// Messages sent from the Inside Job server to connected clients.
public enum ServerMessage: Codable, Sendable {
    /// Version-negotiation hello sent immediately on connection.
    case serverHello

    /// Exact protocol version mismatch.
    case protocolMismatch(ProtocolMismatchPayload)

    /// Server requires authentication (sent after successful hello handshake)
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

    // MARK: - Observer Broadcasts

    /// An action was performed by the driver — broadcast to observers
    case interaction(InteractionEvent)

    /// Lightweight server health + identity snapshot.
    /// Returned in response to ClientMessage.status without acquiring a session.
    case status(StatusPayload)
}

/// Sent when the client's protocol version does not match the server's expected version.
public struct ProtocolMismatchPayload: Codable, Sendable {
    public let expectedProtocolVersion: String
    public let receivedProtocolVersion: String

    public init(expectedProtocolVersion: String, receivedProtocolVersion: String) {
        self.expectedProtocolVersion = expectedProtocolVersion
        self.receivedProtocolVersion = receivedProtocolVersion
    }
}

/// Top-level status payload returned by the Inside Job server.
public struct StatusPayload: Codable, Sendable {
    public let identity: StatusIdentity
    public let session: StatusSession

    public init(identity: StatusIdentity, session: StatusSession) {
        self.identity = identity
        self.session = session
    }
}

/// App/device identity for a running Inside Job instance.
public struct StatusIdentity: Codable, Sendable {
    public let appName: String
    public let bundleIdentifier: String
    public let appBuild: String
    public let deviceName: String
    public let systemVersion: String
    public let buttonHeistVersion: String

    public init(
        appName: String,
        bundleIdentifier: String,
        appBuild: String,
        deviceName: String,
        systemVersion: String,
        buttonHeistVersion: String
    ) {
        self.appName = appName
        self.bundleIdentifier = bundleIdentifier
        self.appBuild = appBuild
        self.deviceName = deviceName
        self.systemVersion = systemVersion
        self.buttonHeistVersion = buttonHeistVersion
    }
}

/// Session-level availability information for this instance.
public struct StatusSession: Codable, Sendable {
    /// Whether a driver session is currently active on this instance.
    public let active: Bool
    /// Whether additional watcher connections are allowed for this active session.
    /// When `active == false`, this is always false (no watching inactive sessions).
    public let watchersAllowed: Bool
    /// Number of active connections in the session (driver + watchers).
    public let activeConnections: Int

    public init(
        active: Bool,
        watchersAllowed: Bool,
        activeConnections: Int
    ) {
        self.active = active
        self.watchersAllowed = watchersAllowed
        self.activeConnections = activeConnections
    }
}

// MARK: - Action Results

/// Typed error classification for failed actions.
public enum ErrorKind: String, Codable, Sendable, CaseIterable {
    case elementNotFound
    case timeout
    case unsupported
    case inputError
    case validationError
    case actionFailed
}

/// The outcome of executing an action command, including post-action diagnostics.
public struct ActionResult: Codable, Sendable {
    /// Whether the action was delivered and completed normally. `false` means
    /// the action reached the server but the handler reported failure — it is
    /// not a transport-level error (those surface as thrown errors).
    public let success: Bool
    /// Identifies which server-side handler produced this result (e.g.
    /// `.synthesizedTouch`, `.accessibilityActivate`). Useful when diagnosing
    /// why an action succeeded but had no visible effect.
    public let method: ActionMethod
    public let message: String?
    /// Typed error classification (nil on success)
    public let errorKind: ErrorKind?
    /// Current text field value after a typeText operation
    public let value: String?
    /// Compact delta describing what changed in the hierarchy after the action
    public let interfaceDelta: InterfaceDelta?
    /// Whether the UI was still animating when this result was produced.
    /// nil means idle (no animations detected).
    public let animating: Bool?
    /// Post-action accessibility label of the acted-on element
    public let elementLabel: String?
    /// Post-action accessibility value of the acted-on element
    public let elementValue: String?
    /// Post-action accessibility traits of the acted-on element (e.g. [.button, .selected])
    public let elementTraits: [HeistTrait]?
    /// Label of the first header element in the post-action snapshot (screen name hint)
    public let screenName: String?
    /// Slugified screen name for machine use (e.g. "controls_demo")
    public let screenId: String?
    /// Diagnostics from a scroll_to_visible search operation
    public let scrollSearchResult: ScrollSearchResult?
    /// Diagnostics from an explore (full screen census) operation
    public let exploreResult: ExploreResult?
    /// True when the UI reached `cycles` consecutive stable cycles before the
    /// settle timeout. False when the timeout was hit and the tree was still
    /// changing. nil for older clients / pre-auto-settle responses.
    public let settled: Bool?
    /// Wall-clock milliseconds from action start to the settle decision
    /// (whether `settled` is true or false). nil for older clients.
    public let settleTimeMs: Int?

    public init(
        success: Bool,
        method: ActionMethod,
        message: String? = nil,
        errorKind: ErrorKind? = nil,
        value: String? = nil,
        interfaceDelta: InterfaceDelta? = nil,
        animating: Bool? = nil,
        elementLabel: String? = nil,
        elementValue: String? = nil,
        elementTraits: [HeistTrait]? = nil,
        screenName: String? = nil,
        screenId: String? = nil,
        scrollSearchResult: ScrollSearchResult? = nil,
        exploreResult: ExploreResult? = nil,
        settled: Bool? = nil,
        settleTimeMs: Int? = nil
    ) {
        self.success = success
        self.method = method
        self.message = message
        self.errorKind = errorKind
        self.value = value
        self.interfaceDelta = interfaceDelta
        self.animating = animating
        self.elementLabel = elementLabel
        self.elementValue = elementValue
        self.elementTraits = elementTraits
        self.screenName = screenName
        self.screenId = screenId
        self.scrollSearchResult = scrollSearchResult
        self.exploreResult = exploreResult
        self.settled = settled
        self.settleTimeMs = settleTimeMs
    }
}

extension ActionResult {
    /// Return a copy with the scrollSearchResult field set.
    public func adding(scrollSearchResult: ScrollSearchResult?) -> ActionResult {
        ActionResult(
            success: success, method: method, message: message, errorKind: errorKind,
            value: value, interfaceDelta: interfaceDelta, animating: animating,
            elementLabel: elementLabel, elementValue: elementValue, elementTraits: elementTraits,
            screenName: screenName, screenId: screenId, scrollSearchResult: scrollSearchResult,
            exploreResult: exploreResult,
            settled: settled, settleTimeMs: settleTimeMs
        )
    }

    /// Return a copy with the exploreResult's elements populated.
    /// Used by the explicit explore command which needs the full element list.
    public func adding(exploreElements: [HeistElement]) -> ActionResult {
        guard let explore = exploreResult else { return self }
        let fullExplore = ExploreResult(
            elements: exploreElements,
            scrollCount: explore.scrollCount,
            containersExplored: explore.containersExplored,
            containersSkippedObscured: explore.containersSkippedObscured,
            explorationTime: explore.explorationTime
        )
        return ActionResult(
            success: success, method: method, message: message, errorKind: errorKind,
            value: value, interfaceDelta: interfaceDelta, animating: animating,
            elementLabel: elementLabel, elementValue: elementValue, elementTraits: elementTraits,
            screenName: screenName, screenId: screenId, scrollSearchResult: scrollSearchResult,
            exploreResult: fullExplore,
            settled: settled, settleTimeMs: settleTimeMs
        )
    }
}

/// Diagnostics from a scroll_to_visible search operation.
public struct ScrollSearchResult: Codable, Sendable {
    /// Number of scroll operations performed
    public let scrollCount: Int
    /// Number of unique elements seen across all scroll positions
    public let uniqueElementsSeen: Int
    /// Total items in the data source (UITableView/UICollectionView only)
    public let totalItems: Int?
    /// Whether every item in the data source was checked
    public let exhaustive: Bool
    /// The matched element, if found
    public let foundElement: HeistElement?

    public init(
        scrollCount: Int,
        uniqueElementsSeen: Int,
        totalItems: Int? = nil,
        exhaustive: Bool,
        foundElement: HeistElement? = nil
    ) {
        self.scrollCount = scrollCount
        self.uniqueElementsSeen = uniqueElementsSeen
        self.totalItems = totalItems
        self.exhaustive = exhaustive
        self.foundElement = foundElement
    }
}

// MARK: - Explore Result

/// Result from an explore (full screen census) operation.
/// Contains every element discovered across all scroll positions.
public struct ExploreResult: Codable, Sendable {
    /// Every element discovered on the screen, including off-screen content
    public let elements: [HeistElement]
    /// Total scrollByPage calls during exploration
    public let scrollCount: Int
    /// Number of scrollable containers explored
    public let containersExplored: Int
    /// Containers skipped because they were behind a presented view controller
    public let containersSkippedObscured: Int
    /// Wall-clock time spent exploring, in seconds
    public let explorationTime: Double

    public var elementCount: Int { elements.count }

    public init(
        elements: [HeistElement],
        scrollCount: Int,
        containersExplored: Int,
        containersSkippedObscured: Int = 0,
        explorationTime: Double
    ) {
        self.elements = elements
        self.scrollCount = scrollCount
        self.containersExplored = containersExplored
        self.containersSkippedObscured = containersSkippedObscured
        self.explorationTime = explorationTime
    }

    // MARK: - Codable

    private enum CodingKeys: String, CodingKey {
        case elements, scrollCount, containersExplored, containersSkippedObscured, explorationTime
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        elements = try container.decode([HeistElement].self, forKey: .elements)
        scrollCount = try container.decode(Int.self, forKey: .scrollCount)
        containersExplored = try container.decode(Int.self, forKey: .containersExplored)
        containersSkippedObscured = try container.decodeIfPresent(Int.self, forKey: .containersSkippedObscured) ?? 0
        explorationTime = try container.decode(Double.self, forKey: .explorationTime)
    }
}

// MARK: - Interface Delta

/// Compact description of what changed in the accessibility hierarchy after an action.
public struct InterfaceDelta: Codable, Sendable {

    // MARK: - Nested Types

    /// Classification of the change that occurred.
    public enum DeltaKind: String, Codable, Sendable {
        case noChange
        case elementsChanged
        case screenChanged
    }

    // MARK: - Properties

    public let kind: DeltaKind

    public let elementCount: Int

    /// Elements that were added (present for .elementsChanged)
    public let added: [HeistElement]?

    /// HeistIds of elements that were removed (present for .elementsChanged)
    public let removed: [String]?

    /// Elements whose properties changed (present for .elementsChanged)
    public let updated: [ElementUpdate]?

    /// Nodes inserted into the interface tree (present for structural .elementsChanged)
    public let treeInserted: [TreeInsertion]?

    /// Nodes removed from the interface tree (present for structural .elementsChanged)
    public let treeRemoved: [TreeRemoval]?

    /// Existing nodes moved within the interface tree (present for structural .elementsChanged)
    public let treeMoved: [TreeMove]?

    /// Elements that appeared and then disappeared during the observation
    /// window — captured from the snapshot in which they were present.
    /// Rendered by the CLI/MCP as `+- heistId "label" [traits]`. Most
    /// useful when an action triggers a multi-step transition that
    /// auto-dismisses (loading → success → confirmation → dismissal).
    public let transient: [HeistElement]?

    /// Elements that disappeared and then reappeared during the observation
    /// window. Rendered as `-+ heistId "label" [traits]`. Indicates a
    /// flicker — the element is present in baseline and final but went
    /// missing somewhere in between.
    public let flicker: [HeistElement]?

    /// Full new interface (present only for .screenChanged)
    public let newInterface: Interface?

    // MARK: - Init

    public init(
        kind: DeltaKind,
        elementCount: Int,
        added: [HeistElement]? = nil,
        removed: [String]? = nil,
        updated: [ElementUpdate]? = nil,
        treeInserted: [TreeInsertion]? = nil,
        treeRemoved: [TreeRemoval]? = nil,
        treeMoved: [TreeMove]? = nil,
        transient: [HeistElement]? = nil,
        flicker: [HeistElement]? = nil,
        newInterface: Interface? = nil
    ) {
        self.kind = kind
        self.elementCount = elementCount
        self.added = added
        self.removed = removed
        self.updated = updated
        self.treeInserted = treeInserted
        self.treeRemoved = treeRemoved
        self.treeMoved = treeMoved
        self.transient = transient
        self.flicker = flicker
        self.newInterface = newInterface
    }
}

/// Stable identity namespace for a node in `Interface.tree`.
public enum TreeNodeKind: String, Codable, Sendable, Equatable {
    case element
    case container
}

/// A stable reference to an existing tree node.
public struct TreeNodeRef: Codable, Sendable, Equatable {
    public let id: String
    public let kind: TreeNodeKind

    public init(id: String, kind: TreeNodeKind) {
        self.id = id
        self.kind = kind
    }
}

/// A location in the interface tree. `parentId == nil` means the root forest.
public struct TreeLocation: Codable, Sendable, Equatable {
    public let parentId: String?
    public let index: Int

    public init(parentId: String?, index: Int) {
        self.parentId = parentId
        self.index = index
    }
}

/// A node inserted into `Interface.tree`.
public struct TreeInsertion: Codable, Sendable, Equatable {
    public let location: TreeLocation
    public let node: InterfaceNode

    public init(location: TreeLocation, node: InterfaceNode) {
        self.location = location
        self.node = node
    }
}

/// A node removed from `Interface.tree`.
public struct TreeRemoval: Codable, Sendable, Equatable {
    public let ref: TreeNodeRef
    public let location: TreeLocation

    public init(ref: TreeNodeRef, location: TreeLocation) {
        self.ref = ref
        self.location = location
    }
}

/// An existing node moved within `Interface.tree`.
public struct TreeMove: Codable, Sendable, Equatable {
    public let ref: TreeNodeRef
    public let from: TreeLocation
    public let to: TreeLocation

    public init(ref: TreeNodeRef, from: TreeLocation, to: TreeLocation) {
        self.ref = ref
        self.from = from
        self.to = to
    }
}

/// Which accessibility property changed on an element.
public enum ElementProperty: String, Codable, Sendable, CaseIterable {
    case label
    case value
    case traits
    case hint
    case actions
    case frame
    case activationPoint
    case customContent

    /// Geometry properties: frame position/size and activation point coordinates.
    public var isGeometry: Bool {
        self == .frame || self == .activationPoint
    }
}

/// A single property change: what property, old value, new value.
public struct PropertyChange: Codable, Sendable, Equatable {
    public let property: ElementProperty
    public let old: String?
    public let new: String?

    public init(property: ElementProperty, old: String?, new: String?) {
        self.property = property
        self.old = old
        self.new = new
    }
}

/// An element whose state changed — carries the heistId and which properties differ.
public struct ElementUpdate: Codable, Sendable, Equatable {
    public let heistId: String
    public let changes: [PropertyChange]

    public init(heistId: String, changes: [PropertyChange]) {
        self.heistId = heistId
        self.changes = changes
    }
}

/// Payload containing screen capture data
public struct ScreenPayload: Codable, Sendable {
    public let pngData: String
    public let width: Double
    public let height: Double
    public let timestamp: Date

    public init(pngData: String, width: Double, height: Double, timestamp: Date = Date()) {
        self.pngData = pngData
        self.width = width
        self.height = height
        self.timestamp = timestamp
    }
}

/// Payload containing screen recording video data.
public struct RecordingPayload: Codable, Sendable {

    // MARK: - Nested Types

    /// Why the recording was stopped.
    public enum StopReason: String, Codable, Sendable {
        case manual
        case inactivity
        case maxDuration
        case fileSizeLimit
    }

    // MARK: - Properties

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
    /// Ordered log of interactions recorded during this session (nil if no interactions occurred)
    public let interactionLog: [InteractionEvent]?

    // MARK: - Init

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
    /// The result returned to the client (includes interfaceDelta)
    public let result: ActionResult

    public init(
        timestamp: Double,
        command: ClientMessage,
        result: ActionResult
    ) {
        self.timestamp = timestamp
        self.command = command
        self.result = result
    }
}

/// Identifies which action handler produced an ActionResult.
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
    case setPasteboard
    case getPasteboard
    case waitForIdle
    case waitForChange
    case scroll
    case scrollToVisible
    case elementSearch
    case scrollToEdge
    case waitFor
    case explore
    case elementNotFound
    case elementDeallocated
}

/// Payload sent when a connection is approved via the on-device UI
public struct AuthApprovedPayload: Codable, Sendable {
    public let token: String?
    public init(token: String? = nil) { self.token = token }
}

/// Server identity and capabilities sent after a successful handshake.
public struct ServerInfo: Codable, Sendable {
    public let protocolVersion: String
    public let appName: String
    public let bundleIdentifier: String
    public let deviceName: String
    public let systemVersion: String
    public let screenWidth: Double
    public let screenHeight: Double
    /// Per-launch session identifier
    public let instanceId: String?
    /// Human-readable instance identifier (from INSIDEJOB_ID env var, or shortId fallback)
    public let instanceIdentifier: String?
    /// Port the server is listening on
    public let listeningPort: UInt16?
    /// Simulator UDID when running on iOS Simulator (nil on physical devices)
    public let simulatorUDID: String?
    /// Vendor identifier from UIDevice.identifierForVendor (stable per app install per device)
    public let vendorIdentifier: String?
    /// Whether TLS transport encryption is active
    public let tlsActive: Bool?

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
        vendorIdentifier: String? = nil,
        tlsActive: Bool? = nil
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
        self.tlsActive = tlsActive
    }
}

extension ServerInfo {
    /// Computed screen size as CGSize
    public var screenSize: CGSize {
        CGSize(width: screenWidth, height: screenHeight)
    }
}
