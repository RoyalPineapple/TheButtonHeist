#if canImport(UIKit)
#if DEBUG
import Network
import XCTest

import ButtonHeistSupport
@testable import TheInsideJob

final class SocketListenerRuntimeLifecycleTests: XCTestCase {
    func testRuntimeOwnsListenerLifecycle() async throws {
        let runtime = SocketListenerRuntime()
        let gate = ListenerRuntimeStartGate()
        let initialPhase = await runtime.phaseForTesting

        let startTask = Task {
            try await runtime.startForTesting {
                await gate.enterAndWaitForRelease()
                return 2468
            }
        }
        await gate.waitUntilEntered()
        let startingPhase = await runtime.phaseForTesting
        let acceptsWhileStarting = await runtime.isAcceptingConnections()

        gate.release()
        let port = try await startTask.value
        let listeningPhase = await runtime.phaseForTesting
        let acceptsWhileListening = await runtime.isAcceptingConnections()

        await runtime.stop()
        let stoppedPhase = await runtime.phaseForTesting
        let acceptsAfterStop = await runtime.isAcceptingConnections()

        XCTAssertEqual(initialPhase, .idle)
        XCTAssertEqual(startingPhase, .starting)
        XCTAssertFalse(acceptsWhileStarting)
        XCTAssertEqual(port, 2468)
        XCTAssertEqual(listeningPhase, .listening(port: 2468))
        XCTAssertTrue(acceptsWhileListening)
        XCTAssertEqual(stoppedPhase, .stopped)
        XCTAssertFalse(acceptsAfterStop)
    }

    func testRuntimeRejectsSecondStartWhileStarting() async throws {
        let runtime = SocketListenerRuntime()
        let gate = ListenerRuntimeStartGate()
        let startTask = Task {
            try await runtime.startForTesting {
                await gate.enterAndWaitForRelease()
                return 2468
            }
        }
        await gate.waitUntilEntered()

        do {
            _ = try await runtime.startForTesting { 9753 }
            XCTFail("Expected the runtime to reject a second start")
        } catch is CancellationError {
            // The runtime has one irreversible lifecycle.
        } catch {
            XCTFail("Expected CancellationError, got \(error)")
        }

        gate.release()
        _ = try await startTask.value
        await runtime.stop()
    }

    func testStopDuringStartPreventsStaleListeningTransition() async {
        let runtime = SocketListenerRuntime()
        let gate = ListenerRuntimeStartGate()
        let startTask = Task {
            try await runtime.startForTesting {
                await gate.enterAndWaitForRelease()
                return 2468
            }
        }
        await gate.waitUntilEntered()

        await runtime.stop()
        gate.release()

        do {
            _ = try await startTask.value
            XCTFail("Expected stopped startup to reject its stale completion")
        } catch is CancellationError {
            // Expected: only the runtime may transition itself to listening.
        } catch {
            XCTFail("Expected CancellationError, got \(error)")
        }
        let phase = await runtime.phaseForTesting
        XCTAssertEqual(phase, .stopped)
    }

    func testStaleReadyCallbackCannotAttachToReplacementGeneration() async throws {
        let server = SimpleSocketServer()
        let recorder = ListenerGenerationRecorder()
        await server.setListenerRuntimeStartOverrideForTesting { generation in
            let sequence = await recorder.record(generation)
            return UInt16(24_680 + sequence)
        }

        _ = try await server.startPlaintextForTests(addressFamily: .dualStack)
        let staleGeneration = await recorder.entry(at: 0).generation
        let staleConnection = makeConnection()
        XCTAssertTrue(staleGeneration.own(staleConnection))

        await server.stop()
        _ = try await server.startPlaintextForTests(addressFamily: .dualStack)
        let replacementGeneration = await recorder.entry(at: 1).generation
        let acceptance = await server.acceptReadyConnection(
            staleConnection,
            generation: staleGeneration
        )
        let staleIsCurrent = await server.isCurrentListeningGeneration(staleGeneration)
        let replacementIsCurrent = await server.isCurrentListeningGeneration(replacementGeneration)
        let clientCount = await server.clientCountForTesting

        XCTAssertNotEqual(staleGeneration, replacementGeneration)
        XCTAssertEqual(acceptance, .rejected)
        XCTAssertFalse(staleIsCurrent)
        XCTAssertTrue(replacementIsCurrent)
        XCTAssertEqual(staleGeneration.pendingConnectionCountForTesting, 0)
        XCTAssertEqual(clientCount, 0)
        await server.stop()
    }

    func testConcurrentReadyConnectionsCannotExceedCapacity() async throws {
        let server = SimpleSocketServer()
        let recorder = ListenerGenerationRecorder()
        await server.setListenerRuntimeStartOverrideForTesting { generation in
            _ = await recorder.record(generation)
            return 24_680
        }
        await server.setSendContentForTesting { _, _, completion in
            guard case .contentProcessed(let handler) = completion else { return }
            handler(nil)
        }
        _ = try await server.startPlaintextForTests(addressFamily: .dualStack)
        let generation = await recorder.entry(at: 0).generation
        let connections = (0...SimpleSocketServer.maxConnections).map { _ in makeConnection() }
        connections.forEach { XCTAssertTrue(generation.own($0)) }

        let acceptances = await withTaskGroup(
            of: ReadyConnectionAcceptance.self,
            returning: [ReadyConnectionAcceptance].self
        ) { group in
            for connection in connections {
                group.addTask {
                    await server.acceptReadyConnection(connection, generation: generation)
                }
            }
            return await group.reduce(into: []) { $0.append($1) }
        }

        let registeredClientIds = acceptances.compactMap { acceptance -> Int? in
            guard case .registered(let clientId) = acceptance else { return nil }
            return clientId
        }
        XCTAssertEqual(registeredClientIds.count, SimpleSocketServer.maxConnections)
        XCTAssertEqual(Set(registeredClientIds).count, SimpleSocketServer.maxConnections)
        XCTAssertEqual(acceptances.filter { $0 == .rejected }.count, 1)
        let clientCount = await server.clientCountForTesting
        XCTAssertEqual(clientCount, SimpleSocketServer.maxConnections)
        XCTAssertEqual(generation.pendingConnectionCountForTesting, 0)
        await server.stop()
    }

    func testPartialDualListenerStartupFailureCleansPendingCallbacksAndConnections() async {
        let server = SimpleSocketServer()
        let recorder = ListenerGenerationRecorder()
        let pendingConnection = makeConnection()
        let admissionConnection = makeConnection()
        let callbackTask = await MainActor.run { neverEndingTask() }
        await server.setListenerRuntimeStartOverrideForTesting { generation in
            generation.spawnCallbackTask {
                await withTaskCancellationHandler {
                    await callbackTask.value
                } onCancel: {
                    callbackTask.cancel()
                }
            }
            let ownsPendingConnection = generation.own(pendingConnection)
            let ownsAdmissionConnection = generation.own(admissionConnection)
            let acceptance = await server.acceptReadyConnection(
                admissionConnection,
                generation: generation
            )
            _ = await recorder.record(
                generation,
                ownsPendingConnection: ownsPendingConnection,
                ownsAdmissionConnection: ownsAdmissionConnection,
                acceptance: acceptance
            )
            throw ListenerStartFailure.partialDualListener
        }

        do {
            _ = try await server.startPlaintextForTests(addressFamily: .dualStack)
            XCTFail("Expected partial dual-listener startup to fail")
        } catch let error as ListenerStartFailure {
            XCTAssertEqual(error, .partialDualListener)
        } catch {
            XCTFail("Expected ListenerStartFailure, got \(error)")
        }

        let observation = await recorder.entry(at: 0)
        let clientCount = await server.clientCountForTesting
        XCTAssertTrue(observation.ownsPendingConnection)
        XCTAssertTrue(observation.ownsAdmissionConnection)
        XCTAssertEqual(observation.acceptance, .rejected)
        XCTAssertEqual(observation.generation.pendingConnectionCountForTesting, 0)
        XCTAssertTrue(callbackTask.isCancelled)
        XCTAssertEqual(clientCount, 0)
    }

    private func makeConnection() -> NWConnection {
        NWConnection(
            host: .ipv6(.loopback),
            port: NWEndpoint.Port(rawValue: 9)!,
            using: .tcp
        )
    }
}

private enum ListenerStartFailure: Error, Equatable {
    case partialDualListener
}

private final class ListenerRuntimeStartGate: Sendable {
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

private actor ListenerGenerationRecorder {
    struct Entry: Sendable {
        let generation: SocketListenerGeneration
        let ownsPendingConnection: Bool
        let ownsAdmissionConnection: Bool
        let acceptance: ReadyConnectionAcceptance?
    }

    private var entries: [Entry] = []

    @discardableResult
    func record(
        _ generation: SocketListenerGeneration,
        ownsPendingConnection: Bool = false,
        ownsAdmissionConnection: Bool = false,
        acceptance: ReadyConnectionAcceptance? = nil
    ) -> Int {
        entries.append(
            Entry(
                generation: generation,
                ownsPendingConnection: ownsPendingConnection,
                ownsAdmissionConnection: ownsAdmissionConnection,
                acceptance: acceptance
            )
        )
        return entries.count
    }

    func entry(at index: Int) -> Entry {
        entries[index]
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
