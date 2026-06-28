import Foundation
import Network
import os

import TheScore

/// TCP server using Network framework.
/// Owns listener lifecycle and bridges Network callbacks into actor isolation.
/// Actor-isolated — all mutable state is protected by Swift concurrency.
private let logger = ButtonHeistLog.logger(.handoff(.server))

actor SimpleSocketServer {
    // MARK: - State Machines

    private enum ServerPhase {
        case stopped
        case listening(listener: NWListener, port: UInt16)
    }

    // MARK: - Actor-isolated mutable state

    private var serverPhase: ServerPhase = .stopped
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
    ///   - tlsParameters: Non-optional TLS parameters. Production startup must not fall back to plaintext.
    ///   - callbacks: Optional callbacks to install before starting
    /// - Returns: Actual port number bound
    func startAsync(
        port: UInt16 = 0,
        bindToLoopback: Bool = false,
        tlsParameters: NWParameters,
        callbacks: SocketServerCallbacks? = nil
    ) async throws -> UInt16 {
        logger.info("TLS configured for server")
        return try await startListening(
            port: port,
            bindToLoopback: bindToLoopback,
            parameters: tlsParameters,
            callbacks: callbacks
        )
    }

    /// Start a plaintext listener for tests that exercise raw socket behavior.
    /// Production callers must use `startAsync(... tlsParameters:)`.
    func startPlaintextForTests(
        port: UInt16 = 0,
        bindToLoopback: Bool = false,
        callbacks: SocketServerCallbacks? = nil
    ) async throws -> UInt16 {
        try await startListening(
            port: port,
            bindToLoopback: bindToLoopback,
            parameters: .tcp,
            callbacks: callbacks
        )
    }

    private func startListening(
        port: UInt16,
        bindToLoopback: Bool,
        parameters: NWParameters,
        callbacks: SocketServerCallbacks?
    ) async throws -> UInt16 {
        guard case .stopped = serverPhase else {
            throw ServerError.alreadyRunning
        }

        if let callbacks { self.clientLifecycle.callbacks = callbacks }
        let listenerStartup = try await SocketListenerStartup.start(
            port: port,
            bindToLoopback: bindToLoopback,
            parameters: parameters,
            queue: queue
        ) { [weak self] connection in
            guard let self else { return }
            self.spawnTrackedTask { server in
                await server.handleNewConnection(connection)
            }
        }

        self.serverPhase = .listening(listener: listenerStartup.listener, port: listenerStartup.port)
        self._syncListeningPort.withLock { $0 = listenerStartup.port }

        return listenerStartup.port
    }

    /// Stop the server.
    func stop() {
        guard case .listening(let listener, _) = serverPhase else { return }

        let allClients = clientRegistry.drain()
        pendingCallbackTasks.cancelAll()
        serverPhase = .stopped
        _syncListeningPort.withLock { $0 = 0 }

        clientLifecycle.cancelClientsWithoutNotifying(allClients)
        listener.cancel()
        logger.info("Server stopped")
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
                    guard admission.shouldAccept else { return }
                    let clientId = await server.acceptReadyConnection(connection)
                    if admission.assign(clientId), let clientId {
                        await server.removeClient(clientId)
                    }
                }
            case .failed(let error):
                logger.error("Client connection failed: \(error)")
                if let clientId = admission.cancel() {
                    self.spawnTrackedTask { server in await server.removeClient(clientId) }
                }
            case .cancelled:
                if let clientId = admission.cancel() {
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
