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
    case accessibilityTrace
}

private struct EnvelopeCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int?

    init?(stringValue: String) {
        self.stringValue = stringValue
        self.intValue = nil
    }

    init?(intValue: Int) {
        self.stringValue = "\(intValue)"
        self.intValue = intValue
    }
}

// MARK: - ResponseEnvelope Codable

extension ResponseEnvelope {
    public init(from decoder: Decoder) throws {
        try Self.rejectUnknownEnvelopeKeys(decoder)
        let container = try decoder.container(keyedBy: ResponseEnvelopeCodingKeys.self)
        buttonHeistVersion = try container.decode(String.self, forKey: .buttonHeistVersion)
        requestId = try container.decodeIfPresent(String.self, forKey: .requestId)
        accessibilityTrace = try container.decodeIfPresent(AccessibilityTrace.self, forKey: .accessibilityTrace)
        let type = try container.decode(ServerWireMessageType.self, forKey: .type)
        let payloadDecoder: Decoder? = container.contains(.payload)
            ? try container.superDecoder(forKey: .payload)
            : nil
        message = try ServerMessage.decode(from: payloadDecoder, type: type)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: ResponseEnvelopeCodingKeys.self)
        try container.encode(buttonHeistVersion, forKey: .buttonHeistVersion)
        try container.encodeIfPresent(requestId, forKey: .requestId)
        try container.encodeIfPresent(accessibilityTrace, forKey: .accessibilityTrace)
        let wire = message.wireRepresentation
        try container.encode(wire.type, forKey: .type)
        if let payload = wire.payload {
            try payload.encode(to: container.superEncoder(forKey: .payload))
        }
    }

    private static func rejectUnknownEnvelopeKeys(_ decoder: Decoder) throws {
        let knownKeys = Set(ResponseEnvelopeCodingKeys.allCases.map(\.stringValue))
        let dynamicContainer = try decoder.container(keyedBy: EnvelopeCodingKey.self)
        guard let unknownKey = dynamicContainer.allKeys.first(where: { !knownKeys.contains($0.stringValue) }) else {
            return
        }
        throw DecodingError.dataCorrupted(.init(
            codingPath: decoder.codingPath + [unknownKey],
            debugDescription: "Unknown response envelope field \"\(unknownKey.stringValue)\""
        ))
    }
}

// MARK: - ServerMessage Wire Representation

extension ServerMessage {
    /// Single source of truth mapping each `ServerMessage` case to its wire
    /// type tag and (optional) payload value. Used by both encode sites in
    /// this file. Adding a new case requires extending this switch — Swift's
    /// exhaustivity check is the drift detector.
    fileprivate var wireRepresentation: (type: ServerWireMessageType, payload: (any Encodable)?) {
        switch self {
        case .serverHello: return (.serverHello, nil)
        case .authRequired: return (.authRequired, nil)
        case .authApprovalPending(let payload): return (.authApprovalPending, payload)
        case .pong(let payload): return (.pong, payload)
        case .recordingStarted: return (.recordingStarted, nil)
        case .recordingStopped: return (.recordingStopped, nil)
        case .protocolMismatch(let payload): return (.protocolMismatch, payload)
        case .authApproved(let payload): return (.authApproved, payload)
        case .error(let payload): return (.error, payload)
        case .sessionLocked(let payload): return (.sessionLocked, payload)
        case .info(let payload): return (.info, payload)
        case .interface(let payload): return (.interface, payload)
        case .actionResult(let payload): return (.actionResult, payload)
        case .screen(let payload): return (.screen, payload)
        case .interaction(let payload): return (.interaction, payload)
        case .status(let payload): return (.status, payload)
        case .recording(let payload): return (.recording, payload)
        }
    }

    // MARK: - Decoding

    fileprivate static func decode(from payloadDecoder: Decoder?, type: ServerWireMessageType) throws -> ServerMessage {
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
        case .authApprovalPending: return .authApprovalPending(try AuthApprovalPendingPayload(from: try payload()))
        case .pong: return .pong(try PongPayload(from: try payload()))
        case .recordingStarted:
            try noPayload()
            return .recordingStarted
        case .recordingStopped:
            try noPayload()
            return .recordingStopped
        case .protocolMismatch: return .protocolMismatch(try ProtocolMismatchPayload(from: try payload()))
        case .authApproved: return .authApproved(try AuthApprovedPayload(from: try payload()))
        case .error: return .error(try ServerError(from: try payload()))
        case .sessionLocked: return .sessionLocked(try SessionLockedPayload(from: try payload()))
        case .info: return .info(try ServerInfo(from: try payload()))
        case .interface: return .interface(try Interface(from: try payload()))
        case .actionResult: return .actionResult(try ActionResult(from: try payload()))
        case .screen: return .screen(try ScreenPayload(from: try payload()))
        case .interaction: return .interaction(try InteractionEvent(from: try payload()))
        case .status: return .status(try StatusPayload(from: try payload()))
        case .recording: return .recording(try RecordingPayload(from: try payload()))
        }
    }

    // MARK: - Codable Conformance

    public init(from decoder: Decoder) throws {
        try Self.rejectUnknownMessageKeys(decoder)
        let container = try decoder.container(keyedBy: ServerMessageCodingKeys.self)
        let type = try container.decode(ServerWireMessageType.self, forKey: .type)
        let payloadDecoder: Decoder? = container.contains(.payload)
            ? try container.superDecoder(forKey: .payload)
            : nil
        self = try ServerMessage.decode(from: payloadDecoder, type: type)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: ServerMessageCodingKeys.self)
        let wire = wireRepresentation
        try container.encode(wire.type, forKey: .type)
        if let payload = wire.payload {
            try payload.encode(to: container.superEncoder(forKey: .payload))
        }
    }

    private static func rejectUnknownMessageKeys(_ decoder: Decoder) throws {
        let knownKeys = Set(ServerMessageCodingKeys.allCases.map(\.stringValue))
        let dynamicContainer = try decoder.container(keyedBy: EnvelopeCodingKey.self)
        guard let unknownKey = dynamicContainer.allKeys.first(where: { !knownKeys.contains($0.stringValue) }) else {
            return
        }
        throw DecodingError.dataCorrupted(.init(
            codingPath: decoder.codingPath + [unknownKey],
            debugDescription: "Unknown server message field \"\(unknownKey.stringValue)\""
        ))
    }
}

// MARK: - Helpers

private func missingServerPayload(_ type: ServerWireMessageType, codingPath: [CodingKey] = []) -> DecodingError {
    .missingPayload(key: ServerMessageCodingKeys.payload, type: type, codingPath: codingPath)
}

private func unexpectedServerPayload(_ type: ServerWireMessageType, codingPath: [CodingKey]) -> DecodingError {
    .dataCorrupted(.init(
        codingPath: codingPath,
        debugDescription: "\(type.rawValue) must not include a payload"
    ))
}
