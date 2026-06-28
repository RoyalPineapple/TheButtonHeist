import Foundation

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
        message = try ClientMessage.decode(from: payloadDecoder, type: type)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: RequestEnvelopeCodingKeys.self)
        try container.encode(buttonHeistVersion, forKey: .buttonHeistVersion)
        try container.encodeIfPresent(requestId, forKey: .requestId)
        let wire = message.wireRepresentation
        try container.encode(wire.type, forKey: .type)
        if let payload = wire.payload {
            try payload.encode(to: container.superEncoder(forKey: .payload))
        }
    }

}

// MARK: - ClientMessage Wire Representation

extension ClientMessage {
    /// Explicit wire discriminator for this typed message.
    public var wireType: ClientWireMessageType {
        wireRepresentation.type
    }

    /// Single source of truth mapping each `ClientMessage` case to its wire
    /// type tag and (optional) payload value. Used by both encode sites in
    /// this file. Adding a new case requires extending this switch — Swift's
    /// exhaustivity check is the drift detector.
    fileprivate var wireRepresentation: (type: ClientWireMessageType, payload: ClientMessageWirePayload?) {
        switch self {
        case .clientHello: return (.clientHello, nil)
        case .requestInterface(let payload): return (.requestInterface, .requestInterface(payload))
        case .ping: return (.ping, nil)
        case .status: return (.status, nil)
        case .getPasteboard: return (.getPasteboard, nil)
        case .requestScreen: return (.requestScreen, nil)
        case .authenticate(let payload): return (.authenticate, .authenticate(payload))
        case .heistPlan(let payload): return (.heistPlan, .heistPlan(payload))
        }
    }

    // MARK: - Decoding

    fileprivate static func decode(from payloadDecoder: Decoder?, type: ClientWireMessageType) throws -> ClientMessage {
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
        case .requestInterface: return .requestInterface(try InterfaceQuery(from: try payload()))
        case .ping:
            try noPayload()
            return .ping
        case .status:
            try noPayload()
            return .status
        case .getPasteboard:
            try noPayload()
            return .getPasteboard
        case .requestScreen:
            try noPayload()
            return .requestScreen
        case .authenticate: return .authenticate(try AuthenticatePayload(from: try payload()))
        case .heistPlan: return .heistPlan(try HeistPlanRun(from: try payload()))
        }
    }

    // MARK: - Codable Conformance

    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: ClientMessageCodingKeys.self, typeName: "client message")
        let container = try decoder.container(keyedBy: ClientMessageCodingKeys.self)
        let type = try container.decode(ClientWireMessageType.self, forKey: .type)
        let payloadDecoder: Decoder? = container.contains(.payload)
            ? try container.superDecoder(forKey: .payload)
            : nil
        self = try ClientMessage.decode(from: payloadDecoder, type: type)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: ClientMessageCodingKeys.self)
        let wire = wireRepresentation
        try container.encode(wire.type, forKey: .type)
        if let payload = wire.payload {
            try payload.encode(to: container.superEncoder(forKey: .payload))
        }
    }

}

// MARK: - Helpers

private enum ClientMessageWirePayload {
    case requestInterface(InterfaceQuery)
    case authenticate(AuthenticatePayload)
    case heistPlan(HeistPlanRun)

    func encode(to encoder: Encoder) throws {
        switch self {
        case .requestInterface(let payload):
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
