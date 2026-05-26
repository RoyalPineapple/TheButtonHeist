import Foundation

/// Payload containing screen capture data and the current visible accessibility tree.
public struct ScreenPayload: Codable, Sendable {
    public let pngData: String
    public let width: Double
    public let height: Double
    public let timestamp: Date
    public let interface: Interface

    public init(
        pngData: String,
        width: Double,
        height: Double,
        timestamp: Date = Date(),
        interface: Interface = Interface(timestamp: Date(), tree: [])
    ) {
        self.pngData = pngData
        self.width = width
        self.height = height
        self.timestamp = timestamp
        self.interface = interface
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

    /// Base64-encoded MP4 video data (H.264).
    public let videoData: String
    public let width: Int
    public let height: Int
    public let duration: Double
    public let frameCount: Int
    public let fps: Int
    public let startTime: Date
    public let endTime: Date
    public let stopReason: StopReason
    /// Ordered log of interactions recorded during this session, or nil if none occurred.
    public let interactionLog: [InteractionEvent]?
    /// Recording-time evidence about config clamping.
    /// This is diagnostic only; it is never replay authority.
    public let evidence: RecordingPayloadEvidence?

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
        interactionLog: [InteractionEvent]? = nil,
        evidence: RecordingPayloadEvidence? = nil
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
        self.evidence = evidence
    }
}

/// Diagnostic evidence attached to a completed screen recording.
///
/// These fields describe what happened while collecting evidence: values clamped
/// at runtime and hard limits. They do not affect playback.
public struct RecordingPayloadEvidence: Codable, Sendable, Equatable {
    public let caps: [RecordedInputCap]?
    public let interactionLogLimit: Int?
    public let droppedInteractionCount: Int?
    public let fileSizeLimitBytes: Int?

    public init(
        caps: [RecordedInputCap]? = nil,
        interactionLogLimit: Int? = nil,
        droppedInteractionCount: Int? = nil,
        fileSizeLimitBytes: Int? = nil
    ) {
        self.caps = caps?.isEmpty == true ? nil : caps
        self.interactionLogLimit = interactionLogLimit
        self.droppedInteractionCount = droppedInteractionCount
        self.fileSizeLimitBytes = fileSizeLimitBytes
    }
}

/// Evidence that an input value was clamped before execution or recording.
public struct RecordedInputCap: Codable, Sendable, Equatable {
    public let name: String
    public let requested: HeistValue?
    public let applied: HeistValue
    public let minimum: HeistValue?
    public let maximum: HeistValue?
    public let reason: String

    public init(
        name: String,
        requested: HeistValue? = nil,
        applied: HeistValue,
        minimum: HeistValue? = nil,
        maximum: HeistValue? = nil,
        reason: String
    ) {
        self.name = name
        self.requested = requested
        self.applied = applied
        self.minimum = minimum
        self.maximum = maximum
        self.reason = reason
    }
}

/// A single recorded interaction event captured during a TheStakeout recording.
/// The action result carries `AccessibilityTrace` as durable evidence; compact
/// deltas are projections from that trace.
public struct InteractionEvent: Codable, Sendable {
    /// Time offset from recording start, in seconds.
    public let timestamp: Double
    public let command: ClientMessage
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
