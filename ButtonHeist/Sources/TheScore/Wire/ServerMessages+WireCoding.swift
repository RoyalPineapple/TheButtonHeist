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
        buttonHeistVersion = try container.decode(ButtonHeistVersion.self, forKey: .buttonHeistVersion)
        requestId = try container.decodeIfPresent(RequestID.self, forKey: .requestId)
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
        try encodeServerMessage(
            message,
            to: &container,
            typeKey: .type,
            payloadKey: .payload
        )
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
        try encodeServerMessage(
            self,
            to: &container,
            typeKey: .type,
            payloadKey: .payload
        )
    }

}

// MARK: - Helpers

/// Encodes each `ServerMessage` case directly to its wire tag and payload.
private func encodeServerMessage<Key: CodingKey>(
    _ message: ServerMessage,
    to container: inout KeyedEncodingContainer<Key>,
    typeKey: Key,
    payloadKey: Key
) throws {
    switch message {
    case .serverHello:
        try container.encode(ServerWireMessageType.serverHello, forKey: typeKey)
    case .authRequired:
        try container.encode(ServerWireMessageType.authRequired, forKey: typeKey)
    case .pong(let payload):
        try container.encode(ServerWireMessageType.pong, forKey: typeKey)
        try payload.encode(to: container.superEncoder(forKey: payloadKey))
    case .protocolMismatch(let payload):
        try container.encode(ServerWireMessageType.protocolMismatch, forKey: typeKey)
        try payload.encode(to: container.superEncoder(forKey: payloadKey))
    case .error(let payload):
        try container.encode(ServerWireMessageType.error, forKey: typeKey)
        try payload.encode(to: container.superEncoder(forKey: payloadKey))
    case .sessionLocked(let payload):
        try container.encode(ServerWireMessageType.sessionLocked, forKey: typeKey)
        try payload.encode(to: container.superEncoder(forKey: payloadKey))
    case .info(let payload):
        try container.encode(ServerWireMessageType.info, forKey: typeKey)
        try payload.encode(to: container.superEncoder(forKey: payloadKey))
    case .interface(let payload):
        try container.encode(ServerWireMessageType.interface, forKey: typeKey)
        try payload.encode(to: container.superEncoder(forKey: payloadKey))
    case .actionResult(let payload):
        try container.encode(ServerWireMessageType.actionResult, forKey: typeKey)
        try payload.encode(to: container.superEncoder(forKey: payloadKey))
    case .screen(let payload):
        try container.encode(ServerWireMessageType.screen, forKey: typeKey)
        try payload.encode(to: container.superEncoder(forKey: payloadKey))
    case .announcements(let payload):
        try container.encode(ServerWireMessageType.announcements, forKey: typeKey)
        try payload.encode(to: container.superEncoder(forKey: payloadKey))
    case .status(let payload):
        try container.encode(ServerWireMessageType.status, forKey: typeKey)
        try payload.encode(to: container.superEncoder(forKey: payloadKey))
    }
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

private func missingServerPayload(_ type: ServerWireMessageType, codingPath: [CodingKey] = []) -> DecodingError {
    .missingPayload(key: ServerMessageCodingKeys.payload, type: type, codingPath: codingPath)
}

private func unexpectedServerPayload(_ type: ServerWireMessageType, codingPath: [CodingKey]) -> DecodingError {
    .dataCorrupted(.init(
        codingPath: codingPath,
        debugDescription: "\(type.rawValue) must not include a payload"
    ))
}
