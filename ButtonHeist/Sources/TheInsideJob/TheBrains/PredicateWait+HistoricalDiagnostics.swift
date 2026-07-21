#if canImport(UIKit)
#if DEBUG
import ThePlans
import TheScore

internal struct PredicateWaitHistoricalDiagnostics: Sendable, Equatable {
    private let target: ResolvedAccessibilityTarget?
    private let predicateMismatches: [HistoricalWaitDiagnostics.PredicateMismatch]

    internal init(target: ResolvedAccessibilityTarget?) {
        self.target = target
        predicateMismatches = []
    }

    private init(
        target: ResolvedAccessibilityTarget?,
        predicateMismatches: [HistoricalWaitDiagnostics.PredicateMismatch]
    ) {
        self.target = target
        self.predicateMismatches = predicateMismatches
    }

    internal var evidence: HistoricalWaitDiagnostics.Evidence? {
        HistoricalWaitDiagnostics.Evidence(predicateMismatches: predicateMismatches)
    }

    internal func recording(
        _ reduction: PredicateObservationReduction
    ) -> PredicateWaitHistoricalDiagnostics {
        guard !reduction.expectation.met,
              let target,
              let current = reduction.observation.event.trace.captures.last?.interface
        else { return self }

        let candidates = AccessibilityTargetMatchGraph(interface: current)
            .elementCandidates(in: target)
            .elements
            .compactMap(HistoricalWaitDiagnostics.SemanticCandidate.init(element:))
        guard !candidates.isEmpty else { return self }

        let sequence = reduction.observation.event.sequence.rawValue
        let updated = candidates.reduce(predicateMismatches) { history, candidate in
            Self.recording(
                candidate,
                predicate: reduction.expectation.predicate,
                sequence: sequence,
                in: history
            )
        }
        return PredicateWaitHistoricalDiagnostics(
            target: target,
            predicateMismatches: updated
        )
    }

    private static func recording(
        _ candidate: HistoricalWaitDiagnostics.SemanticCandidate,
        predicate: AccessibilityPredicate?,
        sequence: UInt64,
        in history: [HistoricalWaitDiagnostics.PredicateMismatch]
    ) -> [HistoricalWaitDiagnostics.PredicateMismatch] {
        guard let predicate else { return history }
        if let index = history.firstIndex(where: { $0.candidate == candidate }) {
            let first = history[index].provenance.firstObservationSequence
            guard let provenance = HistoricalWaitDiagnostics.CandidateProvenance(
                firstObservationSequence: first,
                lastObservationSequence: max(first, sequence)
            ) else {
                preconditionFailure("historical wait provenance must remain ordered")
            }
            var updated = history
            updated[index] = HistoricalWaitDiagnostics.PredicateMismatch(
                exactPredicate: predicate,
                candidate: candidate,
                provenance: provenance
            )
            return updated
        }

        guard let provenance = HistoricalWaitDiagnostics.CandidateProvenance(
            firstObservationSequence: sequence,
            lastObservationSequence: sequence
        ) else {
            preconditionFailure("single-observation provenance must be valid")
        }
        let mismatch = HistoricalWaitDiagnostics.PredicateMismatch(
            exactPredicate: predicate,
            candidate: candidate,
            provenance: provenance
        )
        let retained = history.count == HistoricalWaitDiagnostics.Evidence.maximumCandidateCount
            ? history.dropFirst()
            : history[...]
        return Array(retained) + [mismatch]
    }
}

private extension HistoricalWaitDiagnostics.SemanticCandidate {
    init?(element: HeistElement) {
        self.init(
            label: element.label,
            value: element.value,
            hint: element.hint,
            traits: element.traits
        )
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
