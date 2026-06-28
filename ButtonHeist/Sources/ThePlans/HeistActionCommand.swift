import Foundation

public enum HeistActionCommandType: String, Codable, Sendable, CaseIterable, Equatable, CustomStringConvertible {
    case activate, increment, decrement, performCustomAction, rotor
    case oneFingerTap, longPress, swipe, drag
    case typeText, editAction, setPasteboard, takeScreenshot
    case scroll, scrollToVisible, scrollToEdge, resignFirstResponder

    public var description: String { rawValue }
}

public enum HeistActionCommand: Codable, Sendable, Equatable {
    case activate(ElementTargetExpr)
    case increment(ElementTargetExpr)
    case decrement(ElementTargetExpr)
    case customAction(name: String, target: ElementTargetExpr)
    case rotor(selection: RotorSelection, target: ElementTargetExpr, direction: RotorDirection)
    case typeText(text: StringExpr, target: ElementTargetExpr?, replacingExisting: Bool = false)
    case mechanicalTap(TapTarget)
    case mechanicalLongPress(LongPressTarget)
    case mechanicalSwipe(SwipeTarget)
    case mechanicalDrag(DragTarget)
    case viewportScroll(ScrollTarget)
    case viewportScrollToVisible(ElementTargetExpr)
    case viewportScrollToEdge(ScrollToEdgeTarget)
    case editAction(EditActionTarget)
    case setPasteboard(SetPasteboardTarget)
    case takeScreenshot
    case dismissKeyboard

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case type, payload
    }

    public var wireType: HeistActionCommandType {
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
        case .takeScreenshot: return .takeScreenshot
        case .dismissKeyboard: return .resignFirstResponder
        }
    }

    func assertResolvedPayloadAdmissible(in environment: HeistExecutionEnvironment) throws {
        switch self {
        case .activate(let target):
            try roundTrip(try target.resolve(in: environment))
        case .increment(let target):
            try roundTrip(try target.resolve(in: environment))
        case .decrement(let target):
            try roundTrip(try target.resolve(in: environment))
        case .customAction(let name, let target):
            try CustomActionTarget.validate(actionName: name)
            try roundTrip(CustomActionTarget(
                elementTarget: try target.resolve(in: environment),
                actionName: name
            ))
        case .rotor(let selection, let target, let direction):
            try roundTrip(RotorTarget(
                elementTarget: try target.resolve(in: environment),
                selection: selection,
                direction: direction
            ))
        case .typeText(let text, let target, let replacingExisting):
            let resolvedText = try text.resolve(in: environment)
            try roundTrip(TypeTextTarget(
                validatingText: resolvedText,
                elementTarget: try target?.resolve(in: environment),
                replacingExisting: replacingExisting
            ))
        case .mechanicalTap(let target):
            try roundTrip(target)
        case .mechanicalLongPress(let target):
            try roundTrip(target)
        case .mechanicalSwipe(let target):
            try roundTrip(target)
        case .mechanicalDrag(let target):
            try roundTrip(target)
        case .viewportScroll(let target):
            try roundTrip(target)
        case .viewportScrollToVisible(let target):
            try roundTrip(ScrollToVisibleTarget(elementTarget: try target.resolve(in: environment)))
        case .viewportScrollToEdge(let target):
            try roundTrip(target)
        case .editAction(let target):
            try roundTrip(target)
        case .setPasteboard(let target):
            try roundTrip(target)
        case .takeScreenshot, .dismissKeyboard:
            break
        }
    }

    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "heist action command")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let typeString = try container.decode(String.self, forKey: .type)
        guard let type = HeistActionCommandType(rawValue: typeString) else {
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "command \"\(typeString)\" is not a heist action command"
            )
        }
        let payloadDecoder = container.contains(.payload) ? try container.superDecoder(forKey: .payload) : nil
        func payload() throws -> Decoder {
            guard let payloadDecoder else {
                throw DecodingError.keyNotFound(
                    CodingKeys.payload,
                    .init(
                        codingPath: container.codingPath,
                        debugDescription: "Missing payload for heist action command type \(type.rawValue)"
                    )
                )
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
            self = .typeText(text: payload.text, target: payload.target, replacingExisting: payload.replacingExisting)
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
        case .takeScreenshot:
            if let payloadDecoder {
                throw DecodingError.dataCorrupted(.init(
                    codingPath: payloadDecoder.codingPath,
                    debugDescription: "\(type.rawValue) must not include a payload"
                ))
            }
            self = .takeScreenshot
        case .resignFirstResponder:
            if let payloadDecoder {
                throw DecodingError.dataCorrupted(.init(
                    codingPath: payloadDecoder.codingPath,
                    debugDescription: "\(type.rawValue) must not include a payload"
                ))
            }
            self = .dismissKeyboard
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
        case .typeText(let text, let target, let replacingExisting):
            try TypeTextExprPayload(text: text, target: target, replacingExisting: replacingExisting)
                .encode(to: container.superEncoder(forKey: .payload))
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
        case .takeScreenshot, .dismissKeyboard:
            break
        }
    }

}

private func roundTrip<T: Codable>(_ payload: T) throws {
    let data = try JSONEncoder().encode(payload)
    _ = try JSONDecoder().decode(T.self, from: data)
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
        let inlineTarget = try ElementTargetExpr.decodeInlineIfPresent(from: decoder)
        let intentCount = [hasNestedTarget, hasTargetRef, inlineTarget != nil].filter { $0 }.count
        guard intentCount == 1 else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: container.codingPath,
                debugDescription: "target payload requires exactly one of target, target_ref, or inline target fields"
            ))
        }
        if let inlineTarget {
            target = inlineTarget
        } else if hasNestedTarget {
            target = try container.decode(ElementTargetExpr.self, forKey: .target)
        } else {
            target = .ref(try HeistReferenceName.decode(from: container, forKey: .targetRef))
        }
    }

    func encode(to encoder: Encoder) throws {
        switch target {
        case .target(let target):
            try target.encode(to: encoder)
        case .predicate:
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
        let decodedActionName = try container.decode(String.self, forKey: .actionName)
        do {
            try CustomActionTarget.validate(actionName: decodedActionName)
        } catch {
            throw DecodingError.dataCorruptedError(
                forKey: .actionName,
                in: container,
                debugDescription: String(describing: error)
            )
        }
        actionName = decodedActionName
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
    let replacingExisting: Bool

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case text
        case textRef = "text_ref"
        case target
        case targetRef = "target_ref"
        case replacingExisting
    }

    init(text: StringExpr, target: ElementTargetExpr?, replacingExisting: Bool = false) {
        self.text = text
        self.target = target
        self.replacingExisting = replacingExisting
    }

    init(from decoder: Decoder) throws {
        try rejectUnknownTargetExprPayloadKeys(from: decoder, commandFields: CodingKeys.allCases.map(\.stringValue))
        let container = try decoder.container(keyedBy: CodingKeys.self)
        replacingExisting = try container.decodeIfPresent(Bool.self, forKey: .replacingExisting) ?? false
        let literal = try container.decodeIfPresent(String.self, forKey: .text)
        let reference = try HeistReferenceName.decodeIfPresent(from: container, forKey: .textRef)
        switch (literal, reference) {
        case (.some(let literal), nil):
            guard replacingExisting || !literal.isEmpty else {
                throw DecodingError.dataCorruptedError(
                    forKey: .text,
                    in: container,
                    debugDescription: "text must be non-empty unless replacingExisting is true"
                )
            }
            text = .literal(literal)
        case (nil, .some(let reference)):
            text = .ref(reference)
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
        if replacingExisting {
            try container.encode(replacingExisting, forKey: .replacingExisting)
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
        let inlineTarget = try ElementTargetExpr.decodeInlineIfPresent(from: decoder)
        let intentCount = [hasNestedTarget, hasTargetRef, inlineTarget != nil].filter { $0 }.count
        guard intentCount <= 1 else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: container.codingPath,
                debugDescription: "target payload accepts only one of target, target_ref, or inline target fields"
            ))
        }
        if let inlineTarget {
            return inlineTarget
        }
        if hasNestedTarget {
            return try container.decode(ElementTargetExpr.self, forKey: nestedKey)
        }
        if hasTargetRef {
            return .ref(try HeistReferenceName.decode(from: container, forKey: refKey))
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
        case .predicate:
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
    let allowed = Set(commandFields + ElementTargetExpr.inlineFieldNames)
    try decoder.rejectUnknownKeys(allowed: allowed, typeName: "heist action command payload")
}
