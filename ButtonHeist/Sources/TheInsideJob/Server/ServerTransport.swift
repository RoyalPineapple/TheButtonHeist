import Foundation
import Network

import ButtonHeistSupport
import TheScore

/// Ordered transport-level event emitted by `ServerTransport`.
enum TransportEvent: Sendable {
    case clientConnected(clientId: Int, remoteAddress: String?)
    case clientDisconnected(clientId: Int)
    case dataReceived(clientId: Int, data: Data, respond: @Sendable (Data) -> Void)
    case sendFailed(clientId: Int, failure: ServerSendFailure)
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
            return "Server transport has been stopped and cannot be restarted; create a new transport."
        }
    }
}

private struct ServerTransportStopAttempt: Equatable, Sendable {
    let id: UUID
    let task: Task<Void, Never>

    static func == (lhs: ServerTransportStopAttempt, rhs: ServerTransportStopAttempt) -> Bool {
        lhs.id == rhs.id
    }
}

private struct ServerTransportStartAttempt: Equatable, Sendable {
    let id: UUID
}

private enum ServerTransportRuntimePhase: Equatable, Sendable {
    case initialized
    case starting(ServerTransportStartAttempt)
    case running
    case stopping(ServerTransportStopAttempt)
    case stopped
}

private struct ServerTransportLifecycleMachine: SimpleStateMachine {
    enum Event: Equatable, Sendable {
        case beginStarting(ServerTransportStartAttempt)
        case finishStarting(UUID)
        case failStarting(UUID)
        case beginStopping(ServerTransportStopAttempt?)
        case finishStopping(UUID)
    }

    enum Effect: Equatable, Sendable {}

    enum Rejection: Equatable, Sendable {
        case alreadyRunning
        case stopped
        case staleStartAttempt
        case missingStopAttempt
        case staleStopAttempt
    }

    func advance(
        _ state: ServerTransportRuntimePhase,
        with event: Event
    ) -> StateChange<ServerTransportRuntimePhase, Effect, Rejection> {
        switch (state, event) {
        case (.initialized, .beginStarting(let attempt)):
            return .changed(to: .starting(attempt))
        case (.starting, .beginStarting),
             (.running, .beginStarting):
            return .rejected(.alreadyRunning, stayingIn: state)
        case (.stopping, .beginStarting),
             (.stopped, .beginStarting):
            return .rejected(.stopped, stayingIn: state)

        case (.starting(let attempt), .finishStarting(let id)) where attempt.id == id:
            return .changed(to: .running)
        case (.initialized, .finishStarting),
             (.starting, .finishStarting),
             (.running, .finishStarting),
             (.stopping, .finishStarting),
             (.stopped, .finishStarting):
            return .rejected(.staleStartAttempt, stayingIn: state)

        case (.starting(let attempt), .failStarting(let id)) where attempt.id == id:
            return .changed(to: .initialized)
        case (.initialized, .failStarting),
             (.starting, .failStarting),
             (.running, .failStarting),
             (.stopping, .failStarting),
             (.stopped, .failStarting):
            return .rejected(.staleStartAttempt, stayingIn: state)

        case (.initialized, .beginStopping(nil)):
            return .changed(to: .stopped)
        case (.starting, .beginStopping):
            return .changed(to: .stopped)
        case (.initialized, .beginStopping):
            return .rejected(.missingStopAttempt, stayingIn: state)
        case (.running, .beginStopping(.some(let attempt))):
            return .changed(to: .stopping(attempt))
        case (.running, .beginStopping(nil)):
            return .rejected(.missingStopAttempt, stayingIn: state)
        case (.stopping, .beginStopping),
             (.stopped, .beginStopping):
            return .changed(to: state)

        case (.stopping(let attempt), .finishStopping(let id)) where attempt.id == id:
            return .changed(to: .stopped)
        case (.stopping, .finishStopping):
            return .rejected(.staleStopAttempt, stayingIn: state)
        case (.initialized, .finishStopping),
             (.starting, .finishStopping),
             (.running, .finishStopping),
             (.stopped, .finishStopping):
            return .changed(to: state)
        }
    }
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

    /// Runtime lifecycle. This transport is single-use: `stop()` finishes the
    /// event stream, so a later `start()` must fail instead of creating a
    /// listener whose events cannot be consumed.
    @MainActor private var lifecycle = StateDriver(
        initial: ServerTransportRuntimePhase.initialized,
        machine: ServerTransportLifecycleMachine()
    )

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

    /// Test hook for deterministic listener-start failures after TLS setup.
    @MainActor var startOverride: ((_ port: UInt16, _ bindToLoopback: Bool) async throws -> UInt16)?
    @MainActor var stopOverride: (() async -> Void)?

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
        if case .stopping(let attempt) = lifecycle.state {
            await attempt.task.value
            lifecycle.send(.finishStopping(attempt.id))
        }

        switch lifecycle.state {
        case .initialized:
            break
        case .starting:
            throw ServerTransportError.alreadyRunning
        case .running:
            throw ServerTransportError.alreadyRunning
        case .stopping:
            throw ServerTransportError.stopped
        case .stopped:
            throw ServerTransportError.stopped
        }

        guard let token = token, !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ServerTransportError.tlsTokenRequired
        }
        let params = ButtonHeistTLSPreSharedKey.networkParameters(from: token)
        let attempt = ServerTransportStartAttempt(id: UUID())
        lifecycle.send(.beginStarting(attempt))

        if let startOverride {
            do {
                let actualPort = try await startOverride(port, bindToLoopback)
                let finish = lifecycle.send(.finishStarting(attempt.id))
                guard finish.state == .running else {
                    throw ServerTransportError.stopped
                }
                return actualPort
            } catch {
                _ = lifecycle.send(.failStarting(attempt.id))
                throw error
            }
        }
        let callbacks = makeCallbacks()
        do {
            let actualPort = try await server.startAsync(
                port: port,
                bindToLoopback: bindToLoopback,
                addressFamily: addressFamily,
                tlsParameters: params,
                callbacks: callbacks
            )
            let finish = lifecycle.send(.finishStarting(attempt.id))
            guard finish.state == .running else {
                await server.stop()
                throw ServerTransportError.stopped
            }
            return actualPort
        } catch {
            _ = lifecycle.send(.failStarting(attempt.id))
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
        eventStream.finish()

        switch lifecycle.state {
        case .initialized:
            lifecycle.send(.beginStopping(nil))
            return
        case .starting:
            lifecycle.send(.beginStopping(nil))
            return
        case .stopped:
            return
        case .stopping(let attempt):
            await attempt.task.value
            lifecycle.send(.finishStopping(attempt.id))
            return
        case .running:
            break
        }

        let task: Task<Void, Never>
        if let stopOverride {
            task = Task { await stopOverride() }
        } else {
            task = Task { [server] in
                await server.stop()
            }
        }
        let attempt = ServerTransportStopAttempt(id: UUID(), task: task)
        lifecycle.send(.beginStopping(attempt))
        await task.value
        lifecycle.send(.finishStopping(attempt.id))
    }

    /// Await completion of any in-flight stop operation.
    @MainActor
    func waitForStopped() async {
        if case .starting = lifecycle.state {
            lifecycle.send(.beginStopping(nil))
        } else if case .stopping(let attempt) = lifecycle.state {
            await attempt.task.value
            lifecycle.send(.finishStopping(attempt.id))
        }
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
