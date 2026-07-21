#if canImport(UIKit)
#if DEBUG
import Foundation

import TheScore

extension TheGetaway {

    // MARK: - Transport Wiring

    /// Wire a transport to the crew.
    ///
    /// Async because `muscle.installCallbacks(...)` must complete *before* any
    /// transport event consumer starts. The previous shape kicked off an
    /// unstructured `Task { await muscle.installCallbacks(...) }` and returned
    /// synchronously; the caller then immediately ran `transport.start(...)`
    /// and the event consumer began accepting `.clientConnected` events. Task
    /// submission onto an actor's mailbox is not FIFO across separately-rooted
    /// Tasks, so the first `.clientConnected` could race ahead of the install
    /// — `sendToClient` was still nil — and the serverHello was silently
    /// dropped. Awaiting `installCallbacks` inline closes that race for both
    /// `start()` and `resume()`. See finding PR #352 (High) and #359 M1.
    func wireTransport(
        _ transport: ServerTransport,
        onBacklogOverflow: @escaping @MainActor @Sendable (Int) async -> Void
    ) async -> TransportWiringOutcome {
        let attempt = TransportWiringAttempt(
            transport: transport,
            deliveryGeneration: issueDeliveryGeneration()
        )
        let previousEventConsumer = transportWiring.eventConsumer
        previousEventConsumer?.cancel()
        transportWiring = .wiring(attempt)
        await muscle.beginCallbackWiring(attempt.deliveryGeneration)

        // Install actor-isolated callbacks on TheMuscle. Each callback is
        // `@Sendable`. We capture the inner `SimpleSocketServer` actor (which
        // is Sendable) rather than the `ServerTransport` wrapper (NSObject,
        // non-Sendable) so the closures don't drag a non-Sendable type into
        // actor-isolated storage.
        let server = transport.server
        let sendToClient: @Sendable (Data, Int) async -> ServerSendOutcome = { data, clientId in
            await server.send(data, to: clientId)
        }
        let disconnect: @Sendable (Int) async -> Void = { clientId in
            await server.removeClient(clientId)
        }
        let onAuthenticated: @MainActor @Sendable (Int, @escaping SocketResponseHandler) async -> Void = { [weak self] _, respond in
            await self?.sendServerInfo(respond: respond)
        }
        if let pauseBeforeTransportCallbackInstallationForTesting {
            await pauseBeforeTransportCallbackInstallationForTesting()
        }
        let installOutcome = await muscle.installCallbacks(
            sendToClient: sendToClient,
            disconnectClient: disconnect,
            onClientAuthenticated: onAuthenticated,
            generation: attempt.deliveryGeneration
        )

        guard installOutcome == .installed,
              transportWiring.admits(attempt)
        else {
            await muscle.invalidateCallbacks(for: attempt.deliveryGeneration)
            return .rejected
        }
        let eventConsumer = Task { @MainActor [weak self, events = transport.events, onBacklogOverflow] in
            for await event in events {
                guard let self else { return }
                await self.observeTransportEvent(event, onBacklogOverflow: onBacklogOverflow)
            }
        }
        transportWiring = .wired(WiredTransport(attempt: attempt, eventConsumer: eventConsumer))
        return .admitted(WiredTransportAdmission(attempt: attempt))
    }

    /// Observes one transport event on the main actor. Client frames are handed
    /// to per-client admission streams so unrelated lifecycle and client
    /// traffic can continue while a request is suspended.
    func observeTransportEvent(
        _ event: TransportEvent,
        onBacklogOverflow: @MainActor @Sendable (Int) async -> Void
    ) async {
        switch event {
        case .clientConnected(let clientId, let remoteAddress):
            insideJobLogger.info("Client \(clientId) connected from \(remoteAddress ?? "unknown"), awaiting hello")
            replaceClientRequestPipeline(clientId: clientId)
            if let remoteAddress {
                await muscle.registerClientAddress(
                    clientId,
                    address: ClientNetworkAddress(remoteAddress)
                )
            }
            await muscle.sendServerHello(clientId: clientId)

        case .clientDisconnected(let clientId):
            insideJobLogger.info("Client \(clientId) disconnected")
            stopClientRequestPipeline(clientId: clientId)
            await observeClientDisconnection(clientId: clientId)

        case .dataReceived(let clientId, let data, let respond):
            await enqueueClientRequest(clientId: clientId, data: data, respond: respond)

        case .backlogOverflow(let maxEvents):
            await onBacklogOverflow(maxEvents)

        }
    }

    func tearDown() async {
        let eventConsumer = transportWiring.eventConsumer
        let deliveryGeneration = transportWiring.deliveryGeneration
        transportWiring = .unwired
        eventConsumer?.cancel()
        if let deliveryGeneration {
            await muscle.invalidateCallbacks(for: deliveryGeneration)
        }
        let pipelineConsumers = clientRequestPipelines.values.compactMap { $0.stop() }
        clientRequestPipelines.removeAll()
        await brains.stopInteractionRequests()
        await eventConsumer?.value
        for consumer in pipelineConsumers {
            await consumer.value
        }
    }

    func tearDownIfWired(to expectedTransport: ServerTransport) async {
        guard transport === expectedTransport else { return }
        await tearDown()
    }

    private func observeClientDisconnection(clientId: Int) async {
        await muscle.handleClientDisconnected(clientId)
    }

    private func replaceClientRequestPipeline(clientId: Int) {
        brains.cancelTransportRequests(clientId: clientId)
        clientRequestPipelines.removeValue(forKey: clientId)?.stop()
        clientRequestPipelines[clientId] = ClientRequestPipeline { [weak self] request in
            await self?.executeClientRequest(request)
        }
    }

    private func stopClientRequestPipeline(clientId: Int) {
        brains.cancelTransportRequests(clientId: clientId)
        clientRequestPipelines.removeValue(forKey: clientId)?.stop()
    }

    private func enqueueClientRequest(
        clientId: Int,
        data: Data,
        respond: @escaping SocketResponseHandler
    ) async {
        guard let pipeline = clientRequestPipelines[clientId] else {
            insideJobLogger.error("Dropping request for disconnected client \(clientId)")
            return
        }

        switch pipeline.enqueue(ClientTransportRequest(clientId: clientId, data: data, respond: respond)) {
        case .enqueued:
            break
        case .stopped:
            insideJobLogger.error("Dropping request for stopped client \(clientId)")
        case .overflowed:
            insideJobLogger.error(
                "Client \(clientId) request backlog exceeded \(ClientRequestPipeline.maximumQueuedRequests), disconnecting"
            )
            stopClientRequestPipeline(clientId: clientId)
            await transport?.server.removeClient(clientId)
        }
    }

    private func executeClientRequest(_ request: ClientTransportRequest) async {
        let admission = await muscle.admitClientMessage(
            request.clientId,
            data: request.data,
            respond: request.respond
        )
        guard !Task.isCancelled else { return }

        switch admission {
        case .admitted(let message):
            switch message.envelope.message.executionLane {
            case .control:
                await executeClientMessage(message, respond: request.respond)
            case .userInterface:
                let submission = brains.submitTransportRequest(clientId: request.clientId) { [weak self] in
                    guard !Task.isCancelled else { return }
                    await self?.executeClientMessage(message, respond: request.respond)
                }
                if case .rejected(let rejection) = submission {
                    insideJobLogger.error(
                        "Client \(request.clientId) interaction submission rejected: \(String(describing: rejection))"
                    )
                    stopClientRequestPipeline(clientId: request.clientId)
                    await transport?.server.removeClient(request.clientId)
                }
            }
        case .handled:
            break
        }
    }
}

private enum ClientRequestExecutionLane: Equatable {
    case control
    case userInterface
}

private extension ClientMessage {
    var executionLane: ClientRequestExecutionLane {
        switch self {
        case .clientHello, .authenticate, .ping, .status:
            return .control
        case .requestInterface,
             .getPasteboard,
             .getAnnouncements,
             .requestScreen,
             .runtimeAction,
             .heistPlan:
            return .userInterface
        }
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
