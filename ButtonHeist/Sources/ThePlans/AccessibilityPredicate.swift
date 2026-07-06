import Foundation

// MARK: - Accessibility Predicate

/// The single condition vocabulary for everything Button Heist asks about the
/// accessibility interface: what must be true in a tree, what changed between
/// two trees, and whether no semantic tree change happened.
///
/// Specificity comes from `ElementPredicate` and `StringMatch`, never from a
/// separate expectation or assertion language.
///
/// ## Wire format
/// `"type"`-discriminated object; any element predicate is nested under
/// `"element"`:
/// ```
/// {"type": "exists",  "element": { ...ElementPredicate... }}
/// {"type": "missing", "element": { ...ElementPredicate... }}
/// {"type": "exists",  "target": { ...ElementTarget... }}
/// {"type": "missing", "target": { ...ElementTarget... }}
/// {"type": "all",     "states": [ <State object>, ... ]}
/// {"type": "no_change"}
/// {"type": "change"}
/// {"type": "change",  "scopes": [ {"type": "screen", "assertions": [ <State object>, ... ]} ]}
/// {"type": "change",  "scopes": [ {"type": "elements", "assertions": [ <ElementDeltaPredicate object>, ... ]} ]}
/// {"type": "announcement", "match": { ...StringMatch... }}
/// ```
public enum AccessibilityPredicate: Sendable, Equatable {
    /// A condition over the latest observed interface snapshot.
    case state(State)
    /// A baseline-to-current transition satisfied the change predicate.
    case changePredicate(Change)
    /// No baseline-to-current semantic transition was observed.
    case noChangePredicate
    /// An accessibility announcement was posted.
    case announcement(AnnouncementPredicate)

    // MARK: - Nested Types

    /// A condition evaluated against one observed interface snapshot. A `State`
    /// never nests a `Change`; it composes only with other `State`s via `.all`.
    public enum State: Sendable, Equatable {
        /// An element matching the predicate exists in the observed interface.
        case exists(ElementPredicate)
        /// No element matching the predicate exists in the observed interface.
        case missing(ElementPredicate)
        /// A selected element target exists in the observed interface.
        case existsTarget(ElementTarget)
        /// A selected element target does not exist in the observed interface.
        case missingTarget(ElementTarget)
        /// Every child state holds against the same observed interface.
        case all(NonEmptyArray<State>)
    }

    /// A condition evaluated against a baseline-to-current transition delta.
    public enum Change: Sendable, Equatable {
        /// Any observable semantic transition happened.
        case any
        /// The screen changed. When assertions are present, the resulting
        /// interface must satisfy all of them.
        case screenScope([State] = [])
        /// Elements appeared, disappeared, or updated within the same screen.
        /// When assertions are present, every assertion must match the element
        /// diff.
        case elementsScope([ElementDeltaPredicate] = [])
        /// Every child change predicate holds against the same transition.
        case allScopes(NonEmptyArray<ChangeScope>)
    }

    /// A scoped transition predicate. Unlike `Change`, this type has no
    /// catch-all `any` case, so nested change scopes cannot erase meaning.
    public enum ChangeScope: Sendable, Equatable {
        case screen([State] = [])
        case elements([ElementDeltaPredicate] = [])
        case all(NonEmptyArray<ChangeScope>)
    }
}

// MARK: - Predicate Contract

/// Shared contract that binds predicate wire discriminators to runtime semantics.
public enum AccessibilityPredicateContract: Sendable, Equatable {
    case state(State)
    case change(Change)
    case noChange
    case announcement

    public enum PredicateWireType: String, CaseIterable, Sendable {
        case exists
        case missing
        case all
        case noChange = "no_change"
        case change
        case announcement

        public static var values: [String] {
            allCases.map(\.rawValue)
        }

        public static var validDescription: String {
            values.joined(separator: ", ")
        }
    }

    public enum StateWireType: String, CaseIterable, Sendable {
        case exists
        case missing
        case all

        public static var values: [String] {
            allCases.map(\.rawValue)
        }

        public static var validDescription: String {
            values.joined(separator: ", ")
        }

        public var predicateWireType: PredicateWireType {
            switch self {
            case .exists:
                return .exists
            case .missing:
                return .missing
            case .all:
                return .all
            }
        }
    }

    public enum ChangeScopeWireType: String, CaseIterable, Sendable {
        case screen
        case elements
        case all

        public static var values: [String] {
            allCases.map(\.rawValue)
        }

        public static var validDescription: String {
            values.joined(separator: ", ")
        }
    }

    public enum PresenceRequirement: Sendable, Equatable {
        case present
        case absent

        public var stateWireType: StateWireType {
            switch self {
            case .present:
                return .exists
            case .absent:
                return .missing
            }
        }

        public func isMet(isPresent: Bool) -> Bool {
            switch self {
            case .present:
                return isPresent
            case .absent:
                return !isPresent
            }
        }

        public func failureDescription(for predicate: ElementPredicate) -> String {
            switch self {
            case .present:
                return "no element matches \(predicate)"
            case .absent:
                return "still present: \(predicate)"
            }
        }

        public func failureDescription(for target: ElementTarget) -> String {
            switch self {
            case .present:
                return "target not present: \(target)"
            case .absent:
                return "target still present: \(target)"
            }
        }
    }

    public enum State: Sendable, Equatable {
        case element(PresenceRequirement, ElementPredicate)
        case target(PresenceRequirement, ElementTarget)
        case all(NonEmptyArray<AccessibilityPredicate.State>)

        public var wireType: StateWireType {
            switch self {
            case .element(let requirement, _), .target(let requirement, _):
                return requirement.stateWireType
            case .all:
                return .all
            }
        }
    }

    public enum Change: Sendable, Equatable {
        case any
        case screen([AccessibilityPredicate.State])
        case elements([ElementDeltaPredicate])
        case all(NonEmptyArray<AccessibilityPredicate.ChangeScope>)
    }

    public enum ChangeScope: Sendable, Equatable {
        case screen([AccessibilityPredicate.State])
        case elements([ElementDeltaPredicate])
        case all(NonEmptyArray<AccessibilityPredicate.ChangeScope>)

        public var wireType: ChangeScopeWireType {
            switch self {
            case .screen:
                return .screen
            case .elements:
                return .elements
            case .all:
                return .all
            }
        }
    }

    public var predicateWireType: PredicateWireType {
        switch self {
        case .state(let state):
            return state.wireType.predicateWireType
        case .change:
            return .change
        case .noChange:
            return .noChange
        case .announcement:
            return .announcement
        }
    }
}

private enum AccessibilityPredicateDecodingDescription {
    static let emptyStateAll = "all predicate requires at least one child state"
    static let emptyChangeAllScope = "all change scope requires at least one child scope"
}

public extension AccessibilityPredicate {
    var contract: AccessibilityPredicateContract {
        switch self {
        case .state(let state):
            return .state(state.contract)
        case .changePredicate(let change):
            return .change(change.contract)
        case .noChangePredicate:
            return .noChange
        case .announcement:
            return .announcement
        }
    }
}

public extension AccessibilityPredicate.State {
    var contract: AccessibilityPredicateContract.State {
        switch self {
        case .exists(let predicate):
            return .element(.present, predicate)
        case .missing(let predicate):
            return .element(.absent, predicate)
        case .existsTarget(let target):
            return .target(.present, target)
        case .missingTarget(let target):
            return .target(.absent, target)
        case .all(let states):
            return .all(states)
        }
    }
}

public extension AccessibilityPredicate.Change {
    var contract: AccessibilityPredicateContract.Change {
        switch self {
        case .any:
            return .any
        case .screenScope(let assertions):
            return .screen(assertions)
        case .elementsScope(let assertions):
            return .elements(assertions)
        case .allScopes(let changes):
            return .all(changes)
        }
    }
}

public extension AccessibilityPredicate.ChangeScope {
    var contract: AccessibilityPredicateContract.ChangeScope {
        switch self {
        case .screen(let assertions):
            return .screen(assertions)
        case .elements(let assertions):
            return .elements(assertions)
        case .all(let changes):
            return .all(changes)
        }
    }
}

// MARK: - Codable

extension AccessibilityPredicate: Codable {
    /// Discriminator strings accepted in object-form predicate payloads.
    public static let wireTypeValues: [String] = AccessibilityPredicateContract.PredicateWireType.values

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case type, scopes, match
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let typeString = try container.decode(String.self, forKey: .type)
        guard let wireType = AccessibilityPredicateContract.PredicateWireType(rawValue: typeString) else {
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "Unknown predicate type: \"\(typeString)\". Valid: \(AccessibilityPredicateContract.PredicateWireType.validDescription)"
            )
        }
        switch wireType {
        case .exists, .missing, .all:
            self = .state(try State(from: decoder))
        case .noChange:
            try decoder.rejectUnknownKeys(allowed: ["type"], typeName: "no_change predicate")
            self = .noChangePredicate
        case .change:
            try decoder.rejectUnknownKeys(allowed: ["type", "scopes"], typeName: "change predicate")
            let scopes = try container.decodeIfPresent([AccessibilityPredicate.ChangeScope].self, forKey: .scopes) ?? []
            self = .changePredicate(Self.composedChange(scopes))
        case .announcement:
            try decoder.rejectUnknownKeys(allowed: ["type", "match"], typeName: "announcement predicate")
            self = .announcement(AnnouncementPredicate(
                match: try container.decodeIfPresent(StringMatch<String>.self, forKey: .match)
            ))
        }
    }

    public func encode(to encoder: Encoder) throws {
        let predicateContract = contract
        switch self {
        case .state(let stateClause):
            try stateClause.encode(to: encoder)
        case .changePredicate(let change):
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(predicateContract.predicateWireType.rawValue, forKey: .type)
            let scopes = Self.flatten(change)
            if !scopes.isEmpty {
                try container.encode(scopes, forKey: .scopes)
            }
        case .noChangePredicate:
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(predicateContract.predicateWireType.rawValue, forKey: .type)
        case .announcement(let announcement):
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(predicateContract.predicateWireType.rawValue, forKey: .type)
            try container.encodeIfPresent(announcement.match, forKey: .match)
        }
    }

    private static func composedChange(_ scopes: [AccessibilityPredicate.ChangeScope]) -> AccessibilityPredicate.Change {
        let flattened = scopes.flatMap(flatten)
        switch flattened.count {
        case 0:
            return .any
        case 1:
            return AccessibilityPredicate.Change(flattened[0])
        default:
            return .allScopes(NonEmptyArray(flattened[0], rest: Array(flattened.dropFirst())))
        }
    }

    private static func flatten(_ change: AccessibilityPredicate.Change) -> [AccessibilityPredicate.ChangeScope] {
        switch change {
        case .any:
            return []
        case .screenScope, .elementsScope:
            return [AccessibilityPredicate.ChangeScope(change)]
        case .allScopes(let changes):
            return changes.flatMap(flatten)
        }
    }

    private static func flatten(_ scope: AccessibilityPredicate.ChangeScope) -> [AccessibilityPredicate.ChangeScope] {
        switch scope {
        case .screen, .elements:
            return [scope]
        case .all(let scopes):
            return scopes.flatMap(flatten)
        }
    }
}

// MARK: - State Codable

extension AccessibilityPredicate.State: Codable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case type, element, target, states
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let typeString = try container.decode(String.self, forKey: .type)
        guard let wireType = AccessibilityPredicateContract.StateWireType(rawValue: typeString) else {
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "Unknown state predicate type: \"\(typeString)\". Valid: \(AccessibilityPredicateContract.StateWireType.validDescription)"
            )
        }
        switch wireType {
        case .exists:
            self = try Self.decodeElementState(
                decoder,
                container,
                typeName: "exists predicate",
                predicateState: Self.exists,
                targetState: Self.existsTarget
            )
        case .missing:
            self = try Self.decodeElementState(
                decoder,
                container,
                typeName: "missing predicate",
                predicateState: Self.missing,
                targetState: Self.missingTarget
            )
        case .all:
            try decoder.rejectUnknownKeys(allowed: ["type", "states"], typeName: "all predicate")
            let states = try container.decode([AccessibilityPredicate.State].self, forKey: .states)
            guard let first = states.first else {
                throw DecodingError.dataCorruptedError(
                    forKey: .states,
                    in: container,
                    debugDescription: AccessibilityPredicateDecodingDescription.emptyStateAll
                )
            }
            self = .all(NonEmptyArray(first, rest: Array(states.dropFirst())))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch contract {
        case .element(let requirement, let predicate):
            try container.encode(requirement.stateWireType.rawValue, forKey: .type)
            try container.encode(predicate, forKey: .element)
        case .target(let requirement, let target):
            try container.encode(requirement.stateWireType.rawValue, forKey: .type)
            try container.encode(target, forKey: .target)
        case .all(let states):
            try container.encode(AccessibilityPredicateContract.StateWireType.all.rawValue, forKey: .type)
            try container.encode(states, forKey: .states)
        }
    }

    private static func decodeElementState(
        _ decoder: Decoder,
        _ container: KeyedDecodingContainer<CodingKeys>,
        typeName: String,
        predicateState: (ElementPredicate) -> Self,
        targetState: (ElementTarget) -> Self
    ) throws -> Self {
        try decoder.rejectUnknownKeys(allowed: ["type", "element", "target"], typeName: typeName)
        let hasElement = container.contains(.element)
        let hasTarget = container.contains(.target)
        switch (hasElement, hasTarget) {
        case (true, false):
            return predicateState(try container.decode(ElementPredicate.self, forKey: .element))
        case (false, true):
            return targetState(try container.decode(ElementTarget.self, forKey: .target))
        case (true, true):
            throw DecodingError.dataCorruptedError(
                forKey: .target,
                in: container,
                debugDescription: "\(typeName) accepts either element or target, not both"
            )
        case (false, false):
            throw DecodingError.dataCorruptedError(
                forKey: .element,
                in: container,
                debugDescription: "\(typeName) requires element or target"
            )
        }
    }
}

// MARK: - Change Codable

extension AccessibilityPredicate.Change: Codable {
    public init(from decoder: Decoder) throws {
        self = AccessibilityPredicate.Change(try AccessibilityPredicate.ChangeScope(from: decoder))
    }

    public func encode(to encoder: Encoder) throws {
        switch self {
        case .any:
            throw EncodingError.invalidValue(
                self,
                EncodingError.Context(
                    codingPath: encoder.codingPath,
                    debugDescription: "any change has no scoped wire form"
                )
            )
        case .screenScope, .elementsScope, .allScopes:
            try AccessibilityPredicate.ChangeScope(self).encode(to: encoder)
        }
    }
}

extension AccessibilityPredicate.ChangeScope: Codable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case type, assertions, scopes
    }

    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "change scope")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let typeString = try container.decode(String.self, forKey: .type)
        guard let wireType = AccessibilityPredicateContract.ChangeScopeWireType(rawValue: typeString) else {
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "Unknown change scope type: \"\(typeString)\". Valid: \(AccessibilityPredicateContract.ChangeScopeWireType.validDescription)"
            )
        }
        switch wireType {
        case .screen:
            self = .screen(try container.decodeIfPresent([AccessibilityPredicate.State].self, forKey: .assertions) ?? [])
        case .elements:
            self = .elements(try container.decodeIfPresent([ElementDeltaPredicate].self, forKey: .assertions) ?? [])
        case .all:
            let scopes = try container.decode([AccessibilityPredicate.ChangeScope].self, forKey: .scopes)
            guard let first = scopes.first else {
                throw DecodingError.dataCorruptedError(
                    forKey: .scopes,
                    in: container,
                    debugDescription: AccessibilityPredicateDecodingDescription.emptyChangeAllScope
                )
            }
            self = .all(NonEmptyArray(first, rest: Array(scopes.dropFirst())))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch contract {
        case .screen(let assertions):
            try container.encode(AccessibilityPredicateContract.ChangeScopeWireType.screen.rawValue, forKey: .type)
            if !assertions.isEmpty {
                try container.encode(assertions, forKey: .assertions)
            }
        case .elements(let assertions):
            try container.encode(AccessibilityPredicateContract.ChangeScopeWireType.elements.rawValue, forKey: .type)
            if !assertions.isEmpty {
                try container.encode(assertions, forKey: .assertions)
            }
        case .all(let scopes):
            try container.encode(AccessibilityPredicateContract.ChangeScopeWireType.all.rawValue, forKey: .type)
            try container.encode(scopes, forKey: .scopes)
        }
    }
}

public extension AccessibilityPredicate.Change {
    init(_ scope: AccessibilityPredicate.ChangeScope) {
        switch scope {
        case .screen(let assertions):
            self = .screenScope(assertions)
        case .elements(let assertions):
            self = .elementsScope(assertions)
        case .all(let scopes):
            self = .allScopes(scopes)
        }
    }
}

extension AccessibilityPredicate.ChangeScope {
    init(_ change: AccessibilityPredicate.Change) {
        switch change {
        case .any:
            preconditionFailure("any change has no scoped representation")
        case .screenScope(let assertions):
            self = .screen(assertions)
        case .elementsScope(let assertions):
            self = .elements(assertions)
        case .allScopes(let scopes):
            self = .all(scopes)
        }
    }
}

// MARK: - CustomStringConvertible

extension AccessibilityPredicate: CustomStringConvertible {
    public var description: String {
        switch self {
        case .state(let stateClause): return stateClause.description
        case .changePredicate(let change): return ScoreDescription.call("change", [change.description])
        case .noChangePredicate: return "no_change"
        case .announcement(let announcement): return announcement.description
        }
    }
}

extension AccessibilityPredicate.State: CustomStringConvertible {
    public var description: String {
        switch self {
        case .exists(let predicate): return ScoreDescription.call("exists", [predicate.description])
        case .missing(let predicate): return ScoreDescription.call("missing", [predicate.description])
        case .existsTarget(let target): return ScoreDescription.call("exists", [target.description])
        case .missingTarget(let target): return ScoreDescription.call("missing", [target.description])
        case .all(let states): return ScoreDescription.call("all", states.map(\.description))
        }
    }
}

extension AccessibilityPredicate.Change: CustomStringConvertible {
    public var description: String {
        switch self {
        case .any: return "any_change"
        case .screenScope(let assertions): return ScoreDescription.call("screen", assertions.map(\.description))
        case .elementsScope(let assertions): return ScoreDescription.call("elements", assertions.map(\.description))
        case .allScopes(let changes): return ScoreDescription.call("all", changes.map(\.description))
        }
    }
}

extension AccessibilityPredicate.ChangeScope: CustomStringConvertible {
    public var description: String {
        switch self {
        case .screen(let assertions): return ScoreDescription.call("screen", assertions.map(\.description))
        case .elements(let assertions): return ScoreDescription.call("elements", assertions.map(\.description))
        case .all(let changes): return ScoreDescription.call("all", changes.map(\.description))
        }
    }
}
