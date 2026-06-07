import Foundation
import Network

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

    var errorDescription: String? {
        switch self {
        case .tlsTokenRequired:
            return "TLS token is required before listener startup; listener was not started and Bonjour was not published."
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

    /// In-flight stop task for deterministic lifecycle transitions.
    @MainActor private var stopTask: Task<Void, Never>?

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
    @MainActor var stopOverride: (() -> Task<Void, Never>)?

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
            let stopTask = stop()
            await stopTask.value
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
    func start(port: UInt16 = 0, bindToLoopback: Bool = false) async throws -> UInt16 {
        if let stopTask {
            await stopTask.value
            self.stopTask = nil
        }

        guard let token = token, !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ServerTransportError.tlsTokenRequired
        }
        let params = ButtonHeistTLSPreSharedKey.makeNetworkParameters(token: token)
        if let startOverride {
            let actualPort = try await startOverride(port, bindToLoopback)
            return actualPort
        }
        let callbacks = makeCallbacks()
        let actualPort = try await server.startAsync(
            port: port,
            bindToLoopback: bindToLoopback,
            tlsParameters: params,
            callbacks: callbacks
        )
        return actualPort
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
    @discardableResult
    func stop() -> Task<Void, Never> {
        advertisement.stop()
        eventStream.finish()
        if let stopOverride {
            let task = stopOverride()
            stopTask = task
            return task
        }
        let task = Task { [server] in
            await server.stop()
        }
        stopTask = task
        return task
    }

    /// Await completion of any in-flight stop operation.
    @MainActor
    func waitForStopped() async {
        if let stopTask {
            await stopTask.value
            self.stopTask = nil
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
