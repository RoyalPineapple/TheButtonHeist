import ThePlans
import Foundation

// MARK: - Request Envelope

/// Wraps a client message with an optional request ID for response correlation.
/// When `requestId` is present, the server echoes it in the corresponding response
/// so the client can match request-response pairs. Push broadcasts have no requestId.
public struct RequestEnvelope: Codable, Sendable {
    /// Client's `buttonHeistVersion`. The handshake requires exact equality
    /// with the server's `buttonHeistVersion` — there is no separate wire
    /// protocol version.
    public let buttonHeistVersion: String
    public let requestId: String?
    public let message: ClientMessage
    let requestScreenPayload: ScreenRequestPayload?

    public init(
        buttonHeistVersion: String = TheScore.buttonHeistVersion,
        requestId: String? = nil,
        message: ClientMessage
    ) {
        self.buttonHeistVersion = buttonHeistVersion
        self.requestId = requestId
        self.message = message
        requestScreenPayload = nil
    }

    @_spi(ButtonHeistInternals) public init(
        buttonHeistVersion: String = TheScore.buttonHeistVersion,
        requestId: String? = nil,
        message: ClientMessage,
        requestScreenPayload: ScreenRequestPayload?
    ) {
        self.buttonHeistVersion = buttonHeistVersion
        self.requestId = requestId
        self.message = message
        self.requestScreenPayload = requestScreenPayload
    }

    @_spi(ButtonHeistInternals) public var explicitScreenRequestPayload: ScreenRequestPayload? {
        requestScreenPayload
    }

    /// Decode a request envelope from JSON data. Returns nil on decode failure.
    public static func decoded(from data: Data) throws -> RequestEnvelope {
        try JSONDecoder().decode(RequestEnvelope.self, from: data)
    }
}

// MARK: - Client -> Server Messages

/// Messages sent from a connected client to the Inside Job server.
///
/// Public wire requests are limited to transport/session messages, pure
/// observation reads, non-durable transient direct runtime actions, and
/// `heistPlan`.
/// Durable UI mutation is compiled into `HeistPlan` at the public boundary and
/// dispatched inside the runtime as `RuntimeActionMessage`; transient commands
/// can use `runtimeAction` without creating a heist.
public enum ClientMessage: Codable, Sendable, Equatable {
    // MARK: - Transport / Session

    /// Version-negotiation hello sent immediately after receiving serverHello.
    case clientHello

    /// Authenticate with a token (sent after clientHello handshake completes)
    case authenticate(AuthenticatePayload)

    /// Ping for keepalive
    case ping

    /// Lightweight status command (identity + availability) for authenticated clients.
    case status

    // MARK: - Pure Read / Observation

    /// Request current semantic interface (app accessibility state)
    case requestInterface(InterfaceQuery)

    /// Read text from the general pasteboard
    case getPasteboard

    /// Request a capture of the current screen
    case requestScreen

    // MARK: - Transient Runtime Action

    /// Execute one non-durable runtime action without wrapping it in a durable
    /// `HeistPlan`. Intended for viewport/debug/session commands.
    case runtimeAction(HeistActionCommand)

    // MARK: - Heist Execution

    /// Execute a typed heist plan with the root argument required by its parameter.
    case heistPlan(HeistPlanRun)
}

public struct HeistPlanRun: Codable, Sendable, Equatable {
    public let plan: HeistPlan
    public let argument: HeistArgument

    public init(plan: HeistPlan, argument: HeistArgument = .none) {
        self.plan = plan
        self.argument = argument
    }
}
