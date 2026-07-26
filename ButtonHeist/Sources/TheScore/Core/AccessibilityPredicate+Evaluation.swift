import ThePlans
import Foundation

package extension ResolvedAccessibilityPredicate {
    func evaluate(in evidence: AccessibilityTraceEvidence) -> PredicateEvaluationResult {
        evaluateNode(self, evidence: evidence)
    }

    func validate(against result: ActionResult) -> PredicateEvaluationResult {
        guard let evidence = result.traceEvidence else {
            return PredicateEvaluationResult(met: false, actual: "no observed accessibility trace")
        }
        return evaluate(in: evidence)
    }
}

private extension ResolvedAccessibilityPredicate {
    func evaluateNode(
        _ node: ResolvedAccessibilityPredicate,
        evidence: AccessibilityTraceEvidence
    ) -> PredicateEvaluationResult {
        let current = AccessibilityTargetMatchGraph(interface: evidence.currentInterface)
        switch node {
        case .exists(let target):
            return currentResult(target, shouldExist: true, graph: current)
        case .missing(let target):
            return currentResult(target, shouldExist: false, graph: current)
        case .changed(.screen(let predicate)):
            return evaluateScreen(predicate, evidence: evidence)
        case .changed(.elements(let assertions)):
            return evaluateElements(assertions, evidence: evidence, current: current)
        case .announcement:
            return PredicateEvaluationResult(
                met: false,
                actual: "announcement predicates require spoken accessibility text evidence"
            )
        }
    }

    /// A screen predicate asks about the screen and nothing else: did a
    /// boundary happen, and — if the caller named one — was the screen arrived
    /// at that screen. Which elements left and which arrived are element
    /// questions, and they are asked by element predicates.
    func evaluateScreen(
        _ predicate: ResolvedScreenPredicate,
        evidence: AccessibilityTraceEvidence
    ) -> PredicateEvaluationResult {
        let facts = evidence.changeFacts
        guard facts.contains(where: \.isScreenChanged) else {
            return PredicateEvaluationResult(met: false, actual: facts.kindDescription)
        }
        let arrived = InterfaceSummary.screenName(for: evidence.currentInterface)
        guard predicate.matches(ScreenFacts(idAfter: arrived)) else {
            return PredicateEvaluationResult(met: false, actual: arrived ?? "unnamed screen")
        }
        return PredicateEvaluationResult(met: true, actual: nil)
    }

    /// Element predicates split by arity, and the split decides what evidence
    /// each half is entitled to.
    ///
    /// `exists`/`missing` are snapshot predicates: one graph in, a verdict out.
    /// They hold — or not — whether or not anything changed, so a quiet tree is
    /// a legitimate answer and they are never gated on there being element
    /// facts at all.
    ///
    /// `appeared`/`disappeared`/`updated` are delta predicates: two graphs in,
    /// measured from a baseline.
    ///
    /// A screen change is a wholesale replacement of that baseline. It is not
    /// an edge to be diffed — it discards the old starting point and installs a
    /// new one, and deltas resume from there. So a delta predicate has nothing
    /// to say about the replacement itself: asking "did X appear?" of it is not
    /// vacuously true, it is a question about an edge that does not exist.
    /// `changed(.screen)` is the predicate that speaks about a new baseline,
    /// and it admits snapshot predicates only — the sensible question about a
    /// baseline being what is in it. The projection emits no `elementsChanged`
    /// fact for a replacement, so the filter below leaves delta predicates
    /// unanswerable there rather than trivially satisfied.
    ///
    /// Asserting nothing is itself the nullary delta predicate — "elements
    /// changed, never mind which" — so it keeps the whole-predicate gate. A
    /// quiet tree must not satisfy it, or a wait on it returns immediately.
    func evaluateElements(
        _ assertions: [ResolvedElementAssertion],
        evidence: AccessibilityTraceEvidence,
        current: AccessibilityTargetMatchGraph<HeistElement>
    ) -> PredicateEvaluationResult {
        let facts = evidence.changeFacts
        let elementFacts = facts.compactMap(\.elementsChanged)
        let crossedScreenBoundary = facts.contains(where: \.isScreenChanged)
        guard !assertions.isEmpty || !elementFacts.isEmpty else {
            return PredicateEvaluationResult(met: false, actual: facts.kindDescription)
        }
        let failures = assertions.compactMap { assertion -> String? in
            guard assertion.isSnapshotPredicate || !elementFacts.isEmpty else {
                return crossedScreenBoundary
                    ? "\(assertion) asks about an element change, but the screen changed; use changed(.screen())"
                    : facts.kindDescription
            }
            let result = evaluateElementAssertion(
                assertion,
                facts: elementFacts,
                evidence: evidence,
                current: current
            )
            return result.met ? nil : result.actual
        }
        return PredicateEvaluationResult(
            met: failures.isEmpty,
            actual: failures.isEmpty ? nil : failures.compactMap { $0 }.joined(separator: "; ")
        )
    }

    func evaluateCurrentAssertion(
        _ assertion: ResolvedPresenceCondition,
        graph: AccessibilityTargetMatchGraph<HeistElement>
    ) -> PredicateEvaluationResult {
        switch assertion {
        case .exists(let target):
            return currentResult(target, shouldExist: true, graph: graph)
        case .missing(let target):
            return currentResult(target, shouldExist: false, graph: graph)
        }
    }

    func evaluateElementAssertion(
        _ assertion: ResolvedElementAssertion,
        facts: [AccessibilityTrace.ElementsChangeFact],
        evidence: AccessibilityTraceEvidence,
        current: AccessibilityTargetMatchGraph<HeistElement>
    ) -> PredicateEvaluationResult {
        switch assertion {
        case .exists(let target):
            return currentResult(target, shouldExist: true, graph: current)
        case .missing(let target):
            return currentResult(target, shouldExist: false, graph: current)
        case .appeared(let target):
            let met = facts.contains {
                lifecycleMatches(target, nodes: $0.appeared, side: .after, metadata: $0.metadata, trace: evidence.trace)
            }
            return PredicateEvaluationResult(
                met: met,
                actual: met ? nil : "no appeared node matches \(target)"
            )
        case .disappeared(let target):
            let met = facts.contains {
                lifecycleMatches(target, nodes: $0.disappeared, side: .before, metadata: $0.metadata, trace: evidence.trace)
            }
            return PredicateEvaluationResult(
                met: met,
                actual: met ? nil : "no disappeared node matches \(target)"
            )
        case .updated(let target, let change):
            return evaluateUpdated(target: target, change: change, facts: facts, trace: evidence.trace)
        }
    }

    func currentResult(
        _ target: ResolvedAccessibilityTarget,
        shouldExist: Bool,
        graph: AccessibilityTargetMatchGraph<HeistElement>
    ) -> PredicateEvaluationResult {
        let exists = !graph.resolve(target).isEmpty
        let met = exists == shouldExist
        let requirement = shouldExist ? "exist" : "be missing"
        return PredicateEvaluationResult(
            met: met,
            actual: met ? nil : "expected \(target) to \(requirement)"
        )
    }

    enum CaptureSide {
        case before
        case after
    }

    func lifecycleMatches(
        _ target: ResolvedAccessibilityTarget,
        nodes: [AccessibilityTrace.InterfaceChangeNode],
        side: CaptureSide,
        metadata: AccessibilityTrace.ChangeFactMetadata,
        trace: AccessibilityTrace
    ) -> Bool {
        guard let interface = interface(for: side, metadata: metadata, trace: trace) else { return false }
        let paths = AccessibilityTargetMatchGraph(interface: interface).resolve(target).paths
        return nodes.contains { paths.contains($0.path) }
    }

    func evaluateUpdated(
        target: ResolvedAccessibilityTarget,
        change: ResolvedElementPropertyChange,
        facts: [AccessibilityTrace.ElementsChangeFact],
        trace: AccessibilityTrace
    ) -> PredicateEvaluationResult {
        let matches = facts.lazy.flatMap { fact -> [MatchedElementUpdate] in
            guard let before = interface(for: .before, metadata: fact.metadata, trace: trace),
                  let after = interface(for: .after, metadata: fact.metadata, trace: trace)
            else { return [] }
            let beforeElements = AccessibilityTargetMatchGraph(interface: before).resolve(target).elements.elements
            let afterElements = AccessibilityTargetMatchGraph(interface: after).resolve(target).elements.elements
            return fact.updated.compactMap { update in
                guard beforeElements.contains(update.before) || afterElements.contains(update.after) else { return nil }
                let changes = update.changes.filter { $0.satisfies(change) }
                return changes.isEmpty ? nil : MatchedElementUpdate(update: update, changes: changes)
            }
        }
        guard let match = matches.first else {
            let observed = facts.flatMap(\.updated).map(\.description).joined(separator: "; ")
            return PredicateEvaluationResult(
                met: false,
                actual: observed.isEmpty ? "no matching element updates" : observed
            )
        }
        return PredicateEvaluationResult(met: true, actual: match.description)
    }

    func interface(
        for side: CaptureSide,
        metadata: AccessibilityTrace.ChangeFactMetadata,
        trace: AccessibilityTrace
    ) -> Interface? {
        guard let edge = metadata.captureEdge else { return nil }
        let ref = side == .before ? edge.before : edge.after
        return trace.capture(ref: ref)?.interface
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
    var description: String {
        describe(changes: changes)
    }

    func describe(changes: [PropertyChange]) -> String {
        let properties = changes.map { "\($0.property.rawValue): \($0.displayTransition)" }
        let name = after.label ?? before.label ?? after.description
        return "\(name): \(properties.joined(separator: ", "))"
    }
}

private extension Collection where Element == AccessibilityTrace.ChangeFact {
    var kindDescription: String {
        isEmpty ? "noChange" : map { $0.kind.rawValue }.joined(separator: ",")
    }
}

private extension AccessibilityTrace.ChangeFact {
    var isScreenChanged: Bool {
        if case .screenChanged = self { return true }
        return false
    }

    var elementsChanged: AccessibilityTrace.ElementsChangeFact? {
        if case .elementsChanged(let fact) = self { return fact }
        return nil
    }
}
