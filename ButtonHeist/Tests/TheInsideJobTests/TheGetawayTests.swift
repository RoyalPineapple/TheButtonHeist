#if canImport(UIKit)
import XCTest
import UIKit
@testable import AccessibilitySnapshotParser
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

    // swiftlint:disable:next agent_unchecked_sendable_no_comment - Test callback storage is protected by NSLock.
    private final class SentBox: @unchecked Sendable {
        private var storage: [(Data, Int)] = []
        private let lock = NSLock()
        func append(_ data: Data, clientId: Int) { lock.withLock { storage.append((data, clientId)) } }
        var all: [(Data, Int)] { lock.withLock { storage } }
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

    // MARK: - Stale Targeted Actions

    func testLegacyRuntimeSubscriptionMessagesReturnUnsupportedError() async throws {
        let (getaway, _, _) = await makeGetaway()

        for message in [ClientMessage.subscribe, .unsubscribe, .watch(.init(token: "test-token"))] {
            let data = try JSONEncoder().encode(RequestEnvelope(requestId: message.canonicalName, message: message))
            var responseData: Data?

            await getaway.handleClientMessage(1, data: data) { data in
                responseData = data
            }

            let unwrapped = try XCTUnwrap(responseData)
            let trimmed = unwrapped.last == 0x0A ? unwrapped.dropLast() : unwrapped
            let envelope = try JSONDecoder().decode(ResponseEnvelope.self, from: trimmed)
            XCTAssertEqual(envelope.requestId, message.canonicalName)
            guard case .error(let serverError) = envelope.message else {
                return XCTFail("Expected unsupported error for \(message.canonicalName), got \(envelope.message)")
            }
            XCTAssertEqual(serverError.kind, .unsupported)
            XCTAssertTrue(serverError.message.contains("no longer supported"))
        }
    }

    func testStaleTargetedActionAfterScreenChangeReturnsFailureWithDeltaContext() async throws {
        let (getaway, _, _) = await makeGetaway()
        seedScreen(getaway.brains, elements: [("Home", .header, "home_header"), ("Old", .button, "button_old")])
        getaway.brains.recordSentState(viewportHash: 1)
        seedScreen(getaway.brains, elements: [("Settings", .header, "settings_header"), ("New", .button, "button_new")])

        let result = getaway.staleTargetedActionFailure(
            for: .touchTap(.init(elementTarget: .heistId("button_old"))),
            backgroundTrace: screenChangedBackgroundTrace()
        )

        let unwrapped = try XCTUnwrap(result)
        XCTAssertFalse(unwrapped.success)
        XCTAssertEqual(unwrapped.method, .syntheticTap)
        XCTAssertEqual(unwrapped.errorKind, .actionFailed)
        XCTAssertEqual(unwrapped.screenId, "settings")
        XCTAssertTrue(unwrapped.accessibilityDelta?.isScreenChanged == true)
        XCTAssertTrue(unwrapped.message?.contains("target became stale after a screen change") == true)
        XCTAssertTrue(unwrapped.message?.contains("retry against the current interface") == true)
    }

    func testStaleWaitForTargetDoesNotUseActionFailurePath() async {
        let (getaway, _, _) = await makeGetaway()
        seedScreen(getaway.brains, elements: [("Home", .header, "home_header"), ("Old", .button, "button_old")])
        getaway.brains.recordSentState(viewportHash: 1)
        seedScreen(getaway.brains, elements: [("Settings", .header, "settings_header")])

        let result = getaway.staleTargetedActionFailure(
            for: .waitFor(.init(elementTarget: .heistId("button_old"), timeout: 0.1)),
            backgroundTrace: screenChangedBackgroundTrace()
        )

        XCTAssertNil(result, "waitFor is wait-only; stale action failure semantics are only for targeted actions")
    }

    // MARK: - Recording auto-finish

    /// Regression: when a recording auto-finishes (max duration, file-size
    /// cap, inactivity) there is no `stop_recording` waiter on the server.
    /// With no originator known, the payload is cached in `completedRecording`
    /// for the next `stop_recording` pickup, and `.recordingStopped` is
    /// broadcast as the notification.
    /// The previous shape broadcast `.recording(payload)` to every
    /// authenticated client, which was a privacy-leak surface.
    func testAutoFinishWithoutPendingStopBroadcastsRecording() async {
        let (getaway, _, _) = await makeGetaway()
        XCTAssertNil(getaway.pendingRecordingResponse)
        if case .none = getaway.completedRecording {} else {
            XCTFail("Expected .none completedRecording before deliver, got \(getaway.completedRecording)")
        }
        let stubStakeout = TheStakeout(captureFrame: { @MainActor in nil })
        getaway.recordingRouteState = .recording(stakeout: stubStakeout, ownerClientId: nil)

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
        let stubStakeout = TheStakeout(captureFrame: { @MainActor in nil })
        getaway.recordingRouteState = .stopping(stakeout: stubStakeout, waiter: .init(
            requestId: "stop-1",
            ownerClientId: 7,
            respond: { data in receivedData = data }
        ))

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

    func testAutoFinishWithOriginatorStillConnectedSendsPayloadOnlyToOriginator() async {
        let (getaway, muscle, _) = await makeGetaway()
        let sent = SentBox()
        await muscle.installCallbacks(
            sendToClient: { data, clientId in
                sent.append(data, clientId: clientId)
                return .enqueued
            },
            markClientAuthenticated: { _ in },
            disconnectClient: { _ in },
            onClientAuthenticated: { _, _ in },
            onSessionActiveChanged: { _ in }
        )
        await muscle.installAuthenticatedClientForTest(7)
        await muscle.installAuthenticatedClientForTest(8)
        let stubStakeout = TheStakeout(captureFrame: { @MainActor in nil })
        getaway.recordingRouteState = .recording(stakeout: stubStakeout, ownerClientId: 7)

        let payload = RecordingPayload(
            videoData: "AAAA",
            width: 100, height: 200,
            duration: 1.0, frameCount: 8, fps: 8,
            startTime: Date(), endTime: Date(),
            stopReason: .maxDuration
        )

        await getaway.deliverRecordingResult(.success(payload))

        let messagesByClient = sent.all.reduce(into: [Int: [ServerMessage]]()) { result, entry in
            let trimmed = entry.0.last == 0x0A ? entry.0.dropLast() : entry.0
            if let envelope = try? JSONDecoder().decode(ResponseEnvelope.self, from: trimmed) {
                result[entry.1, default: []].append(envelope.message)
            }
        }
        XCTAssertTrue(messagesByClient[7]?.contains { message in
            if case .recording(let delivered) = message {
                return delivered.frameCount == 8
            }
            return false
        } == true)
        XCTAssertTrue(messagesByClient[8]?.contains { message in
            if case .recordingStopped = message { return true }
            return false
        } == true)
        XCTAssertFalse(messagesByClient[8]?.contains { message in
            if case .recording = message { return true }
            return false
        } == true, "Non-originator must not receive the recording payload")
        if case .none = getaway.completedRecording {} else {
            XCTFail("Successful targeted delivery must clear the completion cache, got \(getaway.completedRecording)")
        }
    }

    func testManualStopAfterAutoFinishTargetDeliveryDoesNotDeliverSecondPayload() async {
        let (getaway, muscle, _) = await makeGetaway()
        let sent = SentBox()
        await muscle.installCallbacks(
            sendToClient: { data, clientId in
                sent.append(data, clientId: clientId)
                return .enqueued
            },
            markClientAuthenticated: { _ in },
            disconnectClient: { _ in },
            onClientAuthenticated: { _, _ in },
            onSessionActiveChanged: { _ in }
        )
        await muscle.installAuthenticatedClientForTest(7)
        let stubStakeout = TheStakeout(captureFrame: { @MainActor in nil })
        getaway.recordingRouteState = .recording(stakeout: stubStakeout, ownerClientId: 7)
        let payload = RecordingPayload(
            videoData: "AAAA",
            width: 100, height: 200,
            duration: 1.0, frameCount: 8, fps: 8,
            startTime: Date(), endTime: Date(),
            stopReason: .maxDuration
        )

        await getaway.deliverRecordingResult(.success(payload))
        var stopResponse: Data?
        await getaway.handleStopRecording(clientId: 7, requestId: "late-stop") { data in
            stopResponse = data
        }
        await getaway.deliverRecordingResult(.success(payload))

        let recordingDeliveries = sent.all.filter { entry in
            let trimmed = entry.0.last == 0x0A ? entry.0.dropLast() : entry.0
            guard let envelope = try? JSONDecoder().decode(ResponseEnvelope.self, from: trimmed) else { return false }
            if case .recording = envelope.message { return true }
            return false
        }
        XCTAssertEqual(recordingDeliveries.count, 1, "Auto-finish and manual stop race must not produce two recording payloads")
        guard let stopResponse else {
            return XCTFail("Late stop must receive an error response")
        }
        let trimmedStop = stopResponse.last == 0x0A ? stopResponse.dropLast() : stopResponse
        let stopEnvelope = try? JSONDecoder().decode(ResponseEnvelope.self, from: trimmedStop)
        guard case .error(let serverError)? = stopEnvelope?.message else {
            return XCTFail("Late stop must receive a no-recording error, got \(String(describing: stopEnvelope?.message))")
        }
        XCTAssertTrue(serverError.message.contains("No recording in progress"))
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

    // MARK: - Recording lifecycle invalidation

    /// PR #314 H1: a recording payload completed by client A must not be
    /// returned to client B who never asked for it. When the originator
    /// disconnects, the cache is dropped.
    func testDisconnectInvalidatesCachedCompletedRecordingForOriginator() async {
        let (getaway, _, _) = await makeGetaway()
        let payload = RecordingPayload(
            videoData: "AAAA",
            width: 100, height: 200,
            duration: 1.0, frameCount: 8, fps: 8,
            startTime: Date(), endTime: Date(),
            stopReason: .maxDuration
        )
        getaway.recordingRouteState = .completed(.init(
            outcome: .succeeded(payload),
            cachePolicy: .originatorOnly(7)
        ))

        getaway.invalidateRecordingForDisconnect(clientId: 7)

        XCTAssertNil(getaway.recordingOriginatorClientId)
        XCTAssertNil(getaway.pendingRecordingResponse)
        if case .none = getaway.completedRecording { } else {
            XCTFail("completedRecording must drop to .none on originator disconnect, got \(getaway.completedRecording)")
        }
    }

    /// Counterpart: an unrelated client disconnecting must not nuke a
    /// cached payload that belongs to a still-connected originator.
    func testDisconnectByNonOriginatorPreservesCache() async {
        let (getaway, _, _) = await makeGetaway()
        let payload = RecordingPayload(
            videoData: "AAAA",
            width: 100, height: 200,
            duration: 1.0, frameCount: 8, fps: 8,
            startTime: Date(), endTime: Date(),
            stopReason: .maxDuration
        )
        getaway.recordingRouteState = .completed(.init(
            outcome: .succeeded(payload),
            cachePolicy: .originatorOnly(7)
        ))

        getaway.invalidateRecordingForDisconnect(clientId: 99)

        XCTAssertEqual(getaway.recordingOriginatorClientId, 7)
        if case .succeeded = getaway.completedRecording { } else {
            XCTFail("Cache must survive disconnect of a non-originator client, got \(getaway.completedRecording)")
        }
    }

    /// PR #314 H2: `pendingRecordingResponse` retains the respond closure
    /// indefinitely. If the originator's connection drops, the closure
    /// must be cleared so the next legitimate `stop_recording` isn't
    /// blocked by the "Recording stop already in progress" guard.
    func testDisconnectClearsPendingRecordingResponseForOriginator() async {
        let (getaway, _, _) = await makeGetaway()
        var deliveriesAfterDisconnect = 0
        let stubStakeout = TheStakeout(captureFrame: { @MainActor in nil })
        getaway.recordingRouteState = .stopping(stakeout: stubStakeout, waiter: .init(
            requestId: "stop-1",
            ownerClientId: 3,
            respond: { _ in deliveriesAfterDisconnect += 1 }
        ))

        getaway.invalidateRecordingForDisconnect(clientId: 3)

        XCTAssertNil(getaway.pendingRecordingResponse, "Pending stop closure must be released when originator disconnects")
        XCTAssertEqual(deliveriesAfterDisconnect, 0, "The captured closure must never fire after disconnect")
    }

    /// PR #314 H1 (session boundary): a driver session releasing — either
    /// by inactivity timeout or last-connection drain — must drop any
    /// cached payload so a future driver can't pick up a video the
    /// previous driver started.
    func testSessionReleaseInvalidatesCachedRecording() async {
        let (getaway, _, _) = await makeGetaway()
        let payload = RecordingPayload(
            videoData: "AAAA",
            width: 100, height: 200,
            duration: 1.0, frameCount: 8, fps: 8,
            startTime: Date(), endTime: Date(),
            stopReason: .maxDuration
        )
        getaway.recordingRouteState = .completed(.init(
            outcome: .succeeded(payload),
            cachePolicy: .originatorOnly(7)
        ))

        getaway.invalidateRecordingForSessionRelease()

        XCTAssertNil(getaway.recordingOriginatorClientId)
        XCTAssertNil(getaway.pendingRecordingResponse)
        if case .none = getaway.completedRecording { } else {
            XCTFail("Session release must clear the cache, got \(getaway.completedRecording)")
        }
    }

    /// PR #348 M3: when the originator disconnected before the on-complete
    /// fires, the payload must not be delivered to an unrelated client or
    /// cached for a future client. The completion can still arrive from the
    /// stakeout, but the invalidated route discards the payload.
    func testOriginatorDisconnectMidRecordingDoesNotCachePayloadForNewClient() async {
        let (getaway, _, _) = await makeGetaway()
        let stubStakeout = TheStakeout(captureFrame: { @MainActor in nil })
        getaway.recordingRouteState = .recording(stakeout: stubStakeout, ownerClientId: 99)
        getaway.invalidateRecordingForDisconnect(clientId: 99)
        let payload = RecordingPayload(
            videoData: "AAAA",
            width: 100, height: 200,
            duration: 1.0, frameCount: 8, fps: 8,
            startTime: Date(), endTime: Date(),
            stopReason: .maxDuration
        )

        await getaway.deliverRecordingResult(.success(payload))

        XCTAssertNil(getaway.recordingOriginatorClientId, "Originator must clear after delivery resolves")
        XCTAssertNil(getaway.pendingRecordingResponse)
        if case .none = getaway.completedRecording {
            // expected
        } else {
            XCTFail("Completion from an invalidated originator must not be cached, got \(getaway.completedRecording)")
        }

        var newClientStopResponse: Data?
        await getaway.handleStopRecording(clientId: 42, requestId: "new-client-stop") { data in
            newClientStopResponse = data
        }
        guard let newClientStopResponse else {
            return XCTFail("New client stop must receive an error response")
        }
        let trimmed = newClientStopResponse.last == 0x0A ? newClientStopResponse.dropLast() : newClientStopResponse
        let envelope = try? JSONDecoder().decode(ResponseEnvelope.self, from: trimmed)
        guard case .error(let serverError)? = envelope?.message else {
            return XCTFail("New client stop must not receive a recording payload, got \(String(describing: envelope?.message))")
        }
        XCTAssertTrue(serverError.message.contains("No recording in progress"))
    }

    /// PR #314 H3 / PR #348 M3: an originator-owned cached completion is
    /// drained by its owner and then removed from the route state.
    func testStopRecordingDrainsCacheForRequestingClient() async {
        let (getaway, _, _) = await makeGetaway()
        // Pre-cached completion from client A — picked up immediately, so
        // the cache-hit branch in `handleStopRecording` clears originator
        // and drains the payload before ever reaching the rebind path.
        let payload = RecordingPayload(
            videoData: "AAAA",
            width: 100, height: 200,
            duration: 1.0, frameCount: 8, fps: 8,
            startTime: Date(), endTime: Date(),
            stopReason: .maxDuration
        )
        getaway.recordingRouteState = .completed(.init(
            outcome: .succeeded(payload),
            cachePolicy: .originatorOnly(7)
        ))

        await getaway.handleStopRecording(clientId: 7, requestId: "stop-from-a") { _ in }

        XCTAssertNil(getaway.recordingOriginatorClientId, "Cache pickup must clear originator")
        if case .none = getaway.completedRecording { } else {
            XCTFail("Cache must drain after stop_recording pickup, got \(getaway.completedRecording)")
        }
    }

    func testStopRecordingDrainsAnonymousCacheForAnySessionClient() async {
        let (getaway, _, _) = await makeGetaway()
        let payload = RecordingPayload(
            videoData: "AAAA",
            width: 100, height: 200,
            duration: 1.0, frameCount: 8, fps: 8,
            startTime: Date(), endTime: Date(),
            stopReason: .maxDuration
        )
        getaway.recordingRouteState = .completed(.init(
            outcome: .succeeded(payload),
            cachePolicy: .anySessionClient
        ))

        var stopResponse: Data?
        await getaway.handleStopRecording(clientId: 42, requestId: "anonymous-cache") { data in
            stopResponse = data
        }

        guard let stopResponse else {
            return XCTFail("Anonymous cache pickup must receive a wire response")
        }
        let trimmed = stopResponse.last == 0x0A ? stopResponse.dropLast() : stopResponse
        let envelope = try? JSONDecoder().decode(ResponseEnvelope.self, from: trimmed)
        XCTAssertEqual(envelope?.requestId, "anonymous-cache")
        guard case .recording(let delivered)? = envelope?.message else {
            return XCTFail("Expected anonymous cached recording, got \(String(describing: envelope?.message))")
        }
        XCTAssertEqual(delivered.frameCount, 8)
        if case .none = getaway.completedRecording { } else {
            XCTFail("Anonymous cache must drain after stop_recording pickup, got \(getaway.completedRecording)")
        }
    }

    /// PR #314 H3 / PR #348 M3: direct rebind coverage.
    ///
    /// Drives the parked-waiter path: no cached completion, but
    /// `recordingPhase` is `.recording(stakeout:)` so `handleStopRecording`
    /// skips the cache-hit early return, records the requesting client as the
    /// waiter owner, and parks `pendingRecordingResponse`. The stubbed
    /// stakeout is in `.idle` so `isRecording` returns false and
    /// `stopRecording` is never invoked — the waiter stays parked and we
    /// can inspect the rebind side effect synchronously.
    func testStopRecordingRebindsOriginatorToRequestingClient() async {
        let (getaway, _, _) = await makeGetaway()

        // A stakeout that's never been started: `isRecording` is false and
        // `stopRecording` is a no-op on the idle phase. That lets us park
        // a waiter without driving a real recording-complete callback.
        let stubStakeout = TheStakeout(captureFrame: { @MainActor in nil })
        getaway.recordingRouteState = .recording(stakeout: stubStakeout, ownerClientId: 7)
        // No cache — force the function past the .succeeded/.failed early
        // returns and into the rebind + park branch.

        await getaway.handleStopRecording(clientId: 42, requestId: "stop-from-b") { _ in }

        XCTAssertEqual(
            getaway.recordingOriginatorClientId,
            42,
            "Rebind must replace the originator with the requesting client"
        )
        XCTAssertNotNil(
            getaway.pendingRecordingResponse,
            "Parked-waiter path must store the pending response for the on-complete callback"
        )
        XCTAssertEqual(getaway.pendingRecordingResponse?.requestId, "stop-from-b")
    }

    /// Fix for cache-clear-before-send: when the transport is torn down
    /// (`sendToClient` is nil on TheMuscle), the targeted send to the
    /// originator fails. The cache must be preserved in that case so a
    /// subsequent `stop_recording` (or tearDown) can still resolve the
    /// payload — never drop a recording into the void.
    func testAutoFinishWithTornDownTransportPreservesCache() async {
        let (getaway, muscle, _) = await makeGetaway()
        // Mark client 7 as authenticated so the targeted-delivery branch
        // is entered, then drop `sendToClient` so the send fails and the
        // cache must survive.
        //
        // `wireTransport` installs callbacks via a Task; await a yield to
        // let that install complete before we tear it back down.
        await Task.yield()
        await muscle.installAuthenticatedClientForTest(7)
        await muscle.clearSendToClientForTest()
        let stubStakeout = TheStakeout(captureFrame: { @MainActor in nil })
        getaway.recordingRouteState = .recording(stakeout: stubStakeout, ownerClientId: 7)

        let payload = RecordingPayload(
            videoData: "AAAA",
            width: 100, height: 200,
            duration: 1.0, frameCount: 8, fps: 8,
            startTime: Date(), endTime: Date(),
            stopReason: .maxDuration
        )

        await getaway.deliverRecordingResult(.success(payload))

        guard case .succeeded(let cached) = getaway.completedRecording else {
            XCTFail("Cache must be preserved when transport is torn down, got \(getaway.completedRecording)")
            return
        }
        XCTAssertEqual(cached.frameCount, 8)
        XCTAssertEqual(
            getaway.recordingOriginatorClientId,
            7,
            "Originator must be preserved alongside the cache when delivery did not happen"
        )
    }

    func testAutoFinishWithMissingTargetClientPreservesCache() async {
        let (getaway, muscle, _) = await makeGetaway()
        await muscle.installCallbacks(
            sendToClient: { _, clientId in .failed(.clientNotFound(clientId)) },
            markClientAuthenticated: { _ in },
            disconnectClient: { _ in },
            onClientAuthenticated: { _, _ in },
            onSessionActiveChanged: { _ in }
        )
        await muscle.installAuthenticatedClientForTest(7)
        let stubStakeout = TheStakeout(captureFrame: { @MainActor in nil })
        getaway.recordingRouteState = .recording(stakeout: stubStakeout, ownerClientId: 7)

        let payload = RecordingPayload(
            videoData: "AAAA",
            width: 100, height: 200,
            duration: 1.0, frameCount: 8, fps: 8,
            startTime: Date(), endTime: Date(),
            stopReason: .maxDuration
        )

        await getaway.deliverRecordingResult(.success(payload))

        guard case .succeeded(let cached) = getaway.completedRecording else {
            return XCTFail("Cache must be preserved when targeted delivery fails, got \(getaway.completedRecording)")
        }
        XCTAssertEqual(cached.frameCount, 8)
        XCTAssertEqual(getaway.recordingOriginatorClientId, 7)
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

    private func seedScreen(
        _ brains: TheBrains,
        elements: [(label: String, traits: UIAccessibilityTraits, heistId: String)]
    ) {
        let pairs: [(AccessibilityElement, String)] = elements.map { entry in
            let element = AccessibilityElement.make(
                label: entry.label,
                traits: entry.traits,
                respondsToUserInteraction: false
            )
            return (element, entry.heistId)
        }
        brains.stash.currentScreen = .makeForTests(elements: pairs)
    }

    private func screenChangedBackgroundTrace() -> AccessibilityTrace {
        let beforeInterface = Interface(timestamp: Date(timeIntervalSince1970: 0), tree: [])
        let afterInterface = Interface(timestamp: Date(timeIntervalSince1970: 1), tree: [])
        let before = AccessibilityTrace.Capture(
            sequence: 1,
            interface: beforeInterface,
            context: AccessibilityTrace.Context(screenId: "home")
        )
        let after = AccessibilityTrace.Capture(
            sequence: 2,
            interface: afterInterface,
            parentHash: before.hash,
            context: AccessibilityTrace.Context(screenId: "settings")
        )
        return AccessibilityTrace(captures: [before, after])
    }
}
#endif // canImport(UIKit)
