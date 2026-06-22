import Foundation

// MARK: - Change and Update Predicate Expressions

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
    case updated(ElementUpdatePredicateExpr)

    private enum WireType: String, CaseIterable {
        case screenChanged = "screen_changed"
        case elementsChanged = "elements_changed"
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
        case "screen_changed", "elements_changed", "element_updated":
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
