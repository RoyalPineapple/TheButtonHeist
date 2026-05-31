import Foundation

// MARK: - Action Expectations

/// Outcome signal classifiers for actions.
/// Attached to a request (not to a target type) so any action can opt in.
///
/// Every action implicitly checks delivery (success == true). These tiers
/// classify *what kind of change* the caller expected. The result tells
/// the caller what actually happened — the caller decides what to do with it.
///
/// **"Say what you know" design**: agents express what they care about and omit
/// what they don't. Optional fields act as filters — provide more to tighten the
/// check, fewer to loosen it. The framework scans the result for any match.
/// This minimizes cognitive load on the caller.
///
/// Superset rule: `screen_changed` is a superset of `elements_changed`.
/// Expecting `elements_changed` is met by either `elementsChanged` or `screenChanged`.
/// Expecting `screen_changed` is only met by `screenChanged`.
/// Screen change is detected by view controller identity — if the topmost VC changed,
/// the screen changed.
///
/// ## Wire format
/// Every case is a JSON object with a `"type"` discriminator:
/// ```
/// {"type": "screen_changed"}
/// {"type": "elements_changed"}
/// {"type": "element_updated", "heistId": "...", "property": "value",
///  "oldValue": "...", "newValue": "..."}   // all payload fields optional
/// {"type": "element_appeared", "matcher": { ...ElementMatcher... }}
/// {"type": "element_disappeared", "matcher": { ...ElementMatcher... }}
/// ```
/// See `docs/WIRE-PROTOCOL.md` for the full shape.
public enum ActionExpectation: Sendable, Equatable {
    /// Expected a screen-level change (VC identity changed).
    case screenChanged
    /// Expected elements to be added, removed, updated, or the screen to change.
    case elementsChanged
    /// Expected a property change on an element. All fields are optional filters —
    /// provide what you know, omit what you don't. Met when any entry in
    /// the result's trace-derived delta updates matches all provided fields.
    case elementUpdated(
        heistId: HeistId? = nil, property: ElementProperty? = nil,
        oldValue: String? = nil, newValue: String? = nil
    )
    /// Expected an element matching this predicate to appear in the delta's added list.
    case elementAppeared(ElementMatcher)
    /// Expected an element matching this predicate to disappear from the delta's removed list.
    /// Validation requires elements derived from the pre-action capture to resolve removed heistIds to matchers.
    case elementDisappeared(ElementMatcher)

}

extension ActionExpectation: CustomStringConvertible {
    public var description: String {
        switch self {
        case .screenChanged:
            return "screen_changed"
        case .elementsChanged:
            return "elements_changed"
        case .elementUpdated(let heistId, let property, let oldValue, let newValue):
            return ScoreDescription.call("element_updated", [
                ScoreDescription.stringField("heistId", heistId),
                ScoreDescription.valueField("property", property?.rawValue),
                ScoreDescription.stringField("oldValue", oldValue),
                ScoreDescription.stringField("newValue", newValue),
            ].compactMap { $0 })
        case .elementAppeared(let matcher):
            return ScoreDescription.call("element_appeared", [matcher.description])
        case .elementDisappeared(let matcher):
            return ScoreDescription.call("element_disappeared", [matcher.description])
        }
    }
}

// MARK: - ActionExpectation Codable

extension ActionExpectation: Codable {
    private enum DiscriminatorKey: String, CodingKey {
        case type
    }

    /// Discriminator strings for the `type` field on the wire.
    private enum WireType: String, CaseIterable {
        case screenChanged = "screen_changed"
        case elementsChanged = "elements_changed"
        case elementUpdated = "element_updated"
        case elementAppeared = "element_appeared"
        case elementDisappeared = "element_disappeared"
    }

    /// Discriminator strings accepted in object-form expectation payloads.
    public static let wireTypeValues: [String] = WireType.allCases.map(\.rawValue)

    private enum ElementUpdatedKey: String, CodingKey, CaseIterable {
        case type, heistId, property, oldValue, newValue
    }

    private enum MatcherKey: String, CodingKey, CaseIterable {
        case type, matcher
    }

    public init(from decoder: Decoder) throws {
        let typeContainer = try decoder.container(keyedBy: DiscriminatorKey.self)
        let typeString = try typeContainer.decode(String.self, forKey: .type)
        guard let wireType = WireType(rawValue: typeString) else {
            throw DecodingError.dataCorruptedError(
                forKey: .type, in: typeContainer,
                debugDescription: "Unknown expectation type: \"\(typeString)\". Valid: \(Self.wireTypeValues.joined(separator: ", "))"
            )
        }
        switch wireType {
        case .screenChanged:
            try Self.rejectUnknownKeys(from: decoder, allowed: ["type"], expectationType: wireType.rawValue)
            self = .screenChanged
        case .elementsChanged:
            try Self.rejectUnknownKeys(from: decoder, allowed: ["type"], expectationType: wireType.rawValue)
            self = .elementsChanged
        case .elementUpdated:
            try Self.rejectUnknownKeys(from: decoder, allowed: ElementUpdatedKey.self, expectationType: wireType.rawValue)
            let container = try decoder.container(keyedBy: ElementUpdatedKey.self)
            let property = try Self.decodeElementPropertyIfPresent(in: container)
            self = .elementUpdated(
                heistId: try container.decodeIfPresent(HeistId.self, forKey: .heistId),
                property: property,
                oldValue: try container.decodeIfPresent(String.self, forKey: .oldValue),
                newValue: try container.decodeIfPresent(String.self, forKey: .newValue)
            )
        case .elementAppeared:
            try Self.rejectUnknownKeys(from: decoder, allowed: MatcherKey.self, expectationType: wireType.rawValue)
            let container = try decoder.container(keyedBy: MatcherKey.self)
            let matcher = try container.decode(ElementMatcher.self, forKey: .matcher)
            self = .elementAppeared(matcher)
        case .elementDisappeared:
            try Self.rejectUnknownKeys(from: decoder, allowed: MatcherKey.self, expectationType: wireType.rawValue)
            let container = try decoder.container(keyedBy: MatcherKey.self)
            let matcher = try container.decode(ElementMatcher.self, forKey: .matcher)
            self = .elementDisappeared(matcher)
        }
    }

    private static func decodeElementPropertyIfPresent(
        in container: KeyedDecodingContainer<ElementUpdatedKey>
    ) throws -> ElementProperty? {
        guard let propertyString = try container.decodeIfPresent(String.self, forKey: .property) else {
            return nil
        }
        guard let property = ElementProperty(rawValue: propertyString) else {
            throw DecodingError.dataCorruptedError(
                forKey: .property,
                in: container,
                debugDescription: "Unknown element property: \"\(propertyString)\". Valid: \(ElementProperty.allCases.map(\.rawValue).joined(separator: ", "))"
            )
        }
        return property
    }

    private static func rejectUnknownKeys<K>(
        from decoder: Decoder,
        allowed keyType: K.Type,
        expectationType: String
    ) throws where K: CodingKey & CaseIterable {
        try decoder.rejectUnknownKeys(
            allowed: keyType,
            typeName: "\(expectationType) expectation"
        )
    }

    private static func rejectUnknownKeys(
        from decoder: Decoder,
        allowed: Set<String>,
        expectationType: String
    ) throws {
        try decoder.rejectUnknownKeys(
            allowed: allowed,
            typeName: "\(expectationType) expectation"
        )
    }

    public func encode(to encoder: Encoder) throws {
        switch self {
        case .screenChanged:
            var container = encoder.container(keyedBy: DiscriminatorKey.self)
            try container.encode(WireType.screenChanged.rawValue, forKey: .type)
        case .elementsChanged:
            var container = encoder.container(keyedBy: DiscriminatorKey.self)
            try container.encode(WireType.elementsChanged.rawValue, forKey: .type)
        case .elementUpdated(let heistId, let property, let oldValue, let newValue):
            var container = encoder.container(keyedBy: ElementUpdatedKey.self)
            try container.encode(WireType.elementUpdated.rawValue, forKey: .type)
            try container.encodeIfPresent(heistId, forKey: .heistId)
            try container.encodeIfPresent(property, forKey: .property)
            try container.encodeIfPresent(oldValue, forKey: .oldValue)
            try container.encodeIfPresent(newValue, forKey: .newValue)
        case .elementAppeared(let matcher):
            var container = encoder.container(keyedBy: MatcherKey.self)
            try container.encode(WireType.elementAppeared.rawValue, forKey: .type)
            try container.encode(matcher, forKey: .matcher)
        case .elementDisappeared(let matcher):
            var container = encoder.container(keyedBy: MatcherKey.self)
            try container.encode(WireType.elementDisappeared.rawValue, forKey: .type)
            try container.encode(matcher, forKey: .matcher)
        }
    }
}

/// The outcome of checking an ActionExpectation against an ActionResult.
public struct ExpectationResult: Codable, Sendable, Equatable {
    /// Whether the expectation was met.
    public let met: Bool
    /// The expectation that was checked. Nil for implicit delivery check.
    public let expectation: ActionExpectation?
    /// What was actually observed (for diagnostics when `met` is false).
    public let actual: String?

    public init(met: Bool, expectation: ActionExpectation?, actual: String? = nil) {
        self.met = met
        self.expectation = expectation
        self.actual = actual
    }
}

extension ExpectationResult: CustomStringConvertible {
    public var description: String {
        ScoreDescription.call("expectation", [
            ScoreDescription.valueField("met", met),
            expectation.map { "expected=\($0)" },
            ScoreDescription.stringField("actual", actual),
        ].compactMap { $0 })
    }
}
