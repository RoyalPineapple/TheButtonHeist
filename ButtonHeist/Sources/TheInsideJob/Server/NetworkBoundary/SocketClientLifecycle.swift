import Foundation

struct SocketResponseHandler: Sendable {
    private let deliverResponse: @Sendable (Data) async -> ServerSendOutcome
    private let sendResponseInBackground: @Sendable (Data) -> Void

    init(
        deliver: @escaping @Sendable (Data) async -> ServerSendOutcome,
        sendInBackground: @escaping @Sendable (Data) -> Void
    ) {
        self.deliverResponse = deliver
        self.sendResponseInBackground = sendInBackground
    }

    func callAsFunction(_ data: Data) {
        sendResponseInBackground(data)
    }

    func deliver(_ data: Data) async -> ServerSendOutcome {
        await deliverResponse(data)
    }
}

typealias SocketDataHandler = @Sendable (Int, Data, SocketResponseHandler) -> Void

/// Callback bundle for socket lifecycle and data events.
struct SocketServerCallbacks: Sendable {
    var onClientConnected: (@Sendable (_ clientId: Int, _ remoteAddress: String?) -> Void)?
    var onClientDisconnected: (@Sendable (Int) -> Void)?
    var onDataReceived: SocketDataHandler?

    init(
        onClientConnected: (@Sendable (_ clientId: Int, _ remoteAddress: String?) -> Void)? = nil,
        onClientDisconnected: (@Sendable (Int) -> Void)? = nil,
        onDataReceived: SocketDataHandler? = nil
    ) {
        self.onClientConnected = onClientConnected
        self.onClientDisconnected = onClientDisconnected
        self.onDataReceived = onDataReceived
    }
}

/// Socket client lifecycle invariant: disconnect callbacks fire only after a registered client is removed and cancelled.
struct SocketClientLifecycle: Sendable {
    var callbacks: SocketServerCallbacks

    init(callbacks: SocketServerCallbacks = SocketServerCallbacks()) {
        self.callbacks = callbacks
    }

    func clientConnected(_ clientId: Int, address: String?) {
        callbacks.onClientConnected?(clientId, address)
    }

    func receivedData(
        clientId: Int,
        data: Data,
        respond: SocketResponseHandler
    ) {
        callbacks.onDataReceived?(clientId, data, respond)
    }

    @discardableResult
    func removeClient(_ clientId: Int, from registry: inout SocketClientRegistry) -> Bool {
        guard let state = registry.remove(clientId) else { return false }
        cancel(state)
        callbacks.onClientDisconnected?(clientId)
        return true
    }

    func cancelClientsWithoutNotifying(_ clients: [SocketClientRegistry.Client]) {
        for state in clients {
            cancel(state)
        }
    }

    private func cancel(_ state: SocketClientRegistry.Client) {
        state.connection.cancel()
    }
}
