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
        evaluate(currentMatches: ElementMatchSet(elements: currentElements), delta: delta)
    }

    /// Evaluate against an observed interface and cumulative wait-window change facts.
    func evaluate(
        currentElements: [HeistElement],
        accumulatedDelta: AccessibilityTrace.AccumulatedDelta?
    ) -> ExpectationResult {
        evaluate(currentMatches: ElementMatchSet(elements: currentElements), accumulatedDelta: accumulatedDelta)
    }
}

private extension AccessibilityPredicate {
    func evaluate(
        currentMatches: ElementMatchSet,
        delta: AccessibilityTrace.Delta?
    ) -> ExpectationResult {
        switch self {
        case .state(let stateClause):
            return stateClause.evaluate(in: currentMatches).expectation(for: self)
        case .changePredicate(let change):
            return change.evaluate(delta: delta)
        case .noChangePredicate:
            let met = delta?.isNoChange == true
            return ExpectationResult(met: met, predicate: self, actual: met ? nil : delta?.kindDescription ?? "noTrace")
        }
    }

    func evaluate(
        currentMatches: ElementMatchSet,
        accumulatedDelta: AccessibilityTrace.AccumulatedDelta?
    ) -> ExpectationResult {
        switch self {
        case .state(let stateClause):
            return stateClause.evaluate(in: currentMatches).expectation(for: self)
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
        let currentMatches = trace.captures.last
            .map { ElementMatchSet(interface: $0.interface) }
            ?? .empty
        return evaluate(currentMatches: currentMatches, delta: trace.endpointDelta)
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
    func evaluate(in elements: [HeistElement]) -> PredicateEvaluationResult {
        evaluate(in: ElementMatchSet(elements: elements))
    }
}

extension AccessibilityPredicate.State {
    /// Evaluate this state against a path-keyed interface projection. Element
    /// predicates resolve to typed match sets; target ordinals select from the
    /// narrowed set in traversal order.
    func evaluate(in matches: ElementMatchSet) -> PredicateEvaluationResult {
        switch contract {
        case .element(let requirement, let predicate):
            let isPresent = !matches.matching(predicate).isEmpty
            let met = requirement.isMet(isPresent: isPresent)
            return PredicateEvaluationResult(
                met: met,
                actual: met ? nil : requirement.failureDescription(for: predicate)
            )
        case .target(let requirement, let target):
            let isPresent = !matches.matching(target).isEmpty
            let met = requirement.isMet(isPresent: isPresent)
            return PredicateEvaluationResult(
                met: met,
                actual: met ? nil : requirement.failureDescription(for: target)
            )
        case .all(let states):
            guard !states.isEmpty else {
                return PredicateEvaluationResult(
                    met: false,
                    actual: AccessibilityPredicateContract.Violation.emptyStateAll.evaluationDescription
                )
            }
            let failures = states.compactMap { state -> String? in
                let outcome = state.evaluate(in: matches)
                return outcome.met ? nil : (outcome.actual ?? state.description)
            }
            return PredicateEvaluationResult(
                met: failures.isEmpty,
                actual: failures.isEmpty ? nil : failures.joined(separator: "; ")
            )
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
        let outcome = stateClause.evaluate(in: ElementMatchSet(interface: payload.newInterface))
        return PredicateEvaluationResult(
            met: outcome.met,
            actual: outcome.met ? nil : "screen changed but new interface failed: \(outcome.actual ?? stateClause.description)"
        ).expectation(for: nil)
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
        let outcome = stateClause.evaluate(in: ElementMatchSet(interface: payload.newInterface))
        return PredicateEvaluationResult(
            met: outcome.met,
            actual: outcome.met ? nil : "screen changed but new interface failed: \(outcome.actual ?? stateClause.description)"
        ).expectation(for: nil)
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
            let met = !ElementMatchSet(elements: edits.added).matching(element).isEmpty
            return ExpectationResult(met: met, predicate: nil, actual: met ? nil : "no appeared element matches \(element)")
        case .disappearedElement(let element):
            let met = !ElementMatchSet(elements: edits.removed).matching(element).isEmpty
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
        _ observed: PropertyChange,
        matches change: AnyPropertyChange
    ) -> Bool {
        observed.satisfies(change)
    }

    private static func describeUpdate(_ edit: ElementUpdate, changes: [PropertyChange]) -> String {
        let properties = changes.map { "\($0.property.rawValue): \($0.displayTransition)" }
        let name = edit.after.label ?? edit.before.label ?? edit.after.description
        return "\(name): \(properties.joined(separator: ", "))"
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
