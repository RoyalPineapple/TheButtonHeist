import Foundation

// MARK: - Format Version

/// Version tracking for the session manifest format.
enum SessionFormatVersion {
    static let current = "0.1.0"
}

// MARK: - Metadata Types

/// Dimensions captured alongside a screenshot artifact.
struct ScreenshotMetadata: Sendable {
    let width: Double
    let height: Double
}

// MARK: - Session Manifest

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
