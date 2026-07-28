#if canImport(UIKit)
#if DEBUG

extension TheVault {
    internal actor StateOwner {
        private var state: State

        internal init(state: State = State()) {
            self.state = state
        }

        internal func current() -> State.Current? {
            state.current
        }

        internal func latestSnapshot() -> Observation.Snapshot? {
            state.current?.snapshot
        }

        internal func latestSettleFailureDiagnostic() -> String? {
            state.settleFailureDiagnostic
        }

        internal func notificationIndex() -> AccessibilityNotificationCursor {
            state.notificationIndex
        }

        internal func sequence() -> SettledObservationSequence {
            state.sequence
        }

        internal func historyEndIndex() -> Int {
            state.history.endIndex
        }

        internal func scopedScreenChangedSequence() -> UInt64 {
            state.scopedScreenChangedSequence
        }

        internal func interfaceTree() -> InterfaceTree {
            state.interfaceTree
        }

        internal func discardCurrentObservation() {
            state.discardCurrentObservation()
        }

        internal func invalidateCurrentAdmission() {
            state.invalidateCurrentAdmission()
        }

        internal func discardIfSignalChanged(to signal: TheTripwire.TripwireSignal) {
            state.discardIfSignalChanged(to: signal)
        }

        internal func admittedObservation(
            scope: SemanticObservationScope,
            after sequence: SettledObservationSequence?
        ) -> State.AdmittedObservation? {
            state.admittedObservation(scope: scope, after: sequence)
        }

        internal func current(
            after historyIndex: Int?,
            scope: SemanticObservationScope
        ) -> Result<State.Current?, Observation.History.ReadError> {
            state.current(after: historyIndex, scope: scope)
        }

        internal func current(
            scope: SemanticObservationScope,
            at sequence: SettledObservationSequence
        ) -> State.Current? {
            state.current(scope: scope, at: sequence)
        }

        internal func baseline(
            scope: SemanticObservationScope,
            after sequence: SettledObservationSequence?
        ) -> ObservationBaseline {
            if let sequence,
               let current = state.current(scope: scope, at: sequence) {
                return ObservationBaseline(
                    requiredSequence: sequence,
                    historyIndex: state.history.endIndex,
                    snapshot: current.snapshot
                )
            }
            let current = state.current.flatMap {
                $0.scope.canFulfill(scope) ? $0 : nil
            }
            return ObservationBaseline(
                requiredSequence: current?.sequence ?? sequence,
                historyIndex: state.history.endIndex,
                snapshot: current?.snapshot
            )
        }

        internal func events(
            after historyIndex: Int
        ) -> Result<[Observation.Event], Observation.History.ReadError> {
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
        ) -> Observation.Evidence {
            state.evidence(in: range, baseline: baseline)
        }

        internal func readAdmission(
            _ admission: Observation.Admission
        ) -> State.ReadObservation {
            state.readObservation(admission)
        }

        internal func protectHistory(from index: Int) {
            state.protectHistory(from: index)
        }

        internal func releaseHistory(from index: Int) {
            state.releaseHistory(from: index)
        }

        internal func recordSettleFailure(_ diagnostic: String?) {
            state.recordSettleFailure(diagnostic)
        }

        internal func reset(retentionLimit: Int = State.defaultRetentionLimit) {
            state = State(retentionLimit: retentionLimit)
        }
    }
}

extension TheVault.StateOwner {
    internal struct ObservationBaseline: Sendable {
        internal let requiredSequence: SettledObservationSequence?
        internal let historyIndex: Int
        internal let snapshot: Observation.Snapshot?
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
