import Foundation
import Network
import os

import TheScore

/// TCP server using Network framework.
/// Manages connections, newline-delimited message framing, and broadcasting.
/// Actor-isolated — all mutable state is protected by Swift concurrency.
private let logger = Logger(subsystem: "com.buttonheist.thehandoff", category: "server")

actor SimpleSocketServer {
    typealias DataHandler = @Sendable (Int, Data, @escaping @Sendable (Data) -> Void) -> Void

    private static let maxConnections = 5
    static let maxMessagesPerSecond = SocketRateLimiter.defaultMaxMessagesPerSecond
    private static let errorFlushGracePeriod: Duration = .milliseconds(100)

    // MARK: - State Machines

    private enum ServerPhase {
        case stopped
        case listening(listener: NWListener, port: UInt16)
    }

    // MARK: - Actor-isolated mutable state

    private static let authDeadlineSeconds: UInt64 = 10

    private var serverPhase: ServerPhase = .stopped
    private var clientRegistry = SocketClientRegistry()

    /// Tasks that bridge `NWListener` / `NWConnection` callbacks into actor
    /// isolation. Tracked so `stop()` can cancel in-flight work — without
    /// tracking, a torn-down listener could still have callback Tasks running
    /// against the stopped actor.
    private let pendingCallbackTasks = TaskTracker()

    private let _syncListeningPort = OSAllocatedUnfairLock<UInt16>(initialState: 0)

    nonisolated var listeningPort: UInt16 {
        _syncListeningPort.withLock { $0 }
    }

    // MARK: - Callbacks

    struct Callbacks: Sendable {
        var onClientConnected: (@Sendable (_ clientId: Int, _ remoteAddress: String?) -> Void)?
        var onClientDisconnected: (@Sendable (Int) -> Void)?
        var onDataReceived: DataHandler?
        var onSendFailed: (@Sendable (_ clientId: Int, _ failure: ServerSendFailure) -> Void)?
        var onUnauthenticatedData: (@Sendable (_ clientId: Int, _ data: Data, _ respond: @escaping @Sendable (Data) -> Void) -> Void)?
        var onRateLimited: (@Sendable (_ clientId: Int, _ respond: @escaping @Sendable (Data) -> Void) -> Void)?

        init(
            onClientConnected: (@Sendable (_ clientId: Int, _ remoteAddress: String?) -> Void)? = nil,
            onClientDisconnected: (@Sendable (Int) -> Void)? = nil,
            onDataReceived: DataHandler? = nil,
            onSendFailed: (@Sendable (_ clientId: Int, _ failure: ServerSendFailure) -> Void)? = nil,
            onUnauthenticatedData: (@Sendable (_ clientId: Int, _ data: Data, _ respond: @escaping @Sendable (Data) -> Void) -> Void)? = nil,
            onRateLimited: (@Sendable (_ clientId: Int, _ respond: @escaping @Sendable (Data) -> Void) -> Void)? = nil
        ) {
            self.onClientConnected = onClientConnected
            self.onClientDisconnected = onClientDisconnected
            self.onDataReceived = onDataReceived
            self.onSendFailed = onSendFailed
            self.onUnauthenticatedData = onUnauthenticatedData
            self.onRateLimited = onRateLimited
        }
    }

    private var callbacks = Callbacks()

    /// Connection scopes the server will accept. Connections from disallowed scopes are rejected immediately.
    private let allowedScopes: Set<ConnectionScope>

    private let queue = DispatchQueue(label: "com.buttonheist.thehandoff.server")
    private var sendContent: (
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
        callbacks: Callbacks? = nil
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
        callbacks: Callbacks? = nil
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
        callbacks: Callbacks?
    ) async throws -> UInt16 {
        guard case .stopped = serverPhase else {
            throw ServerError.alreadyRunning
        }

        if let callbacks { self.callbacks = callbacks }
        let host: NWEndpoint.Host = bindToLoopback ? .ipv6(.loopback) : .ipv6(.any)
        parameters.requiredLocalEndpoint = .hostPort(
            host: host,
            port: NWEndpoint.Port(rawValue: port) ?? .any
        )

        let newListener = try NWListener(using: parameters)

        let actualPort: UInt16 = try await withCheckedThrowingContinuation { continuation in
            let resumed = OSAllocatedUnfairLock(initialState: false)
            newListener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    let shouldResume = resumed.withLock { flag -> Bool in
                        guard !flag else { return false }
                        flag = true
                        return true
                    }
                    guard shouldResume else { return }
                    if let port = newListener.port?.rawValue {
                        logger.info("Listening on port \(port)")
                        continuation.resume(returning: port)
                    } else {
                        continuation.resume(throwing: ServerError.failedToBindPort)
                    }
                case .failed(let error):
                    let shouldResume = resumed.withLock { flag -> Bool in
                        guard !flag else { return false }
                        flag = true
                        return true
                    }
                    guard shouldResume else { return }
                    logger.error("Listener failed: \(error)")
                    newListener.cancel()
                    continuation.resume(throwing: error)
                default:
                    break
                }
            }

            newListener.newConnectionHandler = { [weak self] connection in
                guard let self else { return }
                self.spawnTrackedTask { server in
                    await server.handleNewConnection(connection)
                }
            }

            newListener.start(queue: self.queue)
        }

        self.serverPhase = .listening(listener: newListener, port: actualPort)
        self._syncListeningPort.withLock { $0 = actualPort }

        return actualPort
    }

    /// Stop the server.
    func stop() {
        guard case .listening(let listener, _) = serverPhase else { return }

        let allClients = clientRegistry.drain()
        pendingCallbackTasks.cancelAll()
        serverPhase = .stopped
        _syncListeningPort.withLock { $0 = 0 }

        for state in allClients {
            state.authentication.cancelDeadline()
            state.connection.cancel()
        }
        listener.cancel()
        logger.info("Server stopped")
    }

    /// Spawn a Task that bridges an `NWListener` / `NWConnection` callback
    /// into actor isolation, recording the handle so `stop()` can cancel
    /// it. The closure body runs on `SimpleSocketServer`'s actor.
    nonisolated private func spawnTrackedTask(_ body: @escaping @Sendable (SimpleSocketServer) async -> Void) {
        pendingCallbackTasks.spawn { [weak self] in
            guard let self else { return }
            await body(self)
        }
    }

    /// Send data to a specific client.
    ///
    /// Enforces per-client send-buffer accounting before queueing bytes on the socket.
    @discardableResult
    func send(_ data: Data, to clientId: Int) -> ServerSendOutcome {
        var dataToSend = data
        if !dataToSend.hasSuffix(Data([0x0A])) {
            dataToSend.append(0x0A)
        }

        let byteCount = dataToSend.count
        let connection: NWConnection
        switch clientRegistry.reserveSend(clientId: clientId, byteCount: byteCount) {
        case .missingClient:
            return .failed(.clientNotFound(clientId))
        case .accepted(let acceptedConnection):
            connection = acceptedConnection
        case .rejected(let rejection, let state):
            switch rejection {
            case .payloadTooLarge:
                logger.warning("Client \(clientId) send payload exceeds cap (\(byteCount) bytes), failing the originating request")
                sendOversizedResponseError(clientId: clientId, originalData: data, byteCount: byteCount, state: state)
            case .bufferFull(let pendingBytes, _, _):
                logger.warning("Client \(clientId) send buffer full (\(pendingBytes) bytes pending), dropping \(byteCount) bytes")
            }
            return .failed(rejection.sendFailure)
        }

        sendContent(connection, dataToSend, .contentProcessed { [weak self] error in
            if let error {
                logger.error("Send error to client \(clientId): \(error)")
            }
            guard let self else { return }
            self.spawnTrackedTask { server in
                await server.completedSend(clientId: clientId, byteCount: byteCount, error: error)
            }
        })
        return .enqueued
    }

    /// Try to fail the originating request explicitly when a response exceeds the send cap.
    /// Recording responses get `.recording` kind because they use a recording-specific wait path.
    /// Other responses get a request-scoped `.general` kind, allowing the client to fail the pending
    /// request directly instead of surfacing a generic timeout.
    private func sendOversizedResponseError(
        clientId: Int,
        originalData: Data,
        byteCount: Int,
        state: SocketClientRegistry.Client
    ) {
        let envelope: ResponseEnvelope
        do {
            envelope = try JSONDecoder().decode(ResponseEnvelope.self, from: originalData)
        } catch {
            logger.error("Failed to decode oversized response envelope for client \(clientId): \(error.localizedDescription); dropping")
            return
        }
        let message = "Response too large to send over the socket (\(byteCount) bytes)"
        let kind: ErrorKind
        switch envelope.message {
        case .recording, .recordingStarted, .recordingStopped:
            kind = .recording
        default:
            kind = .general
        }
        sendErrorEnvelope(
            clientId: clientId,
            envelope: ResponseEnvelope(
                requestId: envelope.requestId,
                message: .error(TheScore.ServerError(kind: kind, message: message))
            ),
            state: state
        )
    }

    private func sendErrorEnvelope(clientId: Int, envelope: ResponseEnvelope, state: SocketClientRegistry.Client) {
        let response: Data
        do {
            response = try envelope.encoded()
        } catch {
            logger.error("Failed to encode oversized-response error for client \(clientId): \(error.localizedDescription)")
            return
        }
        var errorData = response
        if !errorData.hasSuffix(Data([0x0A])) {
            errorData.append(0x0A)
        }
        sendContent(state.connection, errorData, .contentProcessed { error in
            if let error {
                logger.error("Send error to client \(clientId): \(error)")
            }
        })
    }

    /// Called when NWConnection finishes processing a send.
    private func completedSend(clientId: Int, byteCount: Int, error: NWError?) {
        clientRegistry.completeSend(clientId: clientId, byteCount: byteCount)
        if let error {
            callbacks.onSendFailed?(clientId, .transportFailed(clientId: clientId, message: error.localizedDescription))
        }
    }

    /// Disconnect a client.
    func disconnect(clientId: Int) {
        removeClient(clientId)
    }

    /// Mark a client as authenticated.
    func markAuthenticated(_ clientId: Int) {
        clientRegistry.markAuthenticated(clientId)
    }

    /// Mark a connected client as waiting on the on-device approval prompt.
    func markApprovalPending(_ clientId: Int) {
        guard clientRegistry.markApprovalPending(clientId) else { return }
        logger.info("Client \(clientId): approval pending — waiting for user to tap Allow on device")
    }

    /// Check if a client is authenticated.
    func isAuthenticated(_ clientId: Int) -> Bool {
        clientRegistry.isAuthenticated(clientId)
    }

    /// Broadcast data to all authenticated clients.
    func broadcastToAll(_ data: Data) {
        for clientId in clientRegistry.authenticatedClientIds {
            send(data, to: clientId)
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

    private func acceptReadyConnection(_ connection: NWConnection) -> Int? {
        if clientRegistry.count >= Self.maxConnections {
            logger.warning("Max connections (\(Self.maxConnections)) reached, rejecting")
            rejectStartedConnectionWithServerError(
                connection,
                kind: .general,
                message: "Connection rejected: server already has the maximum number of clients."
            )
            return nil
        }

        let scopeFilter = allowedScopes != ConnectionScope.all ? allowedScopes : nil
        if let scopeFilter {
            guard let host = Self.extractRemoteHost(from: connection) else {
                logger.warning("Cannot classify connection endpoint, rejecting (scope filter active)")
                rejectStartedConnectionWithServerError(
                    connection,
                    kind: .general,
                    message: "Connection rejected: server could not classify the connection scope."
                )
                return nil
            }
            let interfaceNameList = (connection.currentPath?.availableInterfaces ?? []).map(\.name)
            let scope = ConnectionScope.classify(host: host, interfaceNames: interfaceNameList)
            let hostDescription = "\(host)"
            let interfaceNames = interfaceNameList.joined(separator: ", ")
            if !scopeFilter.contains(scope) {
                logger.warning("Rejecting \(scope.rawValue) connection from \(hostDescription) via [\(interfaceNames)]")
                rejectStartedConnectionWithServerError(
                    connection,
                    kind: .general,
                    message: "Connection rejected: \(scope.rawValue) connections are not allowed by this server."
                )
                return nil
            }
            logger.info("Accepted \(scope.rawValue) connection from \(hostDescription) via [\(interfaceNames)]")
        }

        let clientId = clientRegistry.insert(connection: connection) { clientId in
            .awaitingAuthentication(deadline: makeAuthDeadline(for: clientId))
        }
        let remoteAddress = Self.extractRemoteHost(from: connection).map { "\($0)" }
        logger.info("Client \(clientId) connected")
        notifyClientConnected(clientId, address: remoteAddress)
        startReceiving(clientId: clientId, connection: connection)
        return clientId
    }

    private func makeAuthDeadline(for clientId: Int) -> Task<Void, Never> {
        Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(Self.authDeadlineSeconds))
            } catch {
                return
            }
            guard let self else { return }
            switch await self.authentication(for: clientId) {
            case .awaitingAuthentication:
                logger.warning("Client \(clientId) did not authenticate within \(Self.authDeadlineSeconds)s deadline")
                await self.rejectClientWithServerError(
                    clientId,
                    kind: .authFailure,
                    message: "Authentication timed out after \(Self.authDeadlineSeconds) seconds."
                )
            case .awaitingApproval:
                logger.warning("Client \(clientId): approval timed out — user did not respond to the approval prompt on the device")
                await self.rejectClientWithServerError(
                    clientId,
                    kind: .authApprovalPending,
                    message: "Approval timed out — user did not respond to the approval prompt on the device."
                )
            case .authenticated, .none:
                return
            }
        }
    }

    private func notifyClientConnected(_ clientId: Int, address: String?) {
        callbacks.onClientConnected?(clientId, address)
    }

    private func notifyClientDisconnected(_ clientId: Int) {
        callbacks.onClientDisconnected?(clientId)
    }

    private func removeClient(_ clientId: Int) {
        guard let state = clientRegistry.remove(clientId) else { return }
        state.authentication.cancelDeadline()
        state.connection.cancel()
        notifyClientDisconnected(clientId)
    }

    private func rejectStartedConnectionWithServerError(_ connection: NWConnection, kind: ErrorKind, message: String) {
        let response: Data
        do {
            response = try ResponseEnvelope(message: .error(TheScore.ServerError(kind: kind, message: message))).encoded()
        } catch {
            logger.error("Failed to encode connection rejection error: \(error.localizedDescription)")
            connection.cancel()
            return
        }

        var data = response
        if !data.hasSuffix(Data([0x0A])) {
            data.append(0x0A)
        }

        sendContent(connection, data, .contentProcessed { error in
            if let error {
                logger.error("Send error while rejecting unregistered connection: \(error)")
            }
            connection.cancel()
        })
    }

    private func rejectClientWithServerError(_ clientId: Int, kind: ErrorKind, message: String) {
        guard let state = clientRegistry.client(clientId) else { return }
        sendErrorEnvelope(
            clientId: clientId,
            envelope: ResponseEnvelope(message: .error(TheScore.ServerError(kind: kind, message: message))),
            state: state
        )
        scheduleErrorFlushDisconnect(clientId)
    }

    private func scheduleErrorFlushDisconnect(_ clientId: Int) {
        pendingCallbackTasks.spawn { [weak self] in
            guard await Task.cancellableSleep(for: Self.errorFlushGracePeriod) else { return }
            await self?.removeClient(clientId)
        }
    }

    private func authentication(for clientId: Int) -> SocketClientAuthentication? {
        clientRegistry.authentication(for: clientId)
    }

    private func notifyRateLimit(_ clientId: Int) {
        callbacks.onRateLimited?(clientId) { [weak self] response in
            guard let self else { return }
            self.spawnTrackedTask { server in await server.send(response, to: clientId) }
        }
    }

    private func startReceiving(clientId: Int, connection: NWConnection) {
        receiveNextChunk(clientId: clientId, connection: connection, framer: SocketReceiveFramer())
    }

    private func receiveNextChunk(clientId: Int, connection: NWConnection, framer: SocketReceiveFramer) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] content, _, isComplete, error in
            guard let self else { return }
            self.spawnTrackedTask { server in
                await server.handleReceivedData(
                    clientId: clientId,
                    connection: connection,
                    content: content,
                    isComplete: isComplete,
                    error: error,
                    framer: framer
                )
            }
        }
    }

    /// Process received data within actor isolation.
    private func handleReceivedData(
        clientId: Int,
        connection: NWConnection,
        content: Data?,
        isComplete: Bool,
        error: NWError?,
        framer: SocketReceiveFramer
    ) {
        if let error {
            logger.error("Receive error from client \(clientId): \(error)")
            removeClient(clientId)
            return
        }

        var receiveFramer = framer
        let messageFrames: [Data]
        do {
            messageFrames = try receiveFramer.append(content)
        } catch {
            logger.error("Client \(clientId) exceeded max buffer size, disconnecting")
            rejectClientWithServerError(
                clientId,
                kind: .validationError,
                message: "Inbound message exceeded the server buffer limit."
            )
            return
        }

        for messageData in messageFrames {
            switch clientRegistry.recordInboundMessage(clientId: clientId) {
            case .missingClient:
                return
            case .rateLimited(let authenticated, let shouldNotify):
                if authenticated {
                    logger.warning("Client \(clientId) rate limited, dropping message")
                } else {
                    logger.warning("Unauthenticated client \(clientId) rate limited, dropping message")
                }
                if shouldNotify {
                    notifyRateLimit(clientId)
                }
                continue
            case .accepted(let authenticated):
                let dataHandler = authenticated ? callbacks.onDataReceived : callbacks.onUnauthenticatedData
                dataHandler?(clientId, messageData) { [weak self] response in
                    guard let self else { return }
                    self.spawnTrackedTask { server in await server.send(response, to: clientId) }
                }
            }
        }

        if isComplete {
            removeClient(clientId)
        } else {
            receiveNextChunk(clientId: clientId, connection: connection, framer: receiveFramer)
        }
    }

    /// Extract the remote host from an NWConnection using typed Network framework values.
    /// Checks the connection endpoint directly (always available), with currentPath as fallback.
    nonisolated private static func extractRemoteHost(from connection: NWConnection) -> NWEndpoint.Host? {
        if case .hostPort(let host, _) = connection.endpoint {
            return host
        }
        if case .hostPort(let host, _) = connection.currentPath?.remoteEndpoint {
            return host
        }
        return nil
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

extension Data {
    func hasSuffix(_ suffixData: Data) -> Bool {
        guard count >= suffixData.count else { return false }
        return self.suffix(suffixData.count) == suffixData
    }
}
