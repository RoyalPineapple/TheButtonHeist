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
        evaluate(
            currentGraph: ElementMatchGraph(elements: currentElements),
            changeEvidence: ChangeEvaluationEvidence(delta: delta)
        )
    }

    /// Evaluate against an observed interface and cumulative wait-window change facts.
    func evaluate(
        currentElements: [HeistElement],
        accumulatedDelta: AccessibilityTrace.AccumulatedDelta?
    ) -> ExpectationResult {
        evaluate(
            currentGraph: ElementMatchGraph(elements: currentElements),
            changeEvidence: ChangeEvaluationEvidence(accumulatedDelta: accumulatedDelta)
        )
    }

    /// Evaluate against trace-derived predicate evidence. This is the preferred
    /// surface for action results because change predicates need the whole
    /// transition window, not only the first-to-last endpoint projection.
    func evaluate(in evidence: PredicateEvaluationEvidence) -> ExpectationResult {
        let accumulatedDelta = deltaProjection == .geometryAware
            ? evidence.geometryAccumulatedDelta ?? evidence.accumulatedDelta
            : evidence.accumulatedDelta
        return evaluate(
            currentGraph: ElementMatchGraph(elements: evidence.currentElements),
            changeEvidence: ChangeEvaluationEvidence(accumulatedDelta: accumulatedDelta)
        )
    }
}

package extension AccessibilityPredicate {
    var deltaProjection: AccessibilityTrace.DeltaProjection {
        requestsGeometryChangeEvidence ? .geometryAware : .semantic
    }

    var requestsGeometryChangeEvidence: Bool {
        switch self {
        case .state, .noChangePredicate, .announcement:
            return false
        case .changePredicate(let change):
            return change.requestsGeometryChangeEvidence
        }
    }
}

private extension AccessibilityPredicate.Change {
    var requestsGeometryChangeEvidence: Bool {
        switch contract {
        case .any, .screen:
            return false
        case .elements(let assertions):
            return assertions.contains(where: \.requestsGeometryChangeEvidence)
        case .all(let scopes):
            return scopes.elements.contains(where: \.requestsGeometryChangeEvidence)
        }
    }
}

private extension AccessibilityPredicate.ChangeScope {
    var requestsGeometryChangeEvidence: Bool {
        switch contract {
        case .screen:
            return false
        case .elements(let assertions):
            return assertions.contains(where: \.requestsGeometryChangeEvidence)
        case .all(let scopes):
            return scopes.elements.contains(where: \.requestsGeometryChangeEvidence)
        }
    }
}

private extension ElementDeltaPredicate {
    var requestsGeometryChangeEvidence: Bool {
        guard case .updatedElement(let update) = self else { return false }
        return update.change?.property.isGeometry == true
    }
}

private extension AccessibilityPredicate {
    func evaluate(
        currentGraph: ElementMatchGraph,
        changeEvidence: ChangeEvaluationEvidence
    ) -> ExpectationResult {
        switch self {
        case .state(let stateClause):
            return stateClause.evaluate(in: currentGraph).expectation(for: self)
        case .changePredicate(let change):
            return change.evaluate(changeEvidence: changeEvidence)
        case .noChangePredicate:
            let met = changeEvidence.isNoChange
            return ExpectationResult(met: met, predicate: self, actual: met ? nil : changeEvidence.kindDescription)
        case .announcement:
            return ExpectationResult(
                met: false,
                predicate: self,
                actual: "announcement predicates require spoken accessibility text evidence"
            )
        }
    }
}

// MARK: - ActionResult Validation

public extension AccessibilityPredicate {
    /// Check this predicate against an `ActionResult`.
    ///
    /// `state` evaluates against the result's final-capture interface;
    /// `change` evaluates against the full accumulated transition window.
    func validate(against result: ActionResult) -> ExpectationResult {
        guard let trace = result.accessibilityTrace else {
            return ExpectationResult(
                met: false,
                predicate: self,
                actual: "no observed accessibility trace"
            )
        }
        return evaluate(in: PredicateEvaluationEvidence(trace: trace))
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
        evaluate(in: ElementMatchGraph(elements: elements))
    }
}

package extension AccessibilityPredicate.State {
    /// Evaluate this state against a path-keyed interface projection. Element
    /// predicates resolve to typed match sets; target ordinals select from the
    /// narrowed set in traversal order.
    func evaluate(in graph: ElementMatchGraph) -> PredicateEvaluationResult {
        switch contract {
        case .element(let requirement, let predicate):
            let isPresent = !graph.resolve(predicate).isEmpty
            let met = requirement.isMet(isPresent: isPresent)
            return PredicateEvaluationResult(
                met: met,
                actual: met ? nil : requirement.failureDescription(for: predicate)
            )
        case .target(let requirement, let target):
            let isPresent = !graph.resolve(target).isEmpty
            let met = requirement.isMet(isPresent: isPresent)
            return PredicateEvaluationResult(
                met: met,
                actual: met ? nil : requirement.failureDescription(for: target)
            )
        case .screen(let identity):
            let elements = graph.all.elements
            let screenId = InterfaceSummary.screenId(forProjectedElements: elements)
            let header = InterfaceSummary.screenTitle(forProjectedElements: elements)
            let met = identity.matches(screenId: screenId, header: header)
            return PredicateEvaluationResult(
                met: met,
                actual: met ? nil : identity.failureDescription(screenId: screenId, header: header)
            )
        case .all(let states):
            let failures = states.compactMap { state -> String? in
                let outcome = state.evaluate(in: graph)
                return outcome.met ? nil : (outcome.actual ?? state.description)
            }
            return PredicateEvaluationResult(
                met: failures.isEmpty,
                actual: failures.isEmpty ? nil : failures.joined(separator: "; ")
            )
        }
    }
}

private extension ScreenIdentityPredicate {
    func failureDescription(screenId: String?, header: String?) -> String {
        let current = [
            screenId.map { "id=\(ScoreDescription.quoted($0))" },
            header.map { "header=\(ScoreDescription.quoted($0))" },
        ].compactMap { $0 }

        guard !current.isEmpty else {
            return "current screen has no accessibility identity; expected \(description)"
        }

        return "current screen \(current.joined(separator: ", ")) does not match \(description)"
    }
}

// MARK: - Change Evaluation

public extension AccessibilityPredicate.Change {
    func evaluate(
        delta: AccessibilityTrace.Delta?
    ) -> ExpectationResult {
        evaluate(changeEvidence: ChangeEvaluationEvidence(delta: delta))
    }

    func evaluate(
        accumulatedDelta: AccessibilityTrace.AccumulatedDelta?
    ) -> ExpectationResult {
        evaluate(changeEvidence: ChangeEvaluationEvidence(accumulatedDelta: accumulatedDelta))
    }
}

fileprivate extension AccessibilityPredicate.Change {
    func evaluate(
        changeEvidence: ChangeEvaluationEvidence
    ) -> ExpectationResult {
        let result: ExpectationResult
        switch contract {
        case .any:
            result = ExpectationResult(
                met: changeEvidence.isSemanticChange,
                predicate: nil,
                actual: changeEvidence.kindDescription
            )
        case .screen(let assertions):
            result = Self.evaluateScreen(assertions: assertions, changeEvidence: changeEvidence)
        case .elements(let assertions):
            result = Self.evaluateElements(assertions: assertions, changeEvidence: changeEvidence)
        case .all(let changes):
            let results = changes.map { $0.evaluate(changeEvidence: changeEvidence) }
            let failures = results.compactMap { $0.met ? nil : ($0.actual ?? $0.predicate?.description) }
            result = ExpectationResult(met: failures.isEmpty, predicate: nil, actual: failures.isEmpty ? nil : failures.joined(separator: "; "))
        }
        return ExpectationResult(met: result.met, predicate: .changePredicate(self), actual: result.actual)
    }

    static func evaluateScreen(
        assertions: [AccessibilityPredicate.State],
        changeEvidence: ChangeEvaluationEvidence
    ) -> ExpectationResult {
        guard let payload = changeEvidence.screenChanged else {
            return ExpectationResult(met: false, predicate: nil, actual: changeEvidence.kindDescription)
        }
        guard !assertions.isEmpty else {
            return ExpectationResult(met: true, predicate: nil, actual: AccessibilityTrace.DeltaKind.screenChanged.rawValue)
        }
        let stateClause: AccessibilityPredicate.State = assertions.count == 1
            ? assertions[0]
            : .all(NonEmptyArray(assertions[0], rest: Array(assertions.dropFirst())))
        let outcome = stateClause.evaluate(in: ElementMatchGraph(interface: payload.newInterface))
        return PredicateEvaluationResult(
            met: outcome.met,
            actual: outcome.met ? nil : "screen changed but new interface failed: \(outcome.actual ?? stateClause.description)"
        ).expectation(for: nil)
    }

    static func evaluateElements(
        assertions: [ElementDeltaPredicate],
        changeEvidence: ChangeEvaluationEvidence
    ) -> ExpectationResult {
        guard let payload = changeEvidence.elementsChanged else {
            return ExpectationResult(met: false, predicate: nil, actual: changeEvidence.kindDescription)
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
            let met = !ElementMatchGraph(elements: edits.added).resolve(element).isEmpty
            return ExpectationResult(met: met, predicate: nil, actual: met ? nil : "no appeared element matches \(element)")
        case .disappearedElement(let element):
            let met = !ElementMatchGraph(elements: edits.removed).resolve(element).isEmpty
            return ExpectationResult(met: met, predicate: nil, actual: met ? nil : "no disappeared element matches \(element)")
        case .updatedElement(let update):
            return evaluateUpdated(update: update, edits: edits)
        }
    }

    private static func evaluateUpdated(
        update: ElementUpdatePredicate,
        edits: ElementEdits
    ) -> ExpectationResult {
        let updates = edits.updated
        guard !updates.isEmpty else {
            return ExpectationResult(met: false, predicate: nil, actual: "no element updates")
        }
        if let matchedUpdate = updates.lazy.compactMap({ $0.matching(update) }).first {
            return ExpectationResult(
                met: true,
                predicate: nil,
                actual: matchedUpdate.description
            )
        }
        let observed = updates.map(\.description).joined(separator: "; ")
        return ExpectationResult(met: false, predicate: nil, actual: observed)
    }
}

private struct MatchedElementUpdate: Sendable {
    let update: ElementUpdate
    let changes: [PropertyChange]

    var description: String {
        update.describe(changes: changes)
    }
}

private extension ElementUpdate {
    func matching(_ predicate: ElementUpdatePredicate) -> MatchedElementUpdate? {
        if let element = predicate.element {
            guard element.matches(before) || element.matches(after) else { return nil }
        }
        let matchingChanges = predicate.change.map { change in
            changes.filter { $0.satisfies(change) }
        } ?? changes
        guard predicate.change == nil || !matchingChanges.isEmpty else { return nil }
        return MatchedElementUpdate(update: self, changes: matchingChanges)
    }

    var description: String {
        describe(changes: changes)
    }

    func describe(changes: [PropertyChange]) -> String {
        let properties = changes.map { "\($0.property.rawValue): \($0.displayTransition)" }
        let name = after.label ?? before.label ?? after.description
        return "\(name): \(properties.joined(separator: ", "))"
    }
}

fileprivate extension AccessibilityPredicate.ChangeScope {
    func evaluate(
        changeEvidence: ChangeEvaluationEvidence
    ) -> ExpectationResult {
        switch contract {
        case .screen(let assertions):
            return AccessibilityPredicate.Change.evaluateScreen(assertions: assertions, changeEvidence: changeEvidence)
        case .elements(let assertions):
            return AccessibilityPredicate.Change.evaluateElements(assertions: assertions, changeEvidence: changeEvidence)
        case .all(let changes):
            let results = changes.map { $0.evaluate(changeEvidence: changeEvidence) }
            let failures = results.compactMap { $0.met ? nil : ($0.actual ?? $0.predicate?.description) }
            return ExpectationResult(met: failures.isEmpty, predicate: nil, actual: failures.isEmpty ? nil : failures.joined(separator: "; "))
        }
    }
}

// MARK: - Change Evidence

private enum ChangeEvaluationEvidence {
    case missing
    case delta(AccessibilityTrace.Delta)
    case accumulatedDelta(AccessibilityTrace.AccumulatedDelta)

    init(delta: AccessibilityTrace.Delta?) {
        if let delta {
            self = .delta(delta)
        } else {
            self = .missing
        }
    }

    init(accumulatedDelta: AccessibilityTrace.AccumulatedDelta?) {
        if let accumulatedDelta {
            self = .accumulatedDelta(accumulatedDelta)
        } else {
            self = .missing
        }
    }

    var kindDescription: String {
        switch self {
        case .missing:
            return "noTrace"
        case .delta(let delta):
            return delta.kindDescription
        case .accumulatedDelta(let accumulatedDelta):
            return accumulatedDelta.kindDescription
        }
    }

    var isNoChange: Bool {
        switch self {
        case .missing:
            return false
        case .delta(let delta):
            return delta.isNoChange
        case .accumulatedDelta(let accumulatedDelta):
            return accumulatedDelta.isNoChange
        }
    }

    var isSemanticChange: Bool {
        switch self {
        case .missing:
            return false
        case .delta(let delta):
            return delta.isSemanticChange
        case .accumulatedDelta(let accumulatedDelta):
            return accumulatedDelta.isSemanticChange
        }
    }

    var screenChanged: AccessibilityTrace.ScreenChanged? {
        switch self {
        case .missing:
            return nil
        case .delta(let delta):
            return delta.screenChanged
        case .accumulatedDelta(let accumulatedDelta):
            return accumulatedDelta.screenChanged
        }
    }

    var elementsChanged: AccessibilityTrace.ElementsChanged? {
        switch self {
        case .missing:
            return nil
        case .delta(let delta):
            return delta.elementsChanged
        case .accumulatedDelta(let accumulatedDelta):
            return accumulatedDelta.elementsChanged
        }
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

    var isNoChange: Bool {
        if case .noChange = self { return true }
        return false
    }

    var isSemanticChange: Bool {
        !isNoChange
    }

    var screenChanged: AccessibilityTrace.ScreenChanged? {
        if case .screenChanged(let payload) = self { return payload }
        return nil
    }

    var elementsChanged: AccessibilityTrace.ElementsChanged? {
        if case .elementsChanged(let payload) = self { return payload }
        return nil
    }
}
