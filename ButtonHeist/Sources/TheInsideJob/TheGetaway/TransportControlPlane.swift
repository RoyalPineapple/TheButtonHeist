#if canImport(UIKit)
#if DEBUG
import Foundation

import TheScore

/// Owns transport event consumption and request admission without depending on
/// the main actor. Only admitted app work crosses the main-actor stream.
actor TransportControlPlane {
    private static let maximumPendingMainActorDispatches =
        ClientRequestPipeline.maximumQueuedRequests

    enum MainActorEvent: Sendable {
        case leaseEnded(TransportClientLease, generation: ClientDelivery.Generation)
        case dispatch(
            AdmittedClientMessage,
            respond: SocketResponseHandler,
            lease: TransportClientLease,
            generation: ClientDelivery.Generation
        )
        case backlogOverflow(
            maxEvents: Int,
            generation: ClientDelivery.Generation
        )
    }

    typealias Publish = @Sendable (
        sending MainActorEvent
    ) -> AsyncStream<MainActorEvent>.Continuation.YieldResult
    typealias Probe = @Sendable (
        MainThreadProbeRequest
    ) async throws -> MainThreadProbeResponse

    private struct ClientConnection {
        let lease: TransportClientLease
        let pipeline: ClientRequestPipeline
    }

    private enum State {
        case idle
        case running(Task<Void, Never>)
        case stopped
    }

    private let muscle: TheMuscle
    private let generation: ClientDelivery.Generation
    private let pongPayload: PongPayload
    private let events: ServerTransport.Events
    private let probe: Probe
    private let publish: Publish

    private var state = State.idle
    private var clientConnections: [Int: ClientConnection] = [:]
    private var nextClientIncarnation: UInt64 = 1
    private var pendingMainActorDispatches = 0

    private init(
        events: ServerTransport.Events,
        muscle: TheMuscle,
        generation: ClientDelivery.Generation,
        pongPayload: PongPayload,
        probe: @escaping Probe,
        publish: @escaping Publish
    ) {
        self.events = events
        self.muscle = muscle
        self.generation = generation
        self.pongPayload = pongPayload
        self.probe = probe
        self.publish = publish
    }

    @MainActor
    static func wired(
        to transport: ServerTransport,
        muscle: TheMuscle,
        generation: ClientDelivery.Generation,
        pongPayload: PongPayload,
        probe: @escaping Probe,
        publish: @escaping Publish
    ) -> TransportControlPlane {
        TransportControlPlane(
            events: transport.transportEvents,
            muscle: muscle,
            generation: generation,
            pongPayload: pongPayload,
            probe: probe,
            publish: publish
        )
    }

    func start() {
        guard case .idle = state else { return }
        state = .running(Task { [weak self] in
            guard let self else { return }
            for await event in self.events {
                guard !Task.isCancelled else { return }
                await self.observe(event)
            }
        })
    }

    func observe(_ event: TransportEvent) async {
        guard isRunning else { return }
        switch event {
        case .clientConnected(let clientId, let remoteAddress):
            connectClient(clientId)
            if let remoteAddress {
                await muscle.registerClientAddress(
                    clientId,
                    address: ClientNetworkAddress(remoteAddress),
                    generation: generation
                )
            }
            await muscle.sendServerHello(clientId: clientId, generation: generation)

        case .clientDisconnected(let clientId):
            endClientConnection(clientId)
            await muscle.handleClientDisconnected(clientId, generation: generation)

        case .dataReceived(let clientId, let data, let respond):
            await enqueueClientRequest(clientId: clientId, data: data, respond: respond)

        case .backlogOverflow(let maxEvents):
            endAllClientConnections()
            _ = publish(.backlogOverflow(maxEvents: maxEvents, generation: generation))
        }
    }

    func stop() async {
        let eventConsumer: Task<Void, Never>?
        switch state {
        case .idle:
            eventConsumer = nil
        case .running(let consumer):
            eventConsumer = consumer
        case .stopped:
            return
        }
        state = .stopped
        eventConsumer?.cancel()
        let pipelineConsumers = clientConnections.values.compactMap { $0.pipeline.stop() }
        clientConnections.removeAll()
        pendingMainActorDispatches = 0
        await eventConsumer?.value
        for consumer in pipelineConsumers {
            await consumer.value
        }
    }

    func consumeDispatch(for lease: TransportClientLease) -> Bool {
        guard pendingMainActorDispatches > 0 else { return false }
        pendingMainActorDispatches -= 1
        return isCurrent(lease)
    }

    func isCurrent(_ lease: TransportClientLease) -> Bool {
        isRunning && clientConnections[lease.clientId]?.lease == lease
    }

    func disconnect(_ lease: TransportClientLease) async {
        guard endClientConnection(lease) else { return }
        await muscle.disconnectClient(lease.clientId, generation: generation)
    }

    private var isRunning: Bool {
        guard case .running = state else { return false }
        return true
    }

    private func connectClient(_ clientId: Int) {
        endClientConnection(clientId)
        let lease = TransportClientLease(
            clientId: clientId,
            incarnation: nextClientIncarnation
        )
        nextClientIncarnation &+= 1
        let pipeline = ClientRequestPipeline { [weak self] request in
            await self?.executeClientRequest(request)
        }
        clientConnections[clientId] = ClientConnection(lease: lease, pipeline: pipeline)
    }

    private func endClientConnection(_ clientId: Int) {
        guard let connection = clientConnections.removeValue(forKey: clientId) else {
            return
        }
        connection.pipeline.stop()
        _ = publish(.leaseEnded(connection.lease, generation: generation))
    }

    private func endAllClientConnections() {
        for clientId in Array(clientConnections.keys) {
            endClientConnection(clientId)
        }
    }

    @discardableResult
    private func endClientConnection(_ lease: TransportClientLease) -> Bool {
        guard clientConnections[lease.clientId]?.lease == lease else { return false }
        endClientConnection(lease.clientId)
        return true
    }

    private func enqueueClientRequest(
        clientId: Int,
        data: Data,
        respond: @escaping SocketResponseHandler
    ) async {
        guard let connection = clientConnections[clientId] else { return }
        let lease = connection.lease
        let request = ClientTransportRequest(
            lease: lease,
            data: data,
            respond: respond
        )
        switch connection.pipeline.enqueue(request) {
        case .enqueued, .stopped:
            break
        case .overflowed:
            insideJobLogger.error(
                "Client \(clientId) request backlog exceeded \(ClientRequestPipeline.maximumQueuedRequests), disconnecting"
            )
            await disconnect(connection.lease)
        }
    }

    private func executeClientRequest(_ request: ClientTransportRequest) async {
        guard isCurrent(request.lease) else { return }
        let admission = await muscle.admitClientMessage(
            request.clientId,
            data: request.data,
            respond: request.respond,
            generation: generation
        )
        guard !Task.isCancelled, isCurrent(request.lease) else { return }
        guard case .admitted(let message) = admission else { return }

        let envelope = message.envelope
        switch envelope.message {
        case .ping:
            await muscle.noteClientActivity(message.clientId)
            await respond(
                .pong(pongPayload.withServerTimestamp()),
                to: envelope,
                using: request.respond
            )

        case .mainThreadProbe(let probeRequest):
            guard let response = try? await probe(probeRequest) else {
                return
            }
            await respond(
                .mainThreadProbe(response),
                to: envelope,
                using: request.respond
            )

        case .clientHello, .authenticate:
            break

        case .status,
             .requestInterface,
             .getPasteboard,
             .getAnnouncements,
             .requestScreen,
             .runtimeAction,
             .heistPlan:
            guard pendingMainActorDispatches < Self.maximumPendingMainActorDispatches else {
                insideJobLogger.error(
                    "Main-actor request backlog exceeded \(Self.maximumPendingMainActorDispatches), disconnecting client \(request.clientId)"
                )
                await disconnect(request.lease)
                return
            }
            pendingMainActorDispatches += 1
            switch publish(.dispatch(
                message,
                respond: request.respond,
                lease: request.lease,
                generation: generation
            )) {
            case .enqueued:
                break
            case .terminated, .dropped:
                pendingMainActorDispatches -= 1
                await disconnect(request.lease)
            @unknown default:
                pendingMainActorDispatches -= 1
                await disconnect(request.lease)
            }
        }
    }

    private func respond(
        _ message: ServerMessage,
        to envelope: RequestEnvelope,
        using respond: @escaping SocketResponseHandler
    ) async {
        await muscle.sendResponse(
            message,
            requestId: envelope.requestId,
            respond: respond,
            generation: generation
        )
    }
}
#endif // DEBUG
#endif // canImport(UIKit)
