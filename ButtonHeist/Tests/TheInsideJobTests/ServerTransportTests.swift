import XCTest
import ButtonHeistSupport
import TheScore
@testable import TheInsideJob

final class ServerTransportTests: XCTestCase {

    func testTransportEventStreamUsesCheckedSendableConformance() {
        assertSendable(ServerTransport.EventStream.self)
        assertSendable(ServerTransport.Events.self)
    }

    @MainActor
    func testEventOverflowIsDeliveredAsOrderedTerminalEvent() async {
        let transport = ServerTransport(token: "overflow-test-token")
        let callbacks = transport.makeCallbacks()

        for index in 0..<ServerTransport.eventStreamBufferLimit {
            callbacks.onClientConnected?(index, nil)
        }
        callbacks.onClientDisconnected?(ServerTransport.eventStreamBufferLimit)

        var iterator = transport.events.makeAsyncIterator()
        for _ in 0..<ServerTransport.eventStreamBufferLimit {
            _ = await iterator.next()
        }
        guard case .backlogOverflow(let maxEvents) = await iterator.next() else {
            return XCTFail("Expected a terminal backlog-overflow event")
        }
        XCTAssertEqual(maxEvents, ServerTransport.eventStreamBufferLimit)
    }

    @MainActor
    func testStartAfterStopRestartsTransport() async throws {
        let listeners = TestSocketListenerFactory { invocation in
            .ready(UInt16(49_152 + invocation))
        }
        let transport = ServerTransport(
            token: "restart-token",
            serverDependencies: .init(
                listenerFactory: listeners.listenerFactory
            )
        )

        let firstPort = try await transport.start(
            port: 0,
            bindToLoopback: true,
            addressFamily: .ipv4
        )
        await transport.stop()
        let secondPort = try await transport.start(
            port: 0,
            bindToLoopback: true,
            addressFamily: .ipv4
        )

        XCTAssertEqual(firstPort, 49153)
        XCTAssertEqual(secondPort, 49154)
        XCTAssertEqual(listeners.invocationCount, 2)
        XCTAssertEqual(listeners.cancellationCount, 1)
        await transport.stop()
        XCTAssertEqual(listeners.cancellationCount, 2)
    }

    @MainActor
    func testStopDoesNotTerminateTransportEventStreamBeforeRestart() async throws {
        let listeners = TestSocketListenerFactory(port: 49_152)
        let transport = ServerTransport(
            token: "event-stream-restart-token",
            serverDependencies: .init(listenerFactory: listeners.listenerFactory)
        )

        _ = try await transport.start(port: 0, bindToLoopback: true, addressFamily: .ipv4)
        await transport.stop()
        _ = try await transport.start(port: 0, bindToLoopback: true, addressFamily: .ipv4)
        let iteratorTask = Task { @MainActor in
            var iterator = transport.events.makeAsyncIterator()
            return await iterator.next()
        }

        let callbacks = transport.makeCallbacks()
        callbacks.onClientConnected?(7, "127.0.0.1")

        guard case .clientConnected(let clientId, let remoteAddress) = await iteratorTask.value else {
            return XCTFail("Expected restarted transport to keep delivering events")
        }
        XCTAssertEqual(clientId, 7)
        XCTAssertEqual(remoteAddress, "127.0.0.1")
        await transport.stop()
    }

    @MainActor
    func testDuplicateStartWhileStartingIsRejected() async throws {
        let startGate = TransportStartGate()
        let listeners = TestSocketListenerFactory { _ in
            await startGate.enterAndWaitForRelease()
            return .ready(49_152)
        }
        let transport = ServerTransport(
            token: "starting-token",
            serverDependencies: .init(listenerFactory: listeners.listenerFactory)
        )

        let startTask = Task { @MainActor in
            try await transport.start(port: 0, bindToLoopback: true, addressFamily: .ipv4)
        }
        await startGate.waitUntilEntered()

        do {
            _ = try await transport.start(port: 0, bindToLoopback: true, addressFamily: .ipv4)
            XCTFail("Expected ServerTransport to reject duplicate start while starting")
        } catch let error as ServerTransport.Failure {
            XCTAssertEqual(error, .alreadyRunning)
        } catch {
            XCTFail("Expected ServerTransport.Failure.alreadyRunning, got \(error)")
        }

        startGate.release()
        let port = try await startTask.value
        XCTAssertEqual(port, 49152)
        await transport.stop()
    }

    @MainActor
    func testStopWhileStartingRejectsStaleStartCompletion() async {
        let startGate = TransportStartGate()
        let listeners = TestSocketListenerFactory { _ in
            await startGate.enterAndWaitForRelease()
            return .ready(49_152)
        }
        let transport = ServerTransport(
            token: "starting-token",
            serverDependencies: .init(listenerFactory: listeners.listenerFactory)
        )

        let startTask = Task { @MainActor in
            try await transport.start(port: 0, bindToLoopback: true, addressFamily: .ipv4)
        }
        await startGate.waitUntilEntered()

        await transport.stop()
        startGate.release()

        do {
            _ = try await startTask.value
            XCTFail("Expected stale start completion to be rejected")
        } catch let error as ServerTransport.Failure {
            XCTAssertEqual(error, .stopped)
        } catch {
            XCTFail("Expected ServerTransport.Failure.stopped, got \(error)")
        }
        XCTAssertEqual(transport.listeningPort, 0)
        XCTAssertEqual(listeners.cancellationCount, 1)
    }

    @MainActor
    func testRestartAfterStopDuringStartupWaitsForStaleCompletion() async throws {
        let startGate = TransportStartGate()
        let listeners = TestSocketListenerFactory { invocation in
            guard invocation > 1 else {
                await startGate.enterAndWaitForRelease()
                return .ready(49_152)
            }
            return .ready(49_153)
        }
        let transport = ServerTransport(
            token: "starting-token",
            serverDependencies: .init(listenerFactory: listeners.listenerFactory)
        )

        let staleStart = Task { @MainActor in
            try await transport.start(port: 0, bindToLoopback: true, addressFamily: .ipv4)
        }
        await startGate.waitUntilEntered()
        await transport.stop()
        let restart = Task { @MainActor in
            try await transport.start(port: 0, bindToLoopback: true, addressFamily: .ipv4)
        }

        startGate.release()

        do {
            _ = try await staleStart.value
            XCTFail("Expected the stopped start attempt to be rejected")
        } catch let error as ServerTransport.Failure {
            XCTAssertEqual(error, .stopped)
        }
        let restartedPort = try await restart.value
        XCTAssertEqual(restartedPort, 49153)
        XCTAssertEqual(listeners.invocationCount, 2)
        await transport.stop()
    }

    func testTransportEventStreamReservesTerminalOverflowCapacity() async {
        let eventStream = ServerTransport.EventStream(bufferLimit: 2)
        let callbacks = eventStream.makeCallbacks()
        callbacks.onClientConnected?(1, nil)
        callbacks.onClientConnected?(2, nil)
        callbacks.onClientDisconnected?(3)

        var iterator = eventStream.events.makeAsyncIterator()
        guard case .clientConnected(let first, _) = await iterator.next(),
              case .clientConnected(let second, _) = await iterator.next(),
              case .backlogOverflow(let maxEvents) = await iterator.next()
        else {
            return XCTFail("Expected accepted events followed by terminal overflow")
        }
        XCTAssertEqual(first, 1)
        XCTAssertEqual(second, 2)
        XCTAssertEqual(maxEvents, 2)
    }

    @MainActor
    func testAdvertiseWithoutActiveListenerDoesNotPublish() {
        let transport = ServerTransport(token: "inactive-listener-token")

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

        let txt = advertisement.txtRecord
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
        XCTAssertTrue(advertisement.txtRecord.isEmpty)
    }

    @MainActor
    private final class TransportStartGate {
        private let entered = CompletionSignal()
        private let released = CompletionSignal()

        func enterAndWaitForRelease() async {
            entered.finish()
            await released.wait()
        }

        func waitUntilEntered() async {
            await entered.wait()
        }

        func release() {
            released.finish()
        }
    }
}

private func assertSendable<T: Sendable>(_: T.Type) {}
