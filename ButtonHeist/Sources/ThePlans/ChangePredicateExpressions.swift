import Foundation

// MARK: - Change Predicate Expressions

public enum ElementDeltaPredicateExpr: Codable, Sendable, Equatable {
    case appearedElement(ElementPredicateTemplate)
    case disappearedElement(ElementPredicateTemplate)
    case updatedElement(ElementUpdatePredicateExpr)

    private enum WireType: String, CaseIterable {
        case appeared
        case disappeared
        case updated
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case type, element, before, after, property
    }

    public init(_ predicate: ElementDeltaPredicate) {
        switch predicate {
        case .appearedElement(let element):
            self = .appearedElement(ElementPredicateTemplate(element))
        case .disappearedElement(let element):
            self = .disappearedElement(ElementPredicateTemplate(element))
        case .updatedElement(let update):
            self = .updatedElement(ElementUpdatePredicateExpr(update))
        }
    }

    public func resolve(in environment: HeistExecutionEnvironment) throws -> ElementDeltaPredicate {
        switch self {
        case .appearedElement(let element):
            return .appearedElement(try element.resolve(in: environment))
        case .disappearedElement(let element):
            return .disappearedElement(try element.resolve(in: environment))
        case .updatedElement(let update):
            return .updatedElement(try update.resolve(in: environment))
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let typeString = try container.decode(String.self, forKey: .type)
        guard let wireType = WireType(rawValue: typeString) else {
            let validTypes = WireType.allCases.map(\.rawValue).joined(separator: ", ")
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "Unknown element delta predicate expression type: \"\(typeString)\". Valid: \(validTypes)"
            )
        }
        switch wireType {
        case .appeared:
            try decoder.rejectUnknownKeys(allowed: ["type", "element"], typeName: "appeared predicate expression")
            self = .appearedElement(try container.decode(ElementPredicateTemplate.self, forKey: .element))
        case .disappeared:
            try decoder.rejectUnknownKeys(allowed: ["type", "element"], typeName: "disappeared predicate expression")
            self = .disappearedElement(try container.decode(ElementPredicateTemplate.self, forKey: .element))
        case .updated:
            self = .updatedElement(try ElementUpdatePredicateExpr(from: decoder))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .appearedElement(let element):
            try container.encode(WireType.appeared.rawValue, forKey: .type)
            try container.encode(element, forKey: .element)
        case .disappearedElement(let element):
            try container.encode(WireType.disappeared.rawValue, forKey: .type)
            try container.encode(element, forKey: .element)
        case .updatedElement(let update):
            try container.encode(WireType.updated.rawValue, forKey: .type)
            try update.encode(to: encoder)
        }
    }
}

extension ElementDeltaPredicateExpr: CustomStringConvertible {
    public var description: String {
        switch self {
        case .appearedElement(let element):
            return ScoreDescription.call("appeared", [element.description])
        case .disappearedElement(let element):
            return ScoreDescription.call("disappeared", [element.description])
        case .updatedElement(let update):
            return ScoreDescription.call("updated", [update.description])
        }
    }
}

public enum ChangePredicateExpr: Codable, Sendable, Equatable {
    case any
    case screenScope([StatePredicateExpr] = [])
    case elementsScope([ElementDeltaPredicateExpr] = [])
    case allScopes(NonEmptyArray<ChangeScopePredicateExpr>)

    private enum PredicateWireType: String {
        case change
    }

    private enum ScopeWireType: String, CaseIterable {
        case screen
        case elements
        case all
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case type, scopes, assertions
    }

    public init(_ change: AccessibilityPredicate.Change) {
        switch change {
        case .any:
            self = .any
        case .screenScope(let assertions):
            self = .screenScope(assertions.map(StatePredicateExpr.init))
        case .elementsScope(let assertions):
            self = .elementsScope(assertions.map(ElementDeltaPredicateExpr.init))
        case .allScopes(let changes):
            self = .allScopes(changes.mapNonEmpty(ChangeScopePredicateExpr.init))
        }
    }

    public func resolve(in environment: HeistExecutionEnvironment) throws -> AccessibilityPredicate.Change {
        switch self {
        case .any:
            return .any
        case .screenScope(let assertions):
            return .screenScope(try assertions.map { try $0.resolve(in: environment) })
        case .elementsScope(let assertions):
            return .elementsScope(try assertions.map { try $0.resolve(in: environment) })
        case .allScopes(let changes):
            return .allScopes(try changes.mapNonEmpty { try $0.resolve(in: environment) })
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let typeString = try container.decode(String.self, forKey: .type)
        if typeString == PredicateWireType.change.rawValue {
            try decoder.rejectUnknownKeys(allowed: ["type", "scopes"], typeName: "change predicate expression")
            let scopes = try container.decodeIfPresent([ChangeScopePredicateExpr].self, forKey: .scopes) ?? []
            self = Self.composed(scopes)
            return
        }
        self = try ChangeScopePredicateExpr(from: decoder).change
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(PredicateWireType.change.rawValue, forKey: .type)
        let scopes = Self.flatten(self)
        if !scopes.isEmpty {
            try container.encode(scopes, forKey: .scopes)
        }
    }

    private static func composed(_ scopes: [ChangeScopePredicateExpr]) -> ChangePredicateExpr {
        let flattened = scopes.flatMap(ChangeScopePredicateExpr.flatten)
        switch flattened.count {
        case 0:
            return .any
        case 1:
            return flattened[0].change
        default:
            return .allScopes(NonEmptyArray(flattened[0], rest: Array(flattened.dropFirst())))
        }
    }

    fileprivate static func flatten(_ change: ChangePredicateExpr) -> [ChangeScopePredicateExpr] {
        switch change {
        case .any:
            return []
        case .screenScope, .elementsScope:
            return [ChangeScopePredicateExpr(change)]
        case .allScopes(let changes):
            return changes.flatMap(ChangeScopePredicateExpr.flatten)
        }
    }
}

public enum ChangeScopePredicateExpr: Codable, Sendable, Equatable {
    case screen([StatePredicateExpr] = [])
    case elements([ElementDeltaPredicateExpr] = [])
    case all(NonEmptyArray<ChangeScopePredicateExpr>)

    private enum ScopeWireType: String, CaseIterable {
        case screen
        case elements
        case all
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case type, assertions, scopes
    }

    public init(_ scope: AccessibilityPredicate.ChangeScope) {
        switch scope {
        case .screen(let assertions):
            self = .screen(assertions.map(StatePredicateExpr.init))
        case .elements(let assertions):
            self = .elements(assertions.map(ElementDeltaPredicateExpr.init))
        case .all(let scopes):
            self = .all(scopes.mapNonEmpty(ChangeScopePredicateExpr.init))
        }
    }

    fileprivate init(_ change: ChangePredicateExpr) {
        switch change {
        case .any:
            preconditionFailure("any change has no scoped expression representation")
        case .screenScope(let assertions):
            self = .screen(assertions)
        case .elementsScope(let assertions):
            self = .elements(assertions)
        case .allScopes(let scopes):
            self = .all(scopes)
        }
    }

    var change: ChangePredicateExpr {
        switch self {
        case .screen(let assertions):
            return .screenScope(assertions)
        case .elements(let assertions):
            return .elementsScope(assertions)
        case .all(let scopes):
            return .allScopes(scopes)
        }
    }

    public func resolve(in environment: HeistExecutionEnvironment) throws -> AccessibilityPredicate.ChangeScope {
        switch self {
        case .screen(let assertions):
            return .screen(try assertions.map { try $0.resolve(in: environment) })
        case .elements(let assertions):
            return .elements(try assertions.map { try $0.resolve(in: environment) })
        case .all(let scopes):
            return .all(try scopes.mapNonEmpty { try $0.resolve(in: environment) })
        }
    }

    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "change scope expression")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let typeString = try container.decode(String.self, forKey: .type)
        guard let type = ScopeWireType(rawValue: typeString) else {
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "Unknown change scope type: \"\(typeString)\". Valid: \(ScopeWireType.allCases.map(\.rawValue).joined(separator: ", "))"
            )
        }
        switch type {
        case .screen:
            self = .screen(try container.decodeIfPresent([StatePredicateExpr].self, forKey: .assertions) ?? [])
        case .elements:
            self = .elements(try container.decodeIfPresent([ElementDeltaPredicateExpr].self, forKey: .assertions) ?? [])
        case .all:
            let scopes = try container.decode([ChangeScopePredicateExpr].self, forKey: .scopes)
            guard let first = scopes.first else {
                throw DecodingError.dataCorruptedError(
                    forKey: .scopes,
                    in: container,
                    debugDescription: "all change scope expression requires at least one child scope"
                )
            }
            self = .all(NonEmptyArray(first, rest: Array(scopes.dropFirst())))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .screen(let assertions):
            try container.encode(ScopeWireType.screen.rawValue, forKey: .type)
            if !assertions.isEmpty {
                try container.encode(assertions, forKey: .assertions)
            }
        case .elements(let assertions):
            try container.encode(ScopeWireType.elements.rawValue, forKey: .type)
            if !assertions.isEmpty {
                try container.encode(assertions, forKey: .assertions)
            }
        case .all(let changes):
            try container.encode(ScopeWireType.all.rawValue, forKey: .type)
            try container.encode(changes.flatMap(Self.flatten), forKey: .scopes)
        }
    }

    fileprivate static func flatten(_ scope: ChangeScopePredicateExpr) -> [ChangeScopePredicateExpr] {
        switch scope {
        case .screen, .elements:
            return [scope]
        case .all(let scopes):
            return scopes.flatMap(flatten)
        }
    }
}

extension ChangePredicateExpr: CustomStringConvertible {
    public var description: String {
        switch self {
        case .any:
            return "change"
        case .screenScope(let assertions):
            return ScoreDescription.call("screen", assertions.map(\.description))
        case .elementsScope(let assertions):
            return ScoreDescription.call("elements", assertions.map(\.description))
        case .allScopes(let changes):
            return ScoreDescription.call("all", changes.map(\.description))
        }
    }
}

extension ChangeScopePredicateExpr: CustomStringConvertible {
    public var description: String {
        switch self {
        case .screen(let assertions):
            return ScoreDescription.call("screen", assertions.map(\.description))
        case .elements(let assertions):
            return ScoreDescription.call("elements", assertions.map(\.description))
        case .all(let scopes):
            return ScoreDescription.call("all", scopes.map(\.description))
        }
    }
}

public enum AccessibilityPredicateExpr: Codable, Sendable, Equatable {
    case predicate(AccessibilityPredicate)
    case state(StatePredicateExpr)
    case changePredicate(ChangePredicateExpr)
    case noChangePredicate

    public init(_ predicate: AccessibilityPredicate) {
        self = .predicate(predicate)
    }

    public func resolve(in environment: HeistExecutionEnvironment) throws -> AccessibilityPredicate {
        switch self {
        case .predicate(let predicate):
            return predicate
        case .state(let state):
            return .state(try state.resolve(in: environment))
        case .changePredicate(let change):
            return .changePredicate(try change.resolve(in: environment))
        case .noChangePredicate:
            return .noChange
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: PredicateProbeKeys.self)
        let typeString = try container.decode(String.self, forKey: .type)
        switch typeString {
        case "exists", "missing", "all":
            self = .state(try StatePredicateExpr(from: decoder))
        case "change":
            self = .changePredicate(try ChangePredicateExpr(from: decoder))
        case "no_change":
            try decoder.rejectUnknownKeys(allowed: ["type"], typeName: "no_change predicate expression")
            self = .noChangePredicate
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
        case .changePredicate(let change):
            try change.encode(to: encoder)
        case .noChangePredicate:
            var container = encoder.container(keyedBy: PredicateProbeKeys.self)
            try container.encode("no_change", forKey: .type)
        }
    }

    private enum PredicateProbeKeys: String, CodingKey, CaseIterable {
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
        case (.changePredicate(let lhsChange), .changePredicate(let rhsChange)):
            return lhsChange == rhsChange
        case (.noChangePredicate, .noChangePredicate):
            return true
        case (.predicate(let predicate), .state(let state)),
             (.state(let state), .predicate(let predicate)):
            guard case .state(let predicateState) = predicate,
                  let resolvedState = try? state.resolve(in: .empty) else {
                return false
            }
            return predicateState == resolvedState
        case (.predicate(let predicate), .changePredicate(let change)),
             (.changePredicate(let change), .predicate(let predicate)):
            guard case .changePredicate(let predicateChange) = predicate,
                  let resolvedChange = try? change.resolve(in: .empty) else {
                return false
            }
            return predicateChange == resolvedChange
        case (.predicate(let predicate), .noChangePredicate),
             (.noChangePredicate, .predicate(let predicate)):
            return predicate == .noChange
        case (.state, .changePredicate), (.changePredicate, .state), (.state, .noChangePredicate), (.noChangePredicate, .state),
             (.changePredicate, .noChangePredicate), (.noChangePredicate, .changePredicate):
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
        case .changePredicate(let change):
            return ScoreDescription.call("change", [change.description])
        case .noChangePredicate:
            return "no_change"
        }
    }
}
