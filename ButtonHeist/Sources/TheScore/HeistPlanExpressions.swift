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
