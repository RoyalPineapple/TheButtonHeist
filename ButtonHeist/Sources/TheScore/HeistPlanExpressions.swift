import Foundation

// MARK: - Heist Execution Environment

public struct HeistExecutionEnvironment: Sendable, Equatable {
    public static let empty = HeistExecutionEnvironment()

    public let targets: [String: ElementTarget]
    public let strings: [String: String]

    public init(
        targets: [String: ElementTarget] = [:],
        strings: [String: String] = [:]
    ) {
        self.targets = targets
        self.strings = strings
    }

    public func binding(target: ElementTarget, to parameter: String) -> HeistExecutionEnvironment {
        var targets = self.targets
        targets[parameter] = target
        return HeistExecutionEnvironment(targets: targets, strings: strings)
    }

    public func binding(string: String, to parameter: String) -> HeistExecutionEnvironment {
        var strings = self.strings
        strings[parameter] = string
        return HeistExecutionEnvironment(targets: targets, strings: strings)
    }
}

public enum HeistExpressionError: Error, Sendable, Equatable, CustomStringConvertible {
    case unresolvedTargetReference(String)
    case unresolvedStringReference(String)
    case emptyReference(String)
    case unsupportedHeistActionCommand(String)

    public var description: String {
        switch self {
        case .unresolvedTargetReference(let reference):
            return "unresolved target reference \"\(reference)\""
        case .unresolvedStringReference(let reference):
            return "unresolved string reference \"\(reference)\""
        case .emptyReference(let type):
            return "\(type) reference must not be empty"
        case .unsupportedHeistActionCommand(let command):
            return "unsupported heist action command \"\(command)\""
        }
    }
}

// MARK: - Typed Expressions

public enum ElementTargetExpr: Codable, Sendable, Equatable {
    case target(ElementTarget)
    case ref(String)

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case ref
    }

    public init(_ target: ElementTarget) {
        self = .target(target)
    }

    public init(ref: String) throws {
        let trimmed = ref.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw HeistExpressionError.emptyReference("target") }
        self = .ref(trimmed)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if container.contains(.ref) {
            try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "element target expression")
            self = try .ref(Self.decodeReference(from: container, key: .ref, type: "target"))
            return
        }
        self = .target(try ElementTarget(from: decoder))
    }

    public func encode(to encoder: Encoder) throws {
        switch self {
        case .target(let target):
            try target.encode(to: encoder)
        case .ref(let reference):
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(reference, forKey: .ref)
        }
    }

    public func resolve(in environment: HeistExecutionEnvironment) throws -> ElementTarget {
        switch self {
        case .target(let target):
            return target
        case .ref(let reference):
            guard let target = environment.targets[reference] else {
                throw HeistExpressionError.unresolvedTargetReference(reference)
            }
            return target
        }
    }

    private static func decodeReference(
        from container: KeyedDecodingContainer<CodingKeys>,
        key: CodingKeys,
        type: String
    ) throws -> String {
        let reference = try container.decode(String.self, forKey: key)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !reference.isEmpty else {
            throw DecodingError.dataCorruptedError(
                forKey: key,
                in: container,
                debugDescription: "\(type) reference must not be empty"
            )
        }
        return reference
    }
}

extension ElementTargetExpr: CustomStringConvertible {
    public var description: String {
        switch self {
        case .target(let target):
            return target.description
        case .ref(let reference):
            return ScoreDescription.call("targetRef", [ScoreDescription.quoted(reference)])
        }
    }
}

public enum StringExpr: Codable, Sendable, Equatable, Hashable {
    case literal(String)
    case ref(String)

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case ref
    }

    public init(_ literal: String) {
        self = .literal(literal)
    }

    public init(ref: String) throws {
        let trimmed = ref.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw HeistExpressionError.emptyReference("string") }
        self = .ref(trimmed)
    }

    public init(from decoder: Decoder) throws {
        if let literal = try? decoder.singleValueContainer().decode(String.self) {
            self = .literal(literal)
            return
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "string expression")
        let reference = try container.decode(String.self, forKey: .ref)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !reference.isEmpty else {
            throw DecodingError.dataCorruptedError(
                forKey: .ref,
                in: container,
                debugDescription: "string reference must not be empty"
            )
        }
        self = .ref(reference)
    }

    public func encode(to encoder: Encoder) throws {
        switch self {
        case .literal(let literal):
            var container = encoder.singleValueContainer()
            try container.encode(literal)
        case .ref(let reference):
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(reference, forKey: .ref)
        }
    }

    public func resolve(in environment: HeistExecutionEnvironment) throws -> String {
        switch self {
        case .literal(let literal):
            return literal
        case .ref(let reference):
            guard let string = environment.strings[reference] else {
                throw HeistExpressionError.unresolvedStringReference(reference)
            }
            return string
        }
    }
}

extension StringExpr: CustomStringConvertible {
    public var description: String {
        switch self {
        case .literal(let literal):
            return ScoreDescription.quoted(literal)
        case .ref(let reference):
            return ScoreDescription.call("stringRef", [ScoreDescription.quoted(reference)])
        }
    }
}

// MARK: - Predicate Expressions

public struct ElementPredicateExpr: Codable, Sendable, Equatable, Hashable {
    public let label: StringExpr?
    public let identifier: StringExpr?
    public let value: StringExpr?
    public let traits: [HeistTrait]
    public let excludeTraits: [HeistTrait]

    public init(
        label: StringExpr? = nil,
        identifier: StringExpr? = nil,
        value: StringExpr? = nil,
        traits: [HeistTrait] = [],
        excludeTraits: [HeistTrait] = []
    ) {
        self.label = label
        self.identifier = identifier
        self.value = value
        self.traits = traits
        self.excludeTraits = excludeTraits
    }

    public init(_ predicate: ElementPredicate) {
        self.init(
            label: predicate.label.map(StringExpr.literal),
            identifier: predicate.identifier.map(StringExpr.literal),
            value: predicate.value.map(StringExpr.literal),
            traits: predicate.traits,
            excludeTraits: predicate.excludeTraits
        )
    }

    public var hasPredicates: Bool {
        label != nil || identifier != nil || value != nil || !traits.isEmpty || !excludeTraits.isEmpty
    }

    public func resolve(in environment: HeistExecutionEnvironment) throws -> ElementPredicate {
        ElementPredicate(
            label: try label?.resolve(in: environment),
            identifier: try identifier?.resolve(in: environment),
            value: try value?.resolve(in: environment),
            traits: traits,
            excludeTraits: excludeTraits
        )
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case label, labelRef = "label_ref"
        case identifier, identifierRef = "identifier_ref"
        case value, valueRef = "value_ref"
        case traits, excludeTraits
    }

    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "element predicate expression")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        label = try Self.decodeStringExpr(container, literalKey: .label, refKey: .labelRef, field: "label")
        identifier = try Self.decodeStringExpr(container, literalKey: .identifier, refKey: .identifierRef, field: "identifier")
        value = try Self.decodeStringExpr(container, literalKey: .value, refKey: .valueRef, field: "value")
        traits = try container.decodeIfPresent([HeistTrait].self, forKey: .traits) ?? []
        excludeTraits = try container.decodeIfPresent([HeistTrait].self, forKey: .excludeTraits) ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try Self.encode(label, literalKey: .label, refKey: .labelRef, into: &container)
        try Self.encode(identifier, literalKey: .identifier, refKey: .identifierRef, into: &container)
        try Self.encode(value, literalKey: .value, refKey: .valueRef, into: &container)
        if !traits.isEmpty { try container.encode(traits, forKey: .traits) }
        if !excludeTraits.isEmpty { try container.encode(excludeTraits, forKey: .excludeTraits) }
    }

    private static func decodeStringExpr(
        _ container: KeyedDecodingContainer<CodingKeys>,
        literalKey: CodingKeys,
        refKey: CodingKeys,
        field: String
    ) throws -> StringExpr? {
        let literal = try container.decodeIfPresent(String.self, forKey: literalKey)
        let reference = try container.decodeIfPresent(String.self, forKey: refKey)
        switch (literal, reference) {
        case (.some(let literal), nil):
            return .literal(literal)
        case (nil, .some(let reference)):
            let trimmed = reference.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                throw DecodingError.dataCorruptedError(
                    forKey: refKey,
                    in: container,
                    debugDescription: "\(field)_ref must not be empty"
                )
            }
            return .ref(trimmed)
        case (.some, .some):
            throw DecodingError.dataCorruptedError(
                forKey: refKey,
                in: container,
                debugDescription: "element predicate accepts either \(literalKey.stringValue) or \(refKey.stringValue), not both"
            )
        case (nil, nil):
            return nil
        }
    }

    private static func encode(
        _ expression: StringExpr?,
        literalKey: CodingKeys,
        refKey: CodingKeys,
        into container: inout KeyedEncodingContainer<CodingKeys>
    ) throws {
        switch expression {
        case .literal(let literal):
            try container.encode(literal, forKey: literalKey)
        case .ref(let reference):
            try container.encode(reference, forKey: refKey)
        case nil:
            break
        }
    }
}

extension ElementPredicateExpr: CustomStringConvertible {
    public var description: String {
        ScoreDescription.call("predicate", [
            label.map { "label=\($0)" },
            identifier.map { "identifier=\($0)" },
            value.map { "value=\($0)" },
            ScoreDescription.listField("traits", traits.isEmpty ? nil : traits),
            ScoreDescription.listField("excludeTraits", excludeTraits.isEmpty ? nil : excludeTraits),
        ].compactMap { $0 })
    }
}

public enum StatePredicateExpr: Codable, Sendable, Equatable {
    case present(ElementPredicateExpr)
    case absent(ElementPredicateExpr)
    case presentTarget(ElementTargetExpr)
    case absentTarget(ElementTargetExpr)
    case all([StatePredicateExpr])

    private enum WireType: String {
        case present, absent, all
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case type, element, target, targetRef = "target_ref", states
    }

    public func resolve(in environment: HeistExecutionEnvironment) throws -> AccessibilityPredicate.State {
        switch self {
        case .present(let predicate):
            return .present(try predicate.resolve(in: environment))
        case .absent(let predicate):
            return .absent(try predicate.resolve(in: environment))
        case .presentTarget(let target):
            return .presentTarget(try target.resolve(in: environment))
        case .absentTarget(let target):
            return .absentTarget(try target.resolve(in: environment))
        case .all(let states):
            return .all(try states.map { try $0.resolve(in: environment) })
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let typeString = try container.decode(String.self, forKey: .type)
        guard let wireType = WireType(rawValue: typeString) else {
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "Unknown state predicate type: \"\(typeString)\". Valid: present, absent, all"
            )
        }
        switch wireType {
        case .present:
            self = try Self.decodeElementState(decoder, container, predicateState: Self.present, targetState: Self.presentTarget)
        case .absent:
            self = try Self.decodeElementState(decoder, container, predicateState: Self.absent, targetState: Self.absentTarget)
        case .all:
            try decoder.rejectUnknownKeys(allowed: ["type", "states"], typeName: "all predicate expression")
            let states = try container.decode([StatePredicateExpr].self, forKey: .states)
            guard !states.isEmpty else {
                throw DecodingError.dataCorruptedError(
                    forKey: .states,
                    in: container,
                    debugDescription: "all predicate requires at least one child state"
                )
            }
            self = .all(states)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .present(let predicate):
            try container.encode(WireType.present.rawValue, forKey: .type)
            try container.encode(predicate, forKey: .element)
        case .absent(let predicate):
            try container.encode(WireType.absent.rawValue, forKey: .type)
            try container.encode(predicate, forKey: .element)
        case .presentTarget(let target):
            try container.encode(WireType.present.rawValue, forKey: .type)
            try Self.encode(target, into: &container)
        case .absentTarget(let target):
            try container.encode(WireType.absent.rawValue, forKey: .type)
            try Self.encode(target, into: &container)
        case .all(let states):
            try container.encode(WireType.all.rawValue, forKey: .type)
            try container.encode(states, forKey: .states)
        }
    }

    private static func decodeElementState(
        _ decoder: Decoder,
        _ container: KeyedDecodingContainer<CodingKeys>,
        predicateState: (ElementPredicateExpr) -> Self,
        targetState: (ElementTargetExpr) -> Self
    ) throws -> Self {
        try decoder.rejectUnknownKeys(
            allowed: ["type", "element", "target", "target_ref"],
            typeName: "state predicate expression"
        )
        let hasElement = container.contains(.element)
        let hasTarget = container.contains(.target)
        let hasTargetRef = container.contains(.targetRef)
        let intentCount = [hasElement, hasTarget, hasTargetRef].filter { $0 }.count
        guard intentCount == 1 else {
            throw DecodingError.dataCorruptedError(
                forKey: .element,
                in: container,
                debugDescription: "state predicate expression requires exactly one of element, target, or target_ref"
            )
        }
        if hasElement {
            return predicateState(try container.decode(ElementPredicateExpr.self, forKey: .element))
        }
        if hasTarget {
            return targetState(.target(try container.decode(ElementTarget.self, forKey: .target)))
        }
        let reference = try container.decode(String.self, forKey: .targetRef)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !reference.isEmpty else {
            throw DecodingError.dataCorruptedError(
                forKey: .targetRef,
                in: container,
                debugDescription: "target_ref must not be empty"
            )
        }
        return targetState(.ref(reference))
    }

    private static func encode(
        _ target: ElementTargetExpr,
        into container: inout KeyedEncodingContainer<CodingKeys>
    ) throws {
        switch target {
        case .target(let target):
            try container.encode(target, forKey: .target)
        case .ref(let reference):
            try container.encode(reference, forKey: .targetRef)
        }
    }
}

extension StatePredicateExpr: CustomStringConvertible {
    public var description: String {
        switch self {
        case .present(let predicate): return ScoreDescription.call("present", [predicate.description])
        case .absent(let predicate): return ScoreDescription.call("absent", [predicate.description])
        case .presentTarget(let target): return ScoreDescription.call("present", [target.description])
        case .absentTarget(let target): return ScoreDescription.call("absent", [target.description])
        case .all(let states): return ScoreDescription.call("all", states.map(\.description))
        }
    }
}

public enum AccessibilityPredicateExpr: Codable, Sendable, Equatable {
    case predicate(AccessibilityPredicate)
    case state(StatePredicateExpr)

    public init(_ predicate: AccessibilityPredicate) {
        self = .predicate(predicate)
    }

    public func resolve(in environment: HeistExecutionEnvironment) throws -> AccessibilityPredicate {
        switch self {
        case .predicate(let predicate):
            return predicate
        case .state(let state):
            return .state(try state.resolve(in: environment))
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: PredicateProbeKeys.self)
        let typeString = try container.decode(String.self, forKey: .type)
        switch typeString {
        case "present", "absent", "all":
            self = .state(try StatePredicateExpr(from: decoder))
        default:
            self = .predicate(try AccessibilityPredicate(from: decoder))
        }
    }

    public func encode(to encoder: Encoder) throws {
        switch self {
        case .predicate(let predicate):
            try predicate.encode(to: encoder)
        case .state(let state):
            try state.encode(to: encoder)
        }
    }

    private enum PredicateProbeKeys: String, CodingKey {
        case type
    }
}

public extension AccessibilityPredicateExpr {
    static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case (.predicate(let lhsPredicate), .predicate(let rhsPredicate)):
            return lhsPredicate == rhsPredicate
        case (.state(let lhsState), .state(let rhsState)):
            return lhsState == rhsState
        case (.predicate(let predicate), .state(let state)),
             (.state(let state), .predicate(let predicate)):
            guard case .state(let predicateState) = predicate,
                  let resolvedState = try? state.resolve(in: .empty) else {
                return false
            }
            return predicateState == resolvedState
        }
    }
}

extension AccessibilityPredicateExpr: CustomStringConvertible {
    public var description: String {
        switch self {
        case .predicate(let predicate):
            return predicate.description
        case .state(let state):
            return state.description
        }
    }
}

// MARK: - Heist Action Command

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
