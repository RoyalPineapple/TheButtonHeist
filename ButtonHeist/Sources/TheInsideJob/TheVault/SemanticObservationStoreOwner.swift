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

        internal func latestSettleFailureDiagnostic() async -> String? {
            state.settleFailureDiagnostic
        }

        internal func notificationIndex() async -> AccessibilityNotificationCursor {
            state.notificationIndex
        }

        internal func historyEndIndex() async -> Int {
            state.history.endIndex
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

        internal func discardIfSignalChanged(to signal: TheTripwire.TripwireSignal) async {
            state.discardIfSignalChanged(to: signal)
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
            in range: Range<Int>,
            baseline: Observation.Snapshot?
        ) async -> Observation.Evidence {
            state.evidence(in: range, baseline: baseline)
        }

        internal func readAdmission(
            _ admission: Observation.Admission
        ) async -> Observation.Publication {
            state.readObservation(admission)
        }

        internal func protectHistory(from index: Int) async {
            state.protectHistory(from: index)
        }

        internal func releaseHistory(from index: Int) async {
            state.releaseHistory(from: index)
        }

        internal func recordSettleFailure(_ diagnostic: String?) async {
            state.recordSettleFailure(diagnostic)
        }

        internal func reset(retentionLimit: Int = State.defaultRetentionLimit) async {
            state = State(retentionLimit: retentionLimit)
        }
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
