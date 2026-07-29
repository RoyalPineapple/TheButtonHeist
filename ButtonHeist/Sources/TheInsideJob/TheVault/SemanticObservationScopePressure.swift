#if canImport(UIKit)
#if DEBUG

/// Subscription scope and active cadence demand for semantic observation.
struct SemanticObservationScopePressure {
    private var nextSubscriptionID: UInt64 = 0
    private var subscriptions: [UInt64: SemanticObservationScope] = [:]

    private var nextActiveDemandID: UInt64 = 0
    private var activeObservationDemands: Set<UInt64> = []

    var activeDemandCount: Int {
        activeObservationDemands.count
    }

    var hasActiveDemand: Bool {
        !activeObservationDemands.isEmpty
    }

    var demandedObservationScope: SemanticObservationScope? {
        subscriptions.values.max()
            ?? (hasActiveDemand ? .visible : nil)
    }

    mutating func addSubscription(scope: SemanticObservationScope) -> UInt64 {
        let id = nextSubscriptionID
        nextSubscriptionID += 1
        subscriptions[id] = scope
        return id
    }

    mutating func removeSubscription(_ id: UInt64) {
        subscriptions[id] = nil
    }

    mutating func addActiveDemand() -> UInt64 {
        let id = nextActiveDemandID
        nextActiveDemandID += 1
        activeObservationDemands.insert(id)
        return id
    }

    mutating func removeActiveDemand(_ id: UInt64) {
        activeObservationDemands.remove(id)
    }

}

#endif // DEBUG
#endif // canImport(UIKit)
