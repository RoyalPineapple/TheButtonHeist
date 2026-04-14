import Foundation

// MARK: - Format Version

/// Version tracking for the session manifest format.
public enum SessionFormatVersion {
    public static let current = "0.1.0"
}

// MARK: - Artifact Types

/// Classification of artifacts stored in a session directory.
public enum ArtifactType: String, Codable, Sendable, CaseIterable {
    case screenshot
    case recording
}

/// Success or failure classification for logged command responses.
public enum ResponseStatus: String, Sendable, CaseIterable {
    case ok
    case error
}

// MARK: - Metadata Types

/// Dimensions captured alongside a screenshot artifact.
public struct ScreenshotMetadata: Sendable {
    public let width: Double
    public let height: Double

    public init(width: Double, height: Double) {
        self.width = width
        self.height = height
    }
}

/// Dimensions and timing captured alongside a recording artifact.
public struct RecordingMetadata: Sendable {
    public let width: Int
    public let height: Int
    public let duration: Double
    public let fps: Int
    public let frameCount: Int

    public init(width: Int, height: Int, duration: Double, fps: Int, frameCount: Int) {
        self.width = width
        self.height = height
        self.duration = duration
        self.fps = fps
        self.frameCount = frameCount
    }
}

// MARK: - Artifact Entry

/// A single artifact (screenshot or recording) stored in a session directory.
public struct ArtifactEntry: Codable, Sendable, Equatable {
    public let type: ArtifactType
    public let path: String
    public let size: Int
    public let timestamp: Date
    public let requestId: String
    public let command: String
    public let metadata: [String: Double]

    public init(
        type: ArtifactType,
        path: String,
        size: Int,
        timestamp: Date,
        requestId: String,
        command: String,
        metadata: [String: Double]
    ) {
        self.type = type
        self.path = path
        self.size = size
        self.timestamp = timestamp
        self.requestId = requestId
        self.command = command
        self.metadata = metadata
    }
}

// MARK: - Session Manifest

/// Durable index of a BookKeeper session — commands, artifacts, and timing.
public struct SessionManifest: Codable, Sendable, Equatable {
    public let formatVersion: String
    public let sessionId: String
    public let startTime: Date
    public var endTime: Date?
    public var artifacts: [ArtifactEntry]
    public var commandCount: Int
    public var errorCount: Int

    public init(
        sessionId: String,
        startTime: Date,
        endTime: Date? = nil,
        artifacts: [ArtifactEntry] = [],
        commandCount: Int = 0,
        errorCount: Int = 0
    ) {
        self.formatVersion = SessionFormatVersion.current
        self.sessionId = sessionId
        self.startTime = startTime
        self.endTime = endTime
        self.artifacts = artifacts
        self.commandCount = commandCount
        self.errorCount = errorCount
    }
}
