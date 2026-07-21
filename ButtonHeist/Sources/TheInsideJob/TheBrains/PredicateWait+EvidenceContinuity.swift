#if canImport(UIKit)
#if DEBUG
import Foundation
import ThePlans
import TheScore

internal enum PredicateWaitContinuity: Sendable, Equatable {
    case notProvided
    case candidate(reference: EvidenceContinuity.Reference, boundary: EvidenceContinuity.Boundary)
    case fallback(reference: EvidenceContinuity.Reference, reason: EvidenceContinuity.FallbackReason)
    case ineligible(reference: EvidenceContinuity.Reference)

    internal var reference: EvidenceContinuity.Reference? {
        switch self {
        case .notProvided:
            return nil
        case .candidate(let reference, _),
             .fallback(let reference, _),
             .ineligible(let reference):
            return reference
        }
    }

    internal func initialEvidence(
        for source: EvidenceContinuity.PositionSource
    ) -> EvidenceContinuity.WaitEvidence? {
        switch self {
        case .notProvided:
            return nil
        case .candidate(let reference, let boundary):
            let position = boundary.position(for: source)
            return EvidenceContinuity.WaitEvidence(
                status: .applied(reference: reference),
                actionBoundary: position,
                observedThrough: position
            )
        case .fallback(_, let reason):
            return EvidenceContinuity.WaitEvidence(status: .fallback(reason: reason))
        case .ineligible:
            return EvidenceContinuity.WaitEvidence(status: .ineligible)
        }
    }

    internal func excludingExplicitBaseline(
        _ baseline: PredicateChangeBaselineSource
    ) -> PredicateWaitContinuity {
        guard case .supplied = baseline, let reference else { return self }
        return .ineligible(reference: reference)
    }
}

internal struct EvidenceContinuityDiagnosticsSnapshot: Sendable, Equatable {
    internal var recordedOutcomes = 0
    internal var admittedReferences = 0
    internal var unknownReferenceFallbacks = 0
    internal var generationMismatchFallbacks = 0
    internal var observationHistoryFallbacks = 0
    internal var announcementHistoryFallbacks = 0
    internal var backdatedMatches = 0

    internal func fallbackCount(for reason: EvidenceContinuity.FallbackReason) -> Int {
        switch reason {
        case .unknownReference:
            unknownReferenceFallbacks
        case .generationMismatch:
            generationMismatchFallbacks
        case .observationHistoryUnavailable:
            observationHistoryFallbacks
        case .announcementHistoryUnavailable:
            announcementHistoryFallbacks
        }
    }
}

internal struct EvidenceContinuityDiagnostics {
    internal private(set) var snapshot = EvidenceContinuityDiagnosticsSnapshot()

    internal mutating func recordOutcome(
        _ continuity: PredicateWaitContinuity,
        status: EvidenceContinuity.Status?,
        family: String
    ) {
        guard let reference = continuity.reference else { return }
        snapshot.recordedOutcomes += 1
        if case .candidate = continuity {
            snapshot.admittedReferences += 1
        }
        let outcome: String
        switch status {
        case .applied:
            outcome = "applied"
        case .fallback(let reason):
            incrementFallback(reason)
            outcome = "fallback:\(reason.rawValue)"
        case .ineligible:
            outcome = "ineligible"
        case .notProvided, .none:
            outcome = "not_provided"
        }
        let fingerprint = reference.fingerprint
        insideJobLogger.info(
            "evidence_continuity reference=\(fingerprint, privacy: .public) predicate=\(family, privacy: .public) outcome=\(outcome, privacy: .public)"
        )
    }

    internal mutating func recordBackdatedMatch() {
        snapshot.backdatedMatches += 1
    }

    private mutating func incrementFallback(_ reason: EvidenceContinuity.FallbackReason) {
        switch reason {
        case .unknownReference:
            snapshot.unknownReferenceFallbacks += 1
        case .generationMismatch:
            snapshot.generationMismatchFallbacks += 1
        case .observationHistoryUnavailable:
            snapshot.observationHistoryFallbacks += 1
        case .announcementHistoryUnavailable:
            snapshot.announcementHistoryFallbacks += 1
        }
    }
}

internal enum PredicateContinuityChangeEvaluation {
    case matched(
        observation: SettledObservationEvidence,
        expectation: ExpectationResult,
        window: ObservationWindow,
        match: EvidenceContinuity.MatchSource,
        observedThrough: EvidenceContinuity.Position
    )
    case unmatched(observedThrough: EvidenceContinuity.Position)
    case fallback
}

extension TheBrains {
    internal func admitWaitContinuity(
        _ reference: EvidenceContinuity.Reference?,
        for predicate: ResolvedAccessibilityPredicate
    ) -> PredicateWaitContinuity {
        guard let reference else { return .notProvided }
        let admission: EvidenceContinuity.Admission
        switch predicate.core {
        case .changed:
            admission = admitEvidenceContinuity(reference, for: .settledObservation)
        case .announcement:
            admission = admitEvidenceContinuity(reference, for: .announcement)
        case .presence, .noChange:
            return .ineligible(reference: reference)
        }
        switch admission {
        case .notProvided:
            return .notProvided
        case .candidate(let admittedReference, let boundary):
            return .candidate(reference: admittedReference, boundary: boundary)
        case .fallback(let reason):
            return .fallback(reference: reference, reason: reason)
        }
    }
}

extension PredicateWait {
    internal func evaluateRetainedChange(
        predicate: ResolvedAccessibilityPredicate,
        expression: AccessibilityPredicate,
        boundary: EvidenceContinuity.Boundary,
        waitStart: ObservationCursor?
    ) -> PredicateContinuityChangeEvaluation {
        let baseline = boundary.settledCapture
        let stream = vault.semanticObservationStream
        guard let observedThroughCursor = stream.latestCommittedObservationCursor(
            scope: baseline.cursor.scope
        ), observedThroughCursor.sequence >= baseline.cursor.sequence else {
            return .fallback
        }
        let observedThrough = observedThroughCursor.continuityPosition
        guard observedThroughCursor.sequence > baseline.cursor.sequence else {
            return .unmatched(observedThrough: observedThrough)
        }

        let retainedEntries = stream.retainedObservationEntries(scope: baseline.cursor.scope).filter {
            $0.cursor.sequence > baseline.cursor.sequence
                && $0.cursor.sequence <= observedThroughCursor.sequence
        }
        guard retainedEntries.first?.transition.previousCursor == baseline.cursor,
              retainedEntries.last?.cursor == observedThroughCursor else {
            return .fallback
        }

        for index in retainedEntries.indices {
            let prefix = Array(retainedEntries[...index])
            let window: ObservationWindow
            do {
                window = try ObservationWindow(baseline: baseline, retainedEntries: prefix)
            } catch {
                return .fallback
            }
            let observation = actionEvidenceProjector.projectSettledEvidence(
                from: retainedEntries[index].event
            )
            let expectation = PredicateObservationEvidence(
                observation: observation,
                baseline: baseline,
                window: window
            ).evaluate(predicate, expression: expression)
            guard expectation.met else { continue }
            let position = retainedEntries[index].cursor.continuityPosition
            let match: EvidenceContinuity.MatchSource
            if let waitStart, position.sequence > waitStart.sequence.rawValue {
                match = .current
            } else {
                match = .backdated(position: position)
            }
            return .matched(
                observation: observation,
                expectation: expectation,
                window: window,
                match: match,
                observedThrough: observedThrough
            )
        }
        return .unmatched(observedThrough: observedThrough)
    }

    internal func recordContinuityOutcome(
        _ continuity: PredicateWaitContinuity,
        status: EvidenceContinuity.Status?,
        predicate: ResolvedAccessibilityPredicate
    ) {
        continuityDiagnostics.recordOutcome(
            continuity,
            status: status,
            family: predicate.continuityFamily
        )
    }

    internal func recordBackdatedContinuityMatch() {
        continuityDiagnostics.recordBackdatedMatch()
    }
}

private extension EvidenceContinuity.Reference {
    var fingerprint: String {
        String(key.uuidString.replacingOccurrences(of: "-", with: "").prefix(12)).lowercased()
    }
}

private extension EvidenceContinuity.Boundary {
    func position(for source: EvidenceContinuity.PositionSource) -> EvidenceContinuity.Position {
        switch source {
        case .settledObservation:
            settledObservationPosition
        case .announcement:
            announcementPosition
        }
    }
}

internal extension ObservationCursor {
    var continuityPosition: EvidenceContinuity.Position {
        EvidenceContinuity.Position(
            source: .settledObservation,
            sequence: sequence.rawValue
        )
    }
}

internal extension AccessibilityNotificationCursor {
    var continuityPosition: EvidenceContinuity.Position {
        EvidenceContinuity.Position(source: .announcement, sequence: sequence)
    }
}

private extension ResolvedAccessibilityPredicate {
    var continuityFamily: String {
        switch core {
        case .changed(.screen):
            "changed_screen"
        case .changed(.elements):
            "changed_elements"
        case .announcement:
            "announcement"
        case .presence:
            "presence"
        case .noChange:
            "no_change"
        }
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
