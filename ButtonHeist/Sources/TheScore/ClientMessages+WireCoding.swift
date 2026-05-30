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

private struct RequestEnvelopeUnknownKey: CodingKey {
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

// MARK: - RequestEnvelope Codable

extension RequestEnvelope {
    public init(from decoder: Decoder) throws {
        try Self.rejectUnknownEnvelopeKeys(decoder)
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

    private static func rejectUnknownEnvelopeKeys(_ decoder: Decoder) throws {
        let knownKeys = Set(RequestEnvelopeCodingKeys.allCases.map(\.stringValue))
        let dynamicContainer = try decoder.container(keyedBy: RequestEnvelopeUnknownKey.self)
        guard let unknownKey = dynamicContainer.allKeys.first(where: { !knownKeys.contains($0.stringValue) }) else {
            return
        }
        throw DecodingError.dataCorrupted(.init(
            codingPath: decoder.codingPath + [unknownKey],
            debugDescription: "Unknown request envelope field \"\(unknownKey.stringValue)\""
        ))
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
    fileprivate var wireRepresentation: (type: ClientWireMessageType, payload: (any Encodable)?) {
        switch self {
        case .clientHello: return (.clientHello, nil)
        case .requestInterface(let payload): return (.requestInterface, payload)
        case .ping: return (.ping, nil)
        case .status: return (.status, nil)
        case .resignFirstResponder: return (.resignFirstResponder, nil)
        case .getPasteboard: return (.getPasteboard, nil)
        case .requestScreen: return (.requestScreen, nil)
        case .authenticate(let payload): return (.authenticate, payload)
        case .activate(let payload): return (.activate, payload)
        case .increment(let payload): return (.increment, payload)
        case .decrement(let payload): return (.decrement, payload)
        case .performCustomAction(let payload): return (.performCustomAction, payload)
        case .rotor(let payload): return (.rotor, payload)
        case .editAction(let payload): return (.editAction, payload)
        case .setPasteboard(let payload): return (.setPasteboard, payload)
        case .oneFingerTap(let payload): return (.oneFingerTap, payload)
        case .longPress(let payload): return (.longPress, payload)
        case .swipe(let payload): return (.swipe, payload)
        case .drag(let payload): return (.drag, payload)
        case .pinch(let payload): return (.pinch, payload)
        case .rotate(let payload): return (.rotate, payload)
        case .twoFingerTap(let payload): return (.twoFingerTap, payload)
        case .drawPath(let payload): return (.drawPath, payload)
        case .drawBezier(let payload): return (.drawBezier, payload)
        case .typeText(let payload): return (.typeText, payload)
        case .scroll(let payload): return (.scroll, payload)
        case .scrollToVisible(let payload): return (.scrollToVisible, payload)
        case .elementSearch(let payload): return (.elementSearch, payload)
        case .scrollToEdge(let payload): return (.scrollToEdge, payload)
        case .waitForIdle(let payload): return (.waitForIdle, payload)
        case .waitFor(let payload): return (.waitFor, payload)
        case .waitForChange(let payload): return (.waitForChange, payload)
        case .batchExecutionPlan(let payload): return (.batchExecutionPlan, payload)
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
        case .resignFirstResponder:
            try noPayload()
            return .resignFirstResponder
        case .getPasteboard:
            try noPayload()
            return .getPasteboard
        case .requestScreen:
            try noPayload()
            return .requestScreen
        case .authenticate: return .authenticate(try AuthenticatePayload(from: try payload()))
        case .activate: return .activate(try ElementTarget(from: try payload()))
        case .increment: return .increment(try ElementTarget(from: try payload()))
        case .decrement: return .decrement(try ElementTarget(from: try payload()))
        case .performCustomAction: return .performCustomAction(try CustomActionTarget(from: try payload()))
        case .rotor: return .rotor(try RotorTarget(from: try payload()))
        case .editAction: return .editAction(try EditActionTarget(from: try payload()))
        case .setPasteboard: return .setPasteboard(try SetPasteboardTarget(from: try payload()))
        case .oneFingerTap: return .oneFingerTap(try TapTarget(from: try payload()))
        case .longPress: return .longPress(try LongPressTarget(from: try payload()))
        case .swipe: return .swipe(try SwipeTarget(from: try payload()))
        case .drag: return .drag(try DragTarget(from: try payload()))
        case .pinch: return .pinch(try PinchTarget(from: try payload()))
        case .rotate: return .rotate(try RotateTarget(from: try payload()))
        case .twoFingerTap: return .twoFingerTap(try TwoFingerTapTarget(from: try payload()))
        case .drawPath: return .drawPath(try DrawPathTarget(from: try payload()))
        case .drawBezier: return .drawBezier(try DrawBezierTarget(from: try payload()))
        case .typeText: return .typeText(try TypeTextTarget(from: try payload()))
        case .scroll: return .scroll(try ScrollTarget(from: try payload()))
        case .scrollToVisible: return .scrollToVisible(try ScrollToVisibleTarget(from: try payload()))
        case .elementSearch: return .elementSearch(try ElementSearchTarget(from: try payload()))
        case .scrollToEdge: return .scrollToEdge(try ScrollToEdgeTarget(from: try payload()))
        case .waitForIdle: return .waitForIdle(try WaitForIdleTarget(from: try payload()))
        case .waitFor: return .waitFor(try WaitForTarget(from: try payload()))
        case .waitForChange: return .waitForChange(try WaitForChangeTarget(from: try payload()))
        case .batchExecutionPlan: return .batchExecutionPlan(try TheScore.BatchPlan(from: try payload()))
        }
    }

    // MARK: - Codable Conformance

    public init(from decoder: Decoder) throws {
        try Self.rejectUnknownMessageKeys(decoder)
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

    private static func rejectUnknownMessageKeys(_ decoder: Decoder) throws {
        let knownKeys = Set(ClientMessageCodingKeys.allCases.map(\.stringValue))
        let dynamicContainer = try decoder.container(keyedBy: RequestEnvelopeUnknownKey.self)
        guard let unknownKey = dynamicContainer.allKeys.first(where: { !knownKeys.contains($0.stringValue) }) else {
            return
        }
        throw DecodingError.dataCorrupted(.init(
            codingPath: decoder.codingPath + [unknownKey],
            debugDescription: "Unknown client message field \"\(unknownKey.stringValue)\""
        ))
    }
}

// MARK: - Helpers

private func missingClientPayload(_ type: ClientWireMessageType, codingPath: [CodingKey] = []) -> DecodingError {
    .missingPayload(key: ClientMessageCodingKeys.payload, type: type, codingPath: codingPath)
}

private func unexpectedClientPayload(_ type: ClientWireMessageType, codingPath: [CodingKey]) -> DecodingError {
    .dataCorrupted(.init(
        codingPath: codingPath,
        debugDescription: "\(type.rawValue) must not include a payload"
    ))
}
