import Foundation

// MARK: - Heist Execution Environment

public typealias HeistReferenceName = String

public struct HeistExecutionEnvironment: Sendable, Equatable {
    public static let empty = HeistExecutionEnvironment()

    public let targets: [HeistReferenceName: ElementTarget]
    public let strings: [HeistReferenceName: String]

    public init(
        targets: [HeistReferenceName: ElementTarget] = [:],
        strings: [HeistReferenceName: String] = [:]
    ) {
        self.targets = targets
        self.strings = strings
    }

    public func binding(target: ElementTarget, to parameter: HeistReferenceName) -> HeistExecutionEnvironment {
        var targets = self.targets
        targets[parameter] = target
        return HeistExecutionEnvironment(targets: targets, strings: strings)
    }

    public func binding(string: String, to parameter: HeistReferenceName) -> HeistExecutionEnvironment {
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
    case parameterArgumentMismatch(parameter: HeistParameterKind, argument: HeistParameterKind)

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
        case .parameterArgumentMismatch(let parameter, let argument):
            return "heist argument type \(argument.rawValue) does not match parameter type \(parameter.rawValue)"
        }
    }
}

public extension HeistExecutionEnvironment {
    func binding(argument: HeistArgument, to parameter: HeistParameter) throws -> HeistExecutionEnvironment {
        guard argument.kind == parameter.kind else {
            throw HeistExpressionError.parameterArgumentMismatch(parameter: parameter.kind, argument: argument.kind)
        }
        switch (parameter, argument) {
        case (.none, .none):
            return self
        case (.string(let name), .string(let value)):
            return binding(string: try value.resolve(in: self), to: name)
        case (.elementTarget(let name), .elementTarget(let target)):
            return binding(target: try target.resolve(in: self), to: name)
        default:
            throw HeistExpressionError.parameterArgumentMismatch(parameter: parameter.kind, argument: argument.kind)
        }
    }
}

// MARK: - Typed Expressions

public enum ElementTargetExpr: Codable, Sendable, Equatable, Hashable {
    case target(ElementTarget)
    case predicate(ElementPredicateTemplate, ordinal: Int? = nil)
    case ref(HeistReferenceName)

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case ref, ordinal
    }

    public static var inlineFieldNames: [String] {
        ElementTarget.inlineFieldNames
            + ElementPredicateTemplate.CodingKeys.allCases.map(\.stringValue)
    }

    public init(_ target: ElementTarget) {
        switch target {
        case .predicate(let predicate, let ordinal):
            self = .predicate(ElementPredicateTemplate(predicate), ordinal: ordinal)
        }
    }

    public init(ref: HeistReferenceName) throws {
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
        let predicate = try ElementPredicateTemplate.decodeAllowingAdditionalKeys(from: decoder)
        if predicate.hasPredicates {
            let ordinal = try container.decodeIfPresent(Int.self, forKey: .ordinal)
            if let ordinal, ordinal < 0 {
                throw DecodingError.dataCorruptedError(
                    forKey: .ordinal,
                    in: container,
                    debugDescription: "ordinal must be non-negative"
                )
            }
            self = .predicate(predicate, ordinal: ordinal)
            return
        }
        self = .target(try ElementTarget(from: decoder))
    }

    public static func decodeInlineIfPresent(from decoder: Decoder) throws -> ElementTargetExpr? {
        struct AnyCodingKey: CodingKey {
            let stringValue: String
            let intValue: Int? = nil

            init?(stringValue: String) {
                self.stringValue = stringValue
            }

            init?(intValue: Int) {
                return nil
            }
        }

        let probe = try decoder.container(keyedBy: AnyCodingKey.self)
        let allowed = Set(inlineFieldNames)
        guard probe.allKeys.contains(where: { allowed.contains($0.stringValue) }) else { return nil }
        return try ElementTargetExpr(from: decoder)
    }

    public func encode(to encoder: Encoder) throws {
        switch self {
        case .target(let target):
            try target.encode(to: encoder)
        case .predicate(let predicate, let ordinal):
            try predicate.encode(to: encoder)
            if let ordinal {
                var container = encoder.container(keyedBy: CodingKeys.self)
                try container.encode(ordinal, forKey: .ordinal)
            }
        case .ref(let reference):
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(reference, forKey: .ref)
        }
    }

    public func resolve(in environment: HeistExecutionEnvironment) throws -> ElementTarget {
        switch self {
        case .target(let target):
            return target
        case .predicate(let predicate, let ordinal):
            return .predicate(try predicate.resolve(in: environment), ordinal: ordinal)
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
    ) throws -> HeistReferenceName {
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

public extension ElementTargetExpr {
    // Keep target-backed predicates equal to their canonical predicate-template form
    // so Swift-authored targets and decoded inline predicate targets compare as the
    // same heist intent.
    static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case (.ref(let lhsReference), .ref(let rhsReference)):
            return lhsReference == rhsReference
        case (.target(let lhsTarget), .target(let rhsTarget)):
            return lhsTarget == rhsTarget
        case (.predicate(let lhsPredicate, let lhsOrdinal), .predicate(let rhsPredicate, let rhsOrdinal)):
            return lhsPredicate == rhsPredicate && lhsOrdinal == rhsOrdinal
        case (.target(let target), .predicate(let predicate, let ordinal)),
             (.predicate(let predicate, let ordinal), .target(let target)):
            guard case .predicate(let targetPredicate, let targetOrdinal) = target else {
                return false
            }
            return ElementPredicateTemplate(targetPredicate) == predicate && targetOrdinal == ordinal
        default:
            return false
        }
    }

    func hash(into hasher: inout Hasher) {
        switch self {
        case .ref(let reference):
            hasher.combine("ref")
            hasher.combine(reference)
        case .target(.predicate(let predicate, let ordinal)):
            hasher.combine("predicate")
            hasher.combine(ElementPredicateTemplate(predicate))
            hasher.combine(ordinal)
        case .predicate(let predicate, let ordinal):
            hasher.combine("predicate")
            hasher.combine(predicate)
            hasher.combine(ordinal)
        }
    }
}

extension ElementTargetExpr: CustomStringConvertible {
    public var description: String {
        switch self {
        case .target(let target):
            return target.description
        case .predicate(let predicate, let ordinal):
            return ScoreDescription.call("targetExpr", [
                predicate.description,
                ScoreDescription.valueField("ordinal", ordinal),
            ].compactMap { $0 })
        case .ref(let reference):
            return ScoreDescription.call("targetRef", [ScoreDescription.quoted(reference)])
        }
    }
}

public enum StringExpr: Codable, Sendable, Equatable, Hashable {
    case literal(String)
    case ref(HeistReferenceName)

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case ref
    }

    public init(_ literal: String) {
        self = .literal(literal)
    }

    public init(ref: HeistReferenceName) throws {
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

extension StringExpr: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) {
        self = .literal(value)
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

public struct ElementPredicateTemplate: Codable, Sendable, Equatable, Hashable {
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

    enum CodingKeys: String, CodingKey, CaseIterable {
        case label, labelRef = "label_ref"
        case identifier, identifierRef = "identifier_ref"
        case value, valueRef = "value_ref"
        case traits, excludeTraits
    }

    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "element predicate template")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(container: container)
    }

    static func decodeAllowingAdditionalKeys(from decoder: Decoder) throws -> ElementPredicateTemplate {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        return try ElementPredicateTemplate(container: container)
    }

    init(container: KeyedDecodingContainer<CodingKeys>) throws {
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

extension ElementPredicateTemplate: CustomStringConvertible {
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
    case present(ElementPredicateTemplate)
    case absent(ElementPredicateTemplate)
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
        predicateState: (ElementPredicateTemplate) -> Self,
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
            return predicateState(try container.decode(ElementPredicateTemplate.self, forKey: .element))
        }
        if hasTarget {
            return targetState(try container.decode(ElementTargetExpr.self, forKey: .target))
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
        case .predicate:
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

public extension StatePredicateExpr {
    init(_ state: AccessibilityPredicate.State) {
        switch state {
        case .present(let predicate):
            self = .present(ElementPredicateTemplate(predicate))
        case .absent(let predicate):
            self = .absent(ElementPredicateTemplate(predicate))
        case .presentTarget(let target):
            self = .presentTarget(ElementTargetExpr(target))
        case .absentTarget(let target):
            self = .absentTarget(ElementTargetExpr(target))
        case .all(let states):
            self = .all(states.map(StatePredicateExpr.init))
        }
    }
}

public struct ElementUpdatePredicateExpr: Codable, Sendable, Equatable {
    public let element: ElementPredicateTemplate?
    public let property: ElementProperty?
    public let from: StringExpr?
    public let to: StringExpr?

    public init(
        element: ElementPredicateTemplate? = nil,
        property: ElementProperty? = nil,
        from: StringExpr? = nil,
        to: StringExpr? = nil
    ) {
        self.element = element
        self.property = property
        self.from = from
        self.to = to
    }

    public init(_ update: ElementUpdatePredicate) {
        self.init(
            element: update.element.map(ElementPredicateTemplate.init),
            property: update.property,
            from: update.from.map(StringExpr.literal),
            to: update.to.map(StringExpr.literal)
        )
    }

    public func resolve(in environment: HeistExecutionEnvironment) throws -> ElementUpdatePredicate {
        ElementUpdatePredicate(
            element: try element?.resolve(in: environment),
            property: property,
            from: try from?.resolve(in: environment),
            to: try to?.resolve(in: environment)
        )
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case type, element, property
        case from, fromRef = "from_ref"
        case to, toRef = "to_ref"
    }

    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "element update predicate expression")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            element: try container.decodeIfPresent(ElementPredicateTemplate.self, forKey: .element),
            property: try container.decodeIfPresent(ElementProperty.self, forKey: .property),
            from: try Self.decodeStringExpr(container, literalKey: .from, refKey: .fromRef, field: "from"),
            to: try Self.decodeStringExpr(container, literalKey: .to, refKey: .toRef, field: "to")
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(element, forKey: .element)
        try container.encodeIfPresent(property, forKey: .property)
        try Self.encode(from, literalKey: .from, refKey: .fromRef, into: &container)
        try Self.encode(to, literalKey: .to, refKey: .toRef, into: &container)
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
                debugDescription: "element update predicate accepts either \(literalKey.stringValue) or \(refKey.stringValue), not both"
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

extension ElementUpdatePredicateExpr: CustomStringConvertible {
    public var description: String {
        ScoreDescription.call("update", [
            element.map { "element=\($0)" },
            ScoreDescription.valueField("property", property?.rawValue),
            from.map { "from=\($0)" },
            to.map { "to=\($0)" },
        ].compactMap { $0 })
    }
}

public enum ChangePredicateExpr: Codable, Sendable, Equatable {
    case screen(where: StatePredicateExpr? = nil)
    case elements
    case appeared(ElementPredicateTemplate)
    case disappeared(ElementPredicateTemplate)
    case updated(ElementUpdatePredicateExpr)

    private enum WireType: String, CaseIterable {
        case screenChanged = "screen_changed"
        case elementsChanged = "elements_changed"
        case elementAppeared = "element_appeared"
        case elementDisappeared = "element_disappeared"
        case elementUpdated = "element_updated"
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case type, element, `where`, property, from, fromRef = "from_ref", to, toRef = "to_ref"
    }

    public init(_ change: AccessibilityPredicate.Change) {
        switch change {
        case .screen(let state):
            self = .screen(where: state.map(StatePredicateExpr.init))
        case .elements:
            self = .elements
        case .appeared(let predicate):
            self = .appeared(ElementPredicateTemplate(predicate))
        case .disappeared(let predicate):
            self = .disappeared(ElementPredicateTemplate(predicate))
        case .updated(let update):
            self = .updated(ElementUpdatePredicateExpr(update))
        }
    }

    public func resolve(in environment: HeistExecutionEnvironment) throws -> AccessibilityPredicate.Change {
        switch self {
        case .screen(let state):
            return .screen(where: try state?.resolve(in: environment))
        case .elements:
            return .elements
        case .appeared(let predicate):
            return .appeared(try predicate.resolve(in: environment))
        case .disappeared(let predicate):
            return .disappeared(try predicate.resolve(in: environment))
        case .updated(let update):
            return .updated(try update.resolve(in: environment))
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let typeString = try container.decode(String.self, forKey: .type)
        guard let wireType = WireType(rawValue: typeString) else {
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "Unknown change predicate type: \"\(typeString)\". Valid: \(WireType.allCases.map(\.rawValue).joined(separator: ", "))"
            )
        }
        switch wireType {
        case .screenChanged:
            try decoder.rejectUnknownKeys(allowed: ["type", "where"], typeName: "screen_changed predicate expression")
            self = .screen(where: try container.decodeIfPresent(StatePredicateExpr.self, forKey: .where))
        case .elementsChanged:
            try decoder.rejectUnknownKeys(allowed: ["type"], typeName: "elements_changed predicate expression")
            self = .elements
        case .elementAppeared:
            try decoder.rejectUnknownKeys(allowed: ["type", "element"], typeName: "element_appeared predicate expression")
            self = .appeared(try container.decode(ElementPredicateTemplate.self, forKey: .element))
        case .elementDisappeared:
            try decoder.rejectUnknownKeys(allowed: ["type", "element"], typeName: "element_disappeared predicate expression")
            self = .disappeared(try container.decode(ElementPredicateTemplate.self, forKey: .element))
        case .elementUpdated:
            self = .updated(try ElementUpdatePredicateExpr(from: decoder))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .screen(let state):
            try container.encode(WireType.screenChanged.rawValue, forKey: .type)
            try container.encodeIfPresent(state, forKey: .where)
        case .elements:
            try container.encode(WireType.elementsChanged.rawValue, forKey: .type)
        case .appeared(let predicate):
            try container.encode(WireType.elementAppeared.rawValue, forKey: .type)
            try container.encode(predicate, forKey: .element)
        case .disappeared(let predicate):
            try container.encode(WireType.elementDisappeared.rawValue, forKey: .type)
            try container.encode(predicate, forKey: .element)
        case .updated(let update):
            try container.encode(WireType.elementUpdated.rawValue, forKey: .type)
            try update.encode(to: encoder)
        }
    }
}

extension ChangePredicateExpr: CustomStringConvertible {
    public var description: String {
        switch self {
        case .screen(let state):
            guard let state else { return "screen_changed" }
            return ScoreDescription.call("screen_changed", ["where=\(state)"])
        case .elements:
            return "elements_changed"
        case .appeared(let predicate):
            return ScoreDescription.call("element_appeared", [predicate.description])
        case .disappeared(let predicate):
            return ScoreDescription.call("element_disappeared", [predicate.description])
        case .updated(let update):
            return ScoreDescription.call("element_updated", [update.description])
        }
    }
}

public enum AccessibilityPredicateExpr: Codable, Sendable, Equatable {
    case predicate(AccessibilityPredicate)
    case state(StatePredicateExpr)
    case changed(ChangePredicateExpr)

    public init(_ predicate: AccessibilityPredicate) {
        self = .predicate(predicate)
    }

    public func resolve(in environment: HeistExecutionEnvironment) throws -> AccessibilityPredicate {
        switch self {
        case .predicate(let predicate):
            return predicate
        case .state(let state):
            return .state(try state.resolve(in: environment))
        case .changed(let change):
            return .changed(try change.resolve(in: environment))
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: PredicateProbeKeys.self)
        let typeString = try container.decode(String.self, forKey: .type)
        switch typeString {
        case "present", "absent", "all":
            self = .state(try StatePredicateExpr(from: decoder))
        case "screen_changed", "elements_changed", "element_appeared", "element_disappeared", "element_updated":
            self = .changed(try ChangePredicateExpr(from: decoder))
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
        case .changed(let change):
            try change.encode(to: encoder)
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
        case (.changed(let lhsChange), .changed(let rhsChange)):
            return lhsChange == rhsChange
        case (.predicate(let predicate), .state(let state)),
             (.state(let state), .predicate(let predicate)):
            guard case .state(let predicateState) = predicate,
                  let resolvedState = try? state.resolve(in: .empty) else {
                return false
            }
            return predicateState == resolvedState
        case (.predicate(let predicate), .changed(let change)),
             (.changed(let change), .predicate(let predicate)):
            guard case .changed(let predicateChange) = predicate,
                  let resolvedChange = try? change.resolve(in: .empty) else {
                return false
            }
            return predicateChange == resolvedChange
        case (.state, .changed), (.changed, .state):
            return false
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
        case .changed(let change):
            return ScoreDescription.call("changed", [change.description])
        }
    }
}
