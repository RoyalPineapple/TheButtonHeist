import Foundation

// MARK: - Coding Keys

private enum ClientMessageCodingKeys: String, CodingKey {
    case type
    case payload
}

private enum RequestEnvelopeCodingKeys: String, CodingKey {
    case buttonHeistVersion
    case requestId
    case type
    case payload
}

// MARK: - RequestEnvelope Codable

extension RequestEnvelope {
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: RequestEnvelopeCodingKeys.self)
        buttonHeistVersion = try container.decode(String.self, forKey: .buttonHeistVersion)
        requestId = try container.decodeIfPresent(String.self, forKey: .requestId)
        let type = try container.decode(WireMessageType.self, forKey: .type)
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
    /// Single source of truth mapping each `ClientMessage` case to its wire
    /// type tag and (optional) payload value. Used by both encode sites in
    /// this file. Adding a new case requires extending this switch — Swift's
    /// exhaustivity check is the drift detector.
    fileprivate var wireRepresentation: (type: WireMessageType, payload: (any Encodable)?) {
        switch self {
        case .clientHello: return (.clientHello, nil)
        case .requestInterface: return (.requestInterface, nil)
        case .subscribe: return (.subscribe, nil)
        case .unsubscribe: return (.unsubscribe, nil)
        case .ping: return (.ping, nil)
        case .status: return (.status, nil)
        case .resignFirstResponder: return (.resignFirstResponder, nil)
        case .getPasteboard: return (.getPasteboard, nil)
        case .requestScreen: return (.requestScreen, nil)
        case .explore: return (.explore, nil)
        case .stopRecording: return (.stopRecording, nil)
        case .authenticate(let payload): return (.authenticate, payload)
        case .activate(let payload): return (.activate, payload)
        case .increment(let payload): return (.increment, payload)
        case .decrement(let payload): return (.decrement, payload)
        case .performCustomAction(let payload): return (.performCustomAction, payload)
        case .editAction(let payload): return (.editAction, payload)
        case .setPasteboard(let payload): return (.setPasteboard, payload)
        case .watch(let payload): return (.watch, payload)
        case .touchTap(let payload): return (.touchTap, payload)
        case .touchLongPress(let payload): return (.touchLongPress, payload)
        case .touchSwipe(let payload): return (.touchSwipe, payload)
        case .touchDrag(let payload): return (.touchDrag, payload)
        case .touchPinch(let payload): return (.touchPinch, payload)
        case .touchRotate(let payload): return (.touchRotate, payload)
        case .touchTwoFingerTap(let payload): return (.touchTwoFingerTap, payload)
        case .touchDrawPath(let payload): return (.touchDrawPath, payload)
        case .touchDrawBezier(let payload): return (.touchDrawBezier, payload)
        case .typeText(let payload): return (.typeText, payload)
        case .scroll(let payload): return (.scroll, payload)
        case .scrollToVisible(let payload): return (.scrollToVisible, payload)
        case .elementSearch(let payload): return (.elementSearch, payload)
        case .scrollToEdge(let payload): return (.scrollToEdge, payload)
        case .waitForIdle(let payload): return (.waitForIdle, payload)
        case .waitFor(let payload): return (.waitFor, payload)
        case .waitForChange(let payload): return (.waitForChange, payload)
        case .startRecording(let payload): return (.startRecording, payload)
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
        let wire = wireRepresentation
        try container.encode(wire.type, forKey: .type)
        if let payload = wire.payload {
            try payload.encode(to: container.superEncoder(forKey: .payload))
        }
    }
}

// MARK: - Helpers

private func missingClientPayload(_ type: WireMessageType, codingPath: [CodingKey] = []) -> DecodingError {
    .missingPayload(key: ClientMessageCodingKeys.payload, type: type, codingPath: codingPath)
}
