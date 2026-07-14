import Foundation

typealias SocketResponseHandler = @Sendable (Data) async -> ServerSendOutcome
typealias SocketDataHandler = @Sendable (Int, Data, @escaping SocketResponseHandler) -> Void

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
