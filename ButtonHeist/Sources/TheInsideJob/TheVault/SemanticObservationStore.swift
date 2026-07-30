#if canImport(UIKit)
#if DEBUG
import Foundation
import ThePlans
import TheScore

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
        private var notificationCursor = AccessibilityNotificationCursor.origin
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
            notificationCursor
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

        internal mutating func advanceHistoryProtection(
            from index: Int,
            to nextIndex: Int
        ) {
            precondition(
                protectedHistoryIndex == index,
                "Observation history index does not belong to the active reader"
            )
            do {
                _ = try history.events(after: nextIndex)
            } catch {
                preconditionFailure("Advanced protected index is unavailable in observation history")
            }
            protectedHistoryIndex = nextIndex
            history.prune(protectedBy: nextIndex)
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
            let admittedNotifications = admission.notifications.admittedNotifications.filter {
                $0.sequence > notificationCursor.sequence
            }
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
                    notifications: admittedNotifications.map(\.kind),
                    lineage: admission.lineage
                )
            }
            let nextTree = continuity.isReplacement ? admission.tree : candidateTree
            let snapshot = Self.snapshot(
                tree: nextTree,
                admission: admission,
                semanticSignal: admission.tripwireSignal.semanticValue
            )
            let notificationEvents = admittedNotifications.compactMap {
                Observation.Notification(text: $0.text, element: $0.element)
                    .map(Observation.Event.notification)
            }
            let forcesElementChange = Self.forcesElementChange(admittedNotifications)
            let currentEvent: Observation.Event
            let events: [Observation.Event]
            if continuity.isReplacement {
                let departure = Observation.Snapshot(
                    interface: Interface(
                        timestamp: currentSnapshot?.interface.timestamp
                            ?? snapshot.interface.timestamp,
                        tree: []
                    ),
                    context: currentSnapshot?.context ?? .empty
                )
                currentEvent = .elementsChanged(snapshot)
                events = notificationEvents + [
                    .elementsChanged(departure),
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
            next.notificationCursor = AccessibilityNotificationCursor(
                sequence: max(
                    notificationCursor.sequence,
                    admission.notifications.through.sequence
                )
            )
            next.scopedScreenChangedSequence = max(
                scopedScreenChangedSequence,
                admission.notifications.scopedScreenChangedThrough
            )
            next.replacementRequired = false
            next.admittedTripwireSignal = admission.tripwireSignal
            self = next
            return Observation.Publication(
                current: current,
                historyRange: historyRange,
                events: events
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

        private static func forcesElementChange(
            _ notifications: [Observation.AdmittedNotification]
        ) -> Bool {
            notifications.contains {
                switch $0.kind {
                case .layoutChanged, .elementUpdate:
                    true
                case .screenChanged, .announcement, .unknown:
                    false
                }
            }
        }
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
