import os

enum ReadyConnectionAcceptance: Equatable, Sendable {
    case registered(clientId: Int)
    case rejected
}

/// Cross-queue admission state for a connection while Network.framework
/// delivers `.ready` and `.cancelled` callbacks. The server actor owns the
/// client table, but those callbacks arrive on the NWConnection queue before
/// the actor has necessarily accepted the ready connection.
final class ConnectionAdmission: @unchecked Sendable { // swiftlint:disable:this agent_unchecked_sendable_no_comment
    enum ReadyTransition: Equatable, Sendable {
        case accept
        case ignore
    }

    enum AcceptanceTransition: Equatable, Sendable {
        case keepRegisteredClient
        case removeRegisteredClient(Int)
        case noRegisteredClient
    }

    enum CancellationTransition: Equatable, Sendable {
        case removeRegisteredClient(Int)
        case noRegisteredClient
    }

    private enum State {
        case waitingForReady
        case acceptingReadyConnection
        case accepted(clientId: Int)
        case rejected
        case cancelledBeforeAcceptance
        case cancelledDuringAcceptance
        case cancelled
    }

    private let state = OSAllocatedUnfairLock<State>(initialState: .waitingForReady)

    func recordReady() -> ReadyTransition {
        state.withLock { current in
            guard case .waitingForReady = current else { return .ignore }
            current = .acceptingReadyConnection
            return .accept
        }
    }

    /// Records the server actor's ready-connection result. When cancellation
    /// arrived while the actor was accepting the socket, returns the accepted
    /// client id so the caller can remove that just-registered client.
    func recordAcceptance(_ acceptance: ReadyConnectionAcceptance) -> AcceptanceTransition {
        state.withLock { current in
            switch (current, acceptance) {
            case (.acceptingReadyConnection, .registered(let clientId)):
                current = .accepted(clientId: clientId)
                return .keepRegisteredClient
            case (.acceptingReadyConnection, .rejected):
                current = .rejected
                return .noRegisteredClient
            case (.cancelledDuringAcceptance, .registered(let clientId)):
                current = .cancelled
                return .removeRegisteredClient(clientId)
            case (.cancelledDuringAcceptance, .rejected):
                current = .cancelled
                return .noRegisteredClient
            default:
                return .noRegisteredClient
            }
        }
    }

    /// Marks the connection cancelled/failed. Returns an already-accepted
    /// client id when cleanup must be scheduled on the server actor.
    func recordCancellation() -> CancellationTransition {
        state.withLock { current in
            switch current {
            case .waitingForReady:
                current = .cancelledBeforeAcceptance
                return .noRegisteredClient
            case .acceptingReadyConnection:
                current = .cancelledDuringAcceptance
                return .noRegisteredClient
            case .accepted(let clientId):
                current = .cancelled
                return .removeRegisteredClient(clientId)
            case .rejected, .cancelledBeforeAcceptance, .cancelledDuringAcceptance, .cancelled:
                return .noRegisteredClient
            }
        }
    }
}
