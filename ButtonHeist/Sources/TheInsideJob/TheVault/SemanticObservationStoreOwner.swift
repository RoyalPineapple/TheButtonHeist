#if canImport(UIKit)
#if DEBUG

extension Observation {
    internal actor StoreOwner {
        private var store: Store
        private var deliveryGeneration = DeliveryGeneration.initial
        private var nextDeliveryOrder: UInt64 = 0
        private var latestDeliveryToken: DeliveryToken?

        internal init(store: Store = Store()) {
            self.store = store
        }

        internal func latestCommittedEvent() -> SnapshotEvent? {
            store.latestCommittedEvent
        }

        internal func latestCommittedSnapshot() -> Snapshot? {
            store.latestCommittedSnapshot
        }

        internal func latestCommittedMoment() -> Moment? {
            store.latestCommittedMoment
        }

        internal func latestSettledObservationInvalidated() -> Bool {
            store.latestSettledObservationInvalidated
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

        @discardableResult
        internal func invalidateCurrentObservation() -> DeliveryGeneration {
            store.invalidateCurrentObservation()
            return advanceDeliveryGeneration()
        }

        @discardableResult
        internal func invalidateIfSignalChanged(
            to signal: TheTripwire.TripwireSignal
        ) -> DeliveryGeneration? {
            guard store.invalidateIfSignalChanged(to: signal) else { return nil }
            return advanceDeliveryGeneration()
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

        internal func commit(_ admission: Admission) throws -> CommittedDelivery {
            let committed = try store.commitObservation(admission)
            nextDeliveryOrder += 1
            let token = DeliveryToken(
                generation: deliveryGeneration,
                order: nextDeliveryOrder
            )
            latestDeliveryToken = token
            return CommittedDelivery(token: token, committed: committed)
        }

        internal func resolveDelivery(
            for token: DeliveryToken,
            readmitting admission: Admission?
        ) throws -> DeliveryResolution {
            if token.generation == deliveryGeneration,
               token.order > 0,
               token.order <= nextDeliveryOrder,
               let latestDeliveryToken {
                return .current(DeliveryAdmission(currentCommitOrder: latestDeliveryToken.order))
            }
            guard token.generation != deliveryGeneration,
                  nextDeliveryOrder == 0,
                  let admission else { return .superseded }
            return .readmitted(try commit(admission))
        }

        internal func settlementDidArm(at moment: Moment) {
            store.settlementDidArm(at: moment)
        }

        internal func settlementDidFinish(at moment: Moment) {
            store.settlementDidFinish(at: moment)
        }

        @discardableResult
        internal func requireReplacement() -> DeliveryGeneration {
            store.requireReplacement()
            return advanceDeliveryGeneration()
        }

        @discardableResult
        internal func clearCurrentInterface() -> DeliveryGeneration {
            store.clearCurrentInterface()
            return advanceDeliveryGeneration()
        }

        internal func recordSettleFailure(_ diagnostic: String?) {
            store.recordSettleFailure(diagnostic)
        }

        @discardableResult
        internal func reset(
            retentionLimit: Int = Store.defaultRetentionLimit
        ) -> DeliveryGeneration {
            store = Store(retentionLimit: retentionLimit)
            return advanceDeliveryGeneration()
        }

        private func advanceDeliveryGeneration() -> DeliveryGeneration {
            deliveryGeneration = deliveryGeneration.advanced()
            nextDeliveryOrder = 0
            latestDeliveryToken = nil
            return deliveryGeneration
        }
    }
}

extension Observation.StoreOwner {
    internal struct DeliveryGeneration: RawRepresentable, Sendable, Equatable, Hashable, Comparable {
        internal static let initial = DeliveryGeneration(rawValue: 0)

        internal let rawValue: UInt64

        fileprivate func advanced() -> DeliveryGeneration {
            DeliveryGeneration(rawValue: rawValue + 1)
        }

        internal static func < (lhs: DeliveryGeneration, rhs: DeliveryGeneration) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }

    internal struct DeliveryToken: Sendable, Equatable, Hashable {
        internal let generation: DeliveryGeneration
        internal let order: UInt64
    }

    internal struct CommittedDelivery: Sendable {
        internal let token: DeliveryToken
        internal let committed: Observation.Store.CommittedObservation
    }

    internal struct DeliveryAdmission: Sendable {
        internal let currentCommitOrder: UInt64
    }

    internal enum DeliveryResolution: Sendable {
        case current(DeliveryAdmission)
        case readmitted(CommittedDelivery)
        case superseded
    }

    internal struct SettledWaitBaseline: Sendable {
        internal let requiredSequence: SettledObservationSequence?
        internal let moment: Observation.Moment?
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
