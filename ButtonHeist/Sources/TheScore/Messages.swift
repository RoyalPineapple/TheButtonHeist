import ThePlans
import Foundation

// MARK: - Wire Protocol Constants

/// Bonjour service type for discovery
public let buttonHeistServiceType = "_buttonheist._tcp"

/// Canonical product version shared by CLI, MCP, and the iOS server.
///
/// SemVer (`MAJOR.MINOR.PATCH`). There is no separate "wire protocol version"
/// — the handshake requires exact equality between
/// the server's and the client's `buttonHeistVersion`. Update this constant
/// only via `scripts/release.sh`. See `docs/WIRE-PROTOCOL.md` and
/// `VERSIONING.md` in bh-infra.
public let buttonHeistVersion = "0.5.5"

/// Direction-specific JSON `type` discriminator shared by client and server wire enums.
public protocol DirectionalWireMessageType: RawRepresentable, Codable, CaseIterable, Sendable, CustomStringConvertible where RawValue == String {
    static var directionName: String { get }
}

extension DirectionalWireMessageType {
    public var description: String { rawValue }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        guard let type = Self(rawValue: rawValue) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported \(Self.directionName) wire message type: \(rawValue)"
            )
        }
        self = type
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

/// Explicit client-to-server wire message discriminator used at JSON boundaries.
public enum ClientWireMessageType: String, DirectionalWireMessageType {
    public static let directionName = "client"

    case clientHello, authenticate, requestInterface, ping, status
    case activate, increment, decrement, performCustomAction, rotor
    case oneFingerTap, longPress, swipe, drag
    case typeText, editAction, setPasteboard, getPasteboard
    case scroll, scrollToVisible, scrollToEdge, resignFirstResponder
    case requestScreen
    case wait, heistPlan
}

/// High-level ownership classification for client-to-server message types.
public enum ClientMessageCategory: String, Sendable, Equatable {
    case transportSession
    case pureReadObservation
    case mutatingAppInteraction
    case heistExecution
}

public extension ClientWireMessageType {
    /// Product-level classification for the client message surface.
    ///
    /// Mutating app interactions, including one-shot waits that need heist
    /// receipts, are intentionally not public direct wire requests. Public
    /// callers send them as `heistPlan` instead.
    var category: ClientMessageCategory {
        switch self {
        case .clientHello, .authenticate, .ping, .status:
            return .transportSession
        case .requestInterface, .getPasteboard, .requestScreen:
            return .pureReadObservation
        case .heistPlan:
            return .heistExecution
        case .activate, .increment, .decrement, .performCustomAction, .rotor,
             .oneFingerTap, .longPress, .swipe, .drag,
             .typeText, .editAction, .setPasteboard,
             .scroll, .scrollToVisible, .scrollToEdge, .resignFirstResponder,
             .wait:
            return .mutatingAppInteraction
        }
    }

    var isPublicWireRequestType: Bool {
        category != .mutatingAppInteraction
    }
}

/// Explicit server-to-client wire message discriminator used at JSON boundaries.
public enum ServerWireMessageType: String, DirectionalWireMessageType {
    public static let directionName = "server"

    case serverHello, protocolMismatch, authRequired, info, interface
    case pong, status, error, actionResult, screen, sessionLocked
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
}

extension TXTRecordKey: CustomStringConvertible {
    public var description: String { rawValue }
}

// MARK: - Environment Keys

/// Centralized environment variable names used across client and server.
public enum EnvironmentKey: String, Sendable {
    // Client
    case buttonheistDevice = "BUTTONHEIST_DEVICE"
    case buttonheistToken = "BUTTONHEIST_TOKEN"
    case buttonheistDriverId = "BUTTONHEIST_DRIVER_ID"
    case buttonheistSessionTimeout = "BUTTONHEIST_SESSION_TIMEOUT"
    case buttonheistConnectionTimeout = "BUTTONHEIST_CONNECTION_TIMEOUT"
    // Server
    case insideJobToken = "INSIDEJOB_TOKEN"
    case insideJobPort = "INSIDEJOB_PORT"
    case insideJobDisable = "INSIDEJOB_DISABLE"
    case insideJobId = "INSIDEJOB_ID"
    case insideJobScope = "INSIDEJOB_SCOPE"
    case insideJobSessionTimeout = "INSIDEJOB_SESSION_TIMEOUT"
}

extension EnvironmentKey: CustomStringConvertible {
    public var description: String { rawValue }
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
    static func missingPayload<T: DirectionalWireMessageType>(key: CodingKey, type: T, codingPath: [CodingKey] = []) -> DecodingError {
        .keyNotFound(key, .init(codingPath: codingPath, debugDescription: "Missing payload for message type \(type.rawValue)"))
    }
}
