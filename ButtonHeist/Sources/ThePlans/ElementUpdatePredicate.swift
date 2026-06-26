import Foundation

// MARK: - Element Update Predicate

/// Predicate over a single element-property change in a baseline-to-current
/// transition. Every field is an optional filter — provide what you know, omit
/// what you don't. The transition's update edits are scanned for any entry that
/// satisfies all provided fields.
///
/// - `property == nil`: any property changed.
/// - `before == nil`: old element state does not matter.
/// - `after == nil`: new element state does not matter.
///
/// All-nil (`ElementUpdatePredicate.any`) is a first-class predicate meaning
/// "any tracked element property changed" — narrower than `.change(.elements())`,
/// which also fires on additions and removals.
public struct ElementUpdatePredicate: Sendable, Equatable {
    /// Required old element state. `nil` means the old element state does not matter.
    public let before: ElementPredicate?
    /// Required new element state. `nil` means the new element state does not matter.
    public let after: ElementPredicate?
    /// Which property changed. `nil` matches any property.
    public let property: ElementProperty?

    public init(
        before: ElementPredicate? = nil,
        after: ElementPredicate? = nil,
        property: ElementProperty? = nil
    ) {
        self.before = before
        self.after = after
        self.property = property
    }

    /// Any tracked element property changed (all filters unset).
    public static let any = ElementUpdatePredicate()
}

// MARK: - Element Delta Predicate

/// Predicate over one same-screen element delta.
///
/// These predicates reuse the same `ElementPredicate` and string matching
/// machinery as targeting. The only difference is the side of the delta they
/// are evaluated against:
/// - `appeared`: matches an element absent from the baseline and present in the
///   final tree.
/// - `disappeared`: matches an element present in the baseline and absent from
///   the final tree.
/// - `updated`: matches a paired element whose tracked properties changed.
public enum ElementDeltaPredicate: Sendable, Equatable {
    case appearedElement(ElementPredicate)
    case disappearedElement(ElementPredicate)
    case updatedElement(ElementUpdatePredicate)
}

extension ElementUpdatePredicate: Codable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case type, before, after, property
    }

    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "element update predicate")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            before: try container.decodeIfPresent(ElementPredicate.self, forKey: .before),
            after: try container.decodeIfPresent(ElementPredicate.self, forKey: .after),
            property: try container.decodeIfPresent(ElementProperty.self, forKey: .property)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(before, forKey: .before)
        try container.encodeIfPresent(after, forKey: .after)
        try container.encodeIfPresent(property, forKey: .property)
    }
}

extension ElementUpdatePredicate: CustomStringConvertible {
    public var description: String {
        ScoreDescription.call("update", [
            before.map { "before=\($0)" },
            after.map { "after=\($0)" },
            ScoreDescription.valueField("property", property?.rawValue),
        ].compactMap { $0 })
    }
}

extension ElementDeltaPredicate: Codable {
    private enum WireType: String, CaseIterable {
        case appeared
        case disappeared
        case updated
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case type, element, before, after, property
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let typeString = try container.decode(String.self, forKey: .type)
        guard let wireType = WireType(rawValue: typeString) else {
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "Unknown element delta predicate type: \"\(typeString)\". Valid: \(WireType.allCases.map(\.rawValue).joined(separator: ", "))"
            )
        }
        switch wireType {
        case .appeared:
            try decoder.rejectUnknownKeys(allowed: ["type", "element"], typeName: "appeared predicate")
            self = .appearedElement(try container.decode(ElementPredicate.self, forKey: .element))
        case .disappeared:
            try decoder.rejectUnknownKeys(allowed: ["type", "element"], typeName: "disappeared predicate")
            self = .disappearedElement(try container.decode(ElementPredicate.self, forKey: .element))
        case .updated:
            try decoder.rejectUnknownKeys(allowed: ["type", "before", "after", "property"], typeName: "updated predicate")
            self = .updatedElement(try ElementUpdatePredicate(from: decoder))
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
            try container.encodeIfPresent(update.before, forKey: .before)
            try container.encodeIfPresent(update.after, forKey: .after)
            try container.encodeIfPresent(update.property, forKey: .property)
        }
    }
}

extension ElementDeltaPredicate: CustomStringConvertible {
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
