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

    private func makeGetaway() async -> (TheGetaway, TheMuscle, ServerTransport) {
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
        await getaway.wireTransport(transport)
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
        let (getaway, muscle, transport) = await makeGetaway()
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
        // Reproduce the production path: SimpleSocketServer invokes these callbacks off-main-actor on its network queue, not from MainActor.
        // swiftlint:disable:next agent_no_task_detached
        await Task.detached {
            callbacks.onClientConnected?(1, "192.168.1.1")
            callbacks.onUnauthenticatedData?(1, helloData) { _ in }
        }.value

        // Wait for the consumer task to drain both events. The for-await loop
        // runs each `handleTransportEvent` to completion before pulling the
        // next; we poll the observable side effect rather than counting hops
        // because XCTest's main-actor scheduling can interleave variably.
        try await waitFor {
            let validated = await muscle.helloValidatedClients
            return validated.contains(1)
        }

        let validated = await muscle.helloValidatedClients
        XCTAssertTrue(
            validated.contains(1),
            "Client 1 should have transitioned to helloValidated, which means clientConnected was observed before the dataReceived/clientHello"
        )
    }

    /// Under the AsyncStream consumer, a burst of events yielded back-to-back
    /// is processed in FIFO order. This guards against any future regression
    /// where someone reintroduces a per-event `Task` and reopens the race.
    func testEventOrderingIsFIFOForBurstYield() async throws {
        let (getaway, muscle, transport) = await makeGetaway()
        _ = getaway

        let helloEnvelope = RequestEnvelope(message: .clientHello)
        let helloData = try JSONEncoder().encode(helloEnvelope)

        let callbacks = transport.makeCallbacks()
        // Three clients connect and immediately send hello. Each pair must
        // process in order or the helloValidated transition is dropped.
        // Drive from off-main to mirror the production network queue.
        // Detached intentionally simulates SimpleSocketServer's off-main-actor callback dispatch.
        // swiftlint:disable:next agent_no_task_detached
        await Task.detached {
            for clientId in 1...3 {
                callbacks.onClientConnected?(clientId, "addr-\(clientId)")
                callbacks.onUnauthenticatedData?(clientId, helloData) { _ in }
            }
        }.value

        try await waitFor {
            let validated = await muscle.helloValidatedClients
            return validated == Set([1, 2, 3])
        }

        let validated = await muscle.helloValidatedClients
        XCTAssertEqual(
            validated,
            Set([1, 2, 3]),
            "All three clients must reach helloValidated; if any clientConnected lost its race against its dataReceived, that client would be missing"
        )
    }

    // MARK: - Recording auto-finish

    /// Regression: when a recording auto-finishes (max duration, file-size
    /// cap, inactivity) there is no `stop_recording` waiter on the server.
    /// Earlier code only broadcast `.recordingStopped`, so the originating
    /// `start_recording` caller — parked on `waitForRecording` — never saw
    /// the payload and timed out. The fix broadcasts `.recording(payload)`
    /// in addition to `.recordingStopped`. We assert via state that the
    /// auto-finish path runs (no pending response is consumed; the result
    /// is stashed in `completedRecording` for any later collection too).
    func testAutoFinishWithoutPendingStopBroadcastsRecording() async {
        let (getaway, _, _) = await makeGetaway()
        XCTAssertNil(getaway.pendingRecordingResponse)
        if case .none = getaway.completedRecording {} else {
            XCTFail("Expected .none completedRecording before deliver, got \(getaway.completedRecording)")
        }

        let payload = RecordingPayload(
            videoData: "AAAA",
            width: 100,
            height: 200,
            duration: 5.0,
            frameCount: 40,
            fps: 8,
            startTime: Date(),
            endTime: Date(),
            stopReason: .maxDuration
        )
        await getaway.deliverRecordingResult(.success(payload))

        XCTAssertNil(getaway.pendingRecordingResponse, "Auto-finish must not leave a stale pending response")
        guard case .succeeded(let captured) = getaway.completedRecording else {
            XCTFail("Auto-finish must keep the result in completedRecording for later collection")
            return
        }
        XCTAssertEqual(captured.frameCount, 40)
        XCTAssertEqual(captured.stopReason, .maxDuration)
    }

    /// Regression sibling: when there *is* a pending stop waiter the
    /// payload must reach that waiter directly via `respond` rather than
    /// broadcasting. The pending slot must clear and the pending requestId
    /// must echo back to the originator.
    func testStopRecordingWaiterReceivesRecordingDirectly() async {
        let (getaway, _, _) = await makeGetaway()

        var receivedData: Data?
        getaway.pendingRecordingResponse = (
            requestId: "stop-1",
            respond: { data in receivedData = data }
        )

        let payload = RecordingPayload(
            videoData: "AAAA",
            width: 100, height: 200,
            duration: 1.0, frameCount: 8, fps: 8,
            startTime: Date(), endTime: Date(),
            stopReason: .manual
        )
        await getaway.deliverRecordingResult(.success(payload))

        XCTAssertNil(getaway.pendingRecordingResponse, "Pending response must clear after delivery")
        let unwrappedData = try? XCTUnwrap(receivedData)
        XCTAssertNotNil(unwrappedData, "Pending stop waiter must receive a wire response")

        if let unwrappedData {
            // Strip trailing newline if present (transport convention).
            let trimmed = unwrappedData.last == 0x0A
                ? unwrappedData.dropLast()
                : unwrappedData
            let envelope = try? JSONDecoder().decode(ResponseEnvelope.self, from: trimmed)
            XCTAssertEqual(envelope?.requestId, "stop-1")
            guard case .recording(let echo)? = envelope?.message else {
                XCTFail("Expected .recording payload, got \(String(describing: envelope?.message))")
                return
            }
            XCTAssertEqual(echo.frameCount, 8)
        }
    }

    // MARK: - start_recording TOCTOU

    /// Regression: `handleStartRecording` reads `recordingPhase`, awaits
    /// stakeout setup, then writes the phase. Without a synchronous claim
    /// before the first await, a second `start_recording` reached the actor
    /// during that gap, observed `.idle`, and built a second TheStakeout —
    /// orphaning one of them. The fix adds a transient `.starting` sentinel
    /// written before the first await so the second caller is rejected.
    func testConcurrentStartRecordingRejectsSecond() async {
        let (getaway, _, _) = await makeGetaway()

        // Drive two start_recording calls in tight succession from the same
        // MainActor context. Both reach `handleStartRecording` before either
        // completes: the first claims `.starting` synchronously and yields at
        // its first await; the second observes `.starting` and must reject.
        final class ResponseBox: @unchecked Sendable { // swiftlint:disable:this agent_unchecked_sendable_no_comment
            // Accessed only from the @MainActor test harness; the @Sendable
            // closure hop is the cost of crossing the actor-isolated stakeout
            // setup. NSLock guards the array.
            private var storage: [Data] = []
            private let lock = NSLock()
            func append(_ data: Data) { lock.withLock { storage.append(data) } }
            var all: [Data] { lock.withLock { storage } }
        }
        let box = ResponseBox()
        let collect: @Sendable (Data) -> Void = { data in box.append(data) }

        async let first: Void = getaway.handleStartRecording(RecordingConfig(), requestId: "a", respond: collect)
        async let second: Void = getaway.handleStartRecording(RecordingConfig(), requestId: "b", respond: collect)
        _ = await (first, second)
        let responses = box.all

        // Exactly one of the two requests must be the rejection. We cannot
        // assert which because either ordering of the two async-let starts
        // is valid — but the rejection's payload should be a ServerError
        // carrying our "in progress" wording. The successful caller may have
        // failed at the AVAssetWriter step (no real screen), which surfaces
        // as a different .error — either way exactly one rejection should
        // mention "start already in progress".
        let envelopes = responses.compactMap { data -> ResponseEnvelope? in
            let trimmed = data.last == 0x0A ? data.dropLast() : data
            return try? JSONDecoder().decode(ResponseEnvelope.self, from: trimmed)
        }
        let rejections = envelopes.compactMap { envelope -> String? in
            guard case .error(let serverError) = envelope.message else { return nil }
            return serverError.message
        }
        XCTAssertTrue(
            rejections.contains { $0.contains("start already in progress") },
            "Second concurrent start_recording must be rejected with the 'starting' sentinel error. Got rejections: \(rejections)"
        )

        // And after both calls complete, the phase must be either `.recording`
        // (first succeeded) or `.idle` (first rolled back on failure) — but
        // never `.starting` (the sentinel must always be cleared).
        switch getaway.recordingPhase {
        case .starting:
            XCTFail("recordingPhase must not linger in .starting after both calls return")
        case .idle, .recording:
            break
        }
    }

    /// `.starting` is an internal sentinel; if `startRecording` throws inside
    /// `TheStakeout`, the phase must roll back to `.idle` so a subsequent
    /// caller can proceed. We exercise the rollback indirectly by observing
    /// that two sequential `handleStartRecording` calls in a no-screen
    /// environment never leave the phase stuck.
    func testFailedStartRollsBackToIdle() async {
        let (getaway, _, _) = await makeGetaway()

        await getaway.handleStartRecording(RecordingConfig(), requestId: "a") { _ in }
        // If the first call succeeded (we ended in .recording), let it stay —
        // the assertion below still covers the "no stale .starting" case.
        if case .recording = getaway.recordingPhase {
            return
        }
        guard case .idle = getaway.recordingPhase else {
            XCTFail("Phase must be .idle after a failed start (or .recording on success), got \(getaway.recordingPhase)")
            return
        }
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
        condition: @MainActor () async -> Bool
    ) async throws {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if await condition() { return }
            // Polls a MainActor-bound condition; no signal to await on.
            // swiftlint:disable:next agent_test_task_sleep
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTFail("waitFor timed out after \(timeout)")
    }
}
#endif // canImport(UIKit)
