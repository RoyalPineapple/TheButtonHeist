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
        private var availability = Availability.invalidated(sourceScope: nil)
        internal private(set) var interfaceTree: InterfaceTree = .empty
        internal private(set) var sequence: SettledObservationSequence = 0
        private var notificationIndices = StoreNotificationIndices()
        internal private(set) var scopedScreenChangedSequence: UInt64 = 0
        internal private(set) var settleFailureDiagnostic: String?
        private var replacementRequired = false
        private var activeSettlementBoundaries: [Moment] = []

        internal var latestCommittedEvent: SnapshotEvent? {
            switch availability {
            case .admitted, .invalidated(.some):
                log.latestSnapshotEvent
            case .invalidated(.none):
                nil
            }
        }

        internal var latestCommittedSnapshot: Snapshot? {
            latestCommittedEvent?.snapshot
        }

        internal var latestCommittedMoment: Moment? {
            latestCommittedEvent?.moment
        }

        internal var latestSettledObservationInvalidated: Bool {
            switch availability {
            case .invalidated:
                true
            case .admitted:
                false
            }
        }

        internal var notificationIndex: AccessibilityNotificationCursor {
            notificationIndices.latest
        }

        internal init(retentionLimit: Int = defaultRetentionLimit) {
            log = Log(retentionLimit: retentionLimit)
        }

        internal mutating func invalidateCurrentObservation() {
            switch availability {
            case .admitted(let sourceScope, _):
                availability = .invalidated(sourceScope: sourceScope)
            case .invalidated:
                break
            }
        }

        @discardableResult
        internal mutating func invalidateIfSignalChanged(
            to tripwireSignal: TheTripwire.TripwireSignal
        ) -> Bool {
            guard case .admitted(let sourceScope, let admittedSignal) = availability,
                  admittedSignal != tripwireSignal else { return false }
            availability = .invalidated(sourceScope: sourceScope)
            return true
        }

        internal func admittedObservation(
            scope: SemanticObservationScope,
            after sequence: SettledObservationSequence?
        ) -> AdmittedObservation? {
            guard case .admitted(let sourceScope, let tripwireSignal) = availability,
                  sourceScope.canFulfill(scope),
                  let latest = log.latestSnapshotEvent,
                  latest.sequence > (sequence ?? 0) else { return nil }
            return AdmittedObservation(event: latest, tripwireSignal: tripwireSignal)
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

        internal mutating func commitObservation(
            _ admission: Admission
        ) throws -> CommittedObservation {
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
            let candidateTree = switch admission.scope {
            case .visible:
                previousTree.updatingViewport(with: admission.tree)
            case .discovery:
                admission.discoveryCommitPolicy == .replaceInterface
                    ? admission.tree
                    : previousTree.merging(admission.tree)
            }
            let classifiedContinuity = ScreenClassifier.classify(
                from: previousTree == .empty ? nil : previousTree,
                to: candidateTree,
                notifications: notifications.kinds,
                lineageEvidence: admission.lineageEvidence
            )
            let continuity = replacementRequired
                ? ScreenContinuity.replacement(.screenChangedNotification)
                : classifiedContinuity
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
                trace: trace
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
            next.replacementRequired = false
            next.availability = .admitted(
                sourceScope: admission.scope,
                tripwireSignal: admission.tripwireSignal
            )
            self = next
            return CommittedObservation(
                tree: nextTree,
                captureID: admission.captureID,
                event: event
            )
        }

        internal mutating func requireReplacement() {
            invalidateCurrentObservation()
            replacementRequired = true
            settleFailureDiagnostic = nil
        }

        internal mutating func clearCurrentInterface() {
            interfaceTree = .empty
            requireReplacement()
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

    internal struct CommittedObservation: Sendable {
        internal let tree: InterfaceTree
        internal let captureID: InterfaceCaptureID
        internal let event: Observation.SnapshotEvent
    }

    private enum Availability: Sendable, Equatable {
        case admitted(sourceScope: SemanticObservationScope, tripwireSignal: TheTripwire.TripwireSignal)
        case invalidated(sourceScope: SemanticObservationScope?)
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
