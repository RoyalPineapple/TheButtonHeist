import ThePlans
import Foundation

// MARK: - Coding Keys

private enum ServerMessageCodingKeys: String, CodingKey, CaseIterable {
    case type
    case payload
}

private enum ResponseEnvelopeCodingKeys: String, CodingKey, CaseIterable {
    case buttonHeistVersion
    case requestId
    case type
    case payload
}

// MARK: - ResponseEnvelope Codable

extension ResponseEnvelope {
    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: ResponseEnvelopeCodingKeys.self, typeName: "response envelope")
        let container = try decoder.container(keyedBy: ResponseEnvelopeCodingKeys.self)
        buttonHeistVersion = try container.decode(String.self, forKey: .buttonHeistVersion)
        requestId = try container.decodeIfPresent(String.self, forKey: .requestId)
        let type = try container.decode(ServerWireMessageType.self, forKey: .type)
        let payloadDecoder: Decoder? = container.contains(.payload)
            ? try container.superDecoder(forKey: .payload)
            : nil
        message = try decodeServerMessage(from: payloadDecoder, type: type)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: ResponseEnvelopeCodingKeys.self)
        try container.encode(buttonHeistVersion, forKey: .buttonHeistVersion)
        try container.encodeIfPresent(requestId, forKey: .requestId)
        let wire = serverMessageWireRepresentation(message)
        try container.encode(wire.type, forKey: .type)
        if let payload = wire.payload {
            try payload.encode(to: container.superEncoder(forKey: .payload))
        }
    }

}

extension ServerMessage {
    // MARK: - Codable Conformance

    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: ServerMessageCodingKeys.self, typeName: "server message")
        let container = try decoder.container(keyedBy: ServerMessageCodingKeys.self)
        let type = try container.decode(ServerWireMessageType.self, forKey: .type)
        let payloadDecoder: Decoder? = container.contains(.payload)
            ? try container.superDecoder(forKey: .payload)
            : nil
        self = try decodeServerMessage(from: payloadDecoder, type: type)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: ServerMessageCodingKeys.self)
        let wire = serverMessageWireRepresentation(self)
        try container.encode(wire.type, forKey: .type)
        if let payload = wire.payload {
            try payload.encode(to: container.superEncoder(forKey: .payload))
        }
    }

}

// MARK: - Helpers

/// Single source of truth mapping each `ServerMessage` case to its wire type
/// tag and optional payload value. Adding a new case requires extending this
/// switch; Swift's exhaustivity check is the drift detector.
private func serverMessageWireRepresentation(
    _ message: ServerMessage
) -> ServerMessageWireRepresentation {
    switch message {
    case .serverHello:
        return ServerMessageWireRepresentation(type: .serverHello, payload: nil)
    case .authRequired:
        return ServerMessageWireRepresentation(type: .authRequired, payload: nil)
    case .pong(let payload):
        return ServerMessageWireRepresentation(type: .pong, payload: .pong(payload))
    case .protocolMismatch(let payload):
        return ServerMessageWireRepresentation(type: .protocolMismatch, payload: .protocolMismatch(payload))
    case .error(let payload):
        return ServerMessageWireRepresentation(type: .error, payload: .error(payload))
    case .sessionLocked(let payload):
        return ServerMessageWireRepresentation(type: .sessionLocked, payload: .sessionLocked(payload))
    case .info(let payload):
        return ServerMessageWireRepresentation(type: .info, payload: .info(payload))
    case .interface(let payload):
        return ServerMessageWireRepresentation(type: .interface, payload: .interface(payload))
    case .actionResult(let payload):
        return ServerMessageWireRepresentation(type: .actionResult, payload: .actionResult(payload))
    case .screen(let payload):
        return ServerMessageWireRepresentation(type: .screen, payload: .screen(payload))
    case .announcements(let payload):
        return ServerMessageWireRepresentation(type: .announcements, payload: .announcements(payload))
    case .status(let payload):
        return ServerMessageWireRepresentation(type: .status, payload: .status(payload))
    }
}

private struct ServerMessageWireRepresentation {
    let type: ServerWireMessageType
    let payload: ServerMessageWirePayload?
}

private func decodeServerMessage(from payloadDecoder: Decoder?, type: ServerWireMessageType) throws -> ServerMessage {
    func payload() throws -> Decoder {
        guard let payloadDecoder else { throw missingServerPayload(type) }
        return payloadDecoder
    }
    func noPayload() throws {
        if let payloadDecoder {
            throw unexpectedServerPayload(type, codingPath: payloadDecoder.codingPath)
        }
    }
    switch type {
    case .serverHello:
        try noPayload()
        return .serverHello
    case .authRequired:
        try noPayload()
        return .authRequired
    case .pong:
        return .pong(try PongPayload(from: try payload()))
    case .protocolMismatch:
        return .protocolMismatch(try ProtocolMismatchPayload(from: try payload()))
    case .error:
        return .error(try ServerError(from: try payload()))
    case .sessionLocked:
        return .sessionLocked(try SessionLockedPayload(from: try payload()))
    case .info:
        return .info(try ServerInfo(from: try payload()))
    case .interface:
        return .interface(try Interface(from: try payload()))
    case .actionResult:
        return .actionResult(try ActionResult(from: try payload()))
    case .screen:
        return .screen(try ScreenPayload(from: try payload()))
    case .announcements:
        return .announcements(try AnnouncementListPayload(from: try payload()))
    case .status:
        return .status(try StatusPayload(from: try payload()))
    }
}

private enum ServerMessageWirePayload {
    case pong(PongPayload)
    case protocolMismatch(ProtocolMismatchPayload)
    case error(ServerError)
    case sessionLocked(SessionLockedPayload)
    case info(ServerInfo)
    case interface(Interface)
    case actionResult(ActionResult)
    case screen(ScreenPayload)
    case announcements(AnnouncementListPayload)
    case status(StatusPayload)

    func encode(to encoder: Encoder) throws {
        switch self {
        case .pong(let payload):
            try payload.encode(to: encoder)
        case .protocolMismatch(let payload):
            try payload.encode(to: encoder)
        case .error(let payload):
            try payload.encode(to: encoder)
        case .sessionLocked(let payload):
            try payload.encode(to: encoder)
        case .info(let payload):
            try payload.encode(to: encoder)
        case .interface(let payload):
            try payload.encode(to: encoder)
        case .actionResult(let payload):
            try payload.encode(to: encoder)
        case .screen(let payload):
            try payload.encode(to: encoder)
        case .announcements(let payload):
            try payload.encode(to: encoder)
        case .status(let payload):
            try payload.encode(to: encoder)
        }
    }
}

private func missingServerPayload(_ type: ServerWireMessageType, codingPath: [CodingKey] = []) -> DecodingError {
    .missingPayload(key: ServerMessageCodingKeys.payload, type: type, codingPath: codingPath)
}

private func unexpectedServerPayload(_ type: ServerWireMessageType, codingPath: [CodingKey]) -> DecodingError {
    .dataCorrupted(.init(
        codingPath: codingPath,
        debugDescription: "\(type.rawValue) must not include a payload"
    ))
}
