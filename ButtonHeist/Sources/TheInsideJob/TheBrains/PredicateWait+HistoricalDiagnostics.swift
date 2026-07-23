#if canImport(UIKit)
#if DEBUG
import ThePlans
import TheScore

internal struct PredicateWaitHistoricalDiagnostics: Sendable, Equatable {
    private static let maximumCandidateCount = 8

    internal enum TerminalPredicateStatus: Sendable, Equatable {
        case satisfied
        case unmet
        case unavailable
    }

    internal struct TerminalEvidence: Sendable, Equatable {
        internal let predicateStatus: TerminalPredicateStatus
        internal let readinessEstablished: Bool
        internal let handoffCompleted: Bool
    }

    internal enum TimeoutIncompleteAxis: Sendable, Equatable {
        case readiness
        case handoff
    }

    internal enum PresenceExpectation: Sendable, Equatable {
        case appear
        case disappear
    }

    internal struct PresenceTimeoutReport: Sendable, Equatable {
        internal let expectation: PresenceExpectation
        internal let target: ResolvedAccessibilityTarget
        internal let interfaceElementCount: Int
    }

    internal struct TimeoutReport: Sendable, Equatable {
        internal let predicateStatus: TerminalPredicateStatus
        internal let incompleteAxis: TimeoutIncompleteAxis?
        internal let presence: PresenceTimeoutReport?
        internal let candidates: [ElementDiagnosticSummary]
        internal let predicate: AccessibilityPredicate
    }

    private let target: ResolvedAccessibilityTarget?
    private let predicate: AccessibilityPredicate
    private let candidates: [ElementDiagnosticSummary]
    private let latestInterfaceElementCount: Int?

    internal init(
        target: ResolvedAccessibilityTarget?,
        predicate: AccessibilityPredicate
    ) {
        self.target = target
        self.predicate = predicate
        candidates = []
        latestInterfaceElementCount = nil
    }

    private init(
        target: ResolvedAccessibilityTarget?,
        predicate: AccessibilityPredicate,
        candidates: [ElementDiagnosticSummary],
        latestInterfaceElementCount: Int?
    ) {
        self.target = target
        self.predicate = predicate
        self.candidates = candidates
        self.latestInterfaceElementCount = latestInterfaceElementCount
    }

    internal var timeoutMismatchMessage: String? {
        guard !candidates.isEmpty else { return nil }
        return candidates.map {
            "observed accessibility candidate \($0.rendered(using: .predicateMismatchCandidate)) "
                + "did not match \(predicate.description)"
        }.joined(separator: "; ")
    }

    internal func timeoutReport(
        terminal: TerminalEvidence
    ) -> TimeoutReport {
        let incompleteAxis: TimeoutIncompleteAxis? = if terminal.predicateStatus != .satisfied {
            nil
        } else if !terminal.readinessEstablished {
            .readiness
        } else if !terminal.handoffCompleted {
            .handoff
        } else {
            nil
        }
        let presence: PresenceTimeoutReport? = switch (predicate.core, target, latestInterfaceElementCount) {
        case (.presence(.exists), let target?, let count?):
            PresenceTimeoutReport(
                expectation: .appear,
                target: target,
                interfaceElementCount: count
            )
        case (.presence(.missing), let target?, let count?):
            PresenceTimeoutReport(
                expectation: .disappear,
                target: target,
                interfaceElementCount: count
            )
        case (.announcement, _, _), (.changed, _, _), (.noChange, _, _),
             (.presence, _, _):
            nil
        }
        return TimeoutReport(
            predicateStatus: terminal.predicateStatus,
            incompleteAxis: incompleteAxis,
            presence: presence,
            candidates: terminal.predicateStatus == .unmet ? candidates : [],
            predicate: predicate
        )
    }

    internal func recording(
        _ reduction: PredicateObservationReduction
    ) -> PredicateWaitHistoricalDiagnostics {
        guard !reduction.expectation.met,
              let current = reduction.observation.event.trace.captures.last?.interface
        else { return self }

        return recording(current)
    }

    internal func recording(
        _ trace: AccessibilityTrace
    ) -> PredicateWaitHistoricalDiagnostics {
        trace.captures.reduce(self) { diagnostics, capture in
            diagnostics.recording(capture.interface)
        }
    }

    private func recording(
        _ current: Interface
    ) -> PredicateWaitHistoricalDiagnostics {
        guard let target else {
            return PredicateWaitHistoricalDiagnostics(
                target: nil,
                predicate: predicate,
                candidates: candidates,
                latestInterfaceElementCount: current.projectedElements.count
            )
        }

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
            candidates: updated,
            latestInterfaceElementCount: current.projectedElements.count
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
