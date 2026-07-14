import Foundation
import Network
import os

import ButtonHeistSupport
import TheScore

/// TCP server using Network framework.
/// Owns listener lifecycle and bridges Network callbacks into actor isolation.
/// Actor-isolated — all mutable state is protected by Swift concurrency.
private let logger = ButtonHeistLog.logger(.handoff(.server))

actor SimpleSocketServer {
    // MARK: - Actor-isolated mutable state

    private var currentListener: SocketListenerGeneration?
    var clientRegistry = SocketClientRegistry()

    /// Tasks that bridge `NWListener` / `NWConnection` callbacks into actor
    /// isolation. Tracked so `stop()` can cancel in-flight work — without
    /// tracking, a torn-down listener could still have callback Tasks running
    /// against the stopped actor.
    nonisolated let pendingCallbackTasks = TaskTracker()

    private let _syncListeningPort = OSAllocatedUnfairLock<UInt16>(initialState: 0)

    nonisolated var listeningPort: UInt16 {
        _syncListeningPort.withLock { $0 }
    }

    var callbacks = SocketServerCallbacks()

    #if DEBUG
    private var listenerRuntimeStartOverride: (@Sendable (SocketListenerGeneration) async throws -> UInt16)?
    private var listenerRuntimeStopOverride: (@Sendable () async -> Void)?
    #endif

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

    func setCallbacksForTesting(_ callbacks: SocketServerCallbacks) {
        self.callbacks = callbacks
    }

    #if DEBUG
    func setListenerRuntimeStartOverrideForTesting(
        _ start: (@Sendable (SocketListenerGeneration) async throws -> UInt16)?
    ) {
        listenerRuntimeStartOverride = start
    }

    func setListenerRuntimeStopOverrideForTesting(
        _ stop: (@Sendable () async -> Void)?
    ) {
        listenerRuntimeStopOverride = stop
    }

    func insertClientForTesting(connection: NWConnection) -> Int {
        clientRegistry.insert(connection: connection)
    }

    func clientPhaseForTesting(_ clientId: Int) -> SocketClientPhase? {
        clientRegistry.phase(for: clientId)
    }

    var clientCountForTesting: Int {
        clientRegistry.count
    }

    nonisolated var pendingCallbackCountForTesting: Int {
        pendingCallbackTasks.taskCountForTesting
    }
    #endif

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
        guard currentListener == nil else {
            throw ServerError.alreadyRunning
        }

        let attemptID = UUID()
        #if DEBUG
        let runtime = SocketListenerRuntime(stopOverride: listenerRuntimeStopOverride)
        #else
        let runtime = SocketListenerRuntime()
        #endif
        let generation = SocketListenerGeneration(attemptID: attemptID, runtime: runtime)
        currentListener = generation

        if let callbacks { self.callbacks = callbacks }

        do {
            let port = try await startListenerRuntime(
                generation: generation,
                port: port,
                bindToLoopback: bindToLoopback,
                addressFamily: addressFamily,
                parameters: parameters,
                queue: queue
            )

            guard currentListener == generation,
                  await runtime.isAcceptingConnections()
            else {
                throw CancellationError()
            }

            _syncListeningPort.withLock { $0 = port }
            return port
        } catch {
            if currentListener == generation {
                clearListenerGenerationResources()
            }
            await runtime.stop()
            if currentListener == generation {
                currentListener = nil
            }
            throw error
        }
    }

    private func startListenerRuntime(
        generation: SocketListenerGeneration,
        port: UInt16,
        bindToLoopback: Bool,
        addressFamily: ListenerAddressFamily,
        parameters: NWParameters,
        queue: DispatchQueue
    ) async throws -> UInt16 {
        #if DEBUG
        if let listenerRuntimeStartOverride {
            return try await generation.runtime.startForTesting {
                try await listenerRuntimeStartOverride(generation)
            }
        }
        #endif

        let attemptID = generation.attemptID
        let runtime = generation.runtime
        return try await runtime.start(
            port: port,
            bindToLoopback: bindToLoopback,
            addressFamily: addressFamily,
            parameters: parameters,
            queue: queue
        ) { [weak self, weak runtime, attemptID] connection in
            guard let runtime else {
                connection.cancel()
                return
            }
            let callbackGeneration = SocketListenerGeneration(
                attemptID: attemptID,
                runtime: runtime
            )
            guard callbackGeneration.own(connection) else { return }
            guard let self else {
                callbackGeneration.cancelIfOwned(connection)
                return
            }
            self.spawnTrackedTask { server in
                await server.handleNewConnection(connection, generation: callbackGeneration)
            }
        }
    }

    /// Stop the server.
    func stop() async {
        guard let generation = currentListener else { return }
        clearListenerGenerationResources()
        await generation.runtime.stop()
        if currentListener == generation {
            currentListener = nil
        }
        logger.info("Server stopped")
    }

    private func clearListenerGenerationResources() {
        pendingCallbackTasks.cancelAll()
        _syncListeningPort.withLock { $0 = 0 }
        clientRegistry.cancelAll()
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

    private func handleNewConnection(
        _ connection: NWConnection,
        generation: SocketListenerGeneration
    ) async {
        guard await isCurrentListeningGeneration(generation) else {
            if !generation.cancelIfOwned(connection) {
                connection.cancel()
            }
            return
        }
        let admission = ConnectionAdmission()
        connection.stateUpdateHandler = { [weak self, weak connection] state in
            guard let connection else { return }
            guard let self else {
                if !generation.cancelIfOwned(connection) {
                    connection.cancel()
                }
                return
            }
            switch state {
            case .ready:
                self.spawnTrackedTask { server in
                    guard admission.recordReady() == .accept else { return }
                    guard await server.revalidateReadyConnection(
                        connection,
                        generation: generation
                    ) else {
                        _ = admission.recordAcceptance(.rejected)
                        return
                    }
                    let acceptance = await server.acceptReadyConnection(
                        connection,
                        generation: generation
                    )
                    if case .removeRegisteredClient(let clientId) = admission.recordAcceptance(acceptance) {
                        await server.removeClient(clientId)
                    }
                }
            case .failed(let error):
                logger.error("Client connection failed: \(error)")
                generation.cancelIfOwned(connection)
                if case .removeRegisteredClient(let clientId) = admission.recordCancellation() {
                    self.spawnTrackedTask { server in await server.removeClient(clientId) }
                }
            case .cancelled:
                generation.cancelIfOwned(connection)
                if case .removeRegisteredClient(let clientId) = admission.recordCancellation() {
                    self.spawnTrackedTask { server in await server.removeClient(clientId) }
                }
            default:
                break
            }
        }

        connection.start(queue: queue)
    }

    func isCurrentListeningGeneration(_ generation: SocketListenerGeneration) async -> Bool {
        guard currentListener == generation else { return false }
        guard await generation.runtime.isAcceptingConnections() else { return false }
        return currentListener == generation
    }

    private func revalidateReadyConnection(
        _ connection: NWConnection,
        generation: SocketListenerGeneration
    ) async -> Bool {
        guard await isCurrentListeningGeneration(generation) else {
            if !generation.cancelIfOwned(connection) {
                connection.cancel()
            }
            return false
        }
        return true
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
