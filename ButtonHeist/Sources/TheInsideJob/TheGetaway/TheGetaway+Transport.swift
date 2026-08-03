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
        let cleanup = replacementCleanup()
        transportWiring = .wiring(attempt, cleanup: cleanup)
        await cleanup?.value
        guard transportWiring.admits(attempt) else {
            return await rejectTransportWiring(attempt)
        }

        await transportWiringBoundary.beforeCallbackBegin(attempt)
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
        await transportWiringBoundary.beforeCallbackInstallation(attempt)
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
            bufferingPolicy: .bufferingOldest(TransportControlPlane.mainActorEventBufferLimit)
        )
        let controlPlane = TransportControlPlane(
            transport: transport,
            muscle: muscle,
            generation: generation,
            pongPayload: pongPayload,
            probe: mainThreadProbe,
            publish: { event in
                mainActorStream.continuation.yield(event)
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
        return .admitted(attempt)
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

    private func replacementCleanup() -> Task<Void, Never>? {
        switch transportWiring {
        case .unwired:
            return nil
        case .wiring(_, let cleanup):
            return cleanup
        case .wired(let wiring):
            return Task { @MainActor [weak self] in
                guard let self else { return }
                await self.stopWiring(wiring)
            }
        }
    }

    private func stopWiring(_ wiring: WiredTransport?) async {
        guard let wiring else { return }
        wiring.mainActorEvents.finish()
        wiring.mainActorConsumer.cancel()
        await wiring.controlPlane.stop()
        await brains.stopInteractionRequests()
        await wiring.mainActorConsumer.value
    }

    func tearDown() async {
        let wiring = transportWiring.wired
        let cleanup = transportWiring.cleanup
        let generation = transportWiring.deliveryGeneration
        transportWiring = .unwired
        wiring?.mainActorEvents.finish()
        wiring?.mainActorConsumer.cancel()
        if let generation {
            await muscle.invalidateCallbacks(for: generation)
        }
        await cleanup?.value
        await stopWiring(wiring)
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
        case .controlChanged(let generation):
            guard case .wired(let wiring) = transportWiring,
                  wiring.attempt.deliveryGeneration == generation
            else { return }
            let changes = await wiring.controlPlane.consumeControlChanges()
            for lease in changes.endedLeases {
                brains.cancelTransportRequests(lease: lease)
            }
            if let maxEvents = changes.backlogOverflowLimit {
                await onBacklogOverflow(maxEvents)
            }

        case .dispatch(let message, let respond, let lease, let generation):
            guard case .wired(let wiring) = transportWiring,
                  wiring.attempt.deliveryGeneration == generation,
                  await wiring.controlPlane.consumeDispatch(for: lease)
            else { return }
            let clientId = message.clientId
            let controlPlane = wiring.controlPlane
            let submission = brains.submitTransportRequest(lease: lease) { [weak self] in
                guard !Task.isCancelled,
                      let self,
                      self.transportWiring.admitsEvent(generation: generation),
                      await controlPlane.isCurrent(lease)
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
                brains.cancelTransportRequests(lease: lease)
                await wiring.controlPlane.disconnect(lease)
            }

        }
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
