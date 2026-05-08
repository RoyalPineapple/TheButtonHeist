import Foundation

// MARK: - Coding Keys

private enum ServerMessageCodingKeys: String, CodingKey {
    case type
    case payload
}

private enum ResponseEnvelopeCodingKeys: String, CodingKey {
    case protocolVersion
    case requestId
    case type
    case payload
    case backgroundDelta
}

// MARK: - ResponseEnvelope Codable

extension ResponseEnvelope {
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: ResponseEnvelopeCodingKeys.self)
        protocolVersion = try container.decode(String.self, forKey: .protocolVersion)
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
        try container.encode(protocolVersion, forKey: .protocolVersion)
        try container.encodeIfPresent(requestId, forKey: .requestId)
        try container.encodeIfPresent(backgroundDelta, forKey: .backgroundDelta)
        try container.encode(message.wireMessageType, forKey: .type)
        if message.hasPayload {
            try message.encodePayload(to: container.superEncoder(forKey: .payload))
        }
    }
}

// MARK: - ServerMessage Wire Type Mapping

extension ServerMessage {
    fileprivate var wireMessageType: WireMessageType {
        switch self {
        case .serverHello: return .serverHello
        case .protocolMismatch: return .protocolMismatch
        case .authRequired: return .authRequired
        case .authFailed: return .authFailed
        case .authApproved: return .authApproved
        case .info: return .info
        case .interface: return .interface
        case .pong: return .pong
        case .error: return .error
        case .actionResult: return .actionResult
        case .screen: return .screen
        case .sessionLocked: return .sessionLocked
        case .recordingStarted: return .recordingStarted
        case .recordingStopped: return .recordingStopped
        case .recording: return .recording
        case .recordingError: return .recordingError
        case .interaction: return .interaction
        case .status: return .status
        }
    }

    fileprivate var hasPayload: Bool {
        switch self {
        case .serverHello, .authRequired, .pong, .recordingStarted, .recordingStopped:
            return false
        default:
            return true
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

    // MARK: - Encoding

    fileprivate func encodePayload(to encoder: Encoder) throws {
        switch self {
        case .serverHello, .authRequired, .pong, .recordingStarted, .recordingStopped:
            return
        case .protocolMismatch(let payload): try payload.encode(to: encoder)
        case .authFailed(let payload): try payload.encode(to: encoder)
        case .authApproved(let payload): try payload.encode(to: encoder)
        case .error(let payload): try payload.encode(to: encoder)
        case .sessionLocked(let payload): try payload.encode(to: encoder)
        case .info(let payload): try payload.encode(to: encoder)
        case .interface(let payload): try payload.encode(to: encoder)
        case .actionResult(let payload): try payload.encode(to: encoder)
        case .screen(let payload): try payload.encode(to: encoder)
        case .interaction(let payload): try payload.encode(to: encoder)
        case .status(let payload): try payload.encode(to: encoder)
        case .recording(let payload): try payload.encode(to: encoder)
        case .recordingError(let payload): try payload.encode(to: encoder)
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
        try container.encode(wireMessageType, forKey: .type)
        if hasPayload {
            try encodePayload(to: container.superEncoder(forKey: .payload))
        }
    }
}

// MARK: - Helpers

private func missingServerPayload(_ type: WireMessageType, codingPath: [CodingKey] = []) -> DecodingError {
    .missingPayload(key: ServerMessageCodingKeys.payload, type: type, codingPath: codingPath)
}
