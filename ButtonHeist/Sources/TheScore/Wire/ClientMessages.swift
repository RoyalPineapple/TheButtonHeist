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
    public let buttonHeistVersion: ButtonHeistVersion
    public let requestId: RequestID?
    public let message: ClientMessage

    public init(
        buttonHeistVersion: ButtonHeistVersion = TheScore.buttonHeistVersion,
        requestId: RequestID? = nil,
        message: ClientMessage
    ) {
        self.buttonHeistVersion = buttonHeistVersion
        self.requestId = requestId
        self.message = message
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
/// dispatched inside the runtime as `ResolvedHeistActionCommand`; transient commands
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

    /// Read recent spoken accessibility text captured from public AX notifications.
    case getAnnouncements

    /// Request a capture of the current screen
    case requestScreen(ScreenRequestPayload = .init())

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

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case plan
        case argument
    }

    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "heist plan run")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        plan = try container.decode(HeistPlan.self, forKey: .plan)
        argument = try container.decode(HeistArgument.self, forKey: .argument)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(plan, forKey: .plan)
        try container.encode(argument, forKey: .argument)
    }
}
