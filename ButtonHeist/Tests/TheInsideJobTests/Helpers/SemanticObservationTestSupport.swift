#if canImport(UIKit)
@testable import TheInsideJob

extension Observation.Stream {
    @discardableResult
    func commitVisibleObservationForTesting(
        _ observation: InterfaceObservation,
        notificationBatch: AccessibilityNotificationBatch? = nil,
        notificationIdentityObservation: InterfaceObservation? = nil
    ) async -> Observation.SnapshotEvent {
        let outcome = await commitSettledVisibleObservation(
            .admittedForTesting(observation, tripwireSignal: currentTripwireSignal(), lineage: .resting),
            notificationBatch: notificationBatch,
            notificationIdentityObservation: notificationIdentityObservation
        )
        guard case .delivered(let event) = outcome else {
            preconditionFailure("Test observation was superseded before publication")
        }
        return event
    }

    func commitVisibleObservationOutcomeForTesting(
        _ observation: InterfaceObservation,
        notificationBatch: AccessibilityNotificationBatch? = nil
    ) async -> Observation.PublicationOutcome {
        await commitSettledVisibleObservation(
            .admittedForTesting(observation, tripwireSignal: currentTripwireSignal(), lineage: .resting),
            notificationBatch: notificationBatch
        )
    }

    @discardableResult
    func commitVisibleObservationAfterViewportMovementForTesting(
        _ observation: InterfaceObservation,
        notificationBatch: AccessibilityNotificationBatch? = nil,
        notificationIdentityObservation: InterfaceObservation? = nil
    ) async -> Observation.SnapshotEvent {
        let outcome = await commitSettledVisibleObservation(
            .admittedForTesting(
                observation,
                tripwireSignal: currentTripwireSignal(),
                lineage: .viewportMovement
            ),
            notificationBatch: notificationBatch,
            notificationIdentityObservation: notificationIdentityObservation
        )
        guard case .delivered(let event) = outcome else {
            preconditionFailure("Test observation was superseded before publication")
        }
        return event
    }

    @discardableResult
    func commitDiscoveryObservationForTesting(
        _ observation: InterfaceObservation,
        notificationBatch: AccessibilityNotificationBatch? = nil
    ) async -> Observation.SnapshotEvent {
        let outcome = await commitSettledDiscoveryObservation(
            .admittedForTesting(observation, tripwireSignal: currentTripwireSignal(), lineage: .resting),
            notificationBatch: notificationBatch
        )
        guard case .delivered(let event) = outcome else {
            preconditionFailure("Test observation was superseded before publication")
        }
        return event
    }

    @discardableResult
    func commitDiscoveryObservationAfterViewportMovementForTesting(
        _ observation: InterfaceObservation,
        notificationBatch: AccessibilityNotificationBatch? = nil
    ) async -> Observation.SnapshotEvent {
        let outcome = await commitSettledDiscoveryObservation(
            .admittedForTesting(
                observation,
                tripwireSignal: currentTripwireSignal(),
                lineage: .viewportMovement
            ),
            notificationBatch: notificationBatch
        )
        guard case .delivered(let event) = outcome else {
            preconditionFailure("Test observation was superseded before publication")
        }
        return event
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
}

extension TheTripwire {
    /// Waits until a window installed just now has been read.
    ///
    /// A window is laid out by the time it is installed, so what is left to
    /// wait for is the pulse taking a reading of it — which is a fact the
    /// tripwire states. Counting frames names a number instead, and the number
    /// is a guess about how long a machine takes; the busier the machine, the
    /// worse the guess, which is why fixed counts fail under load and not at a
    /// desk. The timeout is the one thing allowed to be a duration, because a
    /// reading that never comes has to end the test rather than hang it.
    func awaitObservedWindow() async {
        _ = await waitForNextTick(timeout: .seconds(2), demand: .immediate)
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
                await vault.invalidateSettledObservationFromTripwire()
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

@MainActor
final class ObservationCommitFixture {
    private let continuation: AsyncStream<Void>.Continuation
    private let producer: Task<Void, Never>

    init(
        stream: Observation.Stream,
        observations: [InterfaceObservation],
        afterCommit: @escaping @MainActor () -> Void
    ) {
        let (signal, continuation) = AsyncStream<Void>.makeStream(
            bufferingPolicy: .bufferingNewest(1)
        )
        self.continuation = continuation
        producer = Task {
            for await _ in signal {
                for observation in observations {
                    await stream.commitVisibleObservationForTesting(observation)
                }
                afterCommit()
                break
            }
        }
    }

    func signal() {
        continuation.yield()
        continuation.finish()
    }

    func wait() async {
        await producer.value
    }

    deinit {
        continuation.finish()
        producer.cancel()
    }
}
#endif
