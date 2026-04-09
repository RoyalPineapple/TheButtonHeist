import Foundation

/// Bonjour service type for discovery
public let buttonHeistServiceType = "_buttonheist._tcp"

/// Protocol version for compatibility checking
public let protocolVersion = "6.8"

/// Canonical product version shared by CLI, MCP, and the iOS server.
/// Update this constant when cutting a new release. See VERSIONING.md in bh-infra.
public let buttonHeistVersion = "0.2.8"

/// Explicit wire message discriminator used at JSON boundaries.
public enum WireMessageType: String, Codable, CaseIterable, Sendable {
    case clientHello
    case serverHello
    case protocolMismatch
    case authenticate
    case authRequired
    case authFailed
    case authApproved
    case info
    case requestInterface
    case interface
    case subscribe
    case unsubscribe
    case ping
    case pong
    case status
    case error
    case activate
    case increment
    case decrement
    case performCustomAction
    case actionResult
    case touchTap
    case touchLongPress
    case touchSwipe
    case touchDrag
    case touchPinch
    case touchRotate
    case touchTwoFingerTap
    case touchDrawPath
    case touchDrawBezier
    case typeText
    case editAction
    case setPasteboard
    case getPasteboard
    case scroll
    case scrollToVisible
    case elementSearch
    case scrollToEdge
    case resignFirstResponder
    case requestScreen
    case explore
    case screen
    case waitForIdle
    case sessionLocked
    case startRecording
    case stopRecording
    case recordingStarted
    case recordingStopped
    case recording
    case recordingError
    case waitFor
    case waitForChange
    case interaction
    case watch
}

// MARK: - TXT Record Keys

/// Bonjour TXT record keys used for service advertisement and discovery.
public enum TXTRecordKey: String, Sendable {
    case simUDID = "simudid"
    case installationId = "installationid"
    case deviceName = "devicename"
    case instanceId = "instanceid"
    case certFingerprint = "certfp"
    case transport = "transport"
    case sessionActive = "sessionactive"
}

// MARK: - Environment Keys

/// Centralized environment variable names used across client and server.
public enum EnvironmentKey: String, Sendable {
    // Client
    case buttonheistDevice = "BUTTONHEIST_DEVICE"
    case buttonheistToken = "BUTTONHEIST_TOKEN"
    case buttonheistDriverId = "BUTTONHEIST_DRIVER_ID"
    case buttonheistSessionTimeout = "BUTTONHEIST_SESSION_TIMEOUT"
    // Server
    case insideJobToken = "INSIDEJOB_TOKEN"
    case insideJobPort = "INSIDEJOB_PORT"
    case insideJobDisable = "INSIDEJOB_DISABLE"
    case insideJobDisableFingerprints = "INSIDEJOB_DISABLE_FINGERPRINTS"
    case insideJobPollingInterval = "INSIDEJOB_POLLING_INTERVAL"
    case insideJobId = "INSIDEJOB_ID"
    case insideJobScope = "INSIDEJOB_SCOPE"
    case insideJobRestrictWatchers = "INSIDEJOB_RESTRICT_WATCHERS"
    case insideJobSessionTimeout = "INSIDEJOB_SESSION_TIMEOUT"
}

extension EnvironmentKey {
    public var value: String? { ProcessInfo.processInfo.environment[rawValue] }
    public var boolValue: Bool {
        guard let v = value?.lowercased() else { return false }
        return v == "true" || v == "1" || v == "yes"
    }
}

// MARK: - DecodingError Helpers

extension DecodingError {
    /// Construct a `.keyNotFound` error for a missing wire message payload.
    static func missingPayload(key: CodingKey, type: WireMessageType, codingPath: [CodingKey] = []) -> DecodingError {
        .keyNotFound(key, .init(codingPath: codingPath, debugDescription: "Missing payload for message type \(type.rawValue)"))
    }
}
