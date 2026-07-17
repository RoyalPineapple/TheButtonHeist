import ThePlans
import Foundation

package extension ResolvedAccessibilityPredicate {
    func evaluate(in evidence: AccessibilityTraceEvidence) -> PredicateEvaluationResult {
        evaluateNode(core, evidence: evidence)
    }

    func validate(against result: ActionResult) -> PredicateEvaluationResult {
        guard let evidence = result.traceEvidence else {
            return PredicateEvaluationResult(met: false, actual: "no observed accessibility trace")
        }
        return evaluate(in: evidence)
    }
}

private extension ResolvedAccessibilityPredicate {
    typealias Node = AccessibilityPredicateCore<ResolvedAccessibilityPredicatePhase>
    typealias ScreenAssertion = ScreenAssertionCore<ResolvedAccessibilityPredicatePhase>
    typealias ElementAssertion = ElementAssertionCore<ResolvedAccessibilityPredicatePhase>

    func evaluateNode(
        _ node: Node,
        evidence: AccessibilityTraceEvidence
    ) -> PredicateEvaluationResult {
        let current = AccessibilityTargetMatchGraph(interface: evidence.currentInterface)
        switch node {
        case .presence(.exists(let target)):
            return currentResult(target, shouldExist: true, graph: current)
        case .presence(.missing(let target)):
            return currentResult(target, shouldExist: false, graph: current)
        case .changed(.screen(let assertions)):
            return evaluateScreen(assertions, evidence: evidence, current: current)
        case .changed(.elements(let assertions)):
            return evaluateElements(assertions, evidence: evidence, current: current)
        case .noChange:
            let facts = evidence.changeFacts
            guard evidence.isComplete else {
                return PredicateEvaluationResult(met: false, actual: "observation history incomplete")
            }
            return PredicateEvaluationResult(
                met: facts.isEmpty,
                actual: facts.isEmpty ? nil : facts.kindDescription
            )
        case .announcement:
            return PredicateEvaluationResult(
                met: false,
                actual: "announcement predicates require spoken accessibility text evidence"
            )
        }
    }

    func evaluateScreen(
        _ assertions: [ScreenAssertion],
        evidence: AccessibilityTraceEvidence,
        current: AccessibilityTargetMatchGraph<HeistElement>
    ) -> PredicateEvaluationResult {
        let facts = evidence.changeFacts
        guard facts.contains(where: \.isScreenChanged) else {
            return PredicateEvaluationResult(met: false, actual: facts.kindDescription)
        }
        let failures = assertions.compactMap { assertion -> String? in
            let result = evaluateCurrentAssertion(assertion, graph: current)
            return result.met ? nil : result.actual
        }
        return PredicateEvaluationResult(
            met: failures.isEmpty,
            actual: failures.isEmpty ? nil : failures.compactMap { $0 }.joined(separator: "; ")
        )
    }

    func evaluateElements(
        _ assertions: [ElementAssertion],
        evidence: AccessibilityTraceEvidence,
        current: AccessibilityTargetMatchGraph<HeistElement>
    ) -> PredicateEvaluationResult {
        let facts = evidence.changeFacts
        let elementFacts = facts.compactMap(\.elementsChanged)
        guard !elementFacts.isEmpty else {
            return PredicateEvaluationResult(met: false, actual: facts.kindDescription)
        }
        let failures = assertions.compactMap { assertion -> String? in
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
        _ assertion: ScreenAssertion,
        graph: AccessibilityTargetMatchGraph<HeistElement>
    ) -> PredicateEvaluationResult {
        switch assertion {
        case .presence(.exists(let target)):
            return currentResult(target, shouldExist: true, graph: graph)
        case .presence(.missing(let target)):
            return currentResult(target, shouldExist: false, graph: graph)
        }
    }

    func evaluateElementAssertion(
        _ assertion: ElementAssertion,
        facts: [AccessibilityTrace.ElementsChangeFact],
        evidence: AccessibilityTraceEvidence,
        current: AccessibilityTargetMatchGraph<HeistElement>
    ) -> PredicateEvaluationResult {
        switch assertion {
        case .presence(.exists(let target)):
            return currentResult(target, shouldExist: true, graph: current)
        case .presence(.missing(let target)):
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
        return (trace.capture(ref: ref) ?? trace.capture(hash: ref.hash))?.interface
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
