#if canImport(UIKit)
#if DEBUG
import Foundation
import TheScore

internal struct ObservationGeneration: RawRepresentable, Sendable, Equatable, Hashable {
    internal static let initial = ObservationGeneration(rawValue: 0)

    internal let rawValue: UInt64

    internal func advanced() -> ObservationGeneration {
        ObservationGeneration(rawValue: rawValue + 1)
    }
}

internal struct ObservationCursor: Sendable, Equatable, Hashable {
    internal let generation: ObservationGeneration
    internal let scope: SemanticObservationScope
    internal let sequence: SettledObservationSequence
    internal let captureHash: String
    internal let notificationSequence: UInt64
}

internal struct SettledCapture: Sendable, Equatable {
    internal let cursor: ObservationCursor
    internal let capture: AccessibilityTrace.Capture

    internal init(cursor: ObservationCursor, capture: AccessibilityTrace.Capture) {
        self.cursor = cursor
        self.capture = capture
    }

    internal init?(previousOf event: SettledSemanticObservationEvent) {
        guard let cursor = event.previousCursor,
              let capture = event.trace.captures.first,
              capture.hash == cursor.captureHash
        else { return nil }
        self.init(cursor: cursor, capture: capture)
    }
}

internal struct ScreenAppearance: Sendable, Equatable {
    internal let evidence: AccessibilityTrace.ScreenChanged
}

internal struct ElementTransition: Sendable, Equatable {
    internal let evidence: AccessibilityTrace.ElementsChanged
}

internal struct InteractionTransition: Sendable, Equatable {
    internal let captureEdge: AccessibilityTrace.CaptureEdge
    internal let digest: AccessibilityTrace.InteractionDigest
}

internal enum TransitionFact: Sendable, Equatable {
    case screenAppearance(ScreenAppearance)
    case elementsChanged(ElementTransition)
    case interactionChanged(InteractionTransition)
    case announcement(CapturedAnnouncement)
}

internal struct ObservationGap: Sendable, Equatable {
    internal enum Reason: Sendable, Equatable {
        case noObservationAfterBaseline
        case generationChanged
        case scopeChanged
        case historyUnavailable
    }

    internal let reason: Reason
    internal let baseline: ObservationCursor
    internal let current: ObservationCursor
}

internal enum Completeness: Sendable, Equatable {
    case complete
    case incomplete(ObservationGap)
}

internal struct ChangeFacts: Sendable, Equatable {
    internal let transitions: [TransitionFact]
    internal let accumulatedDelta: AccessibilityTrace.AccumulatedDelta
}

internal struct UnchangedEvidence: Sendable, Equatable {
    internal let baseline: ObservationCursor
    internal let current: ObservationCursor
    internal let elementCount: Int
}

internal enum ChangeVerdict: Sendable, Equatable {
    case changed(ChangeFacts)
    case unchanged(UnchangedEvidence)
}

internal struct ObservationWindow: Sendable, Equatable {
    internal let baseline: SettledCapture
    internal let current: SettledCapture
    internal let transitions: [TransitionFact]
    internal let completeness: Completeness
    internal let trace: AccessibilityTrace
    internal let accumulatedDelta: AccessibilityTrace.AccumulatedDelta?
    internal let verdict: ChangeVerdict?

    internal init(
        baseline: SettledCapture,
        current: SettledCapture,
        captures: [AccessibilityTrace.Capture],
        completeness: Completeness,
        projection: AccessibilityTrace.DeltaProjection
    ) {
        let trace = AccessibilityTrace(captures: captures)
        let transitions = Self.transitions(in: trace, projection: projection)
        self.baseline = baseline
        self.current = current
        self.transitions = transitions
        self.completeness = completeness
        self.trace = trace
        self.accumulatedDelta = trace.accumulatedDelta(projection: projection)
        self.verdict = Self.verdict(
            baseline: baseline,
            current: current,
            transitions: transitions,
            completeness: completeness,
            trace: trace,
            projection: projection
        )
    }

    internal static func direct(
        from baseline: SettledCapture,
        through event: SettledSemanticObservationEvent,
        projection: AccessibilityTrace.DeltaProjection
    ) -> ObservationWindow? {
        guard let current = event.settledCapture else { return nil }
        let completeness: Completeness
        if baseline.cursor.generation != current.cursor.generation {
            completeness = .incomplete(ObservationGap(
                reason: .generationChanged,
                baseline: baseline.cursor,
                current: current.cursor
            ))
        } else if baseline.cursor.scope != current.cursor.scope {
            completeness = .incomplete(ObservationGap(
                reason: .scopeChanged,
                baseline: baseline.cursor,
                current: current.cursor
            ))
        } else if current.cursor.sequence <= baseline.cursor.sequence {
            completeness = .incomplete(ObservationGap(
                reason: .noObservationAfterBaseline,
                baseline: baseline.cursor,
                current: current.cursor
            ))
        } else if event.previousCursor?.sequence == baseline.cursor.sequence,
                  event.previousCursor?.captureHash == baseline.cursor.captureHash {
            completeness = .complete
        } else {
            completeness = .incomplete(ObservationGap(
                reason: .historyUnavailable,
                baseline: baseline.cursor,
                current: current.cursor
            ))
        }
        return ObservationWindow(
            baseline: baseline,
            current: current,
            captures: [baseline.capture, current.capture],
            completeness: completeness,
            projection: projection
        )
    }

    private static func verdict(
        baseline: SettledCapture,
        current: SettledCapture,
        transitions: [TransitionFact],
        completeness: Completeness,
        trace: AccessibilityTrace,
        projection: AccessibilityTrace.DeltaProjection
    ) -> ChangeVerdict? {
        if transitions.contains(where: \.isPredicateChange),
           let accumulatedDelta = trace.accumulatedDelta(projection: projection) {
            return .changed(ChangeFacts(
                transitions: transitions,
                accumulatedDelta: accumulatedDelta
            ))
        }
        switch completeness {
        case .complete:
            return .unchanged(UnchangedEvidence(
                baseline: baseline.cursor,
                current: current.cursor,
                elementCount: current.capture.interface.projectedElements.count
            ))
        case .incomplete:
            return nil
        }
    }

    private static func transitions(
        in trace: AccessibilityTrace,
        projection: AccessibilityTrace.DeltaProjection
    ) -> [TransitionFact] {
        zip(trace.captures, trace.captures.dropFirst()).flatMap { before, after in
            let delta = AccessibilityTrace.Delta.between(before, after, projection: projection)
            return transitionFacts(delta: delta, after: after)
        }
    }

    private static func transitionFacts(
        delta: AccessibilityTrace.Delta,
        after: AccessibilityTrace.Capture
    ) -> [TransitionFact] {
        let change: TransitionFact? = switch delta {
        case .screenChanged(let evidence):
            .screenAppearance(ScreenAppearance(evidence: evidence))
        case .elementsChanged(let evidence)
            where !evidence.edits.isEmpty || !evidence.accessibilityNotifications.isEmpty:
            .elementsChanged(ElementTransition(evidence: evidence))
        case .elementsChanged(let evidence):
            evidence.captureEdge.flatMap { edge in
                evidence.interactionDigest.map {
                    .interactionChanged(InteractionTransition(captureEdge: edge, digest: $0))
                }
            }
        case .noChange:
            nil
        }
        return [change].compactMap { $0 } + after.transition.accessibilityNotifications.compactMap(\.announcement)
    }
}

private extension TransitionFact {
    var isPredicateChange: Bool {
        switch self {
        case .screenAppearance, .elementsChanged:
            true
        case .interactionChanged, .announcement:
            false
        }
    }
}

private extension AccessibilityNotificationEvidence {
    var announcement: TransitionFact? {
        guard case .string(let text) = notificationData else { return nil }
        return .announcement(CapturedAnnouncement(
            sequence: sequence,
            text: text,
            timestamp: timestamp,
            kind: kind,
            associatedElement: associatedElement
        ))
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
