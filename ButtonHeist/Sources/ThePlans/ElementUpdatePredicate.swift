import Foundation

// MARK: - Element Update Predicate

/// Predicate over a single element-property change in a baseline-to-current
/// transition. Every field is an optional filter — provide what you know, omit
/// what you don't. The transition's update edits are scanned for any entry that
/// satisfies all provided fields.
///
/// - `element == nil`: any updated element.
/// - `property == nil`: any property changed.
/// - `from == nil`: old value does not matter.
/// - `to == nil`: new value does not matter.
///
/// All-nil (`ElementUpdatePredicate.any`) is a first-class predicate meaning
/// "any tracked element property changed" — narrower than `.change(.elements())`,
/// which also fires on additions and removals.
public struct ElementUpdatePredicate: Sendable, Equatable {
    /// Which element updated. `nil` matches any updated element.
    public let element: ElementPredicate?
    /// Which property changed. `nil` matches any property.
    public let property: ElementProperty?
    /// Required old value. `nil` means the old value does not matter.
    public let from: StringMatch<String>?
    /// Required new value. `nil` means the new value does not matter.
    public let to: StringMatch<String>?

    public init(
        element: ElementPredicate? = nil,
        property: ElementProperty? = nil,
        from: StringMatch<String>? = nil,
        to: StringMatch<String>? = nil
    ) {
        self.element = element
        self.property = property
        self.from = from
        self.to = to
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
        case element, property, from, to
    }

    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "element update predicate")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            element: try container.decodeIfPresent(ElementPredicate.self, forKey: .element),
            property: try container.decodeIfPresent(ElementProperty.self, forKey: .property),
            from: try container.decodeIfPresent(StringMatch<String>.self, forKey: .from),
            to: try container.decodeIfPresent(StringMatch<String>.self, forKey: .to)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(element, forKey: .element)
        try container.encodeIfPresent(property, forKey: .property)
        try container.encodeIfPresent(from, forKey: .from)
        try container.encodeIfPresent(to, forKey: .to)
    }
}

extension ElementUpdatePredicate: CustomStringConvertible {
    public var description: String {
        ScoreDescription.call("update", [
            element.map { "element=\($0)" },
            ScoreDescription.valueField("property", property?.rawValue),
            ScoreDescription.stringMatchField("from", from),
            ScoreDescription.stringMatchField("to", to),
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
        case type, element, property, from, to
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
            try decoder.rejectUnknownKeys(allowed: ["type", "element", "property", "from", "to"], typeName: "updated predicate")
            self = .updatedElement(ElementUpdatePredicate(
                element: try container.decodeIfPresent(ElementPredicate.self, forKey: .element),
                property: try container.decodeIfPresent(ElementProperty.self, forKey: .property),
                from: try container.decodeIfPresent(StringMatch<String>.self, forKey: .from),
                to: try container.decodeIfPresent(StringMatch<String>.self, forKey: .to)
            ))
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
            try container.encodeIfPresent(update.element, forKey: .element)
            try container.encodeIfPresent(update.property, forKey: .property)
            try container.encodeIfPresent(update.from, forKey: .from)
            try container.encodeIfPresent(update.to, forKey: .to)
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
