import XCTest
@testable import TheInsideJob

final class ServerTransportTests: XCTestCase {

    @MainActor
    func testEventOverflowInvokesFailClosedHandler() async {
        let transport = ServerTransport()
        let overflow = expectation(description: "overflow handler called")
        var observedMaxEvents: Int?
        transport.setEventBacklogOverflowHandler { maxEvents in
            observedMaxEvents = maxEvents
            overflow.fulfill()
        }
        let callbacks = transport.makeCallbacks()

        for index in 0..<ServerTransport.eventStreamBufferLimit {
            callbacks.onClientConnected?(index, nil)
        }
        callbacks.onClientDisconnected?(ServerTransport.eventStreamBufferLimit)

        await fulfillment(of: [overflow], timeout: 1.0)
        XCTAssertEqual(observedMaxEvents, ServerTransport.eventStreamBufferLimit)
    }

    @MainActor
    func testStartWithoutTLSIdentityFailsClosedBeforeListenerStarts() async throws {
        let transport = ServerTransport()

        do {
            _ = try await transport.start(port: 0, bindToLoopback: true)
            XCTFail("Expected ServerTransport to reject listener startup without TLS")
        } catch let error as ServerTransportError {
            XCTAssertEqual(error, .tlsIdentityRequired)
        } catch {
            XCTFail("Expected ServerTransportError, got \(error)")
        }

        XCTAssertEqual(transport.listeningPort, 0)
    }

    func testTransportEventStreamDropsNewestWhenBufferLimitIsReached() {
        let (stream, continuation) = ServerTransport.makeEventStream()
        defer {
            continuation.finish()
            withExtendedLifetime(stream) {}
        }

        for index in 0..<ServerTransport.eventStreamBufferLimit {
            guard case .enqueued = continuation.yield(.clientConnected(clientId: index, remoteAddress: nil)) else {
                return XCTFail("Expected transport event to enqueue before the buffer limit")
            }
        }

        guard case .dropped = continuation.yield(.clientDisconnected(clientId: ServerTransport.eventStreamBufferLimit)) else {
            return XCTFail("Expected newest transport event to drop when the buffer limit is reached")
        }
    }
}
