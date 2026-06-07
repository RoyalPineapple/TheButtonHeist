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
        try rejectInternalMutatingClientMessage(wire.type, codingPath: encoder.codingPath)
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
        case .typeText(let payload): return (.typeText, payload)
        case .scroll(let payload): return (.scroll, payload)
        case .scrollToVisible(let payload): return (.scrollToVisible, payload)
        case .scrollToEdge(let payload): return (.scrollToEdge, payload)
        case .wait(let payload): return (.wait, payload)
        case .heistPlan(let payload): return (.heistPlan, payload)
        }
    }

    // MARK: - Decoding

    fileprivate static func decode(from payloadDecoder: Decoder?, type: ClientWireMessageType) throws -> ClientMessage {
        guard type.isPublicWireRequestType else {
            throw internalMutatingClientMessage(type, codingPath: payloadDecoder?.codingPath ?? [])
        }
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
        case .typeText: return .typeText(try TypeTextTarget(from: try payload()))
        case .scroll: return .scroll(try ScrollTarget(from: try payload()))
        case .scrollToVisible: return .scrollToVisible(try ScrollToVisibleTarget(from: try payload()))
        case .scrollToEdge: return .scrollToEdge(try ScrollToEdgeTarget(from: try payload()))
        case .wait: return .wait(try WaitTarget(from: try payload()))
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
        try rejectInternalMutatingClientMessage(wire.type, codingPath: encoder.codingPath)
        try container.encode(wire.type, forKey: .type)
        if let payload = wire.payload {
            try payload.encode(to: container.superEncoder(forKey: .payload))
        }
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

private func internalMutatingClientMessage(_ type: ClientWireMessageType, codingPath: [CodingKey]) -> DecodingError {
    .dataCorrupted(.init(
        codingPath: codingPath,
        debugDescription: "\(type.rawValue) is an internal heist dispatch primitive; public mutating requests must be sent as heistPlan"
    ))
}

private func rejectInternalMutatingClientMessage(_ type: ClientWireMessageType, codingPath: [CodingKey]) throws {
    guard type.isPublicWireRequestType else {
        throw EncodingError.invalidValue(type.rawValue, .init(
            codingPath: codingPath,
            debugDescription: "\(type.rawValue) is an internal heist dispatch primitive; public mutating requests must be sent as heistPlan"
        ))
    }
}
