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

        internal struct HistoryBoundary: Sendable, Equatable {
            internal let baseline: Observation.Snapshot?
            internal let historyIndex: Int
        }

        private struct NavigationAdmission {
            let scope: SemanticObservationScope
            let continuity: ScreenContinuity
        }

        internal private(set) var history: Observation.History
        internal private(set) var currentSnapshot: Observation.Snapshot?
        internal private(set) var interfaceTree: InterfaceTree = .empty
        internal private(set) var scopedScreenChangedSequence: UInt64 = 0

        private var navigationAdmission: NavigationAdmission?
        private var admittedTripwireSignal: TheTripwire.TripwireSignal?
        private var notificationIndices = StoreNotificationIndices()
        private var replacementRequired = false
        private var protectedHistoryIndex: Int?

        internal var current: Current? {
            guard let currentSnapshot, let navigationAdmission else { return nil }
            return Current(
                snapshot: currentSnapshot,
                scope: navigationAdmission.scope,
                continuity: navigationAdmission.continuity
            )
        }

        internal var notificationIndex: AccessibilityNotificationCursor {
            notificationIndices.latest
        }

        internal var notifications: [Observation.Notification] {
            history.compactMap { event in
                guard case .notification(let notification) = event else {
                    return nil
                }
                return notification
            }
        }

        internal init(retentionLimit: Int = defaultRetentionLimit) {
            history = Observation.History(retentionLimit: retentionLimit)
        }

        internal mutating func discardCurrentObservation() {
            currentSnapshot = nil
            navigationAdmission = nil
            interfaceTree = .empty
            admittedTripwireSignal = nil
            replacementRequired = true
        }

        internal mutating func invalidateCurrentAdmission() {
            admittedTripwireSignal = nil
        }

        internal mutating func invalidateAdmissionIfSignalChanged(
            to tripwireSignal: TheTripwire.TripwireSignal
        ) {
            guard let admittedTripwireSignal,
                  admittedTripwireSignal != tripwireSignal
            else { return }
            invalidateCurrentAdmission()
        }

        internal func admittedObservation(
            scope: SemanticObservationScope,
            after historyIndex: Int?
        ) -> Result<Current?, Observation.History.ReadError> {
            guard admittedTripwireSignal != nil,
                  let current,
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
            after boundary: HistoryBoundary
        ) -> Observation.Evidence {
            history.evidence(
                in: boundary.historyIndex..<history.endIndex,
                baseline: boundary.baseline,
                current: currentSnapshot
            )
        }

        internal func observationBoundary(
            scope: SemanticObservationScope
        ) -> HistoryBoundary {
            let baseline: Observation.Snapshot?
            switch admittedObservation(scope: scope, after: nil) {
            case .success(let current):
                baseline = current?.snapshot
            case .failure:
                baseline = nil
            }
            return HistoryBoundary(
                baseline: baseline,
                historyIndex: history.endIndex
            )
        }

        internal mutating func commitObservation(
            _ admission: Observation.Admission
        ) -> Observation.Publication {
            let notificationRead = notificationRead(for: admission.notificationAdmission)
            let notifications = notificationRead.notifications
            let previousTree = interfaceTree
            let comparedTree: InterfaceTree
            switch admission.scope {
            case .visible:
                comparedTree = previousTree.updatingViewport(with: admission.tree)
            case .discovery:
                comparedTree = admission.discoveryCommitPolicy == .replaceInterface
                    ? admission.tree
                    : previousTree.merging(admission.tree)
            }
            let candidateTree = switch admission.lineage {
            case .resting:
                comparedTree
            case .viewportMovement:
                previousTree.merging(admission.tree)
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
                switch $0.kind {
                case .elementChanged, .elementUpdate:
                    true
                case .screenChanged, .announcement, .unknown:
                    false
                }
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
                let changed = currentSnapshot.map {
                    !$0.hasSameObservedState(
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
                continuity: continuity
            )
            next.currentSnapshot = snapshot
            next.navigationAdmission = NavigationAdmission(
                scope: admission.scope,
                continuity: continuity
            )
            next.interfaceTree = nextTree
            next.notificationIndices[notificationRead.lane] = notifications.through
            next.scopedScreenChangedSequence = notifications.scopedScreenChangedThrough
            next.replacementRequired = false
            next.admittedTripwireSignal = admission.tripwireSignal
            self = next
            return Observation.Publication(
                current: current,
                historyRange: historyRange,
                events: events
            )
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

#endif // DEBUG
#endif // canImport(UIKit)
