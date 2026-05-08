import Foundation

// MARK: - Coding Keys

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

// MARK: - RequestEnvelope Codable

extension RequestEnvelope {
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: RequestEnvelopeCodingKeys.self)
        protocolVersion = try container.decode(String.self, forKey: .protocolVersion)
        requestId = try container.decodeIfPresent(String.self, forKey: .requestId)
        let type = try container.decode(WireMessageType.self, forKey: .type)
        let payloadDecoder: Decoder? = container.contains(.payload)
            ? try container.superDecoder(forKey: .payload)
            : nil
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

// MARK: - ClientMessage Wire Type Mapping

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
        case .setPasteboard: return .setPasteboard
        case .getPasteboard: return .getPasteboard
        case .scroll: return .scroll
        case .scrollToVisible: return .scrollToVisible
        case .elementSearch: return .elementSearch
        case .scrollToEdge: return .scrollToEdge
        case .resignFirstResponder: return .resignFirstResponder
        case .waitForIdle: return .waitForIdle
        case .waitFor: return .waitFor
        case .waitForChange: return .waitForChange
        case .requestScreen: return .requestScreen
        case .explore: return .explore
        case .startRecording: return .startRecording
        case .stopRecording: return .stopRecording
        case .watch: return .watch
        }
    }

    fileprivate var hasPayload: Bool {
        switch self {
        case .clientHello, .requestInterface, .subscribe, .unsubscribe, .ping, .status,
             .resignFirstResponder, .getPasteboard, .requestScreen, .explore, .stopRecording:
            return false
        default:
            return true
        }
    }

    // MARK: - Decoding

    fileprivate static func decode(from payloadDecoder: Decoder?, type: WireMessageType) throws -> ClientMessage {
        func payload() throws -> Decoder {
            guard let payloadDecoder else { throw missingClientPayload(type) }
            return payloadDecoder
        }
        switch type {
        case .clientHello: return .clientHello
        case .requestInterface: return .requestInterface
        case .subscribe: return .subscribe
        case .unsubscribe: return .unsubscribe
        case .ping: return .ping
        case .status: return .status
        case .resignFirstResponder: return .resignFirstResponder
        case .getPasteboard: return .getPasteboard
        case .requestScreen: return .requestScreen
        case .explore: return .explore
        case .stopRecording: return .stopRecording
        case .authenticate: return .authenticate(try AuthenticatePayload(from: try payload()))
        case .activate: return .activate(try ElementTarget(from: try payload()))
        case .increment: return .increment(try ElementTarget(from: try payload()))
        case .decrement: return .decrement(try ElementTarget(from: try payload()))
        case .performCustomAction: return .performCustomAction(try CustomActionTarget(from: try payload()))
        case .editAction: return .editAction(try EditActionTarget(from: try payload()))
        case .setPasteboard: return .setPasteboard(try SetPasteboardTarget(from: try payload()))
        case .watch: return .watch(try WatchPayload(from: try payload()))
        case .touchTap: return .touchTap(try TouchTapTarget(from: try payload()))
        case .touchLongPress: return .touchLongPress(try LongPressTarget(from: try payload()))
        case .touchSwipe: return .touchSwipe(try SwipeTarget(from: try payload()))
        case .touchDrag: return .touchDrag(try DragTarget(from: try payload()))
        case .touchPinch: return .touchPinch(try PinchTarget(from: try payload()))
        case .touchRotate: return .touchRotate(try RotateTarget(from: try payload()))
        case .touchTwoFingerTap: return .touchTwoFingerTap(try TwoFingerTapTarget(from: try payload()))
        case .touchDrawPath: return .touchDrawPath(try DrawPathTarget(from: try payload()))
        case .touchDrawBezier: return .touchDrawBezier(try DrawBezierTarget(from: try payload()))
        case .typeText: return .typeText(try TypeTextTarget(from: try payload()))
        case .scroll: return .scroll(try ScrollTarget(from: try payload()))
        case .scrollToVisible: return .scrollToVisible(try ScrollToVisibleTarget(from: try payload()))
        case .elementSearch: return .elementSearch(try ElementSearchTarget(from: try payload()))
        case .scrollToEdge: return .scrollToEdge(try ScrollToEdgeTarget(from: try payload()))
        case .waitForIdle: return .waitForIdle(try WaitForIdleTarget(from: try payload()))
        case .waitFor: return .waitFor(try WaitForTarget(from: try payload()))
        case .waitForChange: return .waitForChange(try WaitForChangeTarget(from: try payload()))
        case .startRecording: return .startRecording(try RecordingConfig(from: try payload()))
        default:
            throw DecodingError.dataCorrupted(.init(
                codingPath: payloadDecoder?.codingPath ?? [],
                debugDescription: "Unsupported client message type: \(type.rawValue)"
            ))
        }
    }

    // MARK: - Encoding

    fileprivate func encodePayload(to encoder: Encoder) throws {
        switch self {
        case .clientHello, .requestInterface, .subscribe, .unsubscribe, .ping, .status,
             .resignFirstResponder, .getPasteboard, .requestScreen, .explore, .stopRecording:
            return
        case .authenticate(let payload): try payload.encode(to: encoder)
        case .activate(let payload): try payload.encode(to: encoder)
        case .increment(let payload): try payload.encode(to: encoder)
        case .decrement(let payload): try payload.encode(to: encoder)
        case .performCustomAction(let payload): try payload.encode(to: encoder)
        case .editAction(let payload): try payload.encode(to: encoder)
        case .setPasteboard(let payload): try payload.encode(to: encoder)
        case .watch(let payload): try payload.encode(to: encoder)
        case .touchTap(let payload): try payload.encode(to: encoder)
        case .touchLongPress(let payload): try payload.encode(to: encoder)
        case .touchSwipe(let payload): try payload.encode(to: encoder)
        case .touchDrag(let payload): try payload.encode(to: encoder)
        case .touchPinch(let payload): try payload.encode(to: encoder)
        case .touchRotate(let payload): try payload.encode(to: encoder)
        case .touchTwoFingerTap(let payload): try payload.encode(to: encoder)
        case .touchDrawPath(let payload): try payload.encode(to: encoder)
        case .touchDrawBezier(let payload): try payload.encode(to: encoder)
        case .typeText(let payload): try payload.encode(to: encoder)
        case .scroll(let payload): try payload.encode(to: encoder)
        case .scrollToVisible(let payload): try payload.encode(to: encoder)
        case .elementSearch(let payload): try payload.encode(to: encoder)
        case .scrollToEdge(let payload): try payload.encode(to: encoder)
        case .waitForIdle(let payload): try payload.encode(to: encoder)
        case .waitFor(let payload): try payload.encode(to: encoder)
        case .waitForChange(let payload): try payload.encode(to: encoder)
        case .startRecording(let payload): try payload.encode(to: encoder)
        }
    }

    // MARK: - Codable Conformance

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: ClientMessageCodingKeys.self)
        let type = try container.decode(WireMessageType.self, forKey: .type)
        let payloadDecoder: Decoder? = container.contains(.payload)
            ? try container.superDecoder(forKey: .payload)
            : nil
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

// MARK: - Helpers

private func missingClientPayload(_ type: WireMessageType, codingPath: [CodingKey] = []) -> DecodingError {
    .missingPayload(key: ClientMessageCodingKeys.payload, type: type, codingPath: codingPath)
}
