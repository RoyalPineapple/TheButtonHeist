import ThePlans
import Foundation

// MARK: - Unified Evaluation

/// The single evaluation surface for every predicate kind. `state` matches the
/// current capture; `change` reads the baseline→current diff. This is the
/// engine a wait (predicate + deadline), an `expect` slot, and a future
/// search/while loop all share.
public extension AccessibilityPredicate {
    /// Evaluate against an observed interface and (for change predicates) a diff.
    /// - Parameters:
    ///   - currentElements: latest observed interface elements (used by `state`).
    ///   - delta: the baseline→current diff (used by `change`).
    func evaluate(
        currentElements: [HeistElement],
        delta: AccessibilityTrace.Delta? = nil
    ) -> ExpectationResult {
        switch self {
        case .state(let stateClause):
            let outcome = stateClause.evaluate(in: currentElements)
            return ExpectationResult(met: outcome.met, predicate: self, actual: outcome.actual)
        case .changePredicate(let change):
            return change.evaluate(delta: delta)
        case .noChangePredicate:
            let met = delta?.isNoChange == true
            return ExpectationResult(met: met, predicate: self, actual: met ? nil : delta?.kindDescription ?? "noTrace")
        }
    }

    /// Evaluate against an observed interface and cumulative wait-window change facts.
    func evaluate(
        currentElements: [HeistElement],
        accumulatedDelta: AccessibilityTrace.AccumulatedDelta?
    ) -> ExpectationResult {
        switch self {
        case .state(let stateClause):
            let outcome = stateClause.evaluate(in: currentElements)
            return ExpectationResult(met: outcome.met, predicate: self, actual: outcome.actual)
        case .changePredicate(let change):
            return change.evaluate(accumulatedDelta: accumulatedDelta)
        case .noChangePredicate:
            let met = accumulatedDelta?.isNoChange == true
            return ExpectationResult(met: met, predicate: self, actual: met ? nil : accumulatedDelta?.kindDescription ?? "noTrace")
        }
    }
}

// MARK: - ActionResult Validation

public extension AccessibilityPredicate {
    /// Check this predicate against an `ActionResult`.
    ///
    /// `state` evaluates against the result's final-capture interface;
    /// `change` evaluates against the result's endpoint delta. Change
    /// predicates read self-describing deltas such as property updates, so no
    /// pre-action element resolution is needed.
    func validate(against result: ActionResult) -> ExpectationResult {
        guard let trace = result.accessibilityTrace else {
            return ExpectationResult(
                met: false,
                predicate: self,
                actual: "no observed accessibility trace"
            )
        }
        return evaluate(
            currentElements: trace.endpointCurrentElements,
            delta: trace.endpointDelta
        )
    }
}

private extension AccessibilityTrace {
    /// Projected elements of the final capture — the post-action interface.
    var endpointCurrentElements: [HeistElement] {
        captures.last?.interface.projectedElements ?? []
    }
}

// MARK: - State Evaluation

public extension AccessibilityPredicate.State {
    /// Convenience boolean check against an observed interface.
    func evaluatePresence(in elements: [HeistElement]) -> Bool {
        evaluate(in: elements).met
    }

    /// Evaluate this state against a single observed interface. For `.all`,
    /// every child state must hold against the same `elements`.
    func evaluate(in elements: [HeistElement]) -> (met: Bool, actual: String?) {
        switch contract {
        case .element(let requirement, let predicate):
            let isPresent = predicate.anyMatch(in: elements)
            let met = requirement.isMet(isPresent: isPresent)
            return (met, met ? nil : requirement.failureDescription(for: predicate))
        case .target(let requirement, let target):
            let isPresent = target.isPresent(in: elements)
            let met = requirement.isMet(isPresent: isPresent)
            return (met, met ? nil : requirement.failureDescription(for: target))
        case .all(let states):
            guard !states.isEmpty else {
                return (false, AccessibilityPredicateContract.Violation.emptyStateAll.evaluationDescription)
            }
            let failures = states.compactMap { state -> String? in
                let outcome = state.evaluate(in: elements)
                return outcome.met ? nil : (outcome.actual ?? state.description)
            }
            return (failures.isEmpty, failures.isEmpty ? nil : failures.joined(separator: "; "))
        }
    }
}

private extension ElementTarget {
    func isPresent(in elements: [HeistElement]) -> Bool {
        switch self {
        case .predicate(let predicate, let ordinal):
            let matches = elements.filter { predicate.matches($0) }
            guard let ordinal else { return !matches.isEmpty }
            return matches.indices.contains(ordinal)
        }
    }
}

// MARK: - Change Evaluation

public extension AccessibilityPredicate.Change {
    func evaluate(
        delta: AccessibilityTrace.Delta?
    ) -> ExpectationResult {
        evaluate(delta: delta, placement: .predicateRoot)
    }

    func evaluate(
        accumulatedDelta: AccessibilityTrace.AccumulatedDelta?
    ) -> ExpectationResult {
        evaluate(accumulatedDelta: accumulatedDelta, placement: .predicateRoot)
    }

    private func evaluate(
        delta: AccessibilityTrace.Delta?,
        placement: AccessibilityPredicateContract.ChangePlacement
    ) -> ExpectationResult {
        if let violation = contract.violation(in: placement) {
            return ExpectationResult(met: false, predicate: .change(self), actual: violation.evaluationDescription)
        }
        let result: ExpectationResult
        switch contract {
        case .any:
            result = ExpectationResult(
                met: delta?.isSemanticChange == true,
                predicate: nil,
                actual: delta?.kindDescription ?? "noTrace"
            )
        case .screen(let assertions):
            result = Self.evaluateScreen(assertions: assertions, delta: delta)
        case .elements(let assertions):
            result = Self.evaluateElements(assertions: assertions, delta: delta)
        case .all(let changes):
            let results = changes.map { $0.evaluate(delta: delta, placement: .scope) }
            let failures = results.compactMap { $0.met ? nil : ($0.actual ?? $0.predicate?.description) }
            result = ExpectationResult(met: failures.isEmpty, predicate: nil, actual: failures.isEmpty ? nil : failures.joined(separator: "; "))
        }
        return ExpectationResult(met: result.met, predicate: .change(self), actual: result.actual)
    }

    private func evaluate(
        accumulatedDelta: AccessibilityTrace.AccumulatedDelta?,
        placement: AccessibilityPredicateContract.ChangePlacement
    ) -> ExpectationResult {
        if let violation = contract.violation(in: placement) {
            return ExpectationResult(met: false, predicate: .change(self), actual: violation.evaluationDescription)
        }
        let result: ExpectationResult
        switch contract {
        case .any:
            result = ExpectationResult(
                met: accumulatedDelta?.isSemanticChange == true,
                predicate: nil,
                actual: accumulatedDelta?.kindDescription ?? "noTrace"
            )
        case .screen(let assertions):
            result = Self.evaluateScreen(assertions: assertions, accumulatedDelta: accumulatedDelta)
        case .elements(let assertions):
            result = Self.evaluateElements(assertions: assertions, accumulatedDelta: accumulatedDelta)
        case .all(let changes):
            let results = changes.map { $0.evaluate(accumulatedDelta: accumulatedDelta, placement: .scope) }
            let failures = results.compactMap { $0.met ? nil : ($0.actual ?? $0.predicate?.description) }
            result = ExpectationResult(met: failures.isEmpty, predicate: nil, actual: failures.isEmpty ? nil : failures.joined(separator: "; "))
        }
        return ExpectationResult(met: result.met, predicate: .change(self), actual: result.actual)
    }

    private static func evaluateScreen(
        assertions: [AccessibilityPredicate.State],
        delta: AccessibilityTrace.Delta?
    ) -> ExpectationResult {
        guard case .screenChanged(let payload)? = delta else {
            return ExpectationResult(met: false, predicate: nil, actual: delta?.kindDescription ?? "noTrace")
        }
        guard !assertions.isEmpty else {
            return ExpectationResult(met: true, predicate: nil, actual: AccessibilityTrace.DeltaKind.screenChanged.rawValue)
        }
        let stateClause: AccessibilityPredicate.State = assertions.count == 1 ? assertions[0] : .all(assertions)
        let outcome = stateClause.evaluate(in: payload.newInterface.projectedElements)
        return ExpectationResult(
            met: outcome.met,
            predicate: nil,
            actual: outcome.met ? nil : "screen changed but new interface failed: \(outcome.actual ?? stateClause.description)"
        )
    }

    private static func evaluateScreen(
        assertions: [AccessibilityPredicate.State],
        accumulatedDelta: AccessibilityTrace.AccumulatedDelta?
    ) -> ExpectationResult {
        guard let payload = accumulatedDelta?.screenChanged else {
            return ExpectationResult(met: false, predicate: nil, actual: accumulatedDelta?.kindDescription ?? "noTrace")
        }
        guard !assertions.isEmpty else {
            return ExpectationResult(met: true, predicate: nil, actual: AccessibilityTrace.DeltaKind.screenChanged.rawValue)
        }
        let stateClause: AccessibilityPredicate.State = assertions.count == 1 ? assertions[0] : .all(assertions)
        let outcome = stateClause.evaluate(in: payload.newInterface.projectedElements)
        return ExpectationResult(
            met: outcome.met,
            predicate: nil,
            actual: outcome.met ? nil : "screen changed but new interface failed: \(outcome.actual ?? stateClause.description)"
        )
    }

    private static func evaluateElements(
        assertions: [ElementDeltaPredicate],
        delta: AccessibilityTrace.Delta?
    ) -> ExpectationResult {
        guard case .elementsChanged(let payload)? = delta else {
            return ExpectationResult(met: false, predicate: nil, actual: delta?.kindDescription ?? "noTrace")
        }
        guard !assertions.isEmpty else {
            return ExpectationResult(met: true, predicate: nil, actual: AccessibilityTrace.DeltaKind.elementsChanged.rawValue)
        }
        let failures = assertions.compactMap { assertion -> String? in
            let result = evaluateElementDelta(assertion, edits: payload.edits)
            return result.met ? nil : (result.actual ?? assertion.description)
        }
        return ExpectationResult(met: failures.isEmpty, predicate: nil, actual: failures.isEmpty ? nil : failures.joined(separator: "; "))
    }

    private static func evaluateElements(
        assertions: [ElementDeltaPredicate],
        accumulatedDelta: AccessibilityTrace.AccumulatedDelta?
    ) -> ExpectationResult {
        guard let payload = accumulatedDelta?.elementsChanged else {
            return ExpectationResult(met: false, predicate: nil, actual: accumulatedDelta?.kindDescription ?? "noTrace")
        }
        guard !assertions.isEmpty else {
            return ExpectationResult(met: true, predicate: nil, actual: AccessibilityTrace.DeltaKind.elementsChanged.rawValue)
        }
        let failures = assertions.compactMap { assertion -> String? in
            let result = evaluateElementDelta(assertion, edits: payload.edits)
            return result.met ? nil : (result.actual ?? assertion.description)
        }
        return ExpectationResult(met: failures.isEmpty, predicate: nil, actual: failures.isEmpty ? nil : failures.joined(separator: "; "))
    }

    private static func evaluateElementDelta(
        _ predicate: ElementDeltaPredicate,
        edits: ElementEdits
    ) -> ExpectationResult {
        switch predicate {
        case .appearedElement(let element):
            let met = edits.added.contains { element.matches($0) }
            return ExpectationResult(met: met, predicate: nil, actual: met ? nil : "no appeared element matches \(element)")
        case .disappearedElement(let element):
            let met = edits.removed.contains { element.matches($0) }
            return ExpectationResult(met: met, predicate: nil, actual: met ? nil : "no disappeared element matches \(element)")
        case .updatedElement(let update):
            return evaluateUpdated(update: update, edits: edits)
        }
    }

    private static func evaluateUpdated(
        update: ElementUpdatePredicate,
        delta: AccessibilityTrace.Delta?
    ) -> ExpectationResult {
        evaluateUpdated(update: update, edits: delta?.elementEdits ?? ElementEdits())
    }

    private static func evaluateUpdated(
        update: ElementUpdatePredicate,
        edits: ElementEdits
    ) -> ExpectationResult {
        let updates = edits.updated
        guard !updates.isEmpty else {
            return ExpectationResult(met: false, predicate: nil, actual: "no element updates")
        }
        for edit in updates {
            if let element = update.element {
                guard element.matches(edit.before) || element.matches(edit.after) else { continue }
            }
            var targetChanges = edit.changes
            if let change = update.change {
                targetChanges = targetChanges.filter { propertyChange($0, matches: change) }
                guard !targetChanges.isEmpty else { continue }
            }
            return ExpectationResult(
                met: true,
                predicate: nil,
                actual: Self.describeUpdate(edit, changes: targetChanges)
            )
        }
        let observed = updates.map { edit in
            Self.describeUpdate(edit, changes: edit.changes)
        }.joined(separator: "; ")
        return ExpectationResult(met: false, predicate: nil, actual: observed)
    }

    private static func propertyChange(
        _ propertyChange: PropertyChange,
        matches change: AnyPropertyChange
    ) -> Bool {
        guard propertyChange.property == change.property else { return false }
        switch change {
        case .value(let change):
            return stringPropertyChange(propertyChange, matches: change)
        case .traits(let change):
            return traitPropertyChange(propertyChange, matches: change)
        case .hint(let change):
            return stringPropertyChange(propertyChange, matches: change)
        case .actions(let change):
            return stringPropertyChange(propertyChange, matches: change)
        case .frame(let change):
            return stringPropertyChange(propertyChange, matches: change)
        case .activationPoint(let change):
            return stringPropertyChange(propertyChange, matches: change)
        case .customContent(let change):
            return stringPropertyChange(propertyChange, matches: change)
        case .rotors(let change):
            return stringPropertyChange(propertyChange, matches: change)
        }
    }

    private static func stringPropertyChange<P: ElementPropertyKind>(
        _ propertyChange: PropertyChange,
        matches change: ElementPropertyChange<P>
    ) -> Bool where P.Checker == StringMatch<String> {
        if let before = change.before {
            guard before.matchesPropertyValue(propertyChange.oldValue) else { return false }
        }
        if let after = change.after {
            guard after.matchesPropertyValue(propertyChange.newValue) else { return false }
        }
        return true
    }

    private static func traitPropertyChange(
        _ propertyChange: PropertyChange,
        matches change: ElementPropertyChange<TraitsProperty>
    ) -> Bool {
        if let before = change.before {
            guard before.matchesTraitPropertyValue(propertyChange.oldValue) else { return false }
        }
        if let after = change.after {
            guard after.matchesTraitPropertyValue(propertyChange.newValue) else { return false }
        }
        return true
    }

    private static func describeUpdate(_ edit: ElementUpdate, changes: [PropertyChange]) -> String {
        let properties = changes.map { "\($0.property.rawValue): \($0.displayTransition)" }
        let name = edit.after.label ?? edit.before.label ?? edit.after.description
        return "\(name): \(properties.joined(separator: ", "))"
    }
}

private extension StringMatch where Value == String {
    func matchesPropertyValue(_ candidate: ElementPropertyValue?) -> Bool {
        guard let candidate = candidate?.stringMatchText else { return false }
        switch self {
        case .exact(let pattern):
            return ElementPredicate.stringEquals(candidate, pattern)
        case .contains(let pattern):
            guard !pattern.isEmpty else { return false }
            return ElementPredicate.stringContains(candidate, pattern)
        case .prefix(let pattern):
            guard !pattern.isEmpty else { return false }
            return ElementPredicate.stringHasPrefix(candidate, pattern)
        case .suffix(let pattern):
            guard !pattern.isEmpty else { return false }
            return ElementPredicate.stringHasSuffix(candidate, pattern)
        }
    }
}

private extension TraitSetMatch {
    func matchesTraitPropertyValue(_ value: ElementPropertyValue?) -> Bool {
        guard let traits = value?.traitSet else { return false }
        return include.allSatisfy { traits.contains($0) }
            && exclude.allSatisfy { !traits.contains($0) }
    }
}

// MARK: - Delta Facts

private extension AccessibilityTrace.Delta {
    var kindDescription: String {
        switch self {
        case .noChange: return AccessibilityTrace.DeltaKind.noChange.rawValue
        case .elementsChanged: return AccessibilityTrace.DeltaKind.elementsChanged.rawValue
        case .screenChanged: return AccessibilityTrace.DeltaKind.screenChanged.rawValue
        }
    }

    var satisfiesElementsChanged: Bool {
        switch self {
        case .noChange: return false
        case .elementsChanged: return true
        case .screenChanged: return false
        }
    }

    var isNoChange: Bool {
        if case .noChange = self { return true }
        return false
    }

    var isSemanticChange: Bool {
        !isNoChange
    }

    var elementEdits: ElementEdits {
        if case .elementsChanged(let payload) = self { return payload.edits }
        return ElementEdits()
    }
}
