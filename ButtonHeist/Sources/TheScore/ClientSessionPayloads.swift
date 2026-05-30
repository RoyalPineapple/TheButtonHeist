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
