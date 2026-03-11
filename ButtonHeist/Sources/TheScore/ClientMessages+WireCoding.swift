import Foundation

private enum ClientMessageCodingKeys: String, CodingKey {
    case type
    case payload
}

private enum RequestEnvelopeCodingKeys: String, CodingKey {
    case protocolVersion
    case requestId
    case type
    case payload
}

extension RequestEnvelope {
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: RequestEnvelopeCodingKeys.self)
        protocolVersion = try container.decode(String.self, forKey: .protocolVersion)
        requestId = try container.decodeIfPresent(String.self, forKey: .requestId)
        let type = try container.decode(WireMessageType.self, forKey: .type)
        let payloadDecoder = try? container.superDecoder(forKey: .payload)
        message = try ClientMessage.decode(from: payloadDecoder, type: type)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: RequestEnvelopeCodingKeys.self)
        try container.encode(protocolVersion, forKey: .protocolVersion)
        try container.encodeIfPresent(requestId, forKey: .requestId)
        try container.encode(message.wireMessageType, forKey: .type)
        if message.hasPayload {
            try message.encodePayload(to: container.superEncoder(forKey: .payload))
        }
    }
}

extension ClientMessage {
    fileprivate var wireMessageType: WireMessageType {
        switch self {
        case .clientHello: return .clientHello
        case .authenticate: return .authenticate
        case .requestInterface: return .requestInterface
        case .subscribe: return .subscribe
        case .unsubscribe: return .unsubscribe
        case .ping: return .ping
        case .status: return .status
        case .activate: return .activate
        case .increment: return .increment
        case .decrement: return .decrement
        case .performCustomAction: return .performCustomAction
        case .touchTap: return .touchTap
        case .touchLongPress: return .touchLongPress
        case .touchSwipe: return .touchSwipe
        case .touchDrag: return .touchDrag
        case .touchPinch: return .touchPinch
        case .touchRotate: return .touchRotate
        case .touchTwoFingerTap: return .touchTwoFingerTap
        case .touchDrawPath: return .touchDrawPath
        case .touchDrawBezier: return .touchDrawBezier
        case .typeText: return .typeText
        case .editAction: return .editAction
        case .scroll: return .scroll
        case .scrollToVisible: return .scrollToVisible
        case .scrollToEdge: return .scrollToEdge
        case .resignFirstResponder: return .resignFirstResponder
        case .waitForIdle: return .waitForIdle
        case .requestScreen: return .requestScreen
        case .startRecording: return .startRecording
        case .stopRecording: return .stopRecording
        case .watch: return .watch
        }
    }

    fileprivate var hasPayload: Bool {
        switch self {
        case .clientHello, .requestInterface, .subscribe, .unsubscribe, .ping, .status,
             .resignFirstResponder, .requestScreen, .stopRecording:
            return false
        default:
            return true
        }
    }

    private static func decodeProtocolMessage(type: WireMessageType) -> ClientMessage? {
        switch type {
        case .clientHello: return .clientHello
        case .requestInterface: return .requestInterface
        case .subscribe: return .subscribe
        case .unsubscribe: return .unsubscribe
        case .ping: return .ping
        case .status: return .status
        case .resignFirstResponder: return .resignFirstResponder
        case .requestScreen: return .requestScreen
        case .stopRecording: return .stopRecording
        default: return nil
        }
    }

    private static func decodeActionMessage(from decoder: Decoder, type: WireMessageType) throws -> ClientMessage? {
        switch type {
        case .authenticate:
            return .authenticate(try AuthenticatePayload(from: decoder))
        case .activate:
            return .activate(try ActionTarget(from: decoder))
        case .increment:
            return .increment(try ActionTarget(from: decoder))
        case .decrement:
            return .decrement(try ActionTarget(from: decoder))
        case .performCustomAction:
            return .performCustomAction(try CustomActionTarget(from: decoder))
        case .editAction:
            return .editAction(try EditActionTarget(from: decoder))
        case .watch:
            return .watch(try WatchPayload(from: decoder))
        default:
            return nil
        }
    }

    private static func decodeTouchMessage(from decoder: Decoder, type: WireMessageType) throws -> ClientMessage? {
        switch type {
        case .touchTap:
            return .touchTap(try TouchTapTarget(from: decoder))
        case .touchLongPress:
            return .touchLongPress(try LongPressTarget(from: decoder))
        case .touchSwipe:
            return .touchSwipe(try SwipeTarget(from: decoder))
        case .touchDrag:
            return .touchDrag(try DragTarget(from: decoder))
        case .touchPinch:
            return .touchPinch(try PinchTarget(from: decoder))
        case .touchRotate:
            return .touchRotate(try RotateTarget(from: decoder))
        case .touchTwoFingerTap:
            return .touchTwoFingerTap(try TwoFingerTapTarget(from: decoder))
        case .touchDrawPath:
            return .touchDrawPath(try DrawPathTarget(from: decoder))
        case .touchDrawBezier:
            return .touchDrawBezier(try DrawBezierTarget(from: decoder))
        default:
            return nil
        }
    }

    private static func decodeTextAndScrollMessage(from decoder: Decoder, type: WireMessageType) throws -> ClientMessage? {
        switch type {
        case .typeText:
            return .typeText(try TypeTextTarget(from: decoder))
        case .scroll:
            return .scroll(try ScrollTarget(from: decoder))
        case .scrollToVisible:
            return .scrollToVisible(try ActionTarget(from: decoder))
        case .scrollToEdge:
            return .scrollToEdge(try ScrollToEdgeTarget(from: decoder))
        case .waitForIdle:
            return .waitForIdle(try WaitForIdleTarget(from: decoder))
        case .startRecording:
            return .startRecording(try RecordingConfig(from: decoder))
        default:
            return nil
        }
    }

    fileprivate static func decode(from payloadDecoder: Decoder?, type: WireMessageType) throws -> ClientMessage {
        if let message = decodeProtocolMessage(type: type) {
            return message
        }

        guard let payloadDecoder else {
            throw missingClientPayload(type)
        }

        if let message = try decodeActionMessage(from: payloadDecoder, type: type) {
            return message
        }
        if let message = try decodeTouchMessage(from: payloadDecoder, type: type) {
            return message
        }
        if let message = try decodeTextAndScrollMessage(from: payloadDecoder, type: type) {
            return message
        }

        throw DecodingError.dataCorrupted(.init(
            codingPath: payloadDecoder.codingPath,
            debugDescription: "Unsupported client message type: \(type.rawValue)"
        ))
    }

    private func encodeActionPayload(to encoder: Encoder) throws -> Bool {
        switch self {
        case .authenticate(let payload):
            try payload.encode(to: encoder)
        case .activate(let payload):
            try payload.encode(to: encoder)
        case .increment(let payload):
            try payload.encode(to: encoder)
        case .decrement(let payload):
            try payload.encode(to: encoder)
        case .performCustomAction(let payload):
            try payload.encode(to: encoder)
        case .editAction(let payload):
            try payload.encode(to: encoder)
        case .watch(let payload):
            try payload.encode(to: encoder)
        default:
            return false
        }
        return true
    }

    private func encodeTouchPayload(to encoder: Encoder) throws -> Bool {
        switch self {
        case .touchTap(let payload):
            try payload.encode(to: encoder)
        case .touchLongPress(let payload):
            try payload.encode(to: encoder)
        case .touchSwipe(let payload):
            try payload.encode(to: encoder)
        case .touchDrag(let payload):
            try payload.encode(to: encoder)
        case .touchPinch(let payload):
            try payload.encode(to: encoder)
        case .touchRotate(let payload):
            try payload.encode(to: encoder)
        case .touchTwoFingerTap(let payload):
            try payload.encode(to: encoder)
        case .touchDrawPath(let payload):
            try payload.encode(to: encoder)
        case .touchDrawBezier(let payload):
            try payload.encode(to: encoder)
        default:
            return false
        }
        return true
    }

    private func encodeTextAndScrollPayload(to encoder: Encoder) throws -> Bool {
        switch self {
        case .typeText(let payload):
            try payload.encode(to: encoder)
        case .scroll(let payload):
            try payload.encode(to: encoder)
        case .scrollToVisible(let payload):
            try payload.encode(to: encoder)
        case .scrollToEdge(let payload):
            try payload.encode(to: encoder)
        case .waitForIdle(let payload):
            try payload.encode(to: encoder)
        case .startRecording(let payload):
            try payload.encode(to: encoder)
        default:
            return false
        }
        return true
    }

    fileprivate func encodePayload(to encoder: Encoder) throws {
        if try encodeActionPayload(to: encoder) { return }
        if try encodeTouchPayload(to: encoder) { return }
        if try encodeTextAndScrollPayload(to: encoder) { return }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: ClientMessageCodingKeys.self)
        let type = try container.decode(WireMessageType.self, forKey: .type)
        let payloadDecoder = try? container.superDecoder(forKey: .payload)
        self = try ClientMessage.decode(from: payloadDecoder, type: type)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: ClientMessageCodingKeys.self)
        try container.encode(wireMessageType, forKey: .type)
        if hasPayload {
            try encodePayload(to: container.superEncoder(forKey: .payload))
        }
    }
}

private func missingClientPayload(_ type: WireMessageType) -> DecodingError {
    DecodingError.keyNotFound(
        ClientMessageCodingKeys.payload,
        .init(codingPath: [], debugDescription: "Missing payload for client message type \(type.rawValue)")
    )
}
