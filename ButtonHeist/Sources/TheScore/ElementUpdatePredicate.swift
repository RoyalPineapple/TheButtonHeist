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
/// "any tracked element property changed" — narrower than `.changed(.elements)`,
/// which also fires on additions and removals.
public struct ElementUpdatePredicate: Sendable, Equatable {
    /// Which element updated. `nil` matches any updated element.
    public let element: ElementPredicate?
    /// Which property changed. `nil` matches any property.
    public let property: ElementProperty?
    /// Required old value. `nil` means the old value does not matter.
    public let from: String?
    /// Required new value. `nil` means the new value does not matter.
    public let to: String?

    public init(
        element: ElementPredicate? = nil,
        property: ElementProperty? = nil,
        from: String? = nil,
        to: String? = nil
    ) {
        self.element = element
        self.property = property
        self.from = from
        self.to = to
    }

    /// Any tracked element property changed (all filters unset).
    public static let any = ElementUpdatePredicate()
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
            from: try container.decodeIfPresent(String.self, forKey: .from),
            to: try container.decodeIfPresent(String.self, forKey: .to)
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
            ScoreDescription.stringField("from", from),
            ScoreDescription.stringField("to", to),
        ].compactMap { $0 })
    }
}
