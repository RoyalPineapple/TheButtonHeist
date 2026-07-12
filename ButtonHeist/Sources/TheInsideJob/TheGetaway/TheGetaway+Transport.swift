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
    func wireTransport(_ transport: ServerTransport) async {
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
        let onAuthenticated: @MainActor @Sendable (Int, @escaping SocketResponseHandler) async -> Void = {
            [weak self] clientId, respond in
            await self?.handleClientConnected(clientId, respond: respond)
        }
        await muscle.installCallbacks(
            sendToClient: sendToClient,
            disconnectClient: disconnect,
            onClientAuthenticated: onAuthenticated
        )

        eventConsumerTask?.cancel()
        eventConsumerTask = Task { @MainActor [weak self, events = transport.events] in
            for await event in events {
                guard let self else { return }
                await self.handleTransportEvent(event)
            }
        }
    }

    /// Dispatch a single transport event on the main actor.
    ///
    /// The consumer awaits this method per event, so `clientConnected` always
    /// completes before the first `dataReceived` for that client and message
    /// N+1 cannot start before message N finishes.
    func handleTransportEvent(_ event: TransportEvent) async {
        switch event {
        case .clientConnected(let clientId, let remoteAddress):
            insideJobLogger.info("Client \(clientId) connected from \(remoteAddress ?? "unknown"), awaiting hello")
            if let remoteAddress {
                await muscle.registerClientAddress(clientId, address: remoteAddress)
            }
            await muscle.sendServerHello(clientId: clientId)

        case .clientDisconnected(let clientId):
            insideJobLogger.info("Client \(clientId) disconnected")
            await handleClientDeliveryTerminated(clientId: clientId)

        case .dataReceived(let clientId, let data, let respond):
            switch await muscle.admitClientMessage(clientId, data: data, respond: respond) {
            case .admitted(let message):
                await handleClientMessage(message, respond: respond)
            case .handled:
                break
            }

        }
    }

    func tearDown() async {
        eventConsumerTask?.cancel()
        eventConsumerTask = nil
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
}

#endif // DEBUG
#endif // canImport(UIKit)
