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
public enum ActionExpectation: Codable, Sendable, Equatable {
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
            let kind = result.interfaceDelta?.kind
            return ExpectationResult(
                met: kind == .screenChanged,
                expectation: self,
                actual: kind?.rawValue ?? "noChange"
            )
        case .elementsChanged:
            // Superset rule: screen_changed implies elements_changed.
            let kind = result.interfaceDelta?.kind
            let met = kind == .elementsChanged || kind == .screenChanged
            return ExpectationResult(
                met: met,
                expectation: self,
                actual: kind?.rawValue ?? "noChange"
            )
        case .elementUpdated(let heistId, let property, let oldValue, let newValue):
            return Self.validateElementUpdated(
                heistId: heistId, property: property,
                oldValue: oldValue, newValue: newValue,
                expectation: self, result: result
            )

        case .elementAppeared(let matcher):
            let delta = result.interfaceDelta

            // Normal path: check the added list from element-level diffs.
            if let added = delta?.added, !added.isEmpty {
                if added.contains(where: { $0.matches(matcher) }) {
                    return ExpectationResult(met: true, expectation: self, actual: nil)
                }
                let labels = added.compactMap(\.label).prefix(5).joined(separator: ", ")
                return ExpectationResult(
                    met: false, expectation: self,
                    actual: "added: [\(labels)]"
                )
            }

            // Screen-change path: the entire interface is new, so every element
            // on the new screen effectively "appeared". Check newInterface.
            if delta?.kind == .screenChanged,
               let elements = delta?.newInterface?.elements,
               elements.contains(where: { $0.matches(matcher) }) {
                return ExpectationResult(met: true, expectation: self, actual: nil)
            }

            return ExpectationResult(
                met: false, expectation: self,
                actual: delta?.kind == .screenChanged
                    ? "screen changed but element not found in new interface"
                    : "no elements added"
            )

        case .elementDisappeared(let matcher):
            let delta = result.interfaceDelta

            // Normal path: check the removed list from element-level diffs.
            if let removed = delta?.removed, !removed.isEmpty {
                let matched = removed.contains { heistId in
                    guard let element = preActionElements[heistId] else { return false }
                    return element.matches(matcher)
                }
                if matched {
                    return ExpectationResult(met: true, expectation: self, actual: nil)
                }
                let removedIds = removed.prefix(5).joined(separator: ", ")
                return ExpectationResult(
                    met: false, expectation: self,
                    actual: "removed: [\(removedIds)]"
                )
            }

            // Screen-change path: the entire old screen is gone. Check if a
            // matching element existed before and is absent from the new interface.
            if delta?.kind == .screenChanged {
                let matchedBefore = preActionElements.values.contains { $0.matches(matcher) }
                let stillPresent = delta?.newInterface?.elements.contains { $0.matches(matcher) } ?? false
                if matchedBefore, !stillPresent {
                    return ExpectationResult(met: true, expectation: self, actual: nil)
                }
                return ExpectationResult(
                    met: false, expectation: self,
                    actual: matchedBefore
                        ? "screen changed but element still present in new interface"
                        : "screen changed but element was not in pre-action state"
                )
            }

            return ExpectationResult(met: false, expectation: self, actual: "no elements removed")

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
        guard let updates = result.interfaceDelta?.updated, !updates.isEmpty else {
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

    /// Baseline delivery check — always run for every action.
    public static func validateDelivery(_ result: ActionResult) -> ExpectationResult {
        ExpectationResult(
            met: result.success,
            expectation: nil,
            actual: result.success ? "delivered" : (result.message ?? "failed")
        )
    }
}
