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

extension ActionExpectation {
    /// Check this expectation against an ActionResult.
    /// - Parameter preActionElements: Elements from the pre-action capture, keyed by heistId.
    ///   Required for `elementDisappeared` validation (resolves removed heistIds to matchers).
    ///   Pass an empty dictionary if unavailable.
    public func validate(
        against result: ActionResult,
        preActionElements: [HeistId: HeistElement] = [:]
    ) -> ExpectationResult {
        switch self {
        case .screenChanged:
            let delta = result.accessibilityTrace?.endpointDeltaProjection
            return ExpectationResult(
                met: delta?.isScreenChangeProjection == true,
                expectation: self,
                actual: delta?.kindDescription ?? "noTrace"
            )
        case .elementsChanged:
            // Superset rule: screen_changed implies elements_changed.
            let delta = result.accessibilityTrace?.endpointDeltaProjection
            let met: Bool = {
                guard let delta else { return false }
                switch delta {
                case .noChange: return false
                case .elementsChanged, .screenChanged: return true
                }
            }()
            return ExpectationResult(
                met: met,
                expectation: self,
                actual: delta?.kindDescription ?? "noTrace"
            )
        case .elementUpdated(let heistId, let property, let oldValue, let newValue):
            return Self.validateElementUpdated(
                heistId: heistId, property: property,
                oldValue: oldValue, newValue: newValue,
                expectation: self, result: result
            )

        case .elementAppeared(let matcher):
            return Self.validateElementAppeared(matcher: matcher, expectation: self, result: result)

        case .elementDisappeared(let matcher):
            return Self.validateElementDisappeared(
                matcher: matcher, expectation: self, result: result,
                preActionElements: preActionElements
            )

        }
    }

    private static func validateElementUpdated(
        heistId: HeistId?, property: ElementProperty?,
        oldValue: String?, newValue: String?,
        expectation: ActionExpectation, result: ActionResult
    ) -> ExpectationResult {
        let updates = result.accessibilityTrace?.endpointDeltaProjection?.elementEditsProjection.updated ?? []
        guard !updates.isEmpty else {
            return ExpectationResult(met: false, expectation: expectation, actual: "no element updates")
        }
        let match = updates.contains { update in
            if let heistId, update.heistId != heistId { return false }
            let targetChanges: [PropertyChange]
            if let property {
                targetChanges = update.changes.filter { $0.property == property }
                if targetChanges.isEmpty { return false }
            } else {
                targetChanges = update.changes
            }
            if oldValue != nil || newValue != nil {
                guard targetChanges.contains(where: { change in
                    if let oldValue, change.old != oldValue { return false }
                    if let newValue, change.new != newValue { return false }
                    return true
                }) else { return false }
            }
            return true
        }
        if match {
            return ExpectationResult(met: true, expectation: expectation, actual: nil)
        }
        let observed = updates.map { update in
            let props = update.changes.map { "\($0.property.rawValue): \($0.old ?? "nil") → \($0.new ?? "nil")" }
            return "\(update.heistId): \(props.joined(separator: ", "))"
        }.joined(separator: "; ")
        return ExpectationResult(met: false, expectation: expectation, actual: observed)
    }

    private static func validateElementAppeared(
        matcher: ElementMatcher, expectation: ActionExpectation, result: ActionResult
    ) -> ExpectationResult {
        let delta = result.accessibilityTrace?.endpointDeltaProjection

        // Normal path: check the added list from element-level diffs.
        let added = delta?.elementEditsProjection.added ?? []
        if !added.isEmpty {
            if added.contains(where: { $0.matches(matcher) }) {
                return ExpectationResult(met: true, expectation: expectation, actual: nil)
            }
            let labels = added.compactMap(\.label).prefix(5).joined(separator: ", ")
            return ExpectationResult(
                met: false, expectation: expectation,
                actual: "added: [\(labels)]"
            )
        }

        // Screen-change path: the entire interface is new, so every element
        // on the new screen effectively "appeared". Check newInterface.
        if case .screenChanged(let payload)? = delta {
            if payload.newInterface.projectedElements.contains(where: { $0.matches(matcher) }) {
                return ExpectationResult(met: true, expectation: expectation, actual: nil)
            }
            return ExpectationResult(
                met: false, expectation: expectation,
                actual: "screen changed but element not found in new interface"
            )
        }

        return ExpectationResult(
            met: false, expectation: expectation,
            actual: "no elements added"
        )
    }

    private static func validateElementDisappeared(
        matcher: ElementMatcher,
        expectation: ActionExpectation,
        result: ActionResult,
        preActionElements: [HeistId: HeistElement]
    ) -> ExpectationResult {
        let delta = result.accessibilityTrace?.endpointDeltaProjection

        // Normal path: check the removed list from element-level diffs.
        let removed = delta?.elementEditsProjection.removed ?? []
        if !removed.isEmpty {
            let matched = removed.contains { heistId in
                guard let element = preActionElements[heistId] else { return false }
                return element.matches(matcher)
            }
            if matched {
                return ExpectationResult(met: true, expectation: expectation, actual: nil)
            }
            let removedIds = removed.prefix(5).joined(separator: ", ")
            return ExpectationResult(
                met: false, expectation: expectation,
                actual: "removed: [\(removedIds)]"
            )
        }

        // Screen-change path: the entire old screen is gone. Check if a
        // matching element existed before and is absent from the new interface.
        if case .screenChanged(let payload)? = delta {
            let matchedBefore = preActionElements.values.contains { $0.matches(matcher) }
            let stillPresent = payload.newInterface.projectedElements.contains { $0.matches(matcher) }
            if matchedBefore, !stillPresent {
                return ExpectationResult(met: true, expectation: expectation, actual: nil)
            }
            return ExpectationResult(
                met: false, expectation: expectation,
                actual: matchedBefore
                    ? "screen changed but element still present in new interface"
                    : "screen changed but element was not in pre-action state"
            )
        }

        return ExpectationResult(met: false, expectation: expectation, actual: "no elements removed")
    }

    /// Baseline delivery check — always run for every action.
    public static func validateDelivery(_ result: ActionResult) -> ExpectationResult {
        ExpectationResult(
            met: result.success,
            expectation: nil,
            actual: result.success ? "delivered" : (result.message ?? "failed")
        )
    }
}

private extension AccessibilityTrace.Delta {
    var kindDescription: String {
        switch self {
        case .noChange: return AccessibilityTrace.DeltaKind.noChange.rawValue
        case .elementsChanged: return AccessibilityTrace.DeltaKind.elementsChanged.rawValue
        case .screenChanged: return AccessibilityTrace.DeltaKind.screenChanged.rawValue
        }
    }

    var isScreenChangeProjection: Bool {
        if case .screenChanged = self { return true }
        return false
    }

    var elementEditsProjection: ElementEdits {
        if case .elementsChanged(let payload) = self { return payload.edits }
        return ElementEdits()
    }
}
