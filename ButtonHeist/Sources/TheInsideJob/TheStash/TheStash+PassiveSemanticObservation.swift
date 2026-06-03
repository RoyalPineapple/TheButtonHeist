#if canImport(UIKit)
#if DEBUG
import Foundation

extension TheStash {
    typealias DiscoveryObservation = SemanticObservationStream.DiscoveryObservation

    func startPassiveSemanticObservation(discovery: @escaping DiscoveryObservation) {
        semanticObservationStream.start(discovery: discovery)
    }

    func stopPassiveSemanticObservation() {
        semanticObservationStream.stop()
    }

    func subscribeSemanticObservation(scope: SemanticObservationScope) -> SemanticObservationSubscription {
        semanticObservationStream.subscribe(scope: scope)
    }

    func removeSemanticObservationSubscription(_ id: UInt64) {
        semanticObservationStream.removeSubscription(id)
    }

    func currentSubscribedObservationScope() -> SemanticObservationScope {
        semanticObservationStream.currentSubscribedScope()
    }

    func settledSemanticObservationEvent(
        scope: SemanticObservationScope,
        after sequence: UInt64?,
        timeout: Double?
    ) async -> SettledSemanticObservationEvent? {
        await semanticObservationStream.settledEvent(scope: scope, after: sequence, timeout: timeout)
    }

    func markDirtyFromTripwire() {
        semanticObservationStream.markDirtyFromTripwire()
    }

    func markCurrentSemanticObservationSettled(scope: SemanticObservationScope = .visible) {
        semanticObservationStream.markCurrentSettled(scope: scope)
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
