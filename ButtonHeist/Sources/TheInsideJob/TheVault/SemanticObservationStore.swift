#if canImport(UIKit)
#if DEBUG
import Foundation
import TheScore
import ThePlans

private enum StoreNotificationLane {
    case passive
    case action
}

private struct StoreNotificationIndices {
    private var passive = AccessibilityNotificationCursor.origin
    private var action = AccessibilityNotificationCursor.origin

    var latest: AccessibilityNotificationCursor {
        AccessibilityNotificationCursor(sequence: max(passive.sequence, action.sequence))
    }

    subscript(lane: StoreNotificationLane) -> AccessibilityNotificationCursor {
        get {
            switch lane {
            case .passive:
                passive
            case .action:
                action
            }
        }
        set {
            switch lane {
            case .passive:
                passive = newValue
            case .action:
                action = newValue
            }
        }
    }
}

extension Observation {
    internal struct Store {
        internal nonisolated static let defaultRetentionLimit = 256

        internal private(set) var log: Log
        private var admittedTripwireSignal: TheTripwire.TripwireSignal?
        internal private(set) var interfaceTree: InterfaceTree = .empty
        internal private(set) var sequence: SettledObservationSequence = 0
        private var notificationIndices = StoreNotificationIndices()
        internal private(set) var scopedScreenChangedSequence: UInt64 = 0
        internal private(set) var settleFailureDiagnostic: String?
        private var activeSettlementBoundaries: [Moment] = []

        /// The newest reading in the log.
        ///
        /// Callers ask this for its position, to wait for what comes after it.
        /// The log is a sequence, so the newest entry is the answer — there is no
        /// freshness to consult, because the machine has no now.
        internal var latestReadEvent: SnapshotEvent? {
            log.latestSnapshotEvent
        }

        internal var latestReadSnapshot: Snapshot? {
            latestReadEvent?.snapshot
        }

        internal var latestReadMoment: Moment? {
            latestReadEvent?.moment
        }

        internal var notificationIndex: AccessibilityNotificationCursor {
            notificationIndices.latest
        }

        internal init(retentionLimit: Int = defaultRetentionLimit) {
            log = Log(retentionLimit: retentionLimit)
        }

        /// Throws away what the vault holds.
        ///
        /// The empty tree is the whole record: the next reading has nothing
        /// before it, so the classifier compares against nothing and says what
        /// the reading is. Nothing is marked, because there is nothing a mark
        /// could add to a tree that is already gone.
        ///
        /// The settle diagnostic stays. It records why a past settle failed,
        /// which is a fact about something that already happened; the tree is
        /// what the vault holds now. Letting go of the second says nothing about
        /// the first.
        internal mutating func discardCurrentObservation() {
            interfaceTree = .empty
            admittedTripwireSignal = nil
        }

        /// The newest reading past `sequence`, when it answers this scope.
        ///
        /// The newest reading is the present — a tick is now until the next one
        /// arrives — so this asks about position only: is there one after the one
        /// the caller already has.
        internal func admittedObservation(
            scope: SemanticObservationScope,
            after sequence: SettledObservationSequence?
        ) -> AdmittedObservation? {
            guard let admittedTripwireSignal,
                  let latest = log.latestSnapshotEvent,
                  latest.scope.canFulfill(scope),
                  latest.sequence > (sequence ?? 0) else { return nil }
            return AdmittedObservation(event: latest, tripwireSignal: admittedTripwireSignal)
        }

        internal func readSnapshot(
            since moment: Moment?,
            scope: SemanticObservationScope
        ) -> SnapshotRead {
            log.readSnapshot(after: moment, fulfilling: scope)
        }

        internal func latestMoment(scope: SemanticObservationScope) -> Moment? {
            log.latestSnapshot(fulfilling: scope)?.moment
        }

        internal func snapshotEvent(at moment: Moment) -> SnapshotEvent? {
            log.snapshotEvent(at: moment)
        }

        internal func snapshotEvent(
            scope: SemanticObservationScope,
            sequence: SettledObservationSequence
        ) -> SnapshotEvent? {
            log.snapshotEvent(fulfilling: scope, sequence: sequence)
        }

        internal func moment(
            scope: SemanticObservationScope,
            at sequence: SettledObservationSequence
        ) -> Moment? {
            snapshotEvent(scope: scope, sequence: sequence)?.moment
        }

        internal mutating func settlementDidArm(at moment: Moment) {
            if case .unavailable = log.events(since: moment) {
                preconditionFailure("Settlement boundary belongs to a different observation log")
            }
            precondition(
                !activeSettlementBoundaries.contains(moment),
                "Settlement observation boundary is already active"
            )
            activeSettlementBoundaries.append(moment)
        }

        internal mutating func settlementDidFinish(at moment: Moment) {
            guard let index = activeSettlementBoundaries.firstIndex(of: moment) else {
                preconditionFailure("Settlement observation boundary is not active")
            }
            activeSettlementBoundaries.remove(at: index)
            log.prune(protectedBy: earliestActiveSettlementBoundary)
        }

        /// Reads the admission into the vault, emitting a tick at each moment it
        /// passes through.
        ///
        /// One reading is one moment when the screen held, and three when it was
        /// replaced: the old screen's nodes depart, the identity moves, the new
        /// screen's nodes arrive. The ticks go out as those moments happen, so
        /// the departure is emitted while the old tree is still what the vault
        /// holds and the arrival only after the new one is installed.
        internal mutating func readObservation(
            _ admission: Admission,
            emit: (Tick) -> Void
        ) throws -> ReadObservation {
            let notificationLane: StoreNotificationLane
            let notificationSnapshot: NotificationSnapshot
            switch admission.notificationAdmission {
            case .passive(let snapshot):
                notificationLane = .passive
                notificationSnapshot = snapshot
            case .action(let snapshot):
                notificationLane = .action
                notificationSnapshot = snapshot
            }
            let notifications = notificationSnapshot.notifications(
                after: notificationIndices[notificationLane],
                scopedScreenChangedCursor: scopedScreenChangedSequence
            )
            let previousTree = interfaceTree
            // A viewport census covers the whole viewport, so an element missing
            // from it has gone away. That is what the screen is compared over.
            // What Button Heist keeps is a wider question: once it is the one
            // scrolling, leaving the viewport is what the scroll does, and an
            // element the census no longer sees is still known to be there.
            let comparedTree: InterfaceTree
            let candidateTree: InterfaceTree
            switch admission.scope {
            case .visible:
                comparedTree = previousTree.updatingViewport(with: admission.tree)
                candidateTree = switch admission.lineage {
                case .resting: comparedTree
                case .viewportMovement: previousTree.merging(admission.tree)
                }
            case .discovery:
                comparedTree = admission.discoveryCommitPolicy == .replaceInterface
                    ? admission.tree
                    : previousTree.merging(admission.tree)
                candidateTree = comparedTree
            }
            // A tree thrown away is a screen that went. The classifier compares
            // two trees and cannot see that, because what it would compare
            // against is exactly what is gone — so the store, which knows a
            // reading came before this one, says so. With nothing read yet there
            // is no screen to have left, and the reading is a first sighting.
            let continuity = if previousTree == .empty, log.latestSnapshotEvent != nil {
                ScreenContinuity.replacement(.screenChangedNotification)
            } else {
                ScreenClassifier.classify(
                    from: previousTree == .empty ? nil : previousTree,
                    to: comparedTree,
                    notifications: notifications.kinds,
                    lineage: admission.lineage
                )
            }
            if continuity.isReplacement {
                // The departure, emitted before the old tree is let go. Identity
                // does not survive a boundary, so a `missing` half needs a
                // reading holding none of what left.
                emit(.elementsChanged(.empty(at: admission.timestamp)))
            }
            let nextTree = continuity.isReplacement ? admission.tree : candidateTree
            let generation = continuity.isReplacement
                ? (log.latestSnapshotEvent?.generation ?? .initial).advanced()
                : (log.latestSnapshotEvent?.generation ?? .initial)
            let previousCapture = log.latestSnapshotEvent?.trace.captures.last
            let capture = Self.capture(
                tree: nextTree,
                admission: admission,
                sequence: (previousCapture?.sequence ?? 0) + 1,
                parentHash: previousCapture?.hash,
                generation: generation,
                notifications: notifications,
                fallbackReason: continuity.fallbackReason
            )
            let trace = previousCapture.map {
                AccessibilityTrace(captures: [$0, capture])
            } ?? AccessibilityTrace(capture: capture)
            let snapshot = Snapshot(
                sequence: sequence + 1,
                generation: generation,
                sourceScope: admission.scope,
                tree: nextTree,
                captureID: admission.captureID,
                semanticSignal: admission.tripwireSignal.semanticValue,
                notificationSequence: notifications.through.sequence,
                trace: trace,
                viewportFrames: admission.viewportFrames,
                placementTolerance: admission.placementTolerance
            )

            var next = self
            let event = try next.log.record(
                snapshot: snapshot,
                continuity: continuity,
                protectedBy: next.earliestActiveSettlementBoundary
            )
            next.interfaceTree = nextTree
            next.sequence = event.sequence
            next.notificationIndices[notificationLane] = notifications.through
            next.scopedScreenChangedSequence = notifications.scopedScreenChangedThrough
            next.settleFailureDiagnostic = nil
            next.admittedTripwireSignal = admission.tripwireSignal
            self = next
            if continuity.isReplacement {
                // The identity moves, ahead of the arriving graph: naming a
                // screen needs only what is on it, so a caller waiting on the
                // name does not also wait for the tree.
                emit(.screenChanged(ScreenFacts(idAfter: event.snapshot.screenHeading)))
                emit(.elementsChanged(event.moment.capture))
            } else {
                emit(event.isChange ? .elementsChanged(event.moment.capture) : .noChange)
            }
            return ReadObservation(
                tree: nextTree,
                captureID: admission.captureID,
                event: event
            )
        }

        internal mutating func recordSettleFailure(_ diagnostic: String?) {
            settleFailureDiagnostic = diagnostic
        }

        private var earliestActiveSettlementBoundary: Moment? {
            activeSettlementBoundaries.reduce(nil) { earliest, candidate in
                guard let earliest else { return candidate }
                return candidate.isSameOrAfter(earliest) ? earliest : candidate
            }
        }

        private static func capture(
            tree: InterfaceTree,
            admission: Observation.Admission,
            sequence: Int,
            parentHash: String?,
            generation: ScreenGeneration,
            notifications: Observation.Notifications,
            fallbackReason: AccessibilityObservationFallbackReason?
        ) -> AccessibilityTrace.Capture {
            let semanticSignal = admission.tripwireSignal.semanticValue
            let windows = semanticSignal.windows.enumerated().map { index, window in
                AccessibilityTrace.WindowContext(
                    index: index,
                    level: window.level,
                    isKeyWindow: window.isKeyWindow
                )
            }
            return AccessibilityTrace.Capture(
                sequence: sequence,
                interface: TheVault.WireConversion.toSemanticInterface(
                    from: tree,
                    timestamp: admission.timestamp
                ),
                parentHash: parentHash,
                context: AccessibilityTrace.Context(
                    firstResponder: tree.firstResponderTarget,
                    keyboardVisible: admission.keyboardVisible,
                    screenId: tree.id,
                    observationGeneration: generation.rawValue,
                    windowStack: windows
                ),
                transition: AccessibilityTrace.Transition(
                    fallbackReason: fallbackReason,
                    accessibilityNotifications: notifications.evidence,
                    accessibilityNotificationGap: notifications.gap
                )
            )
        }
    }
}

extension Observation.Store {
    internal struct AdmittedObservation: Sendable, Equatable {
        internal let event: Observation.SnapshotEvent
        internal let tripwireSignal: TheTripwire.TripwireSignal
    }

    internal struct ReadObservation: Sendable {
        internal let tree: InterfaceTree
        internal let captureID: InterfaceCaptureID
        internal let event: Observation.SnapshotEvent
    }

}

#endif // DEBUG
#endif // canImport(UIKit)
