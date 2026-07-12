import Foundation

/// Typed callback/delivery wiring for `TheMuscle`.
enum ClientDelivery: Sendable {
    struct Callbacks: Sendable {
        var sendToClient: @Sendable (_ data: Data, _ clientId: Int) async -> ServerSendOutcome
        var disconnectClient: @Sendable (_ clientId: Int) async -> Void
        var onClientAuthenticated: @MainActor @Sendable (
            _ clientId: Int,
            _ respond: @escaping SocketResponseHandler
        ) async -> Void
    }

    enum CallbackOutcome: Equatable, Sendable {
        case delivered
        case failed(ClientDeliveryFailure)
    }

    enum ClientDeliveryFailure: Error, Equatable, Sendable {
        case callbacksNotInstalled(String)
    }

    case unwired
    case wired(Callbacks)

    mutating func install(_ callbacks: Callbacks) {
        self = .wired(callbacks)
    }

    mutating func clearForTesting() {
        self = .unwired
    }

    func send(_ data: Data, toClient clientId: Int) async -> ServerSendOutcome {
        guard case .wired(let callbacks) = self else {
            return .failed(.transportUnavailable)
        }
        return await callbacks.sendToClient(data, clientId)
    }

    @discardableResult
    func disconnect(_ clientId: Int) async -> CallbackOutcome {
        guard case .wired(let callbacks) = self else {
            return .failed(.callbacksNotInstalled("disconnectClient"))
        }
        await callbacks.disconnectClient(clientId)
        return .delivered
    }

    @discardableResult
    func clientAuthenticated(
        _ clientId: Int,
        respond: @escaping SocketResponseHandler
    ) async -> CallbackOutcome {
        guard case .wired(let callbacks) = self else {
            return .failed(.callbacksNotInstalled("onClientAuthenticated"))
        }
        await callbacks.onClientAuthenticated(clientId, respond)
        return .delivered
    }
}
