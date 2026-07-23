#if canImport(UIKit)
#if DEBUG

/// Subscription scope and active cadence demand for semantic observation.
struct SemanticObservationScopePressure {
    private var nextSubscriptionID: UInt64 = 0
    private var subscriptions: [UInt64: SemanticObservationScope] = [:]

    private var nextActiveDemandID: UInt64 = 0
    private var activeObservationDemands: [UInt64: SemanticObservationDemand.Purpose] = [:]

    var activeDemandCount: Int {
        activeObservationDemands.count
    }

    var demandState: SemanticObservationDemandState {
        guard let purpose = activeObservationDemands.values.max() else {
            return .idle
        }
        return .active(purpose)
    }

    var hasActiveDemand: Bool {
        if case .active = demandState { true } else { false }
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

    mutating func addActiveDemand(
        for purpose: SemanticObservationDemand.Purpose
    ) -> UInt64 {
        let id = nextActiveDemandID
        nextActiveDemandID += 1
        activeObservationDemands[id] = purpose
        return id
    }

    mutating func removeActiveDemand(_ id: UInt64) {
        activeObservationDemands[id] = nil
    }

    func subscribedObservationScope() -> SemanticObservationScope {
        subscriptions.values.max() ?? .visible
    }
}

enum SemanticObservationDemandState: Sendable, Equatable {
    case idle
    case active(SemanticObservationDemand.Purpose)

    var samplesSemantics: Bool {
        self == .active(.observation)
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
