import Foundation
import Network

import ButtonHeistSupport
import TheScore

/// Ordered transport-level event emitted by `ServerTransport`.
enum TransportEvent: Sendable {
    case clientConnected(clientId: Int, remoteAddress: String?)
    case clientDisconnected(clientId: Int)
    case dataReceived(clientId: Int, data: Data, respond: SocketResponseHandler)
}

enum ServerTransportError: Error, LocalizedError, Equatable, Sendable {
    case tlsTokenRequired
    case alreadyRunning
    case stopped

    var errorDescription: String? {
        switch self {
        case .tlsTokenRequired:
            return "TLS token is required before listener startup; listener was not started and Bonjour was not published."
        case .alreadyRunning:
            return "Server transport is already running."
        case .stopped:
            return "Server transport stopped before startup completed."
        }
    }
}

private struct ServerTransportStopOperation: Equatable, Sendable {
    let id: UUID
    let task: Task<Void, Never>

    static func == (lhs: ServerTransportStopOperation, rhs: ServerTransportStopOperation) -> Bool {
        lhs.id == rhs.id
    }
}

@MainActor
private final class ServerTransportStartCompletion {
    private enum State {
        case pending([CheckedContinuation<Void, Never>])
        case finished
    }

    private var state = State.pending([])

    func wait() async {
        guard case .pending = state else { return }
        await withCheckedContinuation { continuation in
            switch state {
            case .pending(var waiters):
                waiters.append(continuation)
                state = .pending(waiters)
            case .finished:
                continuation.resume()
            }
        }
    }

    func finish() {
        switch state {
        case .pending(let waiters):
            state = .finished
            waiters.forEach { $0.resume() }
        case .finished:
            return
        }
    }
}

private struct ServerTransportStartOperation: Equatable {
    let id: UUID
    let completion: ServerTransportStartCompletion

    static func == (lhs: ServerTransportStartOperation, rhs: ServerTransportStartOperation) -> Bool {
        lhs.id == rhs.id
    }
}

private enum ServerTransportOperation: Equatable {
    case none
    case start(ServerTransportStartOperation)
    case stop(ServerTransportStopOperation)
}

/// TLS-gated TCP transport plus one ordered event stream.
final class ServerTransport {

    /// Maximum ordered transport events buffered while the consumer is busy.
    ///
    /// Backlog overflow is a transport failure, not a signal to keep allocating:
    /// the server stops and the caller can restart from a clean session.
    nonisolated static let eventStreamBufferLimit = 512

    /// The underlying TCP server (actor-isolated).
    nonisolated let server: SimpleSocketServer

    /// Token used to derive TLS pre-shared key material. Nil is accepted only for inert tests.
    private nonisolated let token: String?

    /// Tracks only in-flight transport operations. Listener state and resources
    /// belong to `SocketListenerRuntime`.
    @MainActor private var operation = ServerTransportOperation.none

    /// Bonjour advertisement lifecycle and TXT record state.
    @MainActor private let advertisement = BonjourAdvertisement()

    /// Owner callback for fail-closed shutdown when ordered event delivery
    /// overflows. If unset, the transport still stops itself and unpublished
    /// Bonjour rather than leaving a stale listener advertised.
    @MainActor private var eventBacklogOverflowHandler: (@MainActor @Sendable (_ maxEvents: Int) async -> Void)?

    // MARK: - Event Stream

    /// Ordered event stream. Only one consumer should iterate it.
    nonisolated let events: AsyncStream<TransportEvent>
    private nonisolated let eventStream: TransportEventStream

    #if DEBUG
    /// Test hooks installed on each `SocketListenerRuntime` before it starts.
    @MainActor var startOverride: (@MainActor @Sendable (
        _ generation: SocketListenerGeneration,
        _ port: UInt16,
        _ bindToLoopback: Bool
    ) async throws -> UInt16)?
    @MainActor var stopOverride: (@MainActor @Sendable () async -> Void)?
    #endif

    @MainActor
    func setEventBacklogOverflowHandler(
        _ handler: (@MainActor @Sendable (_ maxEvents: Int) async -> Void)?
    ) {
        eventBacklogOverflowHandler = handler
    }

    @MainActor
    func handleEventBacklogOverflow(maxEvents: Int) async {
        if let handler = eventBacklogOverflowHandler {
            await handler(maxEvents)
        } else {
            await stop()
        }
    }

    /// The port the server is listening on (0 if not started).
    nonisolated var listeningPort: UInt16 {
        server.listeningPort
    }

    // MARK: - Init

    nonisolated init(token: String? = nil, allowedScopes: Set<ConnectionScope> = ConnectionScope.all) {
        self.server = SimpleSocketServer(allowedScopes: allowedScopes)
        self.token = token
        let eventStream = TransportEventStream(bufferLimit: Self.eventStreamBufferLimit)
        self.eventStream = eventStream
        self.events = eventStream.events
    }

    // No deinit needed: ServerTransport is owned by the TheInsideJob singleton
    // (which never deallocates). All cleanup runs through stop(). NWListener and
    // NWConnection self-clean when references are released.

    // MARK: - Lifecycle

    @MainActor
    @discardableResult
    func start(
        port: UInt16 = 0,
        bindToLoopback: Bool = false,
        addressFamily: ListenerAddressFamily = .dualStack
    ) async throws -> UInt16 {
        if case .stop(let attempt) = operation {
            await attempt.task.value
        }

        switch operation {
        case .none:
            break
        case .start:
            throw ServerTransportError.alreadyRunning
        case .stop:
            throw ServerTransportError.stopped
        }

        guard let token = token, !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ServerTransportError.tlsTokenRequired
        }
        let params = ButtonHeistTLSPreSharedKey.networkParameters(from: token)
        let attempt = ServerTransportStartOperation(
            id: UUID(),
            completion: ServerTransportStartCompletion()
        )
        operation = .start(attempt)
        defer { finishStarting(attempt) }

        #if DEBUG
        if let startOverride {
            await server.setListenerRuntimeStartOverrideForTesting { generation in
                try await startOverride(generation, port, bindToLoopback)
            }
        } else {
            await server.setListenerRuntimeStartOverrideForTesting(nil)
        }
        if let stopOverride {
            await server.setListenerRuntimeStopOverrideForTesting {
                await stopOverride()
            }
        } else {
            await server.setListenerRuntimeStopOverrideForTesting(nil)
        }
        #endif

        let callbacks = makeCallbacks()
        do {
            guard operation == .start(attempt) else {
                throw ServerTransportError.stopped
            }
            let actualPort = try await server.startAsync(
                port: port,
                bindToLoopback: bindToLoopback,
                addressFamily: addressFamily,
                tlsParameters: params,
                callbacks: callbacks
            )
            guard operation == .start(attempt) else {
                await server.stop()
                throw ServerTransportError.stopped
            }
            return actualPort
        } catch SimpleSocketServer.ServerError.alreadyRunning {
            throw ServerTransportError.alreadyRunning
        } catch {
            if case .stop = operation, error is CancellationError {
                throw ServerTransportError.stopped
            }
            throw error
        }
    }

    @MainActor
    internal func makeCallbacks() -> SocketServerCallbacks {
        eventStream.makeCallbacks { [weak self] maxEvents in
            guard let self else { return }
            await self.handleEventBacklogOverflow(maxEvents: maxEvents)
        }
    }

    /// Stop the TCP server and any Bonjour advertisement.
    @MainActor
    func stop() async {
        advertisement.stop()

        switch operation {
        case .start(let startOperation):
            beginStopping(waitingFor: startOperation.completion)
            return
        case .stop(let stopOperation):
            await stopOperation.task.value
            return
        case .none:
            let stopOperation = beginStopping(waitingFor: nil)
            await stopOperation.task.value
        }
    }

    /// Await completion of any in-flight stop operation.
    @MainActor
    func waitForStopped() async {
        if case .start = operation {
            await stop()
        }
        if case .stop(let attempt) = operation {
            await attempt.task.value
        }
    }

    @MainActor
    private func finishStarting(_ startOperation: ServerTransportStartOperation) {
        startOperation.completion.finish()
        guard case .start(let currentOperation) = operation,
              currentOperation == startOperation
        else { return }
        operation = .none
    }

    @MainActor
    @discardableResult
    private func beginStopping(
        waitingFor startCompletion: ServerTransportStartCompletion?
    ) -> ServerTransportStopOperation {
        let id = UUID()
        let task = Task { @MainActor [weak self, server] in
            await server.stop()
            if let startCompletion {
                await startCompletion.wait()
            }
            self?.finishStopping(id: id)
        }
        let stopOperation = ServerTransportStopOperation(id: id, task: task)
        operation = .stop(stopOperation)
        return stopOperation
    }

    @MainActor
    private func finishStopping(id: UUID) {
        guard case .stop(let stopOperation) = operation,
              stopOperation.id == id
        else { return }
        operation = .none
    }

    // MARK: - Bonjour Advertisement

    @MainActor
    func advertise(
        serviceName: String,
        simulatorUDID: String? = nil,
        installationId: String? = nil,
        instanceId: String? = nil,
        additionalTXT: [String: String] = [:]
    ) {
        advertisement.publish(
            serviceName: serviceName,
            port: server.listeningPort,
            simulatorUDID: simulatorUDID,
            installationId: installationId,
            instanceId: instanceId,
            additionalTXT: additionalTXT
        )
    }

    @MainActor
    func updateTXTRecord(_ entries: [String: String]) {
        advertisement.updateTXTRecord(entries)
    }

    /// Stop Bonjour advertisement without stopping the TCP server.
    @MainActor
    func stopAdvertising() {
        advertisement.stop()
    }

    @MainActor
    var isAdvertisingForTesting: Bool {
        advertisement.isAdvertising
    }

    @MainActor
    var currentTXTRecordForTesting: [String: Data] {
        advertisement.currentTXTRecord
    }
}
