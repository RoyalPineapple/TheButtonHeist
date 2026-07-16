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
    ) async {
        self.transport = transport

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
        let onAuthenticated: @MainActor @Sendable (Int, @escaping SocketResponseHandler) async -> Void = { [weak self] clientId, respond in
            await self?.handleClientConnected(clientId, respond: respond)
        }
        await muscle.installCallbacks(
            sendToClient: sendToClient,
            disconnectClient: disconnect,
            onClientAuthenticated: onAuthenticated
        )

        eventConsumerTask?.cancel()
        eventConsumerTask = Task { @MainActor [weak self, events = transport.events, onBacklogOverflow] in
            for await event in events {
                guard let self else { return }
                await self.handleTransportEvent(event, onBacklogOverflow: onBacklogOverflow)
            }
        }
    }

    /// Routes one transport event on the main actor. Client frames are handed
    /// to per-client admission streams so unrelated lifecycle and client
    /// traffic can continue while a request is suspended.
    func handleTransportEvent(
        _ event: TransportEvent,
        onBacklogOverflow: @MainActor @Sendable (Int) async -> Void
    ) async {
        switch event {
        case .clientConnected(let clientId, let remoteAddress):
            insideJobLogger.info("Client \(clientId) connected from \(remoteAddress ?? "unknown"), awaiting hello")
            replaceClientRequestPipeline(clientId: clientId)
            if let remoteAddress {
                await muscle.registerClientAddress(clientId, address: remoteAddress)
            }
            await muscle.sendServerHello(clientId: clientId)

        case .clientDisconnected(let clientId):
            insideJobLogger.info("Client \(clientId) disconnected")
            stopClientRequestPipeline(clientId: clientId)
            await handleClientDeliveryTerminated(clientId: clientId)

        case .dataReceived(let clientId, let data, let respond):
            await enqueueClientRequest(clientId: clientId, data: data, respond: respond)

        case .backlogOverflow(let maxEvents):
            await onBacklogOverflow(maxEvents)

        }
    }

    func tearDown() async {
        let eventConsumer = eventConsumerTask
        eventConsumer?.cancel()
        eventConsumerTask = nil
        let pipelineConsumers = clientRequestPipelines.values.compactMap { $0.stop() }
        clientRequestPipelines.removeAll()
        await brains.stopInteractionRequests()
        await eventConsumer?.value
        for consumer in pipelineConsumers {
            await consumer.value
        }
        transport = nil
    }

    func tearDownIfWired(to expectedTransport: ServerTransport) async {
        guard transport === expectedTransport else { return }
        await tearDown()
    }

    private func handleClientConnected(_ clientId: Int, respond: @escaping SocketResponseHandler) async {
        await sendServerInfo(respond: respond)
    }

    private func handleClientDeliveryTerminated(clientId: Int) async {
        await muscle.handleClientDisconnected(clientId)
    }

    private func replaceClientRequestPipeline(clientId: Int) {
        brains.cancelTransportRequests(clientId: clientId)
        clientRequestPipelines.removeValue(forKey: clientId)?.stop()
        clientRequestPipelines[clientId] = ClientRequestPipeline { [weak self] request in
            await self?.processClientRequest(request)
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

    private func processClientRequest(_ request: ClientTransportRequest) async {
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
                await handleClientMessage(message, respond: request.respond)
            case .userInterface:
                let submission = brains.submitTransportRequest(clientId: request.clientId) { [weak self] in
                    guard !Task.isCancelled else { return }
                    await self?.handleClientMessage(message, respond: request.respond)
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
