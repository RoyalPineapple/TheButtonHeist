#if canImport(UIKit)
#if DEBUG
import Foundation
import TheScore

internal struct ScreenGeneration: RawRepresentable, Sendable, Equatable, Hashable {
    internal static let initial = ScreenGeneration(rawValue: 0)

    internal let rawValue: UInt64

    internal func advanced() -> ScreenGeneration {
        ScreenGeneration(rawValue: rawValue + 1)
    }
}

internal enum Observation {}

extension Observation {
    internal struct Gap: Sendable, Equatable {
        internal let reason: Reason
        internal let baseline: Moment
        internal let current: Moment
    }

    internal enum TransitionValidationError: Error, Sendable, Equatable {
        case logIndexDidNotAdvance
        case generationMismatch(from: ScreenGeneration, to: ScreenGeneration)
        case replacementGenerationDidNotAdvance(from: ScreenGeneration, to: ScreenGeneration)
    }

    internal enum Transition: Sendable, Equatable {
        case initial
        case sameGeneration(previous: Moment)
        case screenBoundary(previous: Moment)

        internal var previousMoment: Moment? {
            switch self {
            case .initial:
                nil
            case .sameGeneration(let previous), .screenBoundary(let previous):
                previous
            }
        }
    }

    internal struct Snapshot: Sendable, Equatable {
        internal let sequence: SettledObservationSequence
        internal let generation: ScreenGeneration
        internal let sourceScope: SemanticObservationScope
        internal let semanticSignal: TheTripwire.SemanticSignal
        internal let notificationSequence: UInt64
        internal let trace: AccessibilityTrace
        private let tree: InterfaceTree
        private let captureID: InterfaceCaptureID

        internal var observation: InterfaceObservation {
            do {
                return try InterfaceObservation.build(
                    tree: tree,
                    dispatchReferences: .empty,
                    captureID: captureID
                )
            } catch {
                preconditionFailure("Committed semantic observation failed validation: \(error)")
            }
        }

        internal init(
            sequence: SettledObservationSequence,
            generation: ScreenGeneration,
            sourceScope: SemanticObservationScope,
            tree: InterfaceTree,
            captureID: InterfaceCaptureID,
            semanticSignal: TheTripwire.SemanticSignal,
            notificationSequence: UInt64,
            trace: AccessibilityTrace
        ) {
            self.sequence = sequence
            self.generation = generation
            self.sourceScope = sourceScope
            self.semanticSignal = semanticSignal
            self.notificationSequence = notificationSequence
            self.trace = trace
            self.tree = tree
            self.captureID = captureID
        }

        internal init(
            sequence: SettledObservationSequence,
            generation: ScreenGeneration,
            sourceScope: SemanticObservationScope,
            observation: InterfaceObservation,
            semanticSignal: TheTripwire.SemanticSignal,
            notificationSequence: UInt64,
            trace: AccessibilityTrace
        ) {
            self.init(
                sequence: sequence,
                generation: generation,
                sourceScope: sourceScope,
                tree: observation.tree,
                captureID: observation.captureID,
                semanticSignal: semanticSignal,
                notificationSequence: notificationSequence,
                trace: trace
            )
        }
    }

}

extension Observation.Gap {
    internal enum Reason: Sendable, Equatable {
        case noObservationAfterBaseline
        case scopeChanged
        case historyUnavailable
        case historyEvicted
    }
}

extension Observation {
    internal struct Admission: Sendable {
        internal let tree: InterfaceTree
        internal let captureID: InterfaceCaptureID
        internal let tripwireSignal: TheTripwire.TripwireSignal
        internal let discoveryCommitPolicy: Navigation.DiscoveryCommitPolicy
        internal let lineageEvidence: ScreenLineageEvidence?
        internal let scope: SemanticObservationScope
        internal let notificationAdmission: NotificationAdmission
        internal let timestamp: Date
    }

    internal enum NotificationAdmission: Sendable {
        case passive(NotificationSnapshot)
        case action(NotificationSnapshot)
    }

    internal enum PublicationOutcome: Sendable {
        case delivered(SnapshotEvent)
        case superseded

        internal var event: SnapshotEvent? {
            guard case .delivered(let event) = self else { return nil }
            return event
        }
    }

    internal struct NotificationSnapshot: Sendable {
        internal let evidence: [AccessibilityNotificationEvidence]
        internal let through: AccessibilityNotificationCursor
        internal let scopedScreenChangedThrough: UInt64
        internal let gap: AccessibilityNotificationGap?

        internal func notifications(
            after cursor: AccessibilityNotificationCursor,
            scopedScreenChangedCursor: UInt64
        ) -> Notifications {
            let selectedEvidence = evidence.filter { $0.sequence > cursor.sequence }
            return Notifications(
                kinds: selectedEvidence.map(\.kind),
                evidence: selectedEvidence,
                through: AccessibilityNotificationCursor(
                    sequence: max(cursor.sequence, through.sequence)
                ),
                scopedScreenChangedThrough: max(
                    scopedScreenChangedCursor,
                    scopedScreenChangedThrough
                ),
                gap: gap.flatMap {
                    $0.droppedThroughSequence > cursor.sequence ? $0 : nil
                }
            )
        }
    }

    internal struct Notifications: Sendable {
        internal let kinds: [AccessibilityNotificationKind]
        internal let evidence: [AccessibilityNotificationEvidence]
        internal let through: AccessibilityNotificationCursor
        internal let scopedScreenChangedThrough: UInt64
        internal let gap: AccessibilityNotificationGap?
    }
}

/// A semantic observation admitted for commit.
internal struct CommittableInterfaceObservation {
    internal let observation: InterfaceObservation
    internal let tripwireSignal: TheTripwire.TripwireSignal
    internal let discoveryCommitPolicy: Navigation.DiscoveryCommitPolicy
    internal let lineageEvidence: ScreenLineageEvidence?

    private init(
        observation: InterfaceObservation,
        tripwireSignal: TheTripwire.TripwireSignal,
        discoveryCommitPolicy: Navigation.DiscoveryCommitPolicy = .mergeIntoInterface,
        lineageEvidence: ScreenLineageEvidence? = nil
    ) {
        self.observation = observation
        self.tripwireSignal = tripwireSignal
        self.discoveryCommitPolicy = discoveryCommitPolicy
        self.lineageEvidence = lineageEvidence
    }

    internal static func admittedForTesting(
        _ observation: InterfaceObservation,
        tripwireSignal: TheTripwire.TripwireSignal,
        lineageEvidence: ScreenLineageEvidence? = nil
    ) -> Self {
        admitCaptured(
            observation,
            tripwireSignal: tripwireSignal,
            lineageEvidence: lineageEvidence
        )
    }

    internal static func admitCaptured(
        _ observation: InterfaceObservation,
        tripwireSignal: TheTripwire.TripwireSignal,
        lineageEvidence: ScreenLineageEvidence? = nil
    ) -> Self {
        Self(
            observation: observation,
            tripwireSignal: tripwireSignal,
            lineageEvidence: lineageEvidence
        )
    }

    @MainActor internal static func admit(
        _ settleResult: SettleSession.Result,
        discoveryCommitPolicy: Navigation.DiscoveryCommitPolicy = .mergeIntoInterface,
        lineageEvidence: ScreenLineageEvidence? = nil
    ) -> CommittableInterfaceObservation? {
        guard settleResult.outcome.didSettleCleanly,
              let finalObservation = settleResult.finalObservation else { return nil }
        return CommittableInterfaceObservation(
            observation: finalObservation.observation,
            tripwireSignal: settleResult.tripwireSignal,
            discoveryCommitPolicy: discoveryCommitPolicy,
            lineageEvidence: lineageEvidence
        )
    }
}

/// The settlement result available after an action observation attempt.
@MainActor
    internal struct ObservationSettlement {
    internal enum CommitOutcome {
        case committed(Observation.SnapshotEvent)
        case observedUnsettled(InterfaceObservation, notificationBatch: AccessibilityNotificationBatch?)
        case unavailable(notificationBatch: AccessibilityNotificationBatch?)
    }

    internal let settleResult: SettleSession.Result
    internal let commitOutcome: CommitOutcome
}

#endif // DEBUG
#endif // canImport(UIKit)
