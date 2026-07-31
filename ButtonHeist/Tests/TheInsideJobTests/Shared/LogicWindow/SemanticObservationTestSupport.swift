#if canImport(UIKit)
@testable import TheInsideJob

extension Observation.Stream {
    @discardableResult
    func commitVisibleObservationForTesting(
        _ observation: InterfaceObservation
    ) async -> Observation.Publication {
        await commitObservationCycleForTesting(
            observation,
            scope: .visible,
            lineage: .resting
        )
    }

    @discardableResult
    func commitVisibleObservationForTesting(
        _ observation: InterfaceObservation,
        notificationBatch: AccessibilityNotificationBatch
    ) async -> Observation.Publication {
        requireCommittedObservation(
            commitObservation(
                .admitCaptured(observation, tripwireSignal: currentTripwireSignal(), lineage: .resting),
                scope: .visible,
                notificationBatch: notificationBatch
            )
        )
    }

    @discardableResult
    func commitDiscoveryObservationForTesting(
        _ observation: InterfaceObservation
    ) async -> Observation.Publication {
        await commitObservationCycleForTesting(
            observation,
            scope: .discovery,
            lineage: .resting
        )
    }

    @discardableResult
    func commitDiscoveryObservationForTesting(
        _ observation: InterfaceObservation,
        notificationBatch: AccessibilityNotificationBatch
    ) async -> Observation.Publication {
        requireCommittedObservation(
            commitObservation(
                .admitCaptured(observation, tripwireSignal: currentTripwireSignal(), lineage: .resting),
                scope: .discovery,
                notificationBatch: notificationBatch
            )
        )
    }

    @discardableResult
    func commitDiscoveryObservationAfterViewportMovementForTesting(
        _ observation: InterfaceObservation
    ) async -> Observation.Publication {
        await commitObservationCycleForTesting(
            observation,
            scope: .discovery,
            lineage: .viewportMovement
        )
    }

    private func commitObservationCycleForTesting(
        _ observation: InterfaceObservation,
        scope: SemanticObservationScope,
        lineage: ScreenLineage
    ) async -> Observation.Publication {
        let claim = vault.accessibilityNotifications.freezeObservationCycleClaim()
        let admitted = CommittableInterfaceObservation.admitCaptured(
            observation,
            tripwireSignal: currentTripwireSignal(),
            lineage: lineage
        )
        let publication = requireCommittedObservation(
            commitObservation(
                admitted,
                scope: scope,
                notificationBatch: claim.batch
            )
        )
        precondition(
            claim.acknowledgeObservationCycle(),
            "A test observation cycle must acknowledge its exact notification claim"
        )
        return publication
    }

    private func requireCommittedObservation(
        _ result: Result<Observation.Publication, Observation.CaptureFailure>
    ) -> Observation.Publication {
        switch result {
        case .success(let publication):
            publication
        case .failure(let failure):
            preconditionFailure("Test observation was rejected: \(failure.diagnostic)")
        }
    }
}

extension TheVault {
    func installObservationForTesting(_ observation: InterfaceObservation) async {
        await semanticObservationStream.commitVisibleObservationForTesting(observation)
    }
}

@MainActor
final class VisibleObservationSourceFixture {
    private enum Source {
        case liveCapture
        case observation(InterfaceObservation?)
    }

    private var source: Source = .liveCapture
    private var unavailableCapturesRemaining = 0
    private(set) var captureCount = 0

    var observation: InterfaceObservation? {
        get {
            guard case .observation(let observation) = source else { return nil }
            return observation
        }
        set {
            source = .observation(newValue)
        }
    }

    func capture(from vault: TheVault) -> InterfaceObservation? {
        captureCount += 1
        if unavailableCapturesRemaining > 0 {
            unavailableCapturesRemaining -= 1
            return nil
        }
        switch source {
        case .liveCapture:
            return TheVault.captureVisibleObservation(from: vault)
        case .observation(let observation):
            return observation
        }
    }

    func useLiveCapture() {
        source = .liveCapture
    }

    func failNextCapture() {
        unavailableCapturesRemaining = 1
    }
}

@MainActor
final class TripwireInvalidationFixture {
    private let continuation: AsyncStream<Void>.Continuation
    private let invalidation: Task<Void, Never>

    init(vault: TheVault) {
        let (stream, continuation) = AsyncStream<Void>.makeStream(
            bufferingPolicy: .bufferingNewest(1)
        )
        self.continuation = continuation
        invalidation = Task {
            for await _ in stream {
                vault.semanticObservationStream.invalidateCurrentAdmission()
                break
            }
        }
    }

    func signal() {
        continuation.yield()
        continuation.finish()
    }

    func wait() async {
        await invalidation.value
    }

    deinit {
        continuation.finish()
        invalidation.cancel()
    }
}

#endif
