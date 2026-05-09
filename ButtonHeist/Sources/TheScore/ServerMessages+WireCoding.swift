import Foundation

// MARK: - Coding Keys

private enum ServerMessageCodingKeys: String, CodingKey {
    case type
    case payload
}

private enum ResponseEnvelopeCodingKeys: String, CodingKey {
    case buttonHeistVersion
    case requestId
    case type
    case payload
    case backgroundDelta
}

// MARK: - ResponseEnvelope Codable

extension ResponseEnvelope {
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: ResponseEnvelopeCodingKeys.self)
        buttonHeistVersion = try container.decode(String.self, forKey: .buttonHeistVersion)
        requestId = try container.decodeIfPresent(String.self, forKey: .requestId)
        backgroundDelta = try container.decodeIfPresent(InterfaceDelta.self, forKey: .backgroundDelta)
        let type = try container.decode(WireMessageType.self, forKey: .type)
        let payloadDecoder: Decoder? = container.contains(.payload)
            ? try container.superDecoder(forKey: .payload)
            : nil
        message = try ServerMessage.decode(from: payloadDecoder, type: type)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: ResponseEnvelopeCodingKeys.self)
        try container.encode(buttonHeistVersion, forKey: .buttonHeistVersion)
        try container.encodeIfPresent(requestId, forKey: .requestId)
        try container.encodeIfPresent(backgroundDelta, forKey: .backgroundDelta)
        let wire = message.wireRepresentation
        try container.encode(wire.type, forKey: .type)
        if let payload = wire.payload {
            try payload.encode(to: container.superEncoder(forKey: .payload))
        }
    }
}

// MARK: - ServerMessage Wire Representation

extension ServerMessage {
    /// Single source of truth mapping each `ServerMessage` case to its wire
    /// type tag and (optional) payload value. Used by both encode sites in
    /// this file. Adding a new case requires extending this switch — Swift's
    /// exhaustivity check is the drift detector.
    fileprivate var wireRepresentation: (type: WireMessageType, payload: (any Encodable)?) {
        switch self {
        case .serverHello: return (.serverHello, nil)
        case .authRequired: return (.authRequired, nil)
        case .pong: return (.pong, nil)
        case .recordingStarted: return (.recordingStarted, nil)
        case .recordingStopped: return (.recordingStopped, nil)
        case .protocolMismatch(let payload): return (.protocolMismatch, payload)
        case .authFailed(let payload): return (.authFailed, payload)
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
        case .recordingError(let payload): return (.recordingError, payload)
        }
    }

    // MARK: - Decoding

    fileprivate static func decode(from payloadDecoder: Decoder?, type: WireMessageType) throws -> ServerMessage {
        func payload() throws -> Decoder {
            guard let payloadDecoder else { throw missingServerPayload(type) }
            return payloadDecoder
        }
        switch type {
        case .serverHello: return .serverHello
        case .authRequired: return .authRequired
        case .pong: return .pong
        case .recordingStarted: return .recordingStarted
        case .recordingStopped: return .recordingStopped
        case .protocolMismatch: return .protocolMismatch(try ProtocolMismatchPayload(from: try payload()))
        case .authFailed: return .authFailed(try String(from: try payload()))
        case .authApproved: return .authApproved(try AuthApprovedPayload(from: try payload()))
        case .error: return .error(try String(from: try payload()))
        case .sessionLocked: return .sessionLocked(try SessionLockedPayload(from: try payload()))
        case .info: return .info(try ServerInfo(from: try payload()))
        case .interface: return .interface(try Interface(from: try payload()))
        case .actionResult: return .actionResult(try ActionResult(from: try payload()))
        case .screen: return .screen(try ScreenPayload(from: try payload()))
        case .interaction: return .interaction(try InteractionEvent(from: try payload()))
        case .status: return .status(try StatusPayload(from: try payload()))
        case .recording: return .recording(try RecordingPayload(from: try payload()))
        case .recordingError: return .recordingError(try String(from: try payload()))
        default:
            throw DecodingError.dataCorrupted(.init(
                codingPath: payloadDecoder?.codingPath ?? [],
                debugDescription: "Unsupported server message type: \(type.rawValue)"
            ))
        }
    }

    // MARK: - Codable Conformance

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: ServerMessageCodingKeys.self)
        let type = try container.decode(WireMessageType.self, forKey: .type)
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
}

// MARK: - Helpers

private func missingServerPayload(_ type: WireMessageType, codingPath: [CodingKey] = []) -> DecodingError {
    .missingPayload(key: ServerMessageCodingKeys.payload, type: type, codingPath: codingPath)
}
