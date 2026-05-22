import Foundation
import Network
import os.log

import TheScore

private let logger = Logger(subsystem: "com.buttonheist.thehandoff", category: "transport")

/// Ordered transport-level event emitted by `ServerTransport`.
///
/// Each case mirrors a callback that `SimpleSocketServer` previously fired on
/// the network queue. Routing every event through one ordered stream means the
/// consumer cannot observe a `dataReceived` for a client before its
/// `clientConnected` — a race the prior per-event `Task { @MainActor in ... }`
/// bridge could lose.
enum TransportEvent: Sendable {
    /// A client TCP connection became `.ready`.
    case clientConnected(clientId: Int, remoteAddress: String?)
    /// A client connection was cancelled or failed.
    case clientDisconnected(clientId: Int)
    /// An authenticated client sent a complete message. `respond` enqueues a
    /// reply on the underlying connection's send queue.
    case dataReceived(clientId: Int, data: Data, respond: @Sendable (Data) -> Void)
    /// An unauthenticated client sent a complete message; the consumer must
    /// decide whether the message is allowed in the unauthenticated state.
    case unauthenticatedData(clientId: Int, data: Data, respond: @Sendable (Data) -> Void)
    /// The client exceeded the per-second message cap; `respond` lets the
    /// consumer notify the client once per rate-limit window.
    case rateLimited(clientId: Int, respond: @Sendable (Data) -> Void)
    /// A `dataReceived` payload was answered synchronously on the network
    /// queue by `syncDataInterceptor`. The consumer typically only needs to
    /// note client activity; the response has already been sent.
    case fastPathHandled(clientId: Int)
    /// Network.framework reported that an enqueued server-to-client send failed.
    case sendFailed(clientId: Int, failure: ServerSendFailure)
}

private final class TransportOverflowStopper: @unchecked Sendable { // swiftlint:disable:this agent_unchecked_sendable_no_comment
    weak var transport: ServerTransport?

    init(transport: ServerTransport) {
        self.transport = transport
    }

    @MainActor
    func stop(maxEvents: Int) async {
        guard let transport else { return }
        await transport.handleEventBacklogOverflow(maxEvents: maxEvents)
    }
}

enum ServerTransportError: Error, LocalizedError, Equatable, Sendable {
    case tlsIdentityRequired
    case tlsParametersUnavailable(fingerprint: String)

    var errorDescription: String? {
        switch self {
        case .tlsIdentityRequired:
            return "TLS identity is required before listener startup; listener was not started and Bonjour was not published."
        case .tlsParametersUnavailable(let fingerprint):
            return "TLS parameters could not be created for identity \(fingerprint); listener was not started and Bonjour was not published."
        }
    }
}

/// Server-side transport layer for TheInsideJob.
///
/// Combines `SimpleSocketServer` (TCP) with Bonjour `NetService` advertisement
/// into a single type that TheInsideJob can delegate to for all networking concerns.
///
/// Transport events (client connected, data received, rate limited, etc.) are
/// delivered as a single ordered `AsyncStream<TransportEvent>` consumed via
/// `events`. Callers run a single `for await` loop and dispatch by case.
/// Ordering is preserved by construction — there is no per-event `Task` race
/// that could land out of order on the consumer's actor.
///
/// `ServerTransport` is single-use: once `stop()` finishes the event stream,
/// create a new instance for any subsequent run.
///
/// Usage:
/// ```
/// let transport = ServerTransport()
/// transport.setSyncDataInterceptor { clientId, data in ... }  // optional fast path
/// let port = try await transport.start()
/// transport.advertise(serviceName: "MyApp#abc")
/// for await event in transport.events { ... }
/// ```
///
/// Isolation: lifecycle methods (`start`, `stop`, `advertise`, `setSyncDataInterceptor`)
/// are `@MainActor`-isolated because they mutate Bonjour and lifecycle state that the
/// owning `TheInsideJob` (also MainActor) reads synchronously. The pass-through helpers
/// (`send`, `broadcastToAll`, `markAuthenticated`, `markApprovalPending`, `disconnect`, `listeningPort`) only
/// touch the inner `SimpleSocketServer` actor reference and are nonisolated, so callers
/// on any context can use them without an actor hop.
final class ServerTransport: NSObject {

    /// Maximum ordered transport events buffered while the consumer is busy.
    ///
    /// Backlog overflow is a transport failure, not a signal to keep allocating:
    /// the server stops and the caller can restart from a clean session.
    nonisolated static let eventStreamBufferLimit = 512

    /// The underlying TCP server (actor-isolated).
    nonisolated let server: SimpleSocketServer

    /// TLS identity for encrypted transport.
    ///
    /// A nil identity is accepted only so tests can build an inert transport.
    /// `start` and `advertise` fail closed when no identity is present.
    private nonisolated let tlsIdentity: TLSIdentity?

    /// The Bonjour service, if advertising.
    @MainActor private var netService: NetService?

    /// In-flight stop task for deterministic lifecycle transitions.
    @MainActor private var stopTask: Task<Void, Never>?

    /// Callback bridge work that must be cancelled during transport teardown.
    private nonisolated let callbackTasks = TaskTracker()

    /// Current TXT record entries (preserved across updates).
    @MainActor private var currentTXT: [String: Data] = [:]

    /// Owner callback for fail-closed shutdown when ordered event delivery
    /// overflows. If unset, the transport still stops itself and unpublished
    /// Bonjour rather than leaving a stale listener advertised.
    @MainActor private var eventBacklogOverflowHandler: (@MainActor @Sendable (_ maxEvents: Int) async -> Void)?

    // MARK: - Event Stream

    /// Ordered event stream. Each call returns the same stream; only one
    /// consumer should `for await` it at a time.
    nonisolated let events: AsyncStream<TransportEvent>

    /// Continuation for `events`. Yielded to from network-queue callbacks
    /// (`@Sendable`) and finished when the transport is stopped.
    private nonisolated let eventContinuation: AsyncStream<TransportEvent>.Continuation

    /// Synchronous interceptor for off-MainActor fast-path responses.
    ///
    /// Called on the network queue *before* a `.dataReceived` event is yielded
    /// for an authenticated client. If it returns non-nil, the transport sends
    /// the response synchronously and yields a `.fastPathHandled(clientId:)`
    /// event instead. Used to keep ping/pong responsive when the consumer's
    /// actor is wedged on long-running work. Returning nil falls through to
    /// the normal `.dataReceived` path.
    ///
    /// The interceptor is snapshotted at `start()` time; assigning it after
    /// `start()` has been called is a programmer error and trips a
    /// `precondition` rather than being silently dropped. Use
    /// `setSyncDataInterceptor(_:)` to install one before starting.
    @MainActor private(set) var syncDataInterceptor: (@Sendable (_ clientId: Int, _ data: Data) -> Data?)?

    /// Tracks whether `start()` has been called. Once set, the interceptor is
    /// frozen; later assignments would be silently captured-by-value at
    /// `makeCallbacks()` time and have no effect on the running transport.
    @MainActor private var hasStarted = false

    /// Test hook for deterministic listener-start failures after TLS setup.
    @MainActor var startOverride: ((_ port: UInt16, _ bindToLoopback: Bool) async throws -> UInt16)?

    /// Install a synchronous data interceptor. Must be called before
    /// `start()`; calls after start are ignored because `makeCallbacks()`
    /// snapshots the interceptor by value.
    @MainActor
    func setSyncDataInterceptor(_ interceptor: (@Sendable (_ clientId: Int, _ data: Data) -> Data?)?) {
        guard !hasStarted else {
            logger.warning("Ignoring syncDataInterceptor assignment after start; makeCallbacks() snapshots it by value")
            return
        }
        syncDataInterceptor = interceptor
    }

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

    nonisolated init(tlsIdentity: TLSIdentity? = nil, allowedScopes: Set<ConnectionScope> = ConnectionScope.all) {
        self.server = SimpleSocketServer(allowedScopes: allowedScopes)
        self.tlsIdentity = tlsIdentity
        (self.events, self.eventContinuation) = Self.makeEventStream()
        super.init()
    }

    // No deinit needed: ServerTransport is owned by the TheInsideJob singleton
    // (which never deallocates). All cleanup runs through stop(). NWListener and
    // NWConnection self-clean when references are released.

    // MARK: - Lifecycle

    /// Start the TCP server on the specified port.
    /// - Parameters:
    ///   - port: Port to listen on (0 = any available)
    ///   - bindToLoopback: If true, bind to loopback only
    /// - Returns: Actual port number bound
    @MainActor
    @discardableResult
    func start(port: UInt16 = 0, bindToLoopback: Bool = false) async throws -> UInt16 {
        if let stopTask {
            await stopTask.value
            self.stopTask = nil
        }

        guard let tlsIdentity else {
            throw ServerTransportError.tlsIdentityRequired
        }
        guard let params = await tlsIdentity.makeTLSParameters() else {
            throw ServerTransportError.tlsParametersUnavailable(fingerprint: tlsIdentity.fingerprint)
        }
        if let startOverride {
            let actualPort = try await startOverride(port, bindToLoopback)
            hasStarted = true
            return actualPort
        }
        let callbacks = makeCallbacks()
        let actualPort = try await server.startAsync(
            port: port,
            bindToLoopback: bindToLoopback,
            tlsParameters: params,
            callbacks: callbacks
        )
        hasStarted = true
        return actualPort
    }

    /// Build the bridge callbacks that yield onto `eventContinuation`.
    ///
    /// Each closure is `@Sendable` because `SimpleSocketServer` invokes it on
    /// its own network queue, not the main actor. The continuation is itself
    /// Sendable; `yield` is safe to call from any context. The synchronous
    /// data interceptor is snapshotted here at start time; later interceptor
    /// assignments are ignored because they would not reach the captured
    /// `interceptor` constant.
    @MainActor
    internal func makeCallbacks() -> SimpleSocketServer.Callbacks {
        let continuation = eventContinuation
        let interceptor = syncDataInterceptor
        let callbackTasks = callbackTasks
        let overflow = TransportOverflowStopper(transport: self)
        let onOverflow: @Sendable () -> Void = {
            logger.error("Transport event backlog exceeded \(Self.eventStreamBufferLimit), stopping server")
            let task = Task { @MainActor in
                await overflow.stop(maxEvents: Self.eventStreamBufferLimit)
            }
            callbackTasks.record(task)
        }
        return SimpleSocketServer.Callbacks(
            onClientConnected: { clientId, remoteAddress in
                Self.yieldEvent(
                    .clientConnected(clientId: clientId, remoteAddress: remoteAddress),
                    to: continuation,
                    onOverflow: onOverflow
                )
            },
            onClientDisconnected: { clientId in
                Self.yieldEvent(.clientDisconnected(clientId: clientId), to: continuation, onOverflow: onOverflow)
            },
            onDataReceived: { clientId, data, respond in
                if let interceptor, let response = interceptor(clientId, data) {
                    respond(response)
                    Self.yieldEvent(.fastPathHandled(clientId: clientId), to: continuation, onOverflow: onOverflow)
                    return
                }
                Self.yieldEvent(
                    .dataReceived(clientId: clientId, data: data, respond: respond),
                    to: continuation,
                    onOverflow: onOverflow
                )
            },
            onSendFailed: { clientId, failure in
                Self.yieldEvent(.sendFailed(clientId: clientId, failure: failure), to: continuation, onOverflow: onOverflow)
            },
            onUnauthenticatedData: { clientId, data, respond in
                Self.yieldEvent(
                    .unauthenticatedData(clientId: clientId, data: data, respond: respond),
                    to: continuation,
                    onOverflow: onOverflow
                )
            },
            onRateLimited: { clientId, respond in
                Self.yieldEvent(.rateLimited(clientId: clientId, respond: respond), to: continuation, onOverflow: onOverflow)
            }
        )
    }

    nonisolated static func makeEventStream() -> (
        AsyncStream<TransportEvent>,
        AsyncStream<TransportEvent>.Continuation
    ) {
        AsyncStream<TransportEvent>.makeStream(
            bufferingPolicy: .bufferingOldest(eventStreamBufferLimit)
        )
    }

    nonisolated static func yieldEvent(
        _ event: TransportEvent,
        to continuation: AsyncStream<TransportEvent>.Continuation,
        onOverflow: @escaping @Sendable () -> Void
    ) {
        switch continuation.yield(event) {
        case .enqueued, .terminated:
            return
        case .dropped:
            continuation.finish()
            onOverflow()
        @unknown default:
            continuation.finish()
            onOverflow()
        }
    }

    /// Stop the TCP server and any Bonjour advertisement.
    @MainActor
    @discardableResult
    func stop() -> Task<Void, Never> {
        callbackTasks.cancelAll()
        stopAdvertising()
        eventContinuation.finish()
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

    /// Advertise the server via Bonjour.
    ///
    /// - Parameters:
    ///   - serviceName: The Bonjour service name (e.g. "MyApp#instanceId")
    ///   - simulatorUDID: Simulator UDID to include in TXT record (optional)
    ///   - installationId: Stable installation identifier (optional)
    ///   - instanceId: Human-readable instance identifier (optional)
    ///   - additionalTXT: Extra TXT record key-value pairs (optional)
    @MainActor
    func advertise(
        serviceName: String,
        simulatorUDID: String? = nil,
        installationId: String? = nil,
        instanceId: String? = nil,
        additionalTXT: [String: String] = [:]
    ) {
        let port = server.listeningPort
        guard port > 0 else {
            logger.error("Cannot advertise: server not started")
            return
        }
        guard tlsIdentity != nil else {
            logger.error("Cannot advertise: TLS identity is not active")
            return
        }

        stopAdvertising()

        let service = NetService(
            domain: "local.",
            type: buttonHeistServiceType,
            name: serviceName,
            port: Int32(port)
        )

        // Build TXT record
        var txtDict: [String: Data] = [:]
        if let simUDID = simulatorUDID, let data = simUDID.data(using: .utf8) {
            txtDict[TXTRecordKey.simUDID.rawValue] = data
        }
        if let installationId, let data = installationId.data(using: .utf8) {
            txtDict[TXTRecordKey.installationId.rawValue] = data
        }
        if let id = instanceId, let data = id.data(using: .utf8) {
            txtDict[TXTRecordKey.instanceId.rawValue] = data
        }
        for (key, value) in additionalTXT {
            if let data = value.data(using: .utf8) {
                txtDict[key] = data
            }
        }
        if let fp = tlsIdentity?.fingerprint, let data = fp.data(using: .utf8) {
            txtDict[TXTRecordKey.certFingerprint.rawValue] = data
        }
        if tlsIdentity != nil {
            txtDict[TXTRecordKey.transport.rawValue] = Data("tls".utf8)
        }

        currentTXT = txtDict
        service.setTXTRecord(NetService.data(fromTXTRecord: txtDict))

        netService = service
        netService?.delegate = self
        netService?.publish()
        logger.info("Advertising as '\(serviceName)' on port \(port)")
    }

    /// Update the TXT record of the currently advertised service.
    /// Merges entries into the existing TXT record (preserving keys not in `entries`).
    /// - Parameter entries: Key-value pairs to set in the TXT record.
    @MainActor
    func updateTXTRecord(_ entries: [String: String]) {
        guard let service = netService else {
            logger.warning("Cannot update TXT record: not advertising")
            return
        }

        for (key, value) in entries {
            if let data = value.data(using: .utf8) {
                currentTXT[key] = data
            }
        }
        service.setTXTRecord(NetService.data(fromTXTRecord: currentTXT))
    }

    /// Stop Bonjour advertisement without stopping the TCP server.
    @MainActor
    func stopAdvertising() {
        netService?.stop()
        netService = nil
        currentTXT.removeAll()
    }

}

// MARK: - NetServiceDelegate

extension ServerTransport: NetServiceDelegate {

    nonisolated func netServiceDidPublish(_ sender: NetService) {
        logger.info("Bonjour service published: '\(sender.name)' on port \(sender.port)")
    }

    nonisolated func netService(_ sender: NetService, didNotPublish errorDict: [String: NSNumber]) {
        let code = errorDict[NetService.errorCode]?.intValue ?? -1
        let domain = errorDict[NetService.errorDomain]?.intValue ?? -1
        logger.error("Bonjour publish failed for '\(sender.name)': error \(code) domain \(domain)")
    }
}
