#if canImport(UIKit)
#if DEBUG
import Foundation
import ThePlans
import TheScore

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
            case .passive: passive
            case .action: action
            }
        }
        set {
            switch lane {
            case .passive: passive = newValue
            case .action: action = newValue
            }
        }
    }
}

private struct StoreNotificationRead {
    let lane: StoreNotificationLane
    let notifications: Observation.Notifications
}

extension TheVault {
    internal struct State {
        internal nonisolated static let defaultRetentionLimit = 256

        internal private(set) var history: Observation.History
        internal private(set) var current: Current?
        internal private(set) var interfaceTree: InterfaceTree = .empty
        internal private(set) var sequence: SettledObservationSequence = 0
        internal private(set) var scopedScreenChangedSequence: UInt64 = 0
        internal private(set) var settleFailureDiagnostic: String?

        private var admittedTripwireSignal: TheTripwire.TripwireSignal?
        private var notificationIndices = StoreNotificationIndices()
        private var replacementRequired = false
        private var protectedHistoryIndex: Int?

        internal var notificationIndex: AccessibilityNotificationCursor {
            notificationIndices.latest
        }

        internal init(retentionLimit: Int = defaultRetentionLimit) {
            history = Observation.History(retentionLimit: retentionLimit)
        }

        internal mutating func discardCurrentObservation() {
            current = nil
            interfaceTree = .empty
            admittedTripwireSignal = nil
            replacementRequired = true
            settleFailureDiagnostic = nil
        }

        internal mutating func invalidateCurrentAdmission() {
            admittedTripwireSignal = nil
            replacementRequired = true
        }

        internal mutating func discardIfSignalChanged(
            to tripwireSignal: TheTripwire.TripwireSignal
        ) {
            guard let admittedTripwireSignal,
                  admittedTripwireSignal != tripwireSignal
            else { return }
            discardCurrentObservation()
        }

        internal func admittedObservation(
            scope: SemanticObservationScope,
            after sequence: SettledObservationSequence?
        ) -> AdmittedObservation? {
            guard let admittedTripwireSignal,
                  let current,
                  current.scope.canFulfill(scope),
                  current.sequence > (sequence ?? 0)
            else { return nil }
            return AdmittedObservation(
                current: current,
                tripwireSignal: admittedTripwireSignal
            )
        }

        internal func current(
            after historyIndex: Int?,
            scope: SemanticObservationScope
        ) -> Result<Current?, Observation.History.ReadError> {
            guard let current,
                  current.scope.canFulfill(scope)
            else { return .success(nil) }
            guard let historyIndex else { return .success(current) }
            do {
                _ = try history.events(after: historyIndex)
                return .success(history.endIndex > historyIndex ? current : nil)
            } catch {
                return .failure(error)
            }
        }

        internal func current(
            scope: SemanticObservationScope,
            at sequence: SettledObservationSequence
        ) -> Current? {
            guard let current,
                  current.scope.canFulfill(scope),
                  current.sequence == sequence
            else { return nil }
            return current
        }

        internal mutating func protectHistory(from index: Int) {
            do {
                _ = try history.events(after: index)
            } catch {
                preconditionFailure("Protected index is unavailable in observation history")
            }
            precondition(
                protectedHistoryIndex == nil,
                "Observation history already has an active reader"
            )
            protectedHistoryIndex = index
        }

        internal mutating func releaseHistory(from index: Int) {
            precondition(
                protectedHistoryIndex == index,
                "Observation history index does not belong to the active reader"
            )
            protectedHistoryIndex = nil
            history.prune(protectedBy: nil)
        }

        internal func evidence(
            in range: Range<Int>,
            baseline: Observation.Snapshot?
        ) -> Observation.Evidence {
            history.evidence(
                in: range,
                baseline: baseline,
                current: current?.snapshot
            )
        }

        internal mutating func readObservation(
            _ admission: Observation.Admission
        ) -> ReadObservation {
            let notificationRead = notificationRead(for: admission.notificationAdmission)
            let notifications = notificationRead.notifications
            let previousTree = interfaceTree
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

            let continuity: ScreenContinuity
            if replacementRequired {
                continuity = .replacement(.screenChangedNotification)
            } else {
                continuity = ScreenClassifier.classify(
                    from: previousTree == .empty ? nil : previousTree,
                    to: comparedTree,
                    notifications: notifications.admittedNotifications.map(\.kind),
                    lineage: admission.lineage
                )
            }
            let nextTree = continuity.isReplacement ? admission.tree : candidateTree
            let nextSequence = sequence + 1
            let snapshot = Self.snapshot(
                tree: nextTree,
                admission: admission,
                semanticSignal: admission.tripwireSignal.semanticValue
            )
            let notificationEvents = notifications.admittedNotifications.compactMap {
                Observation.Notification(text: $0.text, element: $0.element)
                    .map(Observation.Event.notification)
            }
            let forcesElementChange = notifications.admittedNotifications.contains {
                if case .elementChanged = $0.kind { return true }
                return false
            }
            let currentEvent: Observation.Event
            let events: [Observation.Event]
            if continuity.isReplacement {
                currentEvent = .elementsChanged(snapshot)
                events = notificationEvents + [
                    .elementsChanged(.empty(timestamp: snapshot.interface.timestamp)),
                    .screenChanged(ScreenFacts(
                        idAfter: InterfaceSummary.screenName(for: snapshot.interface)
                    )),
                    currentEvent,
                ]
            } else {
                let changed = current.map {
                    !$0.snapshot.hasSameObservedState(
                        as: snapshot,
                        geometryTolerance: admission.geometryTolerance
                    )
                } ?? true
                currentEvent = forcesElementChange || changed
                    ? .elementsChanged(snapshot)
                    : .noChange
                events = notificationEvents + [currentEvent]
            }

            var next = self
            let historyRange = next.history.record(
                events,
                protectedBy: next.protectedHistoryIndex
            )
            let current = Current(
                snapshot: snapshot,
                scope: admission.scope,
                event: currentEvent,
                continuity: continuity,
                tree: nextTree,
                captureID: admission.captureID,
                semanticSignal: admission.tripwireSignal.semanticValue,
                notificationSequence: notifications.through.sequence,
                sequence: nextSequence
            )
            next.current = current
            next.interfaceTree = nextTree
            next.sequence = nextSequence
            next.notificationIndices[notificationRead.lane] = notifications.through
            next.scopedScreenChangedSequence = notifications.scopedScreenChangedThrough
            next.settleFailureDiagnostic = nil
            next.replacementRequired = false
            next.admittedTripwireSignal = admission.tripwireSignal
            self = next
            return ReadObservation(
                tree: nextTree,
                captureID: admission.captureID,
                current: current,
                historyRange: historyRange,
                events: events
            )
        }

        internal mutating func recordSettleFailure(_ diagnostic: String?) {
            settleFailureDiagnostic = diagnostic
        }

        private func notificationRead(
            for admission: Observation.NotificationAdmission
        ) -> StoreNotificationRead {
            let lane: StoreNotificationLane
            let snapshot: Observation.NotificationSnapshot
            switch admission {
            case .passive(let admittedSnapshot):
                lane = .passive
                snapshot = admittedSnapshot
            case .action(let admittedSnapshot):
                lane = .action
                snapshot = admittedSnapshot
            }
            return StoreNotificationRead(
                lane: lane,
                notifications: snapshot.notifications(
                    after: notificationIndices[lane],
                    scopedScreenChangedCursor: scopedScreenChangedSequence
                )
            )
        }

        private static func snapshot(
            tree: InterfaceTree,
            admission: Observation.Admission,
            semanticSignal: TheTripwire.SemanticSignal
        ) -> Observation.Snapshot {
            let windows = semanticSignal.windows.enumerated().map { index, window in
                Observation.WindowContext(
                    index: index,
                    level: window.level,
                    isKeyWindow: window.isKeyWindow
                )
            }
            return Observation.Snapshot(
                interface: TheVault.WireConversion.toSemanticInterface(
                    from: tree,
                    timestamp: admission.timestamp
                ),
                context: Observation.Context(
                    firstResponder: tree.firstResponderTarget,
                    keyboardVisible: admission.keyboardVisible,
                    screenId: tree.id,
                    windowStack: windows
                )
            )
        }
    }
}

extension TheVault.State {
    internal struct AdmittedObservation: Sendable, Equatable {
        internal let current: Current
        internal let tripwireSignal: TheTripwire.TripwireSignal
    }

    internal struct ReadObservation: Sendable {
        internal let tree: InterfaceTree
        internal let captureID: InterfaceCaptureID
        internal let current: Current
        internal let historyRange: Range<Int>
        internal let events: [Observation.Event]
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
