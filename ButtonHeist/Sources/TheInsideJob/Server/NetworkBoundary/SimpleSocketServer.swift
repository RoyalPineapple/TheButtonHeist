import Foundation
import Network
import os

import ButtonHeistSupport
import TheScore

/// TCP server using Network framework.
/// Owns listener lifecycle and bridges Network callbacks into actor isolation.
/// Actor-isolated — all mutable state is protected by Swift concurrency.
private let logger = ButtonHeistLog.logger(.handoff(.server))

enum SimpleSocketServerPhase: Equatable, Sendable {
    case stopped
    case starting(UUID)
    case listening(port: UInt16)
}

struct SimpleSocketServerLifecycleMachine: SimpleStateMachine {
    enum Event: Equatable, Sendable {
        case beginStarting(UUID)
        case finishStarting(UUID, port: UInt16)
        case failStarting(UUID)
        case stop
    }

    enum Effect: Equatable, Sendable {
        case clearPublishedPort
        case publishPort(UInt16)
        case stopRuntime
    }

    enum Rejection: Equatable, Sendable {
        case alreadyRunning
        case staleStartAttempt
        case alreadyStopped
    }

    func advance(
        _ state: SimpleSocketServerPhase,
        with event: Event
    ) -> StateChange<SimpleSocketServerPhase, Effect, Rejection> {
        switch (state, event) {
        case (.stopped, .beginStarting(let attemptID)):
            return .changed(to: .starting(attemptID))
        case (.starting, .beginStarting),
             (.listening, .beginStarting):
            return .rejected(.alreadyRunning, stayingIn: state)

        case (.starting(let currentID), .finishStarting(let attemptID, let port)) where currentID == attemptID:
            return .changed(to: .listening(port: port), effects: [.publishPort(port)])
        case (.stopped, .finishStarting),
             (.starting, .finishStarting),
             (.listening, .finishStarting):
            return .rejected(.staleStartAttempt, stayingIn: state)

        case (.starting(let currentID), .failStarting(let attemptID)) where currentID == attemptID:
            return .changed(to: .stopped, effects: [.clearPublishedPort])
        case (.stopped, .failStarting),
             (.starting, .failStarting),
             (.listening, .failStarting):
            return .rejected(.staleStartAttempt, stayingIn: state)

        case (.stopped, .stop):
            return .rejected(.alreadyStopped, stayingIn: .stopped)
        case (.starting, .stop),
             (.listening, .stop):
            return .changed(to: .stopped, effects: [.clearPublishedPort, .stopRuntime])
        }
    }
}

actor SimpleSocketServer {
    // MARK: - Actor-isolated mutable state

    private var lifecycle = StateDriver(
        initial: SimpleSocketServerPhase.stopped,
        machine: SimpleSocketServerLifecycleMachine()
    )
    private var activeListeners: [NWListener] = []
    var clientRegistry = SocketClientRegistry()

    /// Tasks that bridge `NWListener` / `NWConnection` callbacks into actor
    /// isolation. Tracked so `stop()` can cancel in-flight work — without
    /// tracking, a torn-down listener could still have callback Tasks running
    /// against the stopped actor.
    let pendingCallbackTasks = TaskTracker()

    private let _syncListeningPort = OSAllocatedUnfairLock<UInt16>(initialState: 0)

    nonisolated var listeningPort: UInt16 {
        _syncListeningPort.withLock { $0 }
    }

    var clientLifecycle = SocketClientLifecycle()

    /// Connection scopes the server will accept. Connections from disallowed scopes are rejected immediately.
    let allowedScopes: Set<ConnectionScope>

    private let queue = DispatchQueue(label: "com.buttonheist.thehandoff.server")
    var sendContent: (
        @Sendable (
            _ connection: NWConnection,
            _ content: Data,
            _ completion: NWConnection.SendCompletion
        ) -> Void
    ) = { connection, content, completion in
        connection.send(content: content, completion: completion)
    }

    init(allowedScopes: Set<ConnectionScope> = ConnectionScope.all) {
        self.allowedScopes = allowedScopes
    }

    func setSendContentForTesting(
        _ sendContent: @escaping @Sendable (
            _ connection: NWConnection,
            _ content: Data,
            _ completion: NWConnection.SendCompletion
        ) -> Void
    ) {
        self.sendContent = sendContent
    }

    // MARK: - Public API (async, actor-isolated)

    /// Start the production server on the specified port with TLS.
    /// Uses structured concurrency to wait for the listener to become ready.
    /// - Parameters:
    ///   - port: Port to listen on (0 = any available)
    ///   - bindToLoopback: If true, bind to loopback only (simulator builds)
    ///   - addressFamily: Address family or families to bind.
    ///   - tlsParameters: Non-optional TLS parameters. Production startup must not fall back to plaintext.
    ///   - callbacks: Optional callbacks to install before starting
    /// - Returns: Actual port number bound
    func startAsync(
        port: UInt16 = 0,
        bindToLoopback: Bool = false,
        addressFamily: ListenerAddressFamily = .dualStack,
        tlsParameters: NWParameters,
        callbacks: SocketServerCallbacks? = nil
    ) async throws -> UInt16 {
        logger.info("TLS configured for server")
        return try await startListening(
            port: port,
            bindToLoopback: bindToLoopback,
            addressFamily: addressFamily,
            parameters: tlsParameters,
            callbacks: callbacks
        )
    }

    /// Start a plaintext listener for tests that exercise raw socket behavior.
    /// Production callers must use `startAsync(... tlsParameters:)`.
    func startPlaintextForTests(
        port: UInt16 = 0,
        bindToLoopback: Bool = false,
        addressFamily: ListenerAddressFamily = .dualStack,
        callbacks: SocketServerCallbacks? = nil
    ) async throws -> UInt16 {
        try await startListening(
            port: port,
            bindToLoopback: bindToLoopback,
            addressFamily: addressFamily,
            parameters: .tcp,
            callbacks: callbacks
        )
    }

    private func startListening(
        port: UInt16,
        bindToLoopback: Bool,
        addressFamily: ListenerAddressFamily,
        parameters: NWParameters,
        callbacks: SocketServerCallbacks?
    ) async throws -> UInt16 {
        let attemptID = UUID()
        guard case .changed = lifecycle.send(.beginStarting(attemptID)) else {
            throw ServerError.alreadyRunning
        }

        if let callbacks { self.clientLifecycle.callbacks = callbacks }

        do {
            let listenerStartup = try await SocketListenerStartup.start(
                port: port,
                bindToLoopback: bindToLoopback,
                addressFamily: addressFamily,
                parameters: parameters,
                queue: queue
            ) { [weak self] connection in
                guard let self else { return }
                self.spawnTrackedTask { server in
                    await server.handleNewConnection(connection)
                }
            }

            let completion = lifecycle.send(.finishStarting(attemptID, port: listenerStartup.port))
            guard case .changed = completion else {
                listenerStartup.listeners.forEach { $0.cancel() }
                throw CancellationError()
            }

            activeListeners = listenerStartup.listeners
            applyLifecycleEffects(completion.effects)

            return listenerStartup.port
        } catch {
            applyLifecycleEffects(lifecycle.send(.failStarting(attemptID)).effects)
            throw error
        }
    }

    /// Stop the server.
    func stop() {
        let stop = lifecycle.send(.stop)
        guard stop.effects.contains(.stopRuntime) else { return }
        let listeners = activeListeners
        activeListeners = []

        let allClients = clientRegistry.drain()
        pendingCallbackTasks.cancelAll()
        applyLifecycleEffects(stop.effects)

        clientLifecycle.cancelClientsWithoutNotifying(allClients)
        for listener in listeners {
            listener.cancel()
        }
        logger.info("Server stopped")
    }

    private func applyLifecycleEffects(_ effects: [SimpleSocketServerLifecycleMachine.Effect]) {
        for effect in effects {
            switch effect {
            case .clearPublishedPort:
                _syncListeningPort.withLock { $0 = 0 }
            case .publishPort(let port):
                _syncListeningPort.withLock { $0 = port }
            case .stopRuntime:
                continue
            }
        }
    }

    /// Spawn a Task that bridges an `NWListener` / `NWConnection` callback
    /// into actor isolation, recording the handle so `stop()` can cancel
    /// it. The closure body runs on `SimpleSocketServer`'s actor.
    nonisolated func spawnTrackedTask(_ body: @escaping @Sendable (SimpleSocketServer) async -> Void) {
        pendingCallbackTasks.spawn { [weak self] in
            guard let self else { return }
            await body(self)
        }
    }

    // MARK: - Private

    private func handleNewConnection(_ connection: NWConnection) {
        let admission = ConnectionAdmission()
        connection.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                self.spawnTrackedTask { server in
                    guard admission.recordReady() == .accept else { return }
                    let acceptance = await server.acceptReadyConnection(connection)
                    if case .removeRegisteredClient(let clientId) = admission.recordAcceptance(acceptance) {
                        await server.removeClient(clientId)
                    }
                }
            case .failed(let error):
                logger.error("Client connection failed: \(error)")
                if case .removeRegisteredClient(let clientId) = admission.recordCancellation() {
                    self.spawnTrackedTask { server in await server.removeClient(clientId) }
                }
            case .cancelled:
                if case .removeRegisteredClient(let clientId) = admission.recordCancellation() {
                    self.spawnTrackedTask { server in await server.removeClient(clientId) }
                }
            default:
                break
            }
        }

        connection.start(queue: queue)
    }

    // MARK: - Errors

    enum ServerError: Error, LocalizedError, Equatable {
        case failedToBindPort
        case alreadyRunning

        var errorDescription: String? {
            switch self {
            case .failedToBindPort:
                return "Server failed to bind to a port"
            case .alreadyRunning:
                return "Server is already running"
            }
        }
    }
}
