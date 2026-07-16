import ThePlans
import Foundation

/// Cheap health payload returned by ping.
///
/// This intentionally excludes dynamic UI/accessibility state, latency, and
/// discovery scans so ping can be answered cheaply.
public struct PongPayload: Codable, Sendable, Equatable {
    public let buttonHeistVersion: ButtonHeistVersion
    public let appName: String
    public let bundleIdentifier: BundleIdentifier
    public let appVersion: String?
    public let appBuild: String?
    public let serverInstanceIdentifier: InsideJobInstanceID?
    public let serverTimestampMs: Int64?

    public init(
        buttonHeistVersion: ButtonHeistVersion = TheScore.buttonHeistVersion,
        appName: String = "",
        bundleIdentifier: BundleIdentifier,
        appVersion: String? = nil,
        appBuild: String? = nil,
        serverInstanceIdentifier: InsideJobInstanceID? = nil,
        serverTimestampMs: Int64? = nil
    ) {
        self.buttonHeistVersion = buttonHeistVersion
        self.appName = appName
        self.bundleIdentifier = bundleIdentifier
        self.appVersion = appVersion
        self.appBuild = appBuild
        self.serverInstanceIdentifier = serverInstanceIdentifier
        self.serverTimestampMs = serverTimestampMs
    }

    public func withServerTimestamp(_ date: Date = Date()) -> PongPayload {
        PongPayload(
            buttonHeistVersion: buttonHeistVersion,
            appName: appName,
            bundleIdentifier: bundleIdentifier,
            appVersion: appVersion,
            appBuild: appBuild,
            serverInstanceIdentifier: serverInstanceIdentifier,
            serverTimestampMs: Int64(date.timeIntervalSince1970 * 1000)
        )
    }
}

/// Sent when the client's `buttonHeistVersion` does not exactly match the server's.
public struct ProtocolMismatchPayload: Codable, Sendable {
    public let serverButtonHeistVersion: ButtonHeistVersion
    public let clientButtonHeistVersion: ButtonHeistVersion

    public init(
        serverButtonHeistVersion: ButtonHeistVersion,
        clientButtonHeistVersion: ButtonHeistVersion
    ) {
        self.serverButtonHeistVersion = serverButtonHeistVersion
        self.clientButtonHeistVersion = clientButtonHeistVersion
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
    public let bundleIdentifier: BundleIdentifier
    public let appBuild: String
    public let deviceName: String
    public let systemVersion: String
    public let buttonHeistVersion: ButtonHeistVersion

    public init(
        appName: String,
        bundleIdentifier: BundleIdentifier,
        appBuild: String,
        deviceName: String,
        systemVersion: String,
        buttonHeistVersion: ButtonHeistVersion
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
    /// Whether additional observer connections are allowed for this active session.
    /// This is always false: a session has one active driver connection.
    public let watchersAllowed: Bool
    /// Number of active connections in the session.
    public let activeConnections: Int
    /// Driver ID that owns the active session, when the client supplied one.
    public let activeDriverId: DriverID?

    public init(
        active: Bool,
        watchersAllowed: Bool,
        activeConnections: Int,
        activeDriverId: DriverID? = nil
    ) {
        self.active = active
        self.watchersAllowed = watchersAllowed
        self.activeConnections = activeConnections
        self.activeDriverId = activeDriverId
    }
}
