#if canImport(UIKit)
#if DEBUG
import Foundation

import TheScore

/// Owns transport event consumption and request admission without depending on
/// the main actor. Only admitted app work crosses the main-actor stream.
actor TransportControlPlane {
    enum MainActorEvent: Sendable {
        case clientConnected(
            clientId: Int,
            generation: ClientDelivery.Generation
        )
        case dispatch(
            AdmittedClientMessage,
            respond: SocketResponseHandler,
            generation: ClientDelivery.Generation
        )
        case clientDisconnected(
            clientId: Int,
            generation: ClientDelivery.Generation
        )
        case backlogOverflow(
            maxEvents: Int,
            generation: ClientDelivery.Generation
        )
    }

    enum Publication: Sendable {
        case enqueued
        case stopped
        case overflowed
    }

    typealias Publish = @Sendable (MainActorEvent) -> Publication
    typealias Probe = @Sendable (MainThreadProbeRequest) async throws -> MainThreadProbeResponse

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
    private var clientRequestPipelines: [Int: ClientRequestPipeline] = [:]

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
            replaceClientRequestPipeline(clientId: clientId)
            _ = publish(.clientConnected(clientId: clientId, generation: generation))
            if let remoteAddress {
                await muscle.registerClientAddress(
                    clientId,
                    address: ClientNetworkAddress(remoteAddress),
                    generation: generation
                )
            }
            await muscle.sendServerHello(clientId: clientId, generation: generation)

        case .clientDisconnected(let clientId):
            stopClientRequestPipeline(clientId: clientId)
            await muscle.handleClientDisconnected(clientId, generation: generation)
            _ = publish(.clientDisconnected(clientId: clientId, generation: generation))

        case .dataReceived(let clientId, let data, let respond):
            await enqueueClientRequest(clientId: clientId, data: data, respond: respond)

        case .backlogOverflow(let maxEvents):
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
        let pipelineConsumers = clientRequestPipelines.values.compactMap { $0.stop() }
        clientRequestPipelines.removeAll()
        await eventConsumer?.value
        for consumer in pipelineConsumers {
            await consumer.value
        }
    }

    func stopClient(_ clientId: Int) {
        stopClientRequestPipeline(clientId: clientId)
    }

    private var isRunning: Bool {
        guard case .running = state else { return false }
        return true
    }

    private func replaceClientRequestPipeline(clientId: Int) {
        clientRequestPipelines.removeValue(forKey: clientId)?.stop()
        clientRequestPipelines[clientId] = ClientRequestPipeline { [weak self] request in
            await self?.executeClientRequest(request)
        }
    }

    private func stopClientRequestPipeline(clientId: Int) {
        clientRequestPipelines.removeValue(forKey: clientId)?.stop()
    }

    private func enqueueClientRequest(
        clientId: Int,
        data: Data,
        respond: @escaping SocketResponseHandler
    ) async {
        guard let pipeline = clientRequestPipelines[clientId] else { return }
        let request = ClientTransportRequest(
            clientId: clientId,
            data: data,
            respond: respond,
            generation: generation
        )
        switch pipeline.enqueue(request) {
        case .enqueued, .stopped:
            break
        case .overflowed:
            insideJobLogger.error(
                "Client \(clientId) request backlog exceeded \(ClientRequestPipeline.maximumQueuedRequests), disconnecting"
            )
            stopClientRequestPipeline(clientId: clientId)
            await muscle.disconnectClient(clientId, generation: generation)
        }
    }

    private func executeClientRequest(_ request: ClientTransportRequest) async {
        guard isRunning, request.generation == generation else { return }
        let admission = await muscle.admitClientMessage(
            request.clientId,
            data: request.data,
            respond: request.respond,
            generation: generation
        )
        guard !Task.isCancelled, isRunning else { return }
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
            guard let response = try? await probe(probeRequest) else { return }
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
            switch publish(.dispatch(message, respond: request.respond, generation: generation)) {
            case .enqueued:
                break
            case .stopped, .overflowed:
                stopClientRequestPipeline(clientId: request.clientId)
                await muscle.disconnectClient(request.clientId, generation: generation)
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
