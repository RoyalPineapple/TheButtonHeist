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
/// ```
public enum AccessibilityPredicate: Sendable, Equatable {
    /// A condition over the latest observed interface snapshot.
    case state(State)
    /// A baseline-to-current transition satisfied the change predicate.
    case changePredicate(Change)
    /// No baseline-to-current semantic transition was observed.
    case noChangePredicate

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
        /// `all([])` is invalid because it carries no condition.
        case all([State])
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
        case allScopes([Change])
    }
}

// MARK: - Codable

extension AccessibilityPredicate: Codable {
    private enum WireType: String, CaseIterable {
        case exists
        case missing
        case all
        case noChange = "no_change"
        case change
    }

    /// Discriminator strings accepted in object-form predicate payloads.
    public static let wireTypeValues: [String] = WireType.allCases.map(\.rawValue)

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case type, scopes
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let typeString = try container.decode(String.self, forKey: .type)
        guard let wireType = WireType(rawValue: typeString) else {
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "Unknown predicate type: \"\(typeString)\". Valid: \(Self.wireTypeValues.joined(separator: ", "))"
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
            let scopes = try container.decodeIfPresent([AccessibilityPredicate.Change].self, forKey: .scopes) ?? []
            self = .changePredicate(Self.composedChange(scopes))
        }
    }

    public func encode(to encoder: Encoder) throws {
        switch self {
        case .state(let stateClause):
            try stateClause.encode(to: encoder)
        case .changePredicate(let change):
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(WireType.change.rawValue, forKey: .type)
            let scopes = Self.flatten(change)
            if !scopes.isEmpty {
                try container.encode(scopes, forKey: .scopes)
            }
        case .noChangePredicate:
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(WireType.noChange.rawValue, forKey: .type)
        }
    }

    private static func composedChange(_ scopes: [AccessibilityPredicate.Change]) -> AccessibilityPredicate.Change {
        let flattened = scopes.flatMap(flatten)
        switch flattened.count {
        case 0:
            return .any
        case 1:
            return flattened[0]
        default:
            return .allScopes(flattened)
        }
    }

    private static func flatten(_ change: AccessibilityPredicate.Change) -> [AccessibilityPredicate.Change] {
        switch change {
        case .any:
            return []
        case .screenScope, .elementsScope:
            return [change]
        case .allScopes(let changes):
            return changes.flatMap(flatten)
        }
    }
}

// MARK: - State Codable

extension AccessibilityPredicate.State: Codable {
    private enum WireType: String {
        case exists
        case missing
        case all
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case type, element, target, states
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let typeString = try container.decode(String.self, forKey: .type)
        guard let wireType = WireType(rawValue: typeString) else {
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "Unknown state predicate type: \"\(typeString)\". Valid: exists, missing, all"
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
        case .exists(let predicate):
            try container.encode(WireType.exists.rawValue, forKey: .type)
            try container.encode(predicate, forKey: .element)
        case .missing(let predicate):
            try container.encode(WireType.missing.rawValue, forKey: .type)
            try container.encode(predicate, forKey: .element)
        case .existsTarget(let target):
            try container.encode(WireType.exists.rawValue, forKey: .type)
            try container.encode(target, forKey: .target)
        case .missingTarget(let target):
            try container.encode(WireType.missing.rawValue, forKey: .type)
            try container.encode(target, forKey: .target)
        case .all(let states):
            try container.encode(WireType.all.rawValue, forKey: .type)
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
    private enum WireType: String, CaseIterable {
        case screen
        case elements
        case all
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case type, assertions, scopes
    }

    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "change scope")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let typeString = try container.decode(String.self, forKey: .type)
        guard let wireType = WireType(rawValue: typeString) else {
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "Unknown change scope type: \"\(typeString)\". Valid: \(WireType.allCases.map(\.rawValue).joined(separator: ", "))"
            )
        }
        switch wireType {
        case .screen:
            self = .screenScope(try container.decodeIfPresent([AccessibilityPredicate.State].self, forKey: .assertions) ?? [])
        case .elements:
            self = .elementsScope(try container.decodeIfPresent([ElementDeltaPredicate].self, forKey: .assertions) ?? [])
        case .all:
            let scopes = try container.decode([AccessibilityPredicate.Change].self, forKey: .scopes)
            guard !scopes.isEmpty else {
                throw DecodingError.dataCorruptedError(
                    forKey: .scopes,
                    in: container,
                    debugDescription: "all change scope requires at least one child scope"
                )
            }
            self = .allScopes(scopes)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .any:
            try container.encode(WireType.all.rawValue, forKey: .type)
            try container.encode([AccessibilityPredicate.Change](), forKey: .scopes)
        case .screenScope(let assertions):
            try container.encode(WireType.screen.rawValue, forKey: .type)
            if !assertions.isEmpty {
                try container.encode(assertions, forKey: .assertions)
            }
        case .elementsScope(let assertions):
            try container.encode(WireType.elements.rawValue, forKey: .type)
            if !assertions.isEmpty {
                try container.encode(assertions, forKey: .assertions)
            }
        case .allScopes(let scopes):
            try container.encode(WireType.all.rawValue, forKey: .type)
            try container.encode(scopes, forKey: .scopes)
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
