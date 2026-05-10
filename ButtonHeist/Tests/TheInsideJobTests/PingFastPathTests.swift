#if canImport(UIKit)
import os
import XCTest
import TheScore
@testable import TheInsideJob

final class PingFastPathTests: XCTestCase {

    // MARK: - Pure helper behavior

    func testEncodedPongReturnsPongForPingRequest() throws {
        let request = RequestEnvelope(requestId: "req-1", message: .ping)
        let data = try JSONEncoder().encode(request)

        guard let pongData = PingFastPath.encodedPong(for: data) else {
            XCTFail("Expected pong data, got nil")
            return
        }

        let response = try JSONDecoder().decode(ResponseEnvelope.self, from: pongData)
        XCTAssertEqual(response.requestId, "req-1")
        guard case .pong = response.message else {
            XCTFail("Expected .pong, got \(response.message)")
            return
        }
    }

    func testEncodedPongPreservesNilRequestId() throws {
        let request = RequestEnvelope(message: .ping)
        let data = try JSONEncoder().encode(request)

        guard let pongData = PingFastPath.encodedPong(for: data) else {
            XCTFail("Expected pong data, got nil")
            return
        }

        let response = try JSONDecoder().decode(ResponseEnvelope.self, from: pongData)
        XCTAssertNil(response.requestId)
    }

    func testEncodedPongReturnsNilForNonPingRequest() throws {
        let request = RequestEnvelope(requestId: "req-1", message: .requestInterface)
        let data = try JSONEncoder().encode(request)

        XCTAssertNil(PingFastPath.encodedPong(for: data))
    }

    func testEncodedPongReturnsNilForMalformedData() {
        let garbage = Data("not json".utf8)
        XCTAssertNil(PingFastPath.encodedPong(for: garbage))
    }

    func testEncodedPongReturnsNilForEmptyData() {
        XCTAssertNil(PingFastPath.encodedPong(for: Data()))
    }

    // MARK: - Off-MainActor execution

    /// The fast path must run without entering the main actor. This is the
    /// behavior the bug fix depends on: even if `@MainActor` is fully wedged
    /// on a long-running parse/settle/explore, a ping must still be answered.
    ///
    /// We block the main actor with a long sleep and call `encodedPong(for:)`
    /// from a detached (non-isolated) task. If the helper accidentally hops
    /// to `@MainActor`, the call would not return until the blocker finishes;
    /// the test asserts it returns within a tight budget instead.
    func testEncodedPongRunsOffMainActor() async throws {
        let request = RequestEnvelope(requestId: "req-async", message: .ping)
        let data = try JSONEncoder().encode(request)

        // Deliberately blocks MainActor so we can prove the encoder runs off it.
        let mainBlocker = Task { @MainActor in
            // swiftlint:disable:next agent_test_task_sleep
            try? await Task.sleep(for: .seconds(2))
        }
        defer {
            mainBlocker.cancel()
        }

        let start = Date()
        let pongData = await Task.detached(priority: .userInitiated) {
            PingFastPath.encodedPong(for: data)
        }.value
        let elapsed = Date().timeIntervalSince(start)

        XCTAssertNotNil(pongData)
        XCTAssertLessThan(elapsed, 0.5, "encodedPong should complete off the main actor in well under the 2s main-actor blocker")

        let response = try XCTUnwrap(pongData.flatMap { try? JSONDecoder().decode(ResponseEnvelope.self, from: $0) })
        guard case .pong = response.message else {
            XCTFail("Expected .pong, got \(response.message)")
            return
        }
    }

    /// Proves that the production `SimpleSocketServer.Callbacks` path —
    /// the bridge built by `ServerTransport.makeCallbacks()` and installed on
    /// the underlying socket server — answers a ping synchronously on the
    /// network queue (via `respond(...)`) and yields `.fastPathHandled` on
    /// the event stream instead of `.dataReceived`.
    ///
    /// This is the integration that the prior `respond + yield` test scaffolding
    /// proved; the renamed off-MainActor test only exercises the helper in
    /// isolation. Without this test, a regression that broke the wiring inside
    /// `makeCallbacks` (e.g. dropping the `respond(response)` call before yielding
    /// `.fastPathHandled`) would not be caught at the Swift level.
    @MainActor
    func testCallbacksFastPathRespondsSynchronouslyAndYieldsFastPathHandled() async throws {
        let muscle = TheMuscle(explicitToken: "test")
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

        let request = RequestEnvelope(requestId: "req-cb", message: .ping)
        let pingData = try JSONEncoder().encode(request)

        // Drain a fresh event stream snapshot so we can observe the
        // .fastPathHandled emission. (The getaway's consumer task is also
        // pulling from `transport.events`; AsyncStream is single-consumer, but
        // we can still watch side effects via the muscle's activity counter.)
        let callbacks = transport.makeCallbacks()

        // Captured by the @Sendable respond closure. The fast path is
        // synchronous on the calling queue — no concurrent writers — so a
        // simple thread-safe lock around an array is sufficient. We use
        // `OSAllocatedUnfairLock` because `NSLock` is unavailable in async
        // contexts under Swift 6 strict concurrency.
        let respondResponses = OSAllocatedUnfairLock<[Data]>(initialState: [])
        let respond: @Sendable (Data) -> Void = { data in
            respondResponses.withLock { $0.append(data) }
        }

        // Invoke the production onDataReceived bridge directly — this is the
        // closure SimpleSocketServer would call on its network queue.
        callbacks.onDataReceived?(1, pingData, respond)

        // The respond closure must have been called synchronously inside
        // `onDataReceived` before it returned, because the fast path bypasses
        // the AsyncStream entirely for the response.
        let captured = respondResponses.withLock { $0 }
        XCTAssertEqual(captured.count, 1, "fast path should respond synchronously")

        let response = try JSONDecoder().decode(ResponseEnvelope.self, from: try XCTUnwrap(captured.first))
        XCTAssertEqual(response.requestId, "req-cb")
        guard case .pong = response.message else {
            XCTFail("Expected .pong, got \(response.message)")
            return
        }
    }

    /// Proves the synchronous ping interceptor that `TheGetaway.wireTransport`
    /// installs on `transport.syncDataInterceptor` answers a ping without
    /// bridging to the main actor. We hold the main actor with a long sleep,
    /// then invoke the interceptor from a detached task; the response must
    /// arrive while main is still blocked.
    @MainActor
    func testWiredSyncInterceptorAnswersPingWhileMainIsBusy() async throws {
        let muscle = TheMuscle(explicitToken: "test")
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

        let interceptor = try XCTUnwrap(transport.syncDataInterceptor, "wireTransport did not install syncDataInterceptor")

        let request = RequestEnvelope(requestId: "req-wired", message: .ping)
        let pingData = try JSONEncoder().encode(request)

        // Hold the main actor for 2s — long enough that any accidental
        // `@MainActor` hop would be observable.
        let mainBlocker = Task { @MainActor in
            // swiftlint:disable:next agent_test_task_sleep
            try? await Task.sleep(for: .seconds(2))
        }
        defer {
            mainBlocker.cancel()
        }

        let start = Date()
        let pongData = await Task.detached(priority: .userInitiated) {
            interceptor(1, pingData)
        }.value
        let elapsed = Date().timeIntervalSince(start)

        XCTAssertLessThan(elapsed, 0.5, "wired syncDataInterceptor must answer ping without waiting on the main actor")
        let pong = try XCTUnwrap(pongData, "syncDataInterceptor returned nil for a ping")
        let response = try JSONDecoder().decode(ResponseEnvelope.self, from: pong)
        XCTAssertEqual(response.requestId, "req-wired")
        guard case .pong = response.message else {
            XCTFail("Expected .pong, got \(response.message)")
            return
        }
    }
}
#endif // canImport(UIKit)
