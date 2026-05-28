#if canImport(UIKit)
import XCTest
import UIKit
import os
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
        let getaway = TheGetaway(muscle: muscle, brains: brains, identity: identity)
        let transport = ServerTransport()
        await getaway.wireTransport(transport)
        return (getaway, muscle, transport)
    }

    private static let recordingTestScreen = TheStakeout.ScreenInfo(
        bounds: CGRect(x: 0, y: 0, width: 100, height: 100),
        scale: 1.0
    )

    // swiftlint:disable:next agent_unchecked_sendable_no_comment - Test callback storage is protected by NSLock.
    private final class SentBox: @unchecked Sendable {
        private var storage: [(Data, Int)] = []
        private let lock = NSLock()
        func append(_ data: Data, clientId: Int) { lock.withLock { storage.append((data, clientId)) } }
        var all: [(Data, Int)] { lock.withLock { storage } }
    }

    private func dispatchAuthenticated(
        _ getaway: TheGetaway,
        muscle: TheMuscle,
        clientId: Int = 1,
        data: Data,
        respond: @escaping @Sendable (Data) -> Void
    ) async throws {
        await muscle.installAuthenticatedClientForTest(clientId)
        switch await muscle.admitClientMessage(clientId, data: data, respond: respond) {
        case .admitted(let message):
            await getaway.handleClientMessage(message, respond: respond)
        case .handled:
            XCTFail("Expected authenticated test message to be admitted")
        }
    }

    private func sendRawMessageThroughTransport(
        _ message: ClientMessage,
        requestId: String,
        transport: ServerTransport,
        clientId: Int = 1
    ) async throws -> ResponseEnvelope {
        let data = try JSONEncoder().encode(RequestEnvelope(requestId: requestId, message: message))
        let responses = SentBox()
        let callbacks = transport.makeCallbacks()

        // Detached intentionally simulates SimpleSocketServer's off-main-actor callback dispatch.
        // swiftlint:disable:next agent_no_task_detached
        await Task.detached {
            callbacks.onClientConnected?(clientId, "192.168.1.1")
            callbacks.onDataReceived?(clientId, data) { response in
                responses.append(response, clientId: clientId)
            }
        }.value

        try await waitFor {
            !responses.all.isEmpty
        }

        return try JSONDecoder().decode(ResponseEnvelope.self, from: try XCTUnwrap(responses.all.first?.0))
    }

    // swiftlint:disable:next agent_unchecked_sendable_no_comment - Test callback storage is protected by NSLock.
    private final class RecordingCompletionBox: @unchecked Sendable {
        private var storage = 0
        private let lock = NSLock()
        func increment() { lock.withLock { storage += 1 } }
        var count: Int { lock.withLock { storage } }
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
            callbacks.onDataReceived?(1, helloData) { _ in }
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
                callbacks.onDataReceived?(clientId, helloData) { _ in }
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

    func testUnauthenticatedStatusIsRejectedByMuscleBeforeGetawayDispatch() async throws {
        let (getaway, _, transport) = await makeGetaway()
        _ = getaway

        let envelope = try await sendRawMessageThroughTransport(.status, requestId: "pre-auth-status", transport: transport)
        XCTAssertEqual(envelope.requestId, "pre-auth-status")
        guard case .error(let error) = envelope.message else {
            return XCTFail("Expected auth failure, got \(envelope.message)")
        }
        XCTAssertEqual(error.kind, .authFailure)
        XCTAssertEqual(error.message, "Authentication required before status.")
    }

    func testUnauthenticatedPingIsRejectedByMuscleBeforeGetawayDispatch() async throws {
        let (getaway, _, transport) = await makeGetaway()
        _ = getaway

        let envelope = try await sendRawMessageThroughTransport(.ping, requestId: "pre-auth-ping", transport: transport)
        XCTAssertEqual(envelope.requestId, "pre-auth-ping")
        guard case .error(let error) = envelope.message else {
            return XCTFail("Expected auth failure, got \(envelope.message)")
        }
        XCTAssertEqual(error.kind, .authFailure)
        XCTAssertEqual(error.message, "Authentication required before ping.")
    }

    func testUnauthenticatedActionIsRejectedByMuscleBeforeGetawayDispatch() async throws {
        let (getaway, _, transport) = await makeGetaway()
        _ = getaway

        let envelope = try await sendRawMessageThroughTransport(
            .activate(.heistId("button_1")),
            requestId: "pre-auth-action",
            transport: transport
        )
        XCTAssertEqual(envelope.requestId, "pre-auth-action")
        guard case .error(let error) = envelope.message else {
            return XCTFail("Expected auth failure, got \(envelope.message)")
        }
        XCTAssertEqual(error.kind, .authFailure)
        XCTAssertEqual(error.message, "Authentication required before activate.")
    }

    func testPostAuthStatusDispatchesAfterMuscleAdmission() async throws {
        let (getaway, muscle, transport) = await makeGetaway()
        _ = getaway

        let callbacks = transport.makeCallbacks()
        let responses = SentBox()
        let helloData = try JSONEncoder().encode(RequestEnvelope(message: .clientHello))
        let authData = try JSONEncoder().encode(RequestEnvelope(message: .authenticate(.init(token: "test-token"))))
        let statusData = try JSONEncoder().encode(RequestEnvelope(requestId: "post-auth-status", message: .status))

        // Detached intentionally simulates SimpleSocketServer's off-main-actor callback dispatch.
        // swiftlint:disable:next agent_no_task_detached
        await Task.detached {
            callbacks.onClientConnected?(1, "192.168.1.1")
            callbacks.onDataReceived?(1, helloData) { data in responses.append(data, clientId: 1) }
            callbacks.onDataReceived?(1, authData) { data in responses.append(data, clientId: 1) }
        }.value

        try await waitFor {
            let authenticated = await muscle.authenticatedClientIDs
            return authenticated.contains(1)
        }

        // Detached intentionally simulates SimpleSocketServer's off-main-actor callback dispatch.
        // swiftlint:disable:next agent_no_task_detached
        await Task.detached {
            callbacks.onDataReceived?(1, statusData) { data in responses.append(data, clientId: 1) }
        }.value

        try await waitFor {
            responses.all.contains { entry in
                let envelope = try? JSONDecoder().decode(ResponseEnvelope.self, from: entry.0)
                return envelope?.requestId == "post-auth-status"
            }
        }

        let statusResponse = try XCTUnwrap(responses.all.compactMap { entry in
            try? JSONDecoder().decode(ResponseEnvelope.self, from: entry.0)
        }.first { $0.requestId == "post-auth-status" })
        guard case .status = statusResponse.message else {
            return XCTFail("Expected status after admission, got \(statusResponse.message)")
        }
    }

    func testPostAuthProtocolMessageIsRejectedByAdmission() async throws {
        let (getaway, muscle, transport) = await makeGetaway()
        _ = getaway

        let callbacks = transport.makeCallbacks()
        let responses = SentBox()
        let helloData = try JSONEncoder().encode(RequestEnvelope(message: .clientHello))
        let authData = try JSONEncoder().encode(RequestEnvelope(message: .authenticate(.init(token: "test-token"))))
        let repeatedHelloData = try JSONEncoder().encode(
            RequestEnvelope(requestId: "post-auth-hello", message: .clientHello)
        )

        // Detached intentionally simulates SimpleSocketServer's off-main-actor callback dispatch.
        // swiftlint:disable:next agent_no_task_detached
        await Task.detached {
            callbacks.onClientConnected?(1, "192.168.1.1")
            callbacks.onDataReceived?(1, helloData) { data in responses.append(data, clientId: 1) }
            callbacks.onDataReceived?(1, authData) { data in responses.append(data, clientId: 1) }
        }.value

        try await waitFor {
            let authenticated = await muscle.authenticatedClientIDs
            return authenticated.contains(1)
        }

        // Detached intentionally simulates SimpleSocketServer's off-main-actor callback dispatch.
        // swiftlint:disable:next agent_no_task_detached
        await Task.detached {
            callbacks.onDataReceived?(1, repeatedHelloData) { data in responses.append(data, clientId: 1) }
        }.value

        try await waitFor {
            responses.all.contains { entry in
                let envelope = try? JSONDecoder().decode(ResponseEnvelope.self, from: entry.0)
                return envelope?.requestId == "post-auth-hello"
            }
        }

        let response = try XCTUnwrap(responses.all.compactMap { entry in
            try? JSONDecoder().decode(ResponseEnvelope.self, from: entry.0)
        }.first { $0.requestId == "post-auth-hello" })
        guard case .error(let error) = response.message else {
            return XCTFail("Expected admission rejection, got \(response.message)")
        }
        XCTAssertEqual(error.kind, .validationError)
        XCTAssertEqual(error.message, "Protocol message client_hello is not an app command after authentication.")
    }

    func testStatusReportsActiveDriverId() async throws {
        let (getaway, muscle, transport) = await makeGetaway()
        _ = getaway

        let callbacks = transport.makeCallbacks()
        let responses = SentBox()
        let helloData = try JSONEncoder().encode(RequestEnvelope(message: .clientHello))
        let authData = try JSONEncoder().encode(
            RequestEnvelope(message: .authenticate(.init(token: "test-token", driverId: "driver-a")))
        )
        let statusData = try JSONEncoder().encode(RequestEnvelope(requestId: "status-driver", message: .status))

        // Detached intentionally simulates SimpleSocketServer's off-main-actor callback dispatch.
        // swiftlint:disable:next agent_no_task_detached
        await Task.detached {
            callbacks.onClientConnected?(1, "192.168.1.1")
            callbacks.onDataReceived?(1, helloData) { data in responses.append(data, clientId: 1) }
            callbacks.onDataReceived?(1, authData) { data in responses.append(data, clientId: 1) }
        }.value

        try await waitFor {
            let authenticated = await muscle.authenticatedClientIDs
            return authenticated.contains(1)
        }

        // Detached intentionally simulates SimpleSocketServer's off-main-actor callback dispatch.
        // swiftlint:disable:next agent_no_task_detached
        await Task.detached {
            callbacks.onDataReceived?(1, statusData) { data in responses.append(data, clientId: 1) }
        }.value

        try await waitFor {
            responses.all.contains { entry in
                let envelope = try? JSONDecoder().decode(ResponseEnvelope.self, from: entry.0)
                return envelope?.requestId == "status-driver"
            }
        }

        let response = try XCTUnwrap(responses.all.compactMap { entry in
            try? JSONDecoder().decode(ResponseEnvelope.self, from: entry.0)
        }.first { $0.requestId == "status-driver" })
        guard case .status(let payload) = response.message else {
            return XCTFail("Expected status, got \(response.message)")
        }
        XCTAssertTrue(payload.session.active)
        XCTAssertEqual(payload.session.activeConnections, 1)
        XCTAssertEqual(payload.session.activeDriverId, "driver-a")
    }

    func testNormalPingReturnsCachedHealthPayloadWithTimestamp() async throws {
        let (getaway, muscle, _) = await makeGetaway()
        let request = RequestEnvelope(requestId: "health-1", message: .ping)
        let data = try JSONEncoder().encode(request)
        let responses = SentBox()
        let beforeMs = Int64(Date().timeIntervalSince1970 * 1000)

        try await dispatchAuthenticated(getaway, muscle: muscle, data: data) { data in
            responses.append(data, clientId: 1)
        }
        let afterMs = Int64(Date().timeIntervalSince1970 * 1000)

        let envelope = try JSONDecoder().decode(ResponseEnvelope.self, from: try XCTUnwrap(responses.all.first?.0))
        XCTAssertEqual(envelope.requestId, "health-1")
        guard case .pong(let payload) = envelope.message else {
            return XCTFail("Expected pong, got \(envelope.message)")
        }
        XCTAssertEqual(payload.serverInstanceIdentifier, "test")
        let timestamp = try XCTUnwrap(payload.serverTimestampMs)
        XCTAssertGreaterThanOrEqual(timestamp, beforeMs)
        XCTAssertLessThanOrEqual(timestamp, afterMs)
    }

    func testMalformedClientMessageReturnsDecodeFailureEnvelope() async throws {
        let (_, muscle, _) = await makeGetaway()
        let responses = SentBox()

        await muscle.installAuthenticatedClientForTest(1)
        switch await muscle.admitClientMessage(1, data: Data("not-json".utf8), respond: { data in
            responses.append(data, clientId: 1)
        }) {
        case .handled:
            break
        case .admitted:
            XCTFail("Malformed data must not be admitted to app dispatch")
        }

        let envelope = try decodeResponseEnvelope(from: try XCTUnwrap(responses.all.first?.0))
        XCTAssertNil(envelope.requestId)
        guard case .error(let error) = envelope.message else {
            return XCTFail("Expected malformed decode error, got \(envelope.message)")
        }
        XCTAssertEqual(error.kind, .general)
        XCTAssertEqual(error.message, "Malformed message — could not decode")
    }

    func testTargetedActionAfterBackgroundScreenChangeDispatchesToBrains() async throws {
        let (getaway, muscle, _) = await makeGetaway()
        seedScreen(getaway.brains, elements: [("Home", .header, "home_header"), ("Old", .button, "button_old")])
        getaway.brains.recordSentState()
        seedScreen(getaway.brains, elements: [("Settings", .header, "settings_header"), ("New", .button, "button_new")])

        let request = RequestEnvelope(
            requestId: "activate-after-change",
            message: .activate(.heistId("button_old"))
        )
        let data = try JSONEncoder().encode(request)
        let responses = SentBox()

        try await dispatchAuthenticated(getaway, muscle: muscle, data: data) { data in
            responses.append(data, clientId: 1)
        }

        let envelope = try decodeResponseEnvelope(from: try XCTUnwrap(responses.all.first?.0))
        XCTAssertEqual(envelope.requestId, "activate-after-change")
        guard case .actionResult(let result) = envelope.message else {
            return XCTFail("Expected action result from TheBrains, got \(envelope.message)")
        }
        XCTAssertFalse(result.success)
        XCTAssertFalse(
            result.message?.contains("target became stale after a screen change") ?? false,
            "Element targeting should dispatch to TheBrains so semantic resolution can inflate or fail with target diagnostics"
        )
    }

    // MARK: - Send Encoding

    func testSendMessageDropsUnencodablePayloadWithoutSynthesizingAlternateError() async {
        let (getaway, _, _) = await makeGetaway()
        var responses: [Data] = []
        let payload = ServerInfo(
            appName: "Test",
            bundleIdentifier: "test.bundle",
            deviceName: "Device",
            systemVersion: "1",
            screenWidth: .nan,
            screenHeight: 100,
            instanceId: "test-session",
            instanceIdentifier: "test",
            listeningPort: 49152,
            tlsActive: true
        )

        let result = getaway.sendMessage(.info(payload), requestId: "bad-info") { data in
            responses.append(data)
        }

        guard case .failed(.responseEncodingFailed(let failure)) = result else {
            return XCTFail("Expected encoding failure, got \(result)")
        }
        XCTAssertEqual(failure.requestId, "bad-info")
        XCTAssertTrue(
            responses.isEmpty,
            "Encoding failure should not send a guessed alternate response for a payload that never reached the wire"
        )
    }

    func testSendMessageStillEncodesExplicitErrorResponses() async throws {
        let (getaway, _, _) = await makeGetaway()
        let responses = SentBox()

        let result = getaway.sendMessage(
            .error(ServerError(kind: .general, message: "Explicit failure")),
            requestId: "explicit-error"
        ) { data in
            responses.append(data, clientId: 1)
        }

        guard case .delivered = result else {
            return XCTFail("Expected explicit error response to encode, got \(result)")
        }
        let envelope = try decodeResponseEnvelope(from: try XCTUnwrap(responses.all.first?.0))
        XCTAssertEqual(envelope.requestId, "explicit-error")
        guard case .error(let error) = envelope.message else {
            return XCTFail("Expected explicit error response, got \(envelope.message)")
        }
        XCTAssertEqual(error.kind, .general)
        XCTAssertEqual(error.message, "Explicit failure")
    }

    func testBroadcastWithoutTransportReturnsTypedFailure() async {
        let (getaway, _, _) = await makeGetaway()
        await getaway.tearDown()

        let result = await getaway.broadcastToAll(.recordingStopped)

        guard case .transportUnavailable(clientId: nil) = result else {
            return XCTFail("Expected missing connection broadcast failure, got \(result)")
        }
    }

    func testBroadcastUnencodablePayloadReturnsTypedEncodeFailure() async {
        let (getaway, _, _) = await makeGetaway()
        let payload = RecordingPayload(
            videoData: "AAAA",
            width: 100,
            height: 200,
            duration: .nan,
            frameCount: 8,
            fps: 8,
            startTime: Date(),
            endTime: Date(),
            stopReason: .maxDuration
        )

        let result = await getaway.broadcastToAll(.recording(payload))

        guard case .failed(.responseEncodingFailed(let failure)) = result else {
            return XCTFail("Expected broadcast encode failure, got \(result)")
        }
        XCTAssertNil(failure.requestId)
    }

    func testBroadcastSendFailureReturnsTypedSendFailure() async {
        let (getaway, muscle, transport) = await makeGetaway()
        _ = transport
        await muscle.installCallbacks(
            sendToClient: { _, clientId in
                .failed(.transportFailed(clientId: clientId, message: "socket write failed"))
            },
            disconnectClient: { _ in },
            onClientAuthenticated: { _, _ in },
            onSessionActiveChanged: { _ in }
        )
        await muscle.installAuthenticatedClientForTest(7)

        let result = await getaway.broadcastToAll(.recordingStopped)

        guard case .failed(.sendFailed(let clientId, let failure)) = result else {
            return XCTFail("Expected broadcast send failure, got \(result)")
        }
        XCTAssertEqual(clientId, 7)
        XCTAssertEqual(failure, .transportFailed(clientId: 7, message: "socket write failed"))
    }

    func testBroadcastContinuesAfterClientSendFailure() async {
        let (getaway, muscle, transport) = await makeGetaway()
        _ = transport
        let sent = SentBox()
        await muscle.installCallbacks(
            sendToClient: { data, clientId in
                sent.append(data, clientId: clientId)
                if clientId == 7 {
                    return .failed(.transportFailed(clientId: clientId, message: "socket write failed"))
                }
                return .enqueued
            },
            disconnectClient: { _ in },
            onClientAuthenticated: { _, _ in },
            onSessionActiveChanged: { _ in }
        )
        await muscle.installAuthenticatedClientForTest(7)
        await muscle.installAuthenticatedClientForTest(8)

        let result = await getaway.broadcastToAll(.recordingStopped)

        guard case .failed(.sendFailed(let clientId, let failure)) = result else {
            return XCTFail("Expected broadcast send failure, got \(result)")
        }
        XCTAssertEqual(clientId, 7)
        XCTAssertEqual(failure, .transportFailed(clientId: 7, message: "socket write failed"))
        XCTAssertEqual(sent.all.map(\.1), [7, 8])
    }

    func testBroadcastClosedConnectionReturnsTypedConnectionFailure() async {
        let (getaway, muscle, transport) = await makeGetaway()
        _ = transport
        await muscle.installCallbacks(
            sendToClient: { _, clientId in .failed(.clientNotFound(clientId)) },
            disconnectClient: { _ in },
            onClientAuthenticated: { _, _ in },
            onSessionActiveChanged: { _ in }
        )
        await muscle.installAuthenticatedClientForTest(7)

        let result = await getaway.broadcastToAll(.recordingStopped)

        guard case .failed(.connectionClosed(clientId: 7)) = result else {
            return XCTFail("Expected closed connection broadcast failure, got \(result)")
        }
    }

    func testBroadcastScreenshotReturnsTypedSessionContractFailure() async {
        let (getaway, _, _) = await makeGetaway()

        let result = await getaway.broadcastToAll(.screen(ScreenPayload(
            pngData: "AAAA",
            width: 10,
            height: 20,
            interface: Interface(timestamp: Date(), tree: [])
        )))

        guard case .refused(.sessionContractViolation(let message)) = result else {
            return XCTFail("Expected session contract broadcast failure, got \(result)")
        }
        XCTAssertTrue(message.contains("screenshots must be requested explicitly"))
    }

    func testTransportSendFailureUsesDisconnectLifecycle() async {
        let (getaway, muscle, _) = await makeGetaway()
        await muscle.installAuthenticatedClientForTest(7)
        let payload = RecordingPayload(
            videoData: "AAAA",
            width: 100,
            height: 200,
            duration: 1.0,
            frameCount: 8,
            fps: 8,
            startTime: Date(),
            endTime: Date(),
            stopReason: .maxDuration
        )
        getaway.installRecordingRouteStateForTest(.completed(.init(
            outcome: .succeeded(payload),
            cachePolicy: .originatorOnly(7)
        )))

        await getaway.handleTransportEvent(.sendFailed(
            clientId: 7,
            failure: .transportFailed(clientId: 7, message: "socket write failed")
        ))

        let authenticated = await muscle.authenticatedClientIDs
        XCTAssertFalse(authenticated.contains(7))
        XCTAssertNil(getaway.recordingOriginatorClientId)
        if case .none = getaway.completedRecording {} else {
            XCTFail("Send failure should clear originator-owned recording cache, got \(getaway.completedRecording)")
        }
    }

    // MARK: - Background change tracking

    func testChangeDuringSettledParseRemainsPending() throws {
        var state = BackgroundChangeState()
        state.noteChange()

        let claim = state.beginSettledParse()
        XCTAssertEqual(claim, 1)

        state.noteChange()
        state.finishSettledParse(claimedGeneration: try XCTUnwrap(claim))

        XCTAssertEqual(state.parsedThroughGeneration, 1)
        XCTAssertEqual(state.latestGeneration, 2)
        XCTAssertTrue(state.hasPendingSettledChange)
        XCTAssertTrue(state.canBeginSettledParse)
    }

    func testObservedGenerationDoesNotClearNewerBackgroundChange() {
        var state = BackgroundChangeState()
        state.noteChange()
        let observedGeneration = state.latestGeneration
        state.noteChange()

        state.markObserved(through: observedGeneration)

        XCTAssertEqual(state.parsedThroughGeneration, 1)
        XCTAssertEqual(state.latestGeneration, 2)
        XCTAssertTrue(state.hasPendingSettledChange)
    }

    func testObservedLatestGenerationClearsPendingBackgroundChange() {
        var state = BackgroundChangeState()
        state.noteChange()

        state.markObserved(through: state.latestGeneration)

        XCTAssertEqual(state.parsedThroughGeneration, state.latestGeneration)
        XCTAssertFalse(state.hasPendingSettledChange)
        XCTAssertFalse(state.canBeginSettledParse)
    }

    func testCommandDuringSettledParseKeepsParserBlockedUntilCommandFinishes() throws {
        var state = BackgroundChangeState()
        state.noteChange()
        let claim = try XCTUnwrap(state.beginSettledParse())

        state.beginCommand()
        state.noteChange()
        state.finishSettledParse(claimedGeneration: claim)

        XCTAssertTrue(state.isCommandInFlight)
        XCTAssertFalse(state.isSettledParseInFlight)
        XCTAssertFalse(state.canBeginSettledParse)

        state.finishCommand()

        XCTAssertTrue(state.hasPendingSettledChange)
        XCTAssertTrue(state.canBeginSettledParse)
    }

    // MARK: - Recording auto-finish

    func testSettledScreenChangePreventsRecordingInactivityAutoStop() async throws {
        let (getaway, _, _) = await makeGetaway()
        let (window, button) = try installRecordingActivityWindow(title: "Initial")
        defer { window.isHidden = true }
        await getaway.brains.tripwire.yieldFrames(3)

        let stakeout = TheStakeout(captureFrame: { @MainActor in nil })
        try await stakeout.startRecording(
            config: RecordingConfig(inactivityTimeout: 1.0, maxDuration: 5.0),
            screen: TheStakeout.ScreenInfo(
                bounds: CGRect(x: 0, y: 0, width: 100, height: 100),
                scale: 1.0
            )
        )
        getaway.installRecordingRouteStateForTest(.recording(stakeout: stakeout, ownerClientId: nil))

        // Wait long enough that the recording would be near the first inactivity
        // check, then process a settled hierarchy change through TheGetaway.
        // swiftlint:disable:next agent_test_task_sleep
        try await Task.sleep(for: .milliseconds(350))
        button.setTitle("Loaded", for: .normal)
        button.accessibilityLabel = "Loaded"
        window.layoutIfNeeded()
        await getaway.brains.tripwire.yieldFrames(3)
        getaway.noteBackgroundChange()
        await getaway.noteSettledChangeIfNeeded()

        // Total elapsed time is now beyond the 1s inactivity timeout from start.
        // The recording should remain active because the settled change bumped
        // `lastActivityTime`; without the Getaway -> Stakeout notification, the
        // first inactivity monitor tick stops it.
        // swiftlint:disable:next agent_test_task_sleep
        try await Task.sleep(for: .milliseconds(900))
        let isRecording = await stakeout.isRecording
        XCTAssertTrue(isRecording)

        await stakeout.stopRecording(reason: .manual)
    }

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
        getaway.installRecordingRouteStateForTest(.recording(stakeout: stubStakeout, ownerClientId: nil))

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
        getaway.installRecordingRouteStateForTest(.stopping(stakeout: stubStakeout, waiter: .init(
            requestId: "stop-1",
            ownerClientId: 7,
            respond: { data in receivedData = data }
        )))

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
            disconnectClient: { _ in },
            onClientAuthenticated: { _, _ in },
            onSessionActiveChanged: { _ in }
        )
        await muscle.installAuthenticatedClientForTest(7)
        await muscle.installAuthenticatedClientForTest(8)
        let stubStakeout = TheStakeout(captureFrame: { @MainActor in nil })
        getaway.installRecordingRouteStateForTest(.recording(stakeout: stubStakeout, ownerClientId: 7))

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

    func testAutoFinishPayloadEncodingFailureDoesNotBroadcastStoppedNotification() async {
        let (getaway, muscle, _) = await makeGetaway()
        let sent = SentBox()
        await muscle.installCallbacks(
            sendToClient: { data, clientId in
                sent.append(data, clientId: clientId)
                return .enqueued
            },
            disconnectClient: { _ in },
            onClientAuthenticated: { _, _ in },
            onSessionActiveChanged: { _ in }
        )
        await muscle.installAuthenticatedClientForTest(7)
        await muscle.installAuthenticatedClientForTest(8)
        let stubStakeout = TheStakeout(captureFrame: { @MainActor in nil })
        getaway.installRecordingRouteStateForTest(.recording(stakeout: stubStakeout, ownerClientId: 7))

        let payload = RecordingPayload(
            videoData: "AAAA",
            width: 100, height: 200,
            duration: .nan, frameCount: 8, fps: 8,
            startTime: Date(), endTime: Date(),
            stopReason: .maxDuration
        )

        await getaway.deliverRecordingResult(.success(payload))

        XCTAssertTrue(
            sent.all.isEmpty,
            "Encoding failure must fail closed instead of broadcasting a success-shaped recordingStopped notification"
        )
        guard case .succeeded(let cached) = getaway.completedRecording else {
            return XCTFail("Failed delivery must keep the completed payload for the route owner")
        }
        XCTAssertTrue(cached.duration.isNaN)
    }

    func testManualStopAfterAutoFinishTargetDeliveryDoesNotDeliverSecondPayload() async {
        let (getaway, muscle, _) = await makeGetaway()
        let sent = SentBox()
        await muscle.installCallbacks(
            sendToClient: { data, clientId in
                sent.append(data, clientId: clientId)
                return .enqueued
            },
            disconnectClient: { _ in },
            onClientAuthenticated: { _, _ in },
            onSessionActiveChanged: { _ in }
        )
        await muscle.installAuthenticatedClientForTest(7)
        let stubStakeout = TheStakeout(captureFrame: { @MainActor in nil })
        getaway.installRecordingRouteStateForTest(.recording(stakeout: stubStakeout, ownerClientId: 7))
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
        getaway.installRecordingRouteStateForTest(.completed(.init(
            outcome: .succeeded(payload),
            cachePolicy: .originatorOnly(7)
        )))

        await getaway.invalidateRecordingForDisconnect(clientId: 7)

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
        getaway.installRecordingRouteStateForTest(.completed(.init(
            outcome: .succeeded(payload),
            cachePolicy: .originatorOnly(7)
        )))

        await getaway.invalidateRecordingForDisconnect(clientId: 99)

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
        getaway.installRecordingRouteStateForTest(.stopping(stakeout: stubStakeout, waiter: .init(
            requestId: "stop-1",
            ownerClientId: 3,
            respond: { _ in deliveriesAfterDisconnect += 1 }
        )))

        await getaway.invalidateRecordingForDisconnect(clientId: 3)

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
        getaway.installRecordingRouteStateForTest(.completed(.init(
            outcome: .succeeded(payload),
            cachePolicy: .originatorOnly(7)
        )))

        await getaway.invalidateRecordingForSessionRelease()

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
        getaway.installRecordingRouteStateForTest(.recording(stakeout: stubStakeout, ownerClientId: 99))
        await getaway.invalidateRecordingForDisconnect(clientId: 99)
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

    func testDisconnectWhileRecordingFinalizesOnceAndClearsRoute() async throws {
        let (getaway, _, _) = await makeGetaway()
        let completion = expectation(description: "recording finalized")
        completion.assertForOverFulfill = true
        let completions = RecordingCompletionBox()
        let stakeout = TheStakeout(captureFrame: { @MainActor in nil })
        await stakeout.setOnRecordingComplete { _ in
            completions.increment()
            completion.fulfill()
        }
        try await stakeout.startRecording(
            config: RecordingConfig(inactivityTimeout: 60.0, maxDuration: 60.0),
            screen: Self.recordingTestScreen
        )
        getaway.installRecordingRouteStateForTest(.recording(stakeout: stakeout, ownerClientId: 7))
        getaway.brains.stakeout = stakeout

        await getaway.invalidateRecordingForDisconnect(clientId: 7)
        await fulfillment(of: [completion], timeout: 5.0)

        XCTAssertEqual(completions.count, 1, "Invalidating an active recording should finalize exactly once")
        let recorderIsIdleAfterDisconnect = await stakeout.isIdle
        XCTAssertTrue(recorderIsIdleAfterDisconnect, "Recorder should be fully finalized after disconnect invalidation")
        assertRecordingRouteCleared(getaway)
        try await assertFutureDriverCannotDrainRecording(from: getaway)
    }

    func testSessionReleaseWhileRecordingFinalizesOnceAndClearsRoute() async throws {
        let (getaway, _, _) = await makeGetaway()
        let completion = expectation(description: "recording finalized")
        completion.assertForOverFulfill = true
        let completions = RecordingCompletionBox()
        let stakeout = TheStakeout(captureFrame: { @MainActor in nil })
        await stakeout.setOnRecordingComplete { _ in
            completions.increment()
            completion.fulfill()
        }
        try await stakeout.startRecording(
            config: RecordingConfig(inactivityTimeout: 60.0, maxDuration: 60.0),
            screen: Self.recordingTestScreen
        )
        getaway.installRecordingRouteStateForTest(.recording(stakeout: stakeout, ownerClientId: 7))
        getaway.brains.stakeout = stakeout

        await getaway.invalidateRecordingForSessionRelease()
        await fulfillment(of: [completion], timeout: 5.0)

        XCTAssertEqual(completions.count, 1, "Session release should finalize an active recorder exactly once")
        let recorderIsIdleAfterSessionRelease = await stakeout.isIdle
        XCTAssertTrue(recorderIsIdleAfterSessionRelease, "Recorder should be fully finalized after session release")
        assertRecordingRouteCleared(getaway)
        try await assertFutureDriverCannotDrainRecording(from: getaway)
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
        getaway.installRecordingRouteStateForTest(.completed(.init(
            outcome: .succeeded(payload),
            cachePolicy: .originatorOnly(7)
        )))

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
        getaway.installRecordingRouteStateForTest(.completed(.init(
            outcome: .succeeded(payload),
            cachePolicy: .anySessionClient
        )))

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
        getaway.installRecordingRouteStateForTest(.recording(stakeout: stubStakeout, ownerClientId: 7))
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
        getaway.installRecordingRouteStateForTest(.recording(stakeout: stubStakeout, ownerClientId: 7))

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
            disconnectClient: { _ in },
            onClientAuthenticated: { _, _ in },
            onSessionActiveChanged: { _ in }
        )
        await muscle.installAuthenticatedClientForTest(7)
        let stubStakeout = TheStakeout(captureFrame: { @MainActor in nil })
        getaway.installRecordingRouteStateForTest(.recording(stakeout: stubStakeout, ownerClientId: 7))

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
        elements: [(label: String, traits: UIAccessibilityTraits, heistId: HeistId)]
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

    private func installRecordingActivityWindow(title: String) throws -> (UIWindow, UIButton) {
        guard let scene = UIApplication.shared.connectedScenes
            .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene
        else {
            throw XCTSkip("No foreground-active UIWindowScene available in test host")
        }

        let button = UIButton(type: .system)
        button.setTitle(title, for: .normal)
        button.accessibilityLabel = title
        button.frame = CGRect(x: 40, y: 120, width: 240, height: 44)

        let rootView = UIView(frame: UIScreen.main.bounds)
        rootView.backgroundColor = .white
        rootView.accessibilityViewIsModal = true
        rootView.addSubview(button)

        let viewController = UIViewController()
        viewController.view = rootView

        let window = UIWindow(windowScene: scene)
        window.windowLevel = .alert + 30
        window.rootViewController = viewController
        window.frame = UIScreen.main.bounds
        window.isHidden = false
        window.layoutIfNeeded()

        return (window, button)
    }

    private func assertRecordingRouteCleared(
        _ getaway: TheGetaway,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertNil(getaway.brains.stakeout, "Brains must not retain the invalidated recorder", file: file, line: line)
        XCTAssertNil(getaway.stakeout, "Getaway route must not expose an active recorder", file: file, line: line)
        XCTAssertNil(getaway.pendingRecordingResponse, "Invalidation must clear any parked stop waiter", file: file, line: line)
        XCTAssertNil(getaway.recordingOriginatorClientId, "Invalidation must clear route ownership", file: file, line: line)
        if case .idle = getaway.recordingPhase {
            // expected
        } else {
            XCTFail("Recording phase should be idle after invalidation, got \(getaway.recordingPhase)", file: file, line: line)
        }
        if case .none = getaway.completedRecording {
            // expected
        } else {
            XCTFail("Invalidation must not leave a cached payload, got \(getaway.completedRecording)", file: file, line: line)
        }
    }

    private func assertFutureDriverCannotDrainRecording(
        from getaway: TheGetaway,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        var stopResponse: Data?
        await getaway.handleStopRecording(clientId: 42, requestId: "future-driver-stop") { data in
            stopResponse = data
        }
        let response = try XCTUnwrap(stopResponse, "Future driver stop should receive an error response", file: file, line: line)
        let envelope = try decodeResponseEnvelope(from: response)
        XCTAssertEqual(envelope.requestId, "future-driver-stop", file: file, line: line)
        guard case .error(let serverError) = envelope.message else {
            XCTFail("Future driver must not receive a recording payload, got \(envelope.message)", file: file, line: line)
            return
        }
        XCTAssertTrue(serverError.message.contains("No recording in progress"), file: file, line: line)
    }

    private func decodeResponseEnvelope(from data: Data) throws -> ResponseEnvelope {
        let trimmed = data.last == 0x0A ? data.dropLast() : data
        return try JSONDecoder().decode(ResponseEnvelope.self, from: trimmed)
    }
}
#endif // canImport(UIKit)
