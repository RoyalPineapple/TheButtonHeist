import Foundation

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

/// Configuration for screen recording
public struct RecordingConfig: Sendable {
    /// Frames per second (default: 8, range: 1-15)
    public let fps: Int?
    /// Resolution scale relative to native pixels (0.25-1.0).
    /// Default: nil — uses 1x point resolution (native pixels / screen scale).
    /// 1.0 = full native resolution (no reduction).
    public let scale: Double?
    /// Optional early-stop timeout in seconds — auto-stop when no screen changes
    /// and no commands are received for this duration. When omitted,
    /// inactivity auto-stop is disabled.
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

extension RecordingConfig: Codable {
    private enum CodingKeys: String, CodingKey {
        case fps, scale, inactivityTimeout, maxDuration
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let fps = try container.decodeIfPresent(Int.self, forKey: .fps)
        let scale = try container.decodeIfPresent(Double.self, forKey: .scale)
        if let fps, fps < 1 || fps > 15 {
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath,
                debugDescription: "fps must be between 1 and 15, got \(fps)"
            ))
        }
        if let scale, scale < 0.25 || scale > 1.0 {
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath,
                debugDescription: "scale must be between 0.25 and 1.0, got \(scale)"
            ))
        }
        self.fps = fps
        self.scale = scale
        self.inactivityTimeout = try container.decodeIfPresent(Double.self, forKey: .inactivityTimeout)
        self.maxDuration = try container.decodeIfPresent(Double.self, forKey: .maxDuration)
    }
}
