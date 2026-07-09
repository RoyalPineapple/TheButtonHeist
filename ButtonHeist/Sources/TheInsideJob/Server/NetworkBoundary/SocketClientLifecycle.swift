import Foundation
import Network

typealias SocketDataHandler = @Sendable (Int, Data, @escaping @Sendable (Data) -> Void) -> Void

/// Callback bundle for socket lifecycle, send, and data events.
struct SocketServerCallbacks: Sendable {
    var onClientConnected: (@Sendable (_ clientId: Int, _ remoteAddress: String?) -> Void)?
    var onClientDisconnected: (@Sendable (Int) -> Void)?
    var onDataReceived: SocketDataHandler?
    var onSendFailed: (@Sendable (_ clientId: Int, _ failure: ServerSendFailure) -> Void)?

    init(
        onClientConnected: (@Sendable (_ clientId: Int, _ remoteAddress: String?) -> Void)? = nil,
        onClientDisconnected: (@Sendable (Int) -> Void)? = nil,
        onDataReceived: SocketDataHandler? = nil,
        onSendFailed: (@Sendable (_ clientId: Int, _ failure: ServerSendFailure) -> Void)? = nil
    ) {
        self.onClientConnected = onClientConnected
        self.onClientDisconnected = onClientDisconnected
        self.onDataReceived = onDataReceived
        self.onSendFailed = onSendFailed
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

    func sendFailed(_ clientId: Int, failure: ServerSendFailure) {
        callbacks.onSendFailed?(clientId, failure)
    }

    func receivedData(
        clientId: Int,
        data: Data,
        respond: @escaping @Sendable (Data) -> Void
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
