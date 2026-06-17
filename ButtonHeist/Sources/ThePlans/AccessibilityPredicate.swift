import Foundation

// MARK: - Accessibility Predicate

/// The single condition vocabulary for everything Button Heist asks about the
/// accessibility interface: what must be true now (`state`) and what must have
/// changed relative to a baseline (`changed`).
///
/// This is the shared primitive for waits (predicate + deadline), action
/// expectations (the `expect` slot), and — later — search loops and DSL control
/// flow. Specificity comes from the `ElementPredicate` fields, never a separate
/// scope or query system.
///
/// ## Wire format
/// `"type"`-discriminated object; any element is nested under `"element"`:
/// ```
/// {"type": "present",            "element": { ...ElementPredicate... }}
/// {"type": "absent",             "element": { ...ElementPredicate... }}
/// {"type": "present",            "target": { ...ElementTarget... }}
/// {"type": "absent",             "target": { ...ElementTarget... }}
/// {"type": "all",                "states": [ <State object>, ... ]}
/// {"type": "screen_changed"}
/// {"type": "screen_changed",     "where": { <State object> }}
/// {"type": "elements_changed"}
/// {"type": "element_updated",    "element": { ... }?, "property": "value"?, "from": "foo"?, "to": "bar"?}
/// ```
public enum AccessibilityPredicate: Sendable, Equatable {
    /// A condition over the latest observed interface snapshot.
    case state(State)
    /// A baseline-to-current transition satisfied the change predicate.
    case changed(Change)

    // MARK: - Nested Types

    /// A condition evaluated against a single observed interface snapshot. A
    /// `State` never nests a `Change`; it composes only with other `State`s via
    /// `.all`, so a snapshot condition can never smuggle in a transition check.
    public enum State: Sendable, Equatable {
        /// An element matching the predicate exists in the observed interface.
        case present(ElementPredicate)
        /// No element matching the predicate exists in the observed interface.
        case absent(ElementPredicate)
        /// A selected element target exists in the observed interface.
        case presentTarget(ElementTarget)
        /// A selected element target does not exist in the observed interface.
        case absentTarget(ElementTarget)
        /// Every child state holds against the same observed interface.
        /// `all([])` is invalid — it carries no condition.
        case all([State])
    }

    /// A condition evaluated against a baseline-to-current transition delta.
    public enum Change: Sendable, Equatable {
        /// The screen changed (top view-controller identity changed). When
        /// `where` is non-nil, the resulting interface must also satisfy it.
        case screen(where: State? = nil)
        /// Elements were added, removed, or updated (or the screen changed).
        case elements
        /// A tracked element property changed, filtered by the update predicate.
        case updated(ElementUpdatePredicate)
    }
}

// MARK: - Codable

extension AccessibilityPredicate: Codable {
    private enum WireType: String, CaseIterable {
        case present
        case absent
        case all
        case screenChanged = "screen_changed"
        case elementsChanged = "elements_changed"
        case elementUpdated = "element_updated"
    }

    /// Discriminator strings accepted in object-form predicate payloads.
    public static let wireTypeValues: [String] = WireType.allCases.map(\.rawValue)

    private enum CodingKeys: String, CodingKey {
        case type, element, target, states, `where`, property, from, to
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let typeString = try container.decode(String.self, forKey: .type)
        guard let wireType = WireType(rawValue: typeString) else {
            throw DecodingError.dataCorruptedError(
                forKey: .type, in: container,
                debugDescription: "Unknown predicate type: \"\(typeString)\". Valid: \(Self.wireTypeValues.joined(separator: ", "))"
            )
        }
        switch wireType {
        case .present, .absent, .all:
            self = .state(try State(from: decoder))
        case .screenChanged:
            try decoder.rejectUnknownKeys(allowed: ["type", "where"], typeName: "screen_changed predicate")
            let stateClause = try container.decodeIfPresent(State.self, forKey: .where)
            self = .changed(.screen(where: stateClause))
        case .elementsChanged:
            try decoder.rejectUnknownKeys(allowed: ["type"], typeName: "elements_changed predicate")
            self = .changed(.elements)
        case .elementUpdated:
            try decoder.rejectUnknownKeys(allowed: ["type", "element", "property", "from", "to"], typeName: "element_updated predicate")
            self = .changed(.updated(ElementUpdatePredicate(
                element: try container.decodeIfPresent(ElementPredicate.self, forKey: .element),
                property: try Self.decodeProperty(container),
                from: try container.decodeIfPresent(String.self, forKey: .from),
                to: try container.decodeIfPresent(String.self, forKey: .to)
            )))
        }
    }

    public func encode(to encoder: Encoder) throws {
        switch self {
        case .state(let stateClause):
            try stateClause.encode(to: encoder)
        case .changed(let change):
            var container = encoder.container(keyedBy: CodingKeys.self)
            switch change {
            case .screen(let stateClause):
                try container.encode(WireType.screenChanged.rawValue, forKey: .type)
                try container.encodeIfPresent(stateClause, forKey: .where)
            case .elements:
                try container.encode(WireType.elementsChanged.rawValue, forKey: .type)
            case .updated(let update):
                try container.encode(WireType.elementUpdated.rawValue, forKey: .type)
                try container.encodeIfPresent(update.element, forKey: .element)
                try container.encodeIfPresent(update.property, forKey: .property)
                try container.encodeIfPresent(update.from, forKey: .from)
                try container.encodeIfPresent(update.to, forKey: .to)
            }
        }
    }

    private static func decodeRequiredElement(
        _ decoder: Decoder,
        _ container: KeyedDecodingContainer<CodingKeys>
    ) throws -> ElementPredicate {
        try decoder.rejectUnknownKeys(allowed: ["type", "element"], typeName: "predicate")
        return try container.decode(ElementPredicate.self, forKey: .element)
    }

    private static func decodeProperty(
        _ container: KeyedDecodingContainer<CodingKeys>
    ) throws -> ElementProperty? {
        guard let propertyString = try container.decodeIfPresent(String.self, forKey: .property) else {
            return nil
        }
        guard let property = ElementProperty(rawValue: propertyString) else {
            throw DecodingError.dataCorruptedError(
                forKey: .property, in: container,
                debugDescription: "Unknown element property: \"\(propertyString)\". Valid: \(ElementProperty.allCases.map(\.rawValue).joined(separator: ", "))"
            )
        }
        return property
    }
}

// MARK: - State Codable

extension AccessibilityPredicate.State: Codable {
    private enum WireType: String {
        case present
        case absent
        case all
    }

    private enum CodingKeys: String, CodingKey {
        case type, element, target, states
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let typeString = try container.decode(String.self, forKey: .type)
        guard let wireType = WireType(rawValue: typeString) else {
            throw DecodingError.dataCorruptedError(
                forKey: .type, in: container,
                debugDescription: "Unknown state predicate type: \"\(typeString)\". Valid: present, absent, all"
            )
        }
        switch wireType {
        case .present:
            self = try Self.decodeElementState(
                decoder,
                container,
                typeName: "present predicate",
                predicateState: Self.present,
                targetState: Self.presentTarget
            )
        case .absent:
            self = try Self.decodeElementState(
                decoder,
                container,
                typeName: "absent predicate",
                predicateState: Self.absent,
                targetState: Self.absentTarget
            )
        case .all:
            try decoder.rejectUnknownKeys(allowed: ["type", "states"], typeName: "all predicate")
            let states = try container.decode([AccessibilityPredicate.State].self, forKey: .states)
            guard !states.isEmpty else {
                throw DecodingError.dataCorruptedError(
                    forKey: .states, in: container,
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
            try container.encode(target, forKey: .target)
        case .absentTarget(let target):
            try container.encode(WireType.absent.rawValue, forKey: .type)
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

// MARK: - CustomStringConvertible

extension AccessibilityPredicate: CustomStringConvertible {
    public var description: String {
        switch self {
        case .state(let stateClause): return stateClause.description
        case .changed(let change): return ScoreDescription.call("changed", [change.description])
        }
    }
}

extension AccessibilityPredicate.State: CustomStringConvertible {
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

extension AccessibilityPredicate.Change: CustomStringConvertible {
    public var description: String {
        switch self {
        case .screen(let stateClause):
            guard let stateClause else { return "screen_changed" }
            return ScoreDescription.call("screen_changed", ["where=\(stateClause)"])
        case .elements: return "elements_changed"
        case .updated(let update): return ScoreDescription.call("element_updated", [update.description])
        }
    }
}
