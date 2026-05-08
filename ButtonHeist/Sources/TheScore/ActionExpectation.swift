import Foundation

// MARK: - Action Expectations

/// The two string-form expectation tiers accepted on the wire.
/// Parsers translate the incoming string (`"screen_changed"` or
/// `"elements_changed"`) into the structured `ActionExpectation` enum without
/// comparing raw string literals deep in the stack.
public enum ExpectationTier: String, CaseIterable, Sendable {
    case screenChanged = "screen_changed"
    case elementsChanged = "elements_changed"

    /// The matching `ActionExpectation` case for this tier.
    public var expectation: ActionExpectation {
        switch self {
        case .screenChanged: return .screenChanged
        case .elementsChanged: return .elementsChanged
        }
    }
}

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
/// {"type": "compound", "expectations": [ ...ActionExpectation... ]}
/// ```
/// See `docs/WIRE-PROTOCOL.md` for the full shape.
public enum ActionExpectation: Sendable, Equatable {
    /// Expected a screen-level change (VC identity changed).
    case screenChanged
    /// Expected elements to be added, removed, updated, or the screen to change.
    case elementsChanged
    /// Expected a property change on an element. All fields are optional filters —
    /// provide what you know, omit what you don't. Met when any entry in
    /// `interfaceDelta.updated` matches all provided fields.
    case elementUpdated(
        heistId: String? = nil, property: ElementProperty? = nil,
        oldValue: String? = nil, newValue: String? = nil
    )
    /// Expected an element matching this predicate to appear in the delta's added list.
    case elementAppeared(ElementMatcher)
    /// Expected an element matching this predicate to disappear from the delta's removed list.
    /// Validation requires a pre-action element cache to resolve removed heistIds to matchers.
    case elementDisappeared(ElementMatcher)
    /// Compound: all sub-expectations must be met.
    case compound([ActionExpectation])

    /// Human-readable summary of this expectation, suitable for failure messages.
    public var summaryDescription: String {
        switch self {
        case .screenChanged:
            return "screen_changed"
        case .elementsChanged:
            return "elements_changed"
        case .elementUpdated(let heistId, let property, _, let newValue):
            var parts = ["element_updated"]
            if let heistId { parts.append(heistId) }
            if let property { parts.append(property.rawValue) }
            if let newValue { parts.append("→ \(newValue)") }
            return parts.joined(separator: " ")
        case .elementAppeared(let matcher):
            let target = matcher.label ?? matcher.identifier ?? "element"
            return "element_appeared(\(target))"
        case .elementDisappeared(let matcher):
            let target = matcher.label ?? matcher.identifier ?? "element"
            return "element_disappeared(\(target))"
        case .compound(let expectations):
            return "compound(\(expectations.count) expectations)"
        }
    }
}

// MARK: - ActionExpectation Codable

extension ActionExpectation: Codable {
    private enum DiscriminatorKey: String, CodingKey {
        case type
    }

    /// Discriminator strings for the `type` field on the wire. Kept distinct
    /// from `ExpectationTier` because `ExpectationTier` covers only the two
    /// string-literal short forms (`screen_changed`, `elements_changed`) for
    /// backwards compatibility with the inline-string arg shape.
    private enum WireType: String {
        case screenChanged = "screen_changed"
        case elementsChanged = "elements_changed"
        case elementUpdated = "element_updated"
        case elementAppeared = "element_appeared"
        case elementDisappeared = "element_disappeared"
        case compound
    }

    private enum ElementUpdatedKey: String, CodingKey {
        case type, heistId, property, oldValue, newValue
    }

    private enum MatcherKey: String, CodingKey {
        case type, matcher
    }

    private enum CompoundKey: String, CodingKey {
        case type, expectations
    }

    public init(from decoder: Decoder) throws {
        let typeContainer = try decoder.container(keyedBy: DiscriminatorKey.self)
        let typeString = try typeContainer.decode(String.self, forKey: .type)
        guard let wireType = WireType(rawValue: typeString) else {
            throw DecodingError.dataCorruptedError(
                forKey: .type, in: typeContainer,
                debugDescription: "Unknown ActionExpectation type: \"\(typeString)\""
            )
        }
        switch wireType {
        case .screenChanged:
            self = .screenChanged
        case .elementsChanged:
            self = .elementsChanged
        case .elementUpdated:
            let container = try decoder.container(keyedBy: ElementUpdatedKey.self)
            self = .elementUpdated(
                heistId: try container.decodeIfPresent(String.self, forKey: .heistId),
                property: try container.decodeIfPresent(ElementProperty.self, forKey: .property),
                oldValue: try container.decodeIfPresent(String.self, forKey: .oldValue),
                newValue: try container.decodeIfPresent(String.self, forKey: .newValue)
            )
        case .elementAppeared:
            let container = try decoder.container(keyedBy: MatcherKey.self)
            let matcher = try container.decode(ElementMatcher.self, forKey: .matcher)
            self = .elementAppeared(matcher)
        case .elementDisappeared:
            let container = try decoder.container(keyedBy: MatcherKey.self)
            let matcher = try container.decode(ElementMatcher.self, forKey: .matcher)
            self = .elementDisappeared(matcher)
        case .compound:
            let container = try decoder.container(keyedBy: CompoundKey.self)
            let expectations = try container.decode([ActionExpectation].self, forKey: .expectations)
            self = .compound(expectations)
        }
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
        case .compound(let expectations):
            var container = encoder.container(keyedBy: CompoundKey.self)
            try container.encode(WireType.compound.rawValue, forKey: .type)
            try container.encode(expectations, forKey: .expectations)
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

extension ActionExpectation {
    /// Check this expectation against an ActionResult.
    /// - Parameter preActionElements: Cached elements from before the action, keyed by heistId.
    ///   Required for `elementDisappeared` validation (resolves removed heistIds to matchers).
    ///   Pass an empty dictionary if unavailable.
    public func validate(
        against result: ActionResult,
        preActionElements: [String: HeistElement] = [:]
    ) -> ExpectationResult {
        switch self {
        case .screenChanged:
            let kindString = result.interfaceDelta?.kindRawValue ?? "noChange"
            return ExpectationResult(
                met: result.interfaceDelta?.isScreenChanged == true,
                expectation: self,
                actual: kindString
            )
        case .elementsChanged:
            // Superset rule: screen_changed implies elements_changed.
            let delta = result.interfaceDelta
            let kindString = delta?.kindRawValue ?? "noChange"
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
                actual: kindString
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

        case .compound(let expectations):
            var failures: [String] = []
            for expectation in expectations {
                let subResult = expectation.validate(
                    against: result, preActionElements: preActionElements
                )
                if !subResult.met {
                    failures.append("\(expectation.summaryDescription): \(subResult.actual ?? "failed")")
                }
            }
            if failures.isEmpty {
                return ExpectationResult(met: true, expectation: self, actual: nil)
            }
            return ExpectationResult(
                met: false, expectation: self,
                actual: failures.joined(separator: "; ")
            )
        }
    }

    private static func validateElementUpdated(
        heistId: String?, property: ElementProperty?,
        oldValue: String?, newValue: String?,
        expectation: ActionExpectation, result: ActionResult
    ) -> ExpectationResult {
        let updates = result.interfaceDelta?.elementEdits?.updated ?? []
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
        let delta = result.interfaceDelta

        // Normal path: check the added list from element-level diffs (or
        // post-screen-change post-edits).
        let added = delta?.elementEdits?.added ?? []
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
            if payload.newInterface.elements.contains(where: { $0.matches(matcher) }) {
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
        preActionElements: [String: HeistElement]
    ) -> ExpectationResult {
        let delta = result.interfaceDelta

        // Normal path: check the removed list from element-level diffs (or
        // post-screen-change post-edits).
        let removed = delta?.elementEdits?.removed ?? []
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
            let stillPresent = payload.newInterface.elements.contains { $0.matches(matcher) }
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
