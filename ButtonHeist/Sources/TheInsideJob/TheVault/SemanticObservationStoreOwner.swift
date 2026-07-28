#if canImport(UIKit)
#if DEBUG

extension Observation {
    internal actor StoreOwner {
        private var store: Store

        internal init(store: Store = Store()) {
            self.store = store
        }

        internal func latestReadEvent() -> SnapshotEvent? {
            store.latestReadEvent
        }

        internal func latestReadSnapshot() -> Snapshot? {
            store.latestReadSnapshot
        }

        internal func latestReadMoment() -> Moment? {
            store.latestReadMoment
        }

        internal func latestSettleFailureDiagnostic() -> String? {
            store.settleFailureDiagnostic
        }

        internal func notificationIndex() -> AccessibilityNotificationCursor {
            store.notificationIndex
        }

        internal func sequence() -> SettledObservationSequence {
            store.sequence
        }

        internal func scopedScreenChangedSequence() -> UInt64 {
            store.scopedScreenChangedSequence
        }

        internal func interfaceTree() -> InterfaceTree {
            store.interfaceTree
        }

        internal func discardCurrentObservation() {
            store.discardCurrentObservation()
        }

        internal func admittedObservation(
            scope: SemanticObservationScope,
            after sequence: SettledObservationSequence?
        ) -> Store.AdmittedObservation? {
            store.admittedObservation(scope: scope, after: sequence)
        }

        internal func readSnapshot(
            since moment: Moment?,
            scope: SemanticObservationScope
        ) -> SnapshotRead {
            store.readSnapshot(since: moment, scope: scope)
        }

        internal func latestMoment(scope: SemanticObservationScope) -> Moment? {
            store.latestMoment(scope: scope)
        }

        internal func moment(
            scope: SemanticObservationScope,
            at sequence: SettledObservationSequence
        ) -> Moment? {
            store.moment(scope: scope, at: sequence)
        }

        internal func settledWaitBaseline(
            scope: SemanticObservationScope,
            after sequence: SettledObservationSequence?
        ) -> SettledWaitBaseline {
            if let sequence {
                return SettledWaitBaseline(
                    requiredSequence: sequence,
                    moment: store.moment(scope: scope, at: sequence)
                )
            }
            let moment = store.latestMoment(scope: scope)
            return SettledWaitBaseline(
                requiredSequence: moment?.sequence,
                moment: moment
            )
        }

        internal func readLog<Value: Sendable>(
            _ read: @Sendable (Log) -> Value
        ) -> Value {
            read(store.log)
        }

        /// Reads the admission and returns the ticks it minted, in order.
        ///
        /// The order is the whole contract: a boundary's departure, identity and
        /// arrival are three moments, and the caller puts them into the pipe one
        /// at a time as they stand here. When they get there is not part of it.
        internal func readAdmission(
            _ admission: Admission
        ) throws -> (read: Store.ReadObservation, ticks: [Tick]) {
            var ticks: [Tick] = []
            let read = try store.readObservation(admission) { ticks.append($0) }
            return (read, ticks)
        }

        internal func settlementDidArm(at moment: Moment) {
            store.settlementDidArm(at: moment)
        }

        internal func settlementDidFinish(at moment: Moment) {
            store.settlementDidFinish(at: moment)
        }

        internal func recordSettleFailure(_ diagnostic: String?) {
            store.recordSettleFailure(diagnostic)
        }

        internal func reset(retentionLimit: Int = Store.defaultRetentionLimit) {
            store = Store(retentionLimit: retentionLimit)
        }
    }
}

extension Observation.StoreOwner {
    internal struct SettledWaitBaseline: Sendable {
        internal let requiredSequence: SettledObservationSequence?
        internal let moment: Observation.Moment?
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
