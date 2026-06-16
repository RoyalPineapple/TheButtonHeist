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

    func beginSemanticObservationDemand(scope: SemanticObservationScope) -> SemanticObservationDemand {
        semanticObservationStream.beginActiveObservationDemand(scope: scope)
    }

    func subscribedObservationScope() -> SemanticObservationScope {
        semanticObservationStream.subscribedObservationScope()
    }

    func observeSettledSemanticObservation(
        scope: SemanticObservationScope,
        after sequence: UInt64?,
        timeout: Double?
    ) async -> SettledSemanticObservationEvent? {
        await semanticObservationStream.settledEvent(scope: scope, after: sequence, timeout: timeout)
    }

    func observeVisibleSemanticEvidence(timeout: Double?) async -> VisibleSemanticObservationEvidence? {
        await semanticObservationStream.visibleEvidence(timeout: timeout)
    }

    func latestSemanticObservationFailureDiagnostic() -> String? {
        semanticObservationStream.latestSettleFailureDiagnostic
    }

    func invalidateSettledObservationFromTripwire() {
        semanticObservationStream.invalidateLatestSettledObservation()
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
