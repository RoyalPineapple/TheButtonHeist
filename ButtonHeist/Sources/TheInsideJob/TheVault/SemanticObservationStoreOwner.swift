#if canImport(UIKit)
#if DEBUG

extension TheVault {
    @MainActor
    internal final class StateOwner {
        private var state: State

        internal init(state: State = State()) {
            self.state = state
        }

        internal func current() async -> State.Current? {
            state.current
        }

        internal func notificationIndex() async -> AccessibilityNotificationCursor {
            state.notificationIndex
        }

        internal func historyEndIndex() async -> Int {
            state.history.endIndex
        }

        internal func notifications() -> [Observation.Notification] {
            state.notifications
        }

        internal func scopedScreenChangedSequence() async -> UInt64 {
            state.scopedScreenChangedSequence
        }

        internal var interfaceTree: InterfaceTree {
            state.interfaceTree
        }

        internal func discardCurrentObservation() async {
            state.discardCurrentObservation()
        }

        internal func invalidateCurrentAdmission() async {
            state.invalidateCurrentAdmission()
        }

        internal func invalidateAdmissionIfSignalChanged(to signal: TheTripwire.TripwireSignal) async {
            state.invalidateAdmissionIfSignalChanged(to: signal)
        }

        internal func admittedObservation(
            scope: SemanticObservationScope,
            after historyIndex: Int?
        ) async -> Result<State.Current?, Observation.History.ReadError> {
            state.admittedObservation(scope: scope, after: historyIndex)
        }

        internal func current(
            after historyIndex: Int?,
            scope: SemanticObservationScope
        ) async -> Result<State.Current?, Observation.History.ReadError> {
            state.current(after: historyIndex, scope: scope)
        }

        internal func events(
            after historyIndex: Int
        ) async -> Result<[Observation.Event], Observation.History.ReadError> {
            do {
                return .success(Array(
                    try state.history.events(after: historyIndex)
                ))
            } catch {
                return .failure(error)
            }
        }

        internal func evidence(
            after boundary: State.HistoryBoundary
        ) async -> Observation.Evidence {
            state.evidence(after: boundary)
        }

        internal func observationBoundary(
            scope: SemanticObservationScope
        ) async -> State.HistoryBoundary {
            state.observationBoundary(scope: scope)
        }

        internal func commitAdmission(
            _ admission: Observation.Admission
        ) async -> Observation.Publication {
            state.commitObservation(admission)
        }

        internal func protectHistory(from index: Int) async {
            state.protectHistory(from: index)
        }

        internal func releaseHistory(from index: Int) async {
            state.releaseHistory(from: index)
        }

        internal func reset(retentionLimit: Int = State.defaultRetentionLimit) async {
            state = State(retentionLimit: retentionLimit)
        }
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
