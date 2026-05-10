#if canImport(UIKit)
import XCTest
import TheScore
@testable import TheInsideJob

/// Integration tests for `TheGetaway`'s transport-event consumption.
///
/// These tests drive the production wiring path: `wireTransport` installs
/// callbacks via `ServerTransport.makeCallbacks()`, those callbacks yield onto
/// the transport's single `AsyncStream<TransportEvent>`, and `TheGetaway`'s
/// long-lived consumer task awaits each event sequentially. The headline
/// motivation is the `clientConnected` → `dataReceived` race that the prior
/// per-event `Task { @MainActor in ... }` bridge could lose.
@MainActor
final class TheGetawayTests: XCTestCase {

    // MARK: - Test Wiring

    private func makeGetaway() -> (TheGetaway, TheMuscle, ServerTransport) {
        let muscle = TheMuscle(explicitToken: "test-token")
        let tripwire = TheTripwire()
        let brains = TheBrains(tripwire: tripwire)
        let identity = TheGetaway.ServerIdentity(
            sessionId: UUID(),
            effectiveInstanceId: "test",
            tlsActive: false
        )
        let getaway = TheGetaway(muscle: muscle, brains: brains, tripwire: tripwire, identity: identity)
        let transport = ServerTransport()
        getaway.wireTransport(transport)
        return (getaway, muscle, transport)
    }

    // MARK: - Ordering

    /// The race fixed by routing transport events through a single
    /// `AsyncStream`: yielding `clientConnected` then immediately `dataReceived`
    /// must result in the connect's side effects being visible *before* the
    /// data event is processed. Under the previous per-event Task bridge, the
    /// two could land on the main actor in either order, so a `clientHello`
    /// arriving on the heels of TCP-ready could be dropped because the muscle
    /// had no record of the client.
    ///
    /// Observable: a `clientHello` from an unknown client is silently ignored
    /// (the `if let phase = clients[clientId]` guard fails and the phase is
    /// never updated). If `clientConnected` ran first, the same `clientHello`
    /// transitions the client to `.helloValidated`, which `helloValidatedClients`
    /// reflects.
    func testClientConnectedIsObservedBeforeDataReceived() async throws {
        let (getaway, muscle, transport) = makeGetaway()
        // The consumer Task captures `self` weakly, so we must retain
        // `getaway` for the lifetime of the test or the for-await loop
        // exits on the very first event.
        _ = getaway

        let helloEnvelope = RequestEnvelope(message: .clientHello)
        let helloData = try JSONEncoder().encode(helloEnvelope)

        // Drive the producer side of the transport's event stream the same way
        // SimpleSocketServer does: from a non-MainActor context, through the
        // callbacks installed by `makeCallbacks()`. This is the production
        // yield path — `SimpleSocketServer` invokes its callbacks on its own
        // network queue, never on @MainActor — and it matches how the bug
        // originally manifested: events arriving from off-main queue racing
        // each other to bridge onto the main actor.
        let callbacks = transport.makeCallbacks()
        await Task.detached {
            callbacks.onClientConnected?(1, "192.168.1.1")
            callbacks.onUnauthenticatedData?(1, helloData) { _ in }
        }.value

        // Wait for the consumer task to drain both events. The for-await loop
        // runs each `handleTransportEvent` to completion before pulling the
        // next; we poll the observable side effect rather than counting hops
        // because XCTest's main-actor scheduling can interleave variably.
        try await waitFor { muscle.helloValidatedClients.contains(1) }

        XCTAssertTrue(
            muscle.helloValidatedClients.contains(1),
            "Client 1 should have transitioned to helloValidated, which means clientConnected was observed before the dataReceived/clientHello"
        )
    }

    /// Under the AsyncStream consumer, a burst of events yielded back-to-back
    /// is processed in FIFO order. This guards against any future regression
    /// where someone reintroduces a per-event `Task` and reopens the race.
    func testEventOrderingIsFIFOForBurstYield() async throws {
        let (getaway, muscle, transport) = makeGetaway()
        _ = getaway

        let helloEnvelope = RequestEnvelope(message: .clientHello)
        let helloData = try JSONEncoder().encode(helloEnvelope)

        let callbacks = transport.makeCallbacks()
        // Three clients connect and immediately send hello. Each pair must
        // process in order or the helloValidated transition is dropped.
        // Drive from off-main to mirror the production network queue.
        await Task.detached {
            for clientId in 1...3 {
                callbacks.onClientConnected?(clientId, "addr-\(clientId)")
                callbacks.onUnauthenticatedData?(clientId, helloData) { _ in }
            }
        }.value

        try await waitFor { muscle.helloValidatedClients == Set([1, 2, 3]) }

        XCTAssertEqual(
            muscle.helloValidatedClients,
            Set([1, 2, 3]),
            "All three clients must reach helloValidated; if any clientConnected lost its race against its dataReceived, that client would be missing"
        )
    }

    // MARK: - Helpers

    /// Wait for the consumer task on `transport.events` to drain queued events.
    ///
    /// Polls a closure that returns true when the expected side effects are
    /// visible. Yielding the main actor between checks lets the consumer's
    /// for-await loop run; polling avoids a fixed sleep that would either
    /// flake or slow the suite.
    private func waitFor(
        timeout: Duration = .seconds(2),
        condition: @MainActor () -> Bool
    ) async throws {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if condition() { return }
            // Polls a MainActor-bound condition; no signal to await on.
            // swiftlint:disable:next agent_test_task_sleep
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTFail("waitFor timed out after \(timeout)")
    }
}
#endif // canImport(UIKit)
