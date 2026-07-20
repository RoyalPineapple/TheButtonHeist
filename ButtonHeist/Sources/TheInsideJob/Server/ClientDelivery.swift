import Foundation

/// Typed callback/delivery wiring for `TheMuscle`.
enum ClientDelivery: Sendable {
    struct Generation: Equatable, Sendable {
        private let id: UUID

        init(id: UUID = UUID()) {
            self.id = id
        }
    }

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

    enum InstallOutcome: Equatable, Sendable {
        case installed
        case rejected
    }

    enum ClientDeliveryFailure: Error, Equatable, Sendable {
        case callbacksNotInstalled(String)
    }

    case unwired
    case wiring(Generation)
    case wired(Generation, Callbacks)

    var generation: Generation? {
        switch self {
        case .unwired:
            nil
        case .wiring(let generation), .wired(let generation, _):
            generation
        }
    }

    mutating func begin(_ generation: Generation) {
        self = .wiring(generation)
    }

    mutating func install(_ callbacks: Callbacks, for generation: Generation) -> InstallOutcome {
        guard case .wiring(let currentGeneration) = self,
              currentGeneration == generation
        else { return .rejected }
        self = .wired(generation, callbacks)
        return .installed
    }

    mutating func invalidate(_ generation: Generation) {
        guard self.generation == generation else { return }
        self = .unwired
    }

    mutating func reset() {
        self = .unwired
    }

    func send(_ data: Data, toClient clientId: Int) async -> ServerSendOutcome {
        guard case .wired(_, let callbacks) = self else {
            return .failed(.transportUnavailable)
        }
        return await callbacks.sendToClient(data, clientId)
    }

    @discardableResult
    func disconnect(_ clientId: Int) async -> CallbackOutcome {
        guard case .wired(_, let callbacks) = self else {
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
        guard case .wired(_, let callbacks) = self else {
            return .failed(.callbacksNotInstalled("onClientAuthenticated"))
        }
        await callbacks.onClientAuthenticated(clientId, respond)
        return .delivered
    }
}
