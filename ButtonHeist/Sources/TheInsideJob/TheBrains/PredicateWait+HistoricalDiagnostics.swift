#if canImport(UIKit)
#if DEBUG
import ThePlans
import TheScore

internal struct PredicateWaitHistoricalDiagnostics: Sendable, Equatable {
    private static let maximumCandidateCount = 8

    private let target: ResolvedAccessibilityTarget?
    private let predicate: AccessibilityPredicate
    private let candidates: [ElementDiagnosticSummary]

    internal init(
        target: ResolvedAccessibilityTarget?,
        predicate: AccessibilityPredicate
    ) {
        self.target = target
        self.predicate = predicate
        candidates = []
    }

    private init(
        target: ResolvedAccessibilityTarget?,
        predicate: AccessibilityPredicate,
        candidates: [ElementDiagnosticSummary]
    ) {
        self.target = target
        self.predicate = predicate
        self.candidates = candidates
    }

    internal var timeoutMismatchMessage: String? {
        guard !candidates.isEmpty else { return nil }
        return candidates.map {
            "observed accessibility candidate \($0.rendered(using: .predicateMismatchCandidate)) "
                + "did not match \(predicate.description)"
        }.joined(separator: "; ")
    }

    internal func recording(
        _ reduction: PredicateObservationReduction
    ) -> PredicateWaitHistoricalDiagnostics {
        guard !reduction.expectation.met,
              let target,
              let current = reduction.observation.event.trace.captures.last?.interface
        else { return self }

        let observedCandidates = AccessibilityTargetMatchGraph(interface: current)
            .elementCandidates(in: target)
            .elements
            .compactMap(ElementDiagnosticSummary.init(waitMismatchCandidate:))
        guard !observedCandidates.isEmpty else { return self }

        var updated = candidates
        for candidate in observedCandidates where !updated.contains(candidate) {
            if updated.count == Self.maximumCandidateCount {
                updated.removeFirst()
            }
            updated.append(candidate)
        }
        return PredicateWaitHistoricalDiagnostics(
            target: target,
            predicate: predicate,
            candidates: updated
        )
    }
}

private extension ElementDiagnosticSummary {
    init?(waitMismatchCandidate element: HeistElement) {
        self.init(element: element)
        guard label != nil
                || identifier != nil
                || value != nil
                || hint != nil
                || !traits.isEmpty
                || !actions.isEmpty
                || !rotors.isEmpty
        else { return nil }
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
