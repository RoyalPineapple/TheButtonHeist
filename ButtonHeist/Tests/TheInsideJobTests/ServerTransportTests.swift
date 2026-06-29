import XCTest
import TheScore
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
    func testStartWithoutTokenFailsClosedBeforeListenerStarts() async throws {
        let transport = ServerTransport()

        do {
            _ = try await transport.start(port: 0, bindToLoopback: true)
            XCTFail("Expected ServerTransport to reject listener startup without token")
        } catch let error as ServerTransportError {
            XCTAssertEqual(error, .tlsTokenRequired)
        } catch {
            XCTFail("Expected ServerTransportError, got \(error)")
        }

        XCTAssertEqual(transport.listeningPort, 0)
    }

    func testTransportEventStreamDropsNewestWhenBufferLimitIsReached() {
        let eventStream = TransportEventStream.makeEventStream(
            bufferLimit: ServerTransport.eventStreamBufferLimit
        )
        defer {
            eventStream.continuation.finish()
            withExtendedLifetime(eventStream.events) {}
        }

        for index in 0..<ServerTransport.eventStreamBufferLimit {
            let yieldResult = eventStream.continuation.yield(.clientConnected(clientId: index, remoteAddress: nil))
            guard case .enqueued = yieldResult else {
                return XCTFail("Expected transport event to enqueue before the buffer limit")
            }
        }

        let overflowResult = eventStream.continuation.yield(
            .clientDisconnected(clientId: ServerTransport.eventStreamBufferLimit)
        )
        guard case .dropped = overflowResult else {
            return XCTFail("Expected newest transport event to drop when the buffer limit is reached")
        }
    }

    @MainActor
    func testAdvertiseWithoutActiveListenerDoesNotPublish() {
        let transport = ServerTransport()

        transport.advertise(serviceName: "Inactive")

        XCTAssertFalse(transport.isAdvertisingForTesting)
    }

    @MainActor
    func testBonjourTXTUpdatesPreservePreviousKeys() {
        let advertisement = BonjourAdvertisement()
        defer { advertisement.stop() }

        advertisement.publish(
            serviceName: "TXT Test",
            port: 12345,
            simulatorUDID: "sim",
            additionalTXT: ["first": "one"]
        )
        advertisement.updateTXTRecord(["second": "two"])

        let txt = advertisement.currentTXTRecord
        XCTAssertEqual(txt["first"].flatMap { String(data: $0, encoding: .utf8) }, "one")
        XCTAssertEqual(txt["second"].flatMap { String(data: $0, encoding: .utf8) }, "two")
        XCTAssertEqual(txt[TXTRecordKey.simUDID.rawValue].flatMap { String(data: $0, encoding: .utf8) }, "sim")
        XCTAssertEqual(txt[TXTRecordKey.transport.rawValue].flatMap { String(data: $0, encoding: .utf8) }, "tls-psk")
    }

    @MainActor
    func testStopUnpublishesBonjour() {
        let advertisement = BonjourAdvertisement()
        advertisement.publish(serviceName: "Stop Test", port: 12345)

        advertisement.stop()

        XCTAssertFalse(advertisement.isAdvertising)
        XCTAssertTrue(advertisement.currentTXTRecord.isEmpty)
    }
}
