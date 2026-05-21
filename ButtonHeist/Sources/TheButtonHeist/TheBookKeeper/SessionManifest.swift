import Foundation

// MARK: - Format Version

/// Version tracking for the session manifest format.
enum SessionFormatVersion {
    static let current = "0.1.0"
}

// MARK: - Artifact Types

/// Classification of artifacts stored in a session directory.
public enum ArtifactType: String, Codable, Sendable, CaseIterable {
    case screenshot
    case recording
}

/// Success or failure classification for logged command responses.
enum ResponseStatus: String, Codable, Sendable, CaseIterable {
    case ok
    case error
}

// MARK: - Metadata Types

/// Dimensions captured alongside a screenshot artifact.
struct ScreenshotMetadata: Sendable {
    let width: Double
    let height: Double
}

/// Dimensions and timing captured alongside a recording artifact.
struct RecordingMetadata: Sendable {
    let width: Int
    let height: Int
    let duration: Double
    let fps: Int
    let frameCount: Int
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

/// Counts derived from authoritative session log events.
public struct SessionLogCounts: Sendable, Equatable {
    public let commandCount: Int
    public let errorCount: Int

    public init(commandCount: Int = 0, errorCount: Int = 0) {
        self.commandCount = commandCount
        self.errorCount = errorCount
    }
}

/// Diagnostic status for projections derived from append-only session logs.
public struct SessionLogProjectionStatus: Sendable, Equatable {
    public let malformedLineCount: Int
    public let firstMalformedLineNumber: Int?
    public let firstMalformedLineCause: String?
    public let malformedArtifactCount: Int

    public var isDegraded: Bool {
        malformedLineCount > 0 || malformedArtifactCount > 0
    }

    public init(
        malformedLineCount: Int = 0,
        firstMalformedLineNumber: Int? = nil,
        firstMalformedLineCause: String? = nil,
        malformedArtifactCount: Int = 0
    ) {
        self.malformedLineCount = malformedLineCount
        self.firstMalformedLineNumber = firstMalformedLineNumber
        self.firstMalformedLineCause = firstMalformedLineCause
        self.malformedArtifactCount = malformedArtifactCount
    }
}

/// Durable session boundary information plus projections derived from its session log.
public struct SessionLogSnapshot: Sendable, Equatable {
    public let manifest: SessionManifest
    public let counts: SessionLogCounts
    public let artifacts: [ArtifactEntry]
    public let projectionStatus: SessionLogProjectionStatus

    public init(
        manifest: SessionManifest,
        counts: SessionLogCounts,
        artifacts: [ArtifactEntry] = [],
        projectionStatus: SessionLogProjectionStatus = SessionLogProjectionStatus()
    ) {
        self.manifest = manifest
        self.counts = counts
        self.artifacts = artifacts
        self.projectionStatus = projectionStatus
    }
}

/// Durable session boundary information.
public struct SessionManifest: Codable, Sendable, Equatable {
    public let formatVersion: String
    public let sessionId: String
    public let startTime: Date
    public let endTime: Date?

    public init(
        sessionId: String,
        startTime: Date,
        endTime: Date? = nil
    ) {
        self.init(
            formatVersion: SessionFormatVersion.current,
            sessionId: sessionId,
            startTime: startTime,
            endTime: endTime
        )
    }

    private init(
        formatVersion: String,
        sessionId: String,
        startTime: Date,
        endTime: Date?
    ) {
        self.formatVersion = formatVersion
        self.sessionId = sessionId
        self.startTime = startTime
        self.endTime = endTime
    }

    public func closed(at endTime: Date) -> SessionManifest {
        SessionManifest(
            formatVersion: formatVersion,
            sessionId: sessionId,
            startTime: startTime,
            endTime: endTime
        )
    }
}
