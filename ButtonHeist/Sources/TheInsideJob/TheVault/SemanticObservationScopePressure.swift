#if canImport(UIKit)
#if DEBUG

/// Subscription and active-demand scope pressure for semantic observation.
struct SemanticObservationScopePressure {
    private var nextSubscriptionID: UInt64 = 0
    private var subscriptions: [UInt64: SemanticObservationScope] = [:]

    private var nextActiveDemandID: UInt64 = 0
    private var activeObservationDemands: [UInt64: SemanticObservationScope] = [:]

    var activeDemandCount: Int {
        activeObservationDemands.count
    }

    var demandState: SemanticObservationDemandState {
        activeObservationDemands.isEmpty ? .idle : .active
    }

    var hasActiveDemand: Bool {
        demandState == .active
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

    mutating func addActiveDemand(scope: SemanticObservationScope) -> UInt64 {
        let id = nextActiveDemandID
        nextActiveDemandID += 1
        activeObservationDemands[id] = scope
        return id
    }

    mutating func removeActiveDemand(_ id: UInt64) {
        activeObservationDemands[id] = nil
    }

    func subscribedObservationScope() -> SemanticObservationScope {
        max(
            subscriptions.values.max() ?? .visible,
            activeObservationDemands.values.max() ?? .visible
        )
    }
}

enum SemanticObservationDemandState: Sendable, Equatable {
    case idle
    case active
}

#endif // DEBUG
#endif // canImport(UIKit)
