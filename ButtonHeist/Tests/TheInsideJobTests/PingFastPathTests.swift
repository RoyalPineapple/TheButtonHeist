#if canImport(UIKit)
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

        let mainBlocker = Task { @MainActor in
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
