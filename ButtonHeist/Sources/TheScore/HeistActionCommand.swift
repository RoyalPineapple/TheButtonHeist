import Foundation

public enum HeistActionCommand: Codable, Sendable, Equatable {
    case activate(ElementTargetExpr)
    case increment(ElementTargetExpr)
    case decrement(ElementTargetExpr)
    case customAction(name: String, target: ElementTargetExpr)
    case rotor(selection: RotorSelection, target: ElementTargetExpr, direction: RotorDirection)
    case typeText(text: StringExpr, target: ElementTargetExpr?)
    case mechanicalTap(TapTarget)
    case mechanicalLongPress(LongPressTarget)
    case mechanicalSwipe(SwipeTarget)
    case mechanicalDrag(DragTarget)
    case viewportScroll(ScrollTarget)
    case viewportScrollToVisible(ElementTargetExpr)
    case viewportScrollToEdge(ScrollToEdgeTarget)
    case editAction(EditActionTarget)
    case setPasteboard(SetPasteboardTarget)
    case dismissKeyboard

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case type, payload
    }

    public init(clientMessage: ClientMessage) throws {
        switch clientMessage {
        case .activate(let target):
            self = .activate(.target(target))
        case .increment(let target):
            self = .increment(.target(target))
        case .decrement(let target):
            self = .decrement(.target(target))
        case .performCustomAction(let target):
            self = .customAction(name: target.actionName, target: .target(target.elementTarget))
        case .rotor(let target):
            self = .rotor(selection: target.selection, target: .target(target.elementTarget), direction: target.direction)
        case .typeText(let target):
            self = .typeText(
                text: .literal(target.text),
                target: target.elementTarget.map(ElementTargetExpr.target)
            )
        case .oneFingerTap(let target):
            self = .mechanicalTap(target)
        case .longPress(let target):
            self = .mechanicalLongPress(target)
        case .swipe(let target):
            self = .mechanicalSwipe(target)
        case .drag(let target):
            self = .mechanicalDrag(target)
        case .scroll(let target):
            self = .viewportScroll(target)
        case .scrollToVisible(let target):
            self = .viewportScrollToVisible(.target(target.elementTarget))
        case .scrollToEdge(let target):
            self = .viewportScrollToEdge(target)
        case .editAction(let target):
            self = .editAction(target)
        case .setPasteboard(let target):
            self = .setPasteboard(target)
        case .resignFirstResponder:
            self = .dismissKeyboard
        case .clientHello, .authenticate, .requestInterface, .ping, .status,
             .getPasteboard, .requestScreen, .wait, .heistPlan:
            throw HeistExpressionError.unsupportedHeistActionCommand(clientMessage.wireType.rawValue)
        }
    }

    public var wireType: ClientWireMessageType {
        switch self {
        case .activate: return .activate
        case .increment: return .increment
        case .decrement: return .decrement
        case .customAction: return .performCustomAction
        case .rotor: return .rotor
        case .typeText: return .typeText
        case .mechanicalTap: return .oneFingerTap
        case .mechanicalLongPress: return .longPress
        case .mechanicalSwipe: return .swipe
        case .mechanicalDrag: return .drag
        case .viewportScroll: return .scroll
        case .viewportScrollToVisible: return .scrollToVisible
        case .viewportScrollToEdge: return .scrollToEdge
        case .editAction: return .editAction
        case .setPasteboard: return .setPasteboard
        case .dismissKeyboard: return .resignFirstResponder
        }
    }

    public func resolve(in environment: HeistExecutionEnvironment) throws -> ClientMessage {
        switch self {
        case .activate(let target):
            return .activate(try target.resolve(in: environment))
        case .increment(let target):
            return .increment(try target.resolve(in: environment))
        case .decrement(let target):
            return .decrement(try target.resolve(in: environment))
        case .customAction(let name, let target):
            return .performCustomAction(CustomActionTarget(
                elementTarget: try target.resolve(in: environment),
                actionName: name
            ))
        case .rotor(let selection, let target, let direction):
            return .rotor(RotorTarget(
                elementTarget: try target.resolve(in: environment),
                selection: selection,
                direction: direction
            ))
        case .typeText(let text, let target):
            let resolvedText = try text.resolve(in: environment)
            return .typeText(try TypeTextTarget(
                validatingText: resolvedText,
                elementTarget: try target?.resolve(in: environment)
            ))
        case .mechanicalTap(let target):
            return .oneFingerTap(target)
        case .mechanicalLongPress(let target):
            return .longPress(target)
        case .mechanicalSwipe(let target):
            return .swipe(target)
        case .mechanicalDrag(let target):
            return .drag(target)
        case .viewportScroll(let target):
            return .scroll(target)
        case .viewportScrollToVisible(let target):
            return .scrollToVisible(ScrollToVisibleTarget(elementTarget: try target.resolve(in: environment)))
        case .viewportScrollToEdge(let target):
            return .scrollToEdge(target)
        case .editAction(let target):
            return .editAction(target)
        case .setPasteboard(let target):
            return .setPasteboard(target)
        case .dismissKeyboard:
            return .resignFirstResponder
        }
    }

    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "heist action command")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(ClientWireMessageType.self, forKey: .type)
        let payloadDecoder = container.contains(.payload) ? try container.superDecoder(forKey: .payload) : nil
        func payload() throws -> Decoder {
            guard let payloadDecoder else {
                throw DecodingError.missingPayload(key: CodingKeys.payload, type: type, codingPath: container.codingPath)
            }
            return payloadDecoder
        }
        switch type {
        case .activate:
            self = .activate(try TargetExprPayload(from: try payload()).target)
        case .increment:
            self = .increment(try TargetExprPayload(from: try payload()).target)
        case .decrement:
            self = .decrement(try TargetExprPayload(from: try payload()).target)
        case .performCustomAction:
            let payload = try CustomActionExprPayload(from: try payload())
            self = .customAction(name: payload.actionName, target: payload.target)
        case .rotor:
            let payload = try RotorExprPayload(from: try payload())
            self = .rotor(selection: payload.selection, target: payload.target, direction: payload.direction)
        case .typeText:
            let payload = try TypeTextExprPayload(from: try payload())
            self = .typeText(text: payload.text, target: payload.target)
        case .oneFingerTap:
            self = .mechanicalTap(try TapTarget(from: try payload()))
        case .longPress:
            self = .mechanicalLongPress(try LongPressTarget(from: try payload()))
        case .swipe:
            self = .mechanicalSwipe(try SwipeTarget(from: try payload()))
        case .drag:
            self = .mechanicalDrag(try DragTarget(from: try payload()))
        case .scroll:
            self = .viewportScroll(try ScrollTarget(from: try payload()))
        case .scrollToVisible:
            self = .viewportScrollToVisible(try TargetExprPayload(from: try payload()).target)
        case .scrollToEdge:
            self = .viewportScrollToEdge(try ScrollToEdgeTarget(from: try payload()))
        case .editAction:
            self = .editAction(try EditActionTarget(from: try payload()))
        case .setPasteboard:
            self = .setPasteboard(try SetPasteboardTarget(from: try payload()))
        case .resignFirstResponder:
            if let payloadDecoder {
                throw DecodingError.dataCorrupted(.init(
                    codingPath: payloadDecoder.codingPath,
                    debugDescription: "\(type.rawValue) must not include a payload"
                ))
            }
            self = .dismissKeyboard
        case .clientHello, .authenticate, .requestInterface, .ping, .status,
             .getPasteboard, .requestScreen, .wait, .heistPlan:
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "command \"\(type.rawValue)\" is not a heist action command"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(wireType, forKey: .type)
        switch self {
        case .activate(let target), .increment(let target), .decrement(let target), .viewportScrollToVisible(let target):
            try TargetExprPayload(target: target).encode(to: container.superEncoder(forKey: .payload))
        case .customAction(let name, let target):
            try CustomActionExprPayload(actionName: name, target: target).encode(to: container.superEncoder(forKey: .payload))
        case .rotor(let selection, let target, let direction):
            try RotorExprPayload(selection: selection, target: target, direction: direction).encode(to: container.superEncoder(forKey: .payload))
        case .typeText(let text, let target):
            try TypeTextExprPayload(text: text, target: target).encode(to: container.superEncoder(forKey: .payload))
        case .mechanicalTap(let target):
            try target.encode(to: container.superEncoder(forKey: .payload))
        case .mechanicalLongPress(let target):
            try target.encode(to: container.superEncoder(forKey: .payload))
        case .mechanicalSwipe(let target):
            try target.encode(to: container.superEncoder(forKey: .payload))
        case .mechanicalDrag(let target):
            try target.encode(to: container.superEncoder(forKey: .payload))
        case .viewportScroll(let target):
            try target.encode(to: container.superEncoder(forKey: .payload))
        case .viewportScrollToEdge(let target):
            try target.encode(to: container.superEncoder(forKey: .payload))
        case .editAction(let target):
            try target.encode(to: container.superEncoder(forKey: .payload))
        case .setPasteboard(let target):
            try target.encode(to: container.superEncoder(forKey: .payload))
        case .dismissKeyboard:
            break
        }
    }

}

// MARK: - Heist Action Command Payloads

private struct TargetExprPayload: Codable, Sendable, Equatable {
    let target: ElementTargetExpr

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case target
        case targetRef = "target_ref"
    }

    init(target: ElementTargetExpr) {
        self.target = target
    }

    init(from decoder: Decoder) throws {
        try rejectUnknownTargetExprPayloadKeys(from: decoder, commandFields: CodingKeys.allCases.map(\.stringValue))
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let hasNestedTarget = container.contains(.target)
        let hasTargetRef = container.contains(.targetRef)
        let inlineTarget = try ElementTarget.decodeInlineIfPresent(from: decoder)
        let intentCount = [hasNestedTarget, hasTargetRef, inlineTarget != nil].filter { $0 }.count
        guard intentCount == 1 else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: container.codingPath,
                debugDescription: "target payload requires exactly one of target, target_ref, or inline target fields"
            ))
        }
        if let inlineTarget {
            target = .target(inlineTarget)
        } else if hasNestedTarget {
            target = .target(try container.decode(ElementTarget.self, forKey: .target))
        } else {
            let reference = try container.decode(String.self, forKey: .targetRef)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !reference.isEmpty else {
                throw DecodingError.dataCorruptedError(
                    forKey: .targetRef,
                    in: container,
                    debugDescription: "target_ref must not be empty"
                )
            }
            target = .ref(reference)
        }
    }

    func encode(to encoder: Encoder) throws {
        switch target {
        case .target(let target):
            try target.encode(to: encoder)
        case .ref(let reference):
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(reference, forKey: .targetRef)
        }
    }
}

private struct CustomActionExprPayload: Codable, Sendable, Equatable {
    let actionName: String
    let target: ElementTargetExpr

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case actionName
        case target
        case targetRef = "target_ref"
    }

    init(actionName: String, target: ElementTargetExpr) {
        self.actionName = actionName
        self.target = target
    }

    init(from decoder: Decoder) throws {
        try rejectUnknownTargetExprPayloadKeys(from: decoder, commandFields: CodingKeys.allCases.map(\.stringValue))
        let container = try decoder.container(keyedBy: CodingKeys.self)
        actionName = try container.decode(String.self, forKey: .actionName)
        target = try TargetExprPayload.decodeTarget(from: decoder, container: container, nestedKey: .target, refKey: .targetRef)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(actionName, forKey: .actionName)
        try TargetExprPayload.encode(target, into: &container, nestedKey: .target, refKey: .targetRef)
    }
}

private struct RotorExprPayload: Codable, Sendable, Equatable {
    let selection: RotorSelection
    let target: ElementTargetExpr
    let direction: RotorDirection

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case rotor
        case rotorIndex
        case direction
        case target
        case targetRef = "target_ref"
    }

    init(selection: RotorSelection, target: ElementTargetExpr, direction: RotorDirection) {
        self.selection = selection
        self.target = target
        self.direction = direction
    }

    init(from decoder: Decoder) throws {
        try rejectUnknownTargetExprPayloadKeys(from: decoder, commandFields: CodingKeys.allCases.map(\.stringValue))
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let rotor = try container.decodeIfPresent(String.self, forKey: .rotor)
        let rotorIndex = try container.decodeIfPresent(Int.self, forKey: .rotorIndex)
        if rotor != nil, rotorIndex != nil {
            throw DecodingError.dataCorrupted(.init(
                codingPath: container.codingPath,
                debugDescription: "rotor accepts either rotor or rotorIndex, not both"
            ))
        }
        if let rotorIndex, rotorIndex < 0 {
            throw DecodingError.dataCorrupted(.init(
                codingPath: container.codingPath,
                debugDescription: "rotorIndex must be non-negative, got \(rotorIndex)"
            ))
        }
        selection = if let rotor {
            .named(rotor)
        } else if let rotorIndex {
            .index(rotorIndex)
        } else {
            .automatic
        }
        direction = try container.decodeIfPresent(RotorDirection.self, forKey: .direction) ?? .next
        target = try TargetExprPayload.decodeTarget(from: decoder, container: container, nestedKey: .target, refKey: .targetRef)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch selection {
        case .automatic:
            break
        case .named(let rotor):
            try container.encode(rotor, forKey: .rotor)
        case .index(let rotorIndex):
            try container.encode(rotorIndex, forKey: .rotorIndex)
        }
        try container.encode(direction, forKey: .direction)
        try TargetExprPayload.encode(target, into: &container, nestedKey: .target, refKey: .targetRef)
    }
}

private struct TypeTextExprPayload: Codable, Sendable, Equatable {
    let text: StringExpr
    let target: ElementTargetExpr?

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case text
        case textRef = "text_ref"
        case target
        case targetRef = "target_ref"
    }

    init(text: StringExpr, target: ElementTargetExpr?) {
        self.text = text
        self.target = target
    }

    init(from decoder: Decoder) throws {
        try rejectUnknownTargetExprPayloadKeys(from: decoder, commandFields: CodingKeys.allCases.map(\.stringValue))
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let literal = try container.decodeIfPresent(String.self, forKey: .text)
        let reference = try container.decodeIfPresent(String.self, forKey: .textRef)
        switch (literal, reference) {
        case (.some(let literal), nil):
            guard !literal.isEmpty else {
                throw DecodingError.dataCorruptedError(
                    forKey: .text,
                    in: container,
                    debugDescription: "text must be non-empty"
                )
            }
            text = .literal(literal)
        case (nil, .some(let reference)):
            let trimmed = reference.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                throw DecodingError.dataCorruptedError(
                    forKey: .textRef,
                    in: container,
                    debugDescription: "text_ref must not be empty"
                )
            }
            text = .ref(trimmed)
        case (.some, .some):
            throw DecodingError.dataCorruptedError(
                forKey: .textRef,
                in: container,
                debugDescription: "type_text accepts either text or text_ref, not both"
            )
        case (nil, nil):
            throw DecodingError.dataCorruptedError(
                forKey: .text,
                in: container,
                debugDescription: "type_text requires text or text_ref"
            )
        }
        target = try TargetExprPayload.decodeOptionalTarget(from: decoder, container: container, nestedKey: .target, refKey: .targetRef)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch text {
        case .literal(let literal):
            try container.encode(literal, forKey: .text)
        case .ref(let reference):
            try container.encode(reference, forKey: .textRef)
        }
        if let target {
            try TargetExprPayload.encode(target, into: &container, nestedKey: .target, refKey: .targetRef)
        }
    }
}

private extension TargetExprPayload {
    static func decodeTarget<K: CodingKey>(
        from decoder: Decoder,
        container: KeyedDecodingContainer<K>,
        nestedKey: K,
        refKey: K
    ) throws -> ElementTargetExpr {
        guard let target = try decodeOptionalTarget(
            from: decoder,
            container: container,
            nestedKey: nestedKey,
            refKey: refKey
        ) else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: container.codingPath,
                debugDescription: "target payload requires target, target_ref, or inline target fields"
            ))
        }
        return target
    }

    static func decodeOptionalTarget<K: CodingKey>(
        from decoder: Decoder,
        container: KeyedDecodingContainer<K>,
        nestedKey: K,
        refKey: K
    ) throws -> ElementTargetExpr? {
        let hasNestedTarget = container.contains(nestedKey)
        let hasTargetRef = container.contains(refKey)
        let inlineTarget = try ElementTarget.decodeInlineIfPresent(from: decoder)
        let intentCount = [hasNestedTarget, hasTargetRef, inlineTarget != nil].filter { $0 }.count
        guard intentCount <= 1 else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: container.codingPath,
                debugDescription: "target payload accepts only one of target, target_ref, or inline target fields"
            ))
        }
        if let inlineTarget {
            return .target(inlineTarget)
        }
        if hasNestedTarget {
            return .target(try container.decode(ElementTarget.self, forKey: nestedKey))
        }
        if hasTargetRef {
            let reference = try container.decode(String.self, forKey: refKey)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !reference.isEmpty else {
                throw DecodingError.dataCorruptedError(
                    forKey: refKey,
                    in: container,
                    debugDescription: "\(refKey.stringValue) must not be empty"
                )
            }
            return .ref(reference)
        }
        return nil
    }

    static func encode<K: CodingKey>(
        _ target: ElementTargetExpr,
        into container: inout KeyedEncodingContainer<K>,
        nestedKey: K,
        refKey: K
    ) throws {
        switch target {
        case .target(let target):
            try container.encode(target, forKey: nestedKey)
        case .ref(let reference):
            try container.encode(reference, forKey: refKey)
        }
    }
}

private func rejectUnknownTargetExprPayloadKeys(
    from decoder: Decoder,
    commandFields: [String]
) throws {
    let allowed = Set(commandFields + ElementTarget.inlineFieldNames)
    try decoder.rejectUnknownKeys(allowed: allowed, typeName: "heist action command payload")
}
