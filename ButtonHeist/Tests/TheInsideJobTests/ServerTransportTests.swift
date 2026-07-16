import XCTest
import TheScore
@testable import TheInsideJob

final class ServerTransportTests: XCTestCase {

    func testTransportEventStreamUsesCheckedSendableConformance() {
        assertSendable(TransportEventStream.self)
        assertSendable(TransportEventStream.EventStream.self)
    }

    @MainActor
    func testEventOverflowInvokesFailClosedHandler() async {
        let transport = ServerTransport(token: "overflow-test-token")
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
    func testStartAfterStopRestartsTransport() async throws {
        let transport = ServerTransport(token: "restart-token")
        var startCount = 0
        var stopCount = 0
        transport.startOverride = { _, _, _ in
            startCount += 1
            return UInt16(49152 + startCount)
        }
        transport.stopOverride = {
            stopCount += 1
        }

        let firstPort = try await transport.start(port: 0, bindToLoopback: true)
        await transport.stop()
        let secondPort = try await transport.start(port: 0, bindToLoopback: true)

        XCTAssertEqual(firstPort, 49153)
        XCTAssertEqual(secondPort, 49154)
        XCTAssertEqual(startCount, 2)
        XCTAssertEqual(stopCount, 1)
        await transport.stop()
        XCTAssertEqual(stopCount, 2)
    }

    @MainActor
    func testRestartWaitsForStopBeforeReplacingListener() async throws {
        let transport = ServerTransport(token: "replacement-token")
        let stopGate = TransportStartGate()
        var startCount = 0
        var stopCount = 0
        transport.startOverride = { _, _, _ in
            startCount += 1
            return UInt16(50000 + startCount)
        }
        transport.stopOverride = {
            stopCount += 1
            await stopGate.enterAndWaitForRelease()
        }

        let firstPort = try await transport.start(port: 0, bindToLoopback: true)
        let stopTask = Task { @MainActor in
            await transport.stop()
        }
        await stopGate.waitUntilEntered()
        let restartTask = Task { @MainActor in
            try await transport.start(port: 0, bindToLoopback: true)
        }

        XCTAssertEqual(startCount, 1)
        stopGate.release()
        await stopTask.value
        let secondPort = try await restartTask.value

        XCTAssertEqual(firstPort, 50001)
        XCTAssertEqual(secondPort, 50002)
        XCTAssertEqual(stopCount, 1)
        XCTAssertEqual(startCount, 2)
        await transport.stop()
        XCTAssertEqual(stopCount, 2)
    }

    @MainActor
    func testStopDoesNotTerminateTransportEventStreamBeforeRestart() async throws {
        let transport = ServerTransport(token: "event-stream-restart-token")
        transport.startOverride = { _, _, _ in 49152 }
        transport.stopOverride = {}

        _ = try await transport.start(port: 0, bindToLoopback: true)
        await transport.stop()
        _ = try await transport.start(port: 0, bindToLoopback: true)
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
        let transport = ServerTransport(token: "starting-token")
        let startGate = TransportStartGate()
        transport.startOverride = { _, _, _ in
            await startGate.enterAndWaitForRelease()
            return 49152
        }

        let startTask = Task { @MainActor in
            try await transport.start(port: 0, bindToLoopback: true)
        }
        await startGate.waitUntilEntered()

        do {
            _ = try await transport.start(port: 0, bindToLoopback: true)
            XCTFail("Expected ServerTransport to reject duplicate start while starting")
        } catch let error as ServerTransportError {
            XCTAssertEqual(error, .alreadyRunning)
        } catch {
            XCTFail("Expected ServerTransportError.alreadyRunning, got \(error)")
        }

        startGate.release()
        let port = try await startTask.value
        XCTAssertEqual(port, 49152)
        await transport.stop()
    }

    @MainActor
    func testStopWhileStartingRejectsStaleStartCompletion() async throws {
        let transport = ServerTransport(token: "starting-token")
        let startGate = TransportStartGate()
        transport.startOverride = { _, _, _ in
            await startGate.enterAndWaitForRelease()
            return 49152
        }

        let startTask = Task { @MainActor in
            try await transport.start(port: 0, bindToLoopback: true)
        }
        await startGate.waitUntilEntered()

        await transport.stop()
        startGate.release()

        do {
            _ = try await startTask.value
            XCTFail("Expected stale start completion to be rejected")
        } catch let error as ServerTransportError {
            XCTAssertEqual(error, .stopped)
        } catch {
            XCTFail("Expected ServerTransportError.stopped, got \(error)")
        }
        XCTAssertEqual(transport.listeningPort, 0)
    }

    @MainActor
    func testStopDuringUnderlyingListenerStartTranslatesCancellationToStopped() async {
        let transport = ServerTransport(token: "underlying-start-token")
        let startSignal = UnderlyingListenerStartSignal()
        transport.startOverride = { generation, _, _ in
            await startSignal.enter()
            await generation.waitUntilStoppedForTesting()
            throw CancellationError()
        }

        let startTask = Task { @MainActor in
            try await transport.start(port: 0, bindToLoopback: true)
        }
        await startSignal.waitUntilEntered()
        await transport.stop()

        do {
            _ = try await startTask.value
            XCTFail("Expected stopped listener startup to fail")
        } catch let error as ServerTransportError {
            XCTAssertEqual(error, .stopped)
        } catch {
            XCTFail("Expected ServerTransportError.stopped, got \(error)")
        }

        await transport.waitForStopped()
        XCTAssertEqual(transport.listeningPort, 0)
    }

    @MainActor
    func testRestartAfterStopDuringStartupWaitsForStaleCompletion() async throws {
        let transport = ServerTransport(token: "starting-token")
        let startGate = TransportStartGate()
        var startCount = 0
        var lifecycleEvents: [String] = []
        transport.startOverride = { _, _, _ in
            startCount += 1
            if startCount == 1 {
                lifecycleEvents.append("first-started")
                await startGate.enterAndWaitForRelease()
                lifecycleEvents.append("first-finished")
                return 49152
            }
            lifecycleEvents.append("restart-started")
            return 49153
        }

        let staleStart = Task { @MainActor in
            try await transport.start(port: 0, bindToLoopback: true)
        }
        await startGate.waitUntilEntered()
        await transport.stop()
        let restart = Task { @MainActor in
            try await transport.start(port: 0, bindToLoopback: true)
        }

        startGate.release()

        do {
            _ = try await staleStart.value
            XCTFail("Expected the stopped start attempt to be rejected")
        } catch let error as ServerTransportError {
            XCTAssertEqual(error, .stopped)
        }
        let restartedPort = try await restart.value
        XCTAssertEqual(restartedPort, 49153)
        XCTAssertEqual(startCount, 2)
        XCTAssertEqual(
            lifecycleEvents,
            ["first-started", "first-finished", "restart-started"]
        )
        await transport.stop()
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

    @MainActor
    private final class TransportStartGate {
        private var entered = false
        private var released = false
        private var enteredWaiters: [CheckedContinuation<Void, Never>] = []
        private var releaseWaiters: [CheckedContinuation<Void, Never>] = []

        func enterAndWaitForRelease() async {
            entered = true
            let waiters = enteredWaiters
            enteredWaiters.removeAll()
            waiters.forEach { $0.resume() }

            guard !released else { return }
            await withCheckedContinuation { continuation in
                releaseWaiters.append(continuation)
            }
        }

        func waitUntilEntered() async {
            guard !entered else { return }
            await withCheckedContinuation { continuation in
                enteredWaiters.append(continuation)
            }
        }

        func release() {
            released = true
            let waiters = releaseWaiters
            releaseWaiters.removeAll()
            waiters.forEach { $0.resume() }
        }
    }
}

private actor UnderlyingListenerStartSignal {
    private enum State {
        case pending([CheckedContinuation<Void, Never>])
        case entered
    }

    private var state = State.pending([])

    func enter() {
        guard case .pending(let waiters) = state else { return }
        state = .entered
        waiters.forEach { $0.resume() }
    }

    func waitUntilEntered() async {
        guard case .pending = state else { return }
        await withCheckedContinuation { continuation in
            switch state {
            case .pending(var waiters):
                waiters.append(continuation)
                state = .pending(waiters)
            case .entered:
                continuation.resume()
            }
        }
    }
}

private func assertSendable<T: Sendable>(_: T.Type) {}
