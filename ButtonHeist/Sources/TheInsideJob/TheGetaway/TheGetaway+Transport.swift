#if canImport(UIKit)
#if DEBUG
import Foundation

import TheScore

extension TheGetaway {

    // MARK: - Transport Wiring

    func wireTransport(
        _ transport: ServerTransport,
        onBacklogOverflow: @escaping @MainActor @Sendable (Int) async -> Void
    ) async -> TransportWiringOutcome {
        let attempt = TransportWiringAttempt(
            transport: transport,
            deliveryGeneration: issueDeliveryGeneration()
        )
        let previousWiring = transportWiring.wired
        transportWiring = .wiring(attempt)
        previousWiring?.mainActorEvents.finish()
        previousWiring?.mainActorConsumer.cancel()
        await previousWiring?.controlPlane.stop()

        if let pauseBeforeTransportCallbackBeginForTesting {
            await pauseBeforeTransportCallbackBeginForTesting()
        }
        let beginOutcome = await muscle.beginCallbackWiring(attempt.deliveryGeneration)
        guard beginOutcome == .admitted,
              transportWiring.admits(attempt)
        else {
            return await rejectTransportWiring(attempt)
        }

        let installOutcome = await installTransportCallbacks(for: attempt)
        guard installOutcome == .installed,
              transportWiring.admits(attempt)
        else {
            return await rejectTransportWiring(attempt)
        }
        return await wireControlPlane(for: attempt, onBacklogOverflow: onBacklogOverflow)
    }

    private func installTransportCallbacks(
        for attempt: TransportWiringAttempt
    ) async -> ClientDelivery.InstallOutcome {
        let transport = attempt.transport
        let server = transport.server
        let generation = attempt.deliveryGeneration
        let sendToClient: @Sendable (Data, Int) async -> ServerSendOutcome = { data, clientId in
            await server.send(data, to: clientId)
        }
        let disconnect: @Sendable (Int) async -> Void = { clientId in
            await server.removeClient(clientId)
        }
        let onAuthenticated: @MainActor @Sendable (
            Int,
            @escaping SocketResponseHandler
        ) async -> Void = { [weak self] _, respond in
            await self?.sendServerInfo(respond: respond, generation: generation)
        }
        if let pauseBeforeTransportCallbackInstallationForTesting {
            await pauseBeforeTransportCallbackInstallationForTesting()
        }
        return await muscle.installCallbacks(
            sendToClient: sendToClient,
            disconnectClient: disconnect,
            onClientAuthenticated: onAuthenticated,
            generation: generation
        )
    }

    private func wireControlPlane(
        for attempt: TransportWiringAttempt,
        onBacklogOverflow: @escaping @MainActor @Sendable (Int) async -> Void
    ) async -> TransportWiringOutcome {
        let transport = attempt.transport
        let generation = attempt.deliveryGeneration
        let mainActorStream = AsyncStream<TransportControlPlane.MainActorEvent>.makeStream(
            bufferingPolicy: .bufferingOldest(ClientRequestPipeline.maximumQueuedRequests)
        )
        let controlPlane = TransportControlPlane.wired(
            to: transport,
            muscle: muscle,
            generation: generation,
            pongPayload: pongPayload,
            probe: { request in
                try await MainThreadProbe.execute(request)
            },
            publish: { event in
                switch mainActorStream.continuation.yield(event) {
                case .enqueued:
                    return .enqueued
                case .terminated:
                    return .stopped
                case .dropped:
                    return .overflowed
                @unknown default:
                    return .overflowed
                }
            }
        )
        let events = mainActorStream.stream
        let mainActorConsumer = Task { @MainActor [weak self, events, onBacklogOverflow] in
            for await event in events {
                guard !Task.isCancelled, let self else { return }
                await self.executeMainActorEvent(event, onBacklogOverflow: onBacklogOverflow)
            }
        }
        let wiring = WiredTransport(
            attempt: attempt,
            controlPlane: controlPlane,
            mainActorEvents: mainActorStream.continuation,
            mainActorConsumer: mainActorConsumer
        )
        transportWiring = .wired(wiring)
        await controlPlane.start()
        guard transportWiring.admitsEvent(generation: generation) else {
            mainActorStream.continuation.finish()
            mainActorConsumer.cancel()
            await controlPlane.stop()
            return await rejectTransportWiring(attempt)
        }
        return .admitted(WiredTransportAdmission(attempt: attempt))
    }

    private func rejectTransportWiring(
        _ attempt: TransportWiringAttempt
    ) async -> TransportWiringOutcome {
        if transportWiring.admits(attempt) {
            transportWiring = .unwired
        }
        await muscle.invalidateCallbacks(for: attempt.deliveryGeneration)
        return .rejected
    }

    func observeTransportEvent(
        _ event: TransportEvent,
        generation: ClientDelivery.Generation,
        onBacklogOverflow _: @MainActor @Sendable (Int) async -> Void
    ) async {
        guard case .wired(let wiring) = transportWiring,
              wiring.attempt.deliveryGeneration == generation
        else { return }
        await wiring.controlPlane.observe(event)
    }

    func tearDown() async {
        let wiring = transportWiring.wired
        let generation = transportWiring.deliveryGeneration
        transportWiring = .unwired
        wiring?.mainActorEvents.finish()
        wiring?.mainActorConsumer.cancel()
        if let generation {
            await muscle.invalidateCallbacks(for: generation)
        }
        await wiring?.controlPlane.stop()
        await brains.stopInteractionRequests()
        await wiring?.mainActorConsumer.value
    }

    func tearDownIfWired(to expectedTransport: ServerTransport) async {
        guard transport === expectedTransport else { return }
        await tearDown()
    }

    private func executeMainActorEvent(
        _ event: TransportControlPlane.MainActorEvent,
        onBacklogOverflow: @escaping @MainActor @Sendable (Int) async -> Void
    ) async {
        switch event {
        case .clientConnected(let clientId, let generation):
            guard transportWiring.admitsEvent(generation: generation) else { return }
            brains.cancelTransportRequests(clientId: clientId)

        case .dispatch(let message, let respond, let generation):
            guard transportWiring.admitsEvent(generation: generation) else { return }
            let clientId = message.clientId
            let submission = brains.submitTransportRequest(clientId: clientId) { [weak self] in
                guard !Task.isCancelled,
                      let self,
                      self.transportWiring.admitsEvent(generation: generation)
                else { return }
                await self.executeClientMessage(
                    message,
                    respond: respond,
                    generation: generation
                )
            }
            if case .rejected(let rejection) = submission {
                guard case .wired(let wiring) = transportWiring,
                      wiring.attempt.deliveryGeneration == generation
                else { return }
                insideJobLogger.error(
                    "Client \(clientId) interaction submission rejected: \(String(describing: rejection))"
                )
                brains.cancelTransportRequests(clientId: clientId)
                await wiring.controlPlane.stopClient(clientId)
                await muscle.disconnectClient(clientId, generation: generation)
            }

        case .clientDisconnected(let clientId, let generation):
            guard transportWiring.admitsEvent(generation: generation) else { return }
            brains.cancelTransportRequests(clientId: clientId)

        case .backlogOverflow(let maxEvents, let generation):
            guard transportWiring.admitsEvent(generation: generation) else { return }
            await onBacklogOverflow(maxEvents)
        }
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
