#if canImport(UIKit)
#if DEBUG
import ThePlans
import TheScore

internal enum HistoricalWaitDiagnostics: Sendable {}

extension HistoricalWaitDiagnostics {
    internal struct PredicateMismatch: Sendable, Equatable {
        internal let exactPredicate: AccessibilityPredicate
        internal let candidate: ElementDiagnosticSummary
    }

    internal struct Evidence: Sendable, Equatable {
        internal static let maximumCandidateCount = 8

        internal let predicateMismatches: [PredicateMismatch]

        internal var timeoutMismatchBreadcrumb: String {
            predicateMismatches.map {
                AutomaticTimeoutMismatchDiagnostic.breadcrumb(
                    candidateDescription: $0.candidate.rendered(using: .predicateMismatchCandidate),
                    exactPredicateDescription: $0.exactPredicate.description
                )
            }.joined(separator: "; ")
        }

        internal init?(predicateMismatches: [PredicateMismatch]) {
            guard !predicateMismatches.isEmpty,
                  predicateMismatches.count <= Self.maximumCandidateCount else {
                return nil
            }
            self.predicateMismatches = predicateMismatches
        }
    }
}

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
            .compactMap(ElementDiagnosticSummary.init(waitMismatchCandidate:))
        guard !candidates.isEmpty else { return self }

        let updated = candidates.reduce(predicateMismatches) { history, candidate in
            Self.recording(
                candidate,
                predicate: reduction.expectation.predicate,
                in: history
            )
        }
        return PredicateWaitHistoricalDiagnostics(
            target: target,
            predicateMismatches: updated
        )
    }

    private static func recording(
        _ candidate: ElementDiagnosticSummary,
        predicate: AccessibilityPredicate?,
        in history: [HistoricalWaitDiagnostics.PredicateMismatch]
    ) -> [HistoricalWaitDiagnostics.PredicateMismatch] {
        guard let predicate else { return history }
        guard !history.contains(where: { $0.candidate == candidate }) else { return history }
        let mismatch = HistoricalWaitDiagnostics.PredicateMismatch(
            exactPredicate: predicate,
            candidate: candidate
        )
        let retained = history.count == HistoricalWaitDiagnostics.Evidence.maximumCandidateCount
            ? history.dropFirst()
            : history[...]
        var updated = Array(retained)
        updated.append(mismatch)
        return updated
    }
}

private extension ElementDiagnosticSummary {
    init?(waitMismatchCandidate element: HeistElement) {
        guard element.label != nil
            || element.value != nil
            || element.hint != nil
            || !element.traits.isEmpty
        else { return nil }
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
