import ThePlans
import Foundation

/// Payload for authenticate message
public struct AuthenticatePayload: Codable, Sendable, Equatable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case token
        case driverId
    }

    public let token: SessionAuthToken
    /// Unique driver identity for session locking. When set, the server uses this
    /// (instead of the auth token) to distinguish drivers. Set via BUTTONHEIST_DRIVER_ID.
    public let driverId: DriverID?
    public init(token: SessionAuthToken, driverId: DriverID? = nil) {
        self.token = token
        self.driverId = driverId
    }

    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "authenticate payload")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        token = try container.decode(SessionAuthToken.self, forKey: .token)
        driverId = try container.decodeIfPresent(DriverID.self, forKey: .driverId)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(token, forKey: .token)
        try container.encodeIfPresent(driverId, forKey: .driverId)
    }
}

/// Information about the active session that is blocking this connection
public struct SessionLockedPayload: Codable, Sendable {
    public let message: String
    public let activeConnections: Int

    package init(message: String, activeConnections: Int) {
        precondition(Self.admits(activeConnections: activeConnections))
        self.message = message
        self.activeConnections = activeConnections
    }

    public static func admit(message: String, activeConnections: Int) -> Self? {
        guard admits(activeConnections: activeConnections) else { return nil }
        return Self(message: message, activeConnections: activeConnections)
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case message
        case activeConnections
    }

    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "session locked payload")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard let admitted = Self.admit(
            message: try container.decode(String.self, forKey: .message),
            activeConnections: try container.decode(Int.self, forKey: .activeConnections)
        ) else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath,
                debugDescription: "session locked activeConnections must be 0 or 1"
            ))
        }
        self = admitted
    }

    private static func admits(activeConnections: Int) -> Bool {
        (0...1).contains(activeConnections)
    }
}
