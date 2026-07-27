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

        /// The semantic state of this screen, for asking whether it moved.
        ///
        /// The hash and not `==`: `InterfaceTree` holds its `viewportCapture`,
        /// so comparing two whole trees counts a scroll that revealed nothing
        /// as a change. The hash is the semantic reading, which is the one the
        /// question means.
        internal var semanticHash: String {
            tree.interfaceHash
        }

        /// Where this screen's visible elements sat when it was read.
        ///
        /// Paired with `semanticHash` to ask whether the tree moved at all:
        /// semantics catch a label or a value changing, placements catch an
        /// element still sliding into position.
        ///
        /// Held as frames rather than a digest because the comparison is a
        /// tolerance, not an equality: "within 8pt of" has nothing to hash.
        internal let viewportFrames: [HeistId: CGRect]

        /// How far an element may drift and still count as having held still.
        /// Read from the device when this observation was taken, because the
        /// comparison happens off the main actor and cannot ask.
        internal let placementTolerance: CGFloat

        /// What a screen predicate matches this screen by: its first heading.
        ///
        /// The same rule the replayed trace uses, deliberately — one reading, so
        /// a caller writing `changed(.screen("Order Details"))` cannot match
        /// live and miss on replay. Nil when the screen has no heading, which
        /// makes a named predicate refuse: there is nothing to have matched.
        internal var screenHeading: String? {
            trace.captures.last.flatMap { InterfaceSummary.screenName(for: $0.interface) }
        }

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
            trace: AccessibilityTrace,
            viewportFrames: [HeistId: CGRect],
            placementTolerance: CGFloat
        ) {
            self.sequence = sequence
            self.generation = generation
            self.sourceScope = sourceScope
            self.semanticSignal = semanticSignal
            self.notificationSequence = notificationSequence
            self.trace = trace
            self.tree = tree
            self.captureID = captureID
            self.viewportFrames = viewportFrames
            self.placementTolerance = placementTolerance
        }

        internal init(
            sequence: SettledObservationSequence,
            generation: ScreenGeneration,
            sourceScope: SemanticObservationScope,
            observation: InterfaceObservation,
            semanticSignal: TheTripwire.SemanticSignal,
            notificationSequence: UInt64,
            trace: AccessibilityTrace,
            viewportFrames: [HeistId: CGRect],
            placementTolerance: CGFloat
        ) {
            self.init(
                sequence: sequence,
                generation: generation,
                sourceScope: sourceScope,
                tree: observation.tree,
                captureID: observation.captureID,
                semanticSignal: semanticSignal,
                notificationSequence: notificationSequence,
                trace: trace,
                viewportFrames: viewportFrames,
                placementTolerance: placementTolerance
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
        internal let lineage: ScreenLineage
        internal let scope: SemanticObservationScope
        internal let notificationAdmission: NotificationAdmission
        internal let keyboardVisible: Bool?
        internal let timestamp: Date
        /// Where the read tree's visible elements sat. Only the viewport has
        /// live geometry, so only the viewport is asked.
        internal let viewportFrames: [HeistId: CGRect]
        /// The device's touch-target size, captured eagerly because the
        /// comparison that uses it runs off the main actor.
        internal let placementTolerance: CGFloat
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
    internal let lineage: ScreenLineage

    private init(
        observation: InterfaceObservation,
        tripwireSignal: TheTripwire.TripwireSignal,
        discoveryCommitPolicy: Navigation.DiscoveryCommitPolicy = .mergeIntoInterface,
        lineage: ScreenLineage
    ) {
        self.observation = observation
        self.tripwireSignal = tripwireSignal
        self.discoveryCommitPolicy = discoveryCommitPolicy
        self.lineage = lineage
    }

    internal static func admittedForTesting(
        _ observation: InterfaceObservation,
        tripwireSignal: TheTripwire.TripwireSignal,
        lineage: ScreenLineage
    ) -> Self {
        admitCaptured(
            observation,
            tripwireSignal: tripwireSignal,
            lineage: lineage
        )
    }

    internal static func admitCaptured(
        _ observation: InterfaceObservation,
        tripwireSignal: TheTripwire.TripwireSignal,
        discoveryCommitPolicy: Navigation.DiscoveryCommitPolicy = .mergeIntoInterface,
        lineage: ScreenLineage
    ) -> Self {
        Self(
            observation: observation,
            tripwireSignal: tripwireSignal,
            discoveryCommitPolicy: discoveryCommitPolicy,
            lineage: lineage
        )
    }

}

/// The settlement result available after an action observation attempt.
@MainActor
internal struct ObservationSettlement {
    internal enum CommitOutcome {
        case committed(Observation.SnapshotEvent)
        case unavailable
    }

    internal let commitOutcome: CommitOutcome
}

#endif // DEBUG
#endif // canImport(UIKit)
