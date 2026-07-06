import Foundation
import ThePlans

// MARK: - Coding Keys

private enum ClientMessageCodingKeys: String, CodingKey, CaseIterable {
    case type
    case payload
}

private enum RequestEnvelopeCodingKeys: String, CodingKey, CaseIterable {
    case buttonHeistVersion
    case requestId
    case type
    case payload
}

// MARK: - RequestEnvelope Codable

extension RequestEnvelope {
    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: RequestEnvelopeCodingKeys.self, typeName: "request envelope")
        let container = try decoder.container(keyedBy: RequestEnvelopeCodingKeys.self)
        buttonHeistVersion = try container.decode(String.self, forKey: .buttonHeistVersion)
        requestId = try container.decodeIfPresent(String.self, forKey: .requestId)
        let type = try container.decode(ClientWireMessageType.self, forKey: .type)
        let payloadDecoder: Decoder? = container.contains(.payload)
            ? try container.superDecoder(forKey: .payload)
            : nil
        requestScreenPayload = type == .requestScreen
            ? try payloadDecoder.map { try ScreenRequestPayload(from: $0) }
            : nil
        message = try decodeClientMessage(from: payloadDecoder, type: type)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: RequestEnvelopeCodingKeys.self)
        try container.encode(buttonHeistVersion, forKey: .buttonHeistVersion)
        try container.encodeIfPresent(requestId, forKey: .requestId)
        let wire = clientMessageWireRepresentation(message)
        try container.encode(wire.type, forKey: .type)
        if let requestScreenPayload, case .requestScreen = message {
            try ClientMessageWirePayload.requestScreen(requestScreenPayload)
                .encode(to: container.superEncoder(forKey: .payload))
        } else if let payload = wire.payload {
            try payload.encode(to: container.superEncoder(forKey: .payload))
        }
    }

}

// MARK: - ClientMessage Wire Representation

extension ClientMessage {
    /// Explicit wire discriminator for this typed message.
    public var wireType: ClientWireMessageType {
        clientMessageWireRepresentation(self).type
    }

    // MARK: - Codable Conformance

    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: ClientMessageCodingKeys.self, typeName: "client message")
        let container = try decoder.container(keyedBy: ClientMessageCodingKeys.self)
        let type = try container.decode(ClientWireMessageType.self, forKey: .type)
        let payloadDecoder: Decoder? = container.contains(.payload)
            ? try container.superDecoder(forKey: .payload)
            : nil
        self = try decodeClientMessage(from: payloadDecoder, type: type)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: ClientMessageCodingKeys.self)
        let wire = clientMessageWireRepresentation(self)
        try container.encode(wire.type, forKey: .type)
        if let payload = wire.payload {
            try payload.encode(to: container.superEncoder(forKey: .payload))
        }
    }

}

// MARK: - Helpers

/// Single source of truth mapping each `ClientMessage` case to its wire type
/// tag and optional payload value. Adding a new case requires extending this
/// switch; Swift's exhaustivity check is the drift detector.
private func clientMessageWireRepresentation(
    _ message: ClientMessage
) -> ClientMessageWireRepresentation {
    switch message {
    case .clientHello:
        return ClientMessageWireRepresentation(type: .clientHello, payload: nil)
    case .requestInterface(let payload):
        return ClientMessageWireRepresentation(type: .requestInterface, payload: .requestInterface(payload))
    case .ping:
        return ClientMessageWireRepresentation(type: .ping, payload: nil)
    case .status:
        return ClientMessageWireRepresentation(type: .status, payload: nil)
    case .getPasteboard:
        return ClientMessageWireRepresentation(type: .getPasteboard, payload: nil)
    case .getAnnouncements:
        return ClientMessageWireRepresentation(type: .getAnnouncements, payload: nil)
    case .requestScreen:
        return ClientMessageWireRepresentation(type: .requestScreen, payload: nil)
    case .runtimeAction(let payload):
        return ClientMessageWireRepresentation(type: .runtimeAction, payload: .runtimeAction(payload))
    case .authenticate(let payload):
        return ClientMessageWireRepresentation(type: .authenticate, payload: .authenticate(payload))
    case .heistPlan(let payload):
        return ClientMessageWireRepresentation(type: .heistPlan, payload: .heistPlan(payload))
    }
}

private struct ClientMessageWireRepresentation {
    let type: ClientWireMessageType
    let payload: ClientMessageWirePayload?
}

private func decodeClientMessage(from payloadDecoder: Decoder?, type: ClientWireMessageType) throws -> ClientMessage {
    func payload() throws -> Decoder {
        guard let payloadDecoder else { throw missingClientPayload(type) }
        return payloadDecoder
    }
    func noPayload() throws {
        if let payloadDecoder {
            throw unexpectedClientPayload(type, codingPath: payloadDecoder.codingPath)
        }
    }
    switch type {
    case .clientHello:
        try noPayload()
        return .clientHello
    case .requestInterface:
        return .requestInterface(try InterfaceQuery(from: try payload()))
    case .ping:
        try noPayload()
        return .ping
    case .status:
        try noPayload()
        return .status
    case .getPasteboard:
        try noPayload()
        return .getPasteboard
    case .getAnnouncements:
        try noPayload()
        return .getAnnouncements
    case .requestScreen:
        if let payloadDecoder {
            _ = try ScreenRequestPayload(from: payloadDecoder)
        }
        return .requestScreen
    case .runtimeAction:
        return .runtimeAction(try HeistActionCommand(from: try payload()))
    case .authenticate:
        return .authenticate(try AuthenticatePayload(from: try payload()))
    case .heistPlan:
        return .heistPlan(try HeistPlanRun(from: try payload()))
    }
}

private enum ClientMessageWirePayload {
    case requestInterface(InterfaceQuery)
    case requestScreen(ScreenRequestPayload)
    case runtimeAction(HeistActionCommand)
    case authenticate(AuthenticatePayload)
    case heistPlan(HeistPlanRun)

    func encode(to encoder: Encoder) throws {
        switch self {
        case .requestInterface(let payload):
            try payload.encode(to: encoder)
        case .requestScreen(let payload):
            try payload.encode(to: encoder)
        case .runtimeAction(let payload):
            try payload.encode(to: encoder)
        case .authenticate(let payload):
            try payload.encode(to: encoder)
        case .heistPlan(let payload):
            try payload.encode(to: encoder)
        }
    }
}

private func missingClientPayload(_ type: ClientWireMessageType, codingPath: [CodingKey] = []) -> DecodingError {
    .missingPayload(key: ClientMessageCodingKeys.payload, type: type, codingPath: codingPath)
}

private func unexpectedClientPayload(_ type: ClientWireMessageType, codingPath: [CodingKey]) -> DecodingError {
    .dataCorrupted(.init(
        codingPath: codingPath,
        debugDescription: "\(type.rawValue) must not include a payload"
    ))
}
