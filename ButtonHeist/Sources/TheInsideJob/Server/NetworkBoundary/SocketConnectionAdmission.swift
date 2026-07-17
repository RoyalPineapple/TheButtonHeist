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

    private let machine = OSAllocatedUnfairLock<ConnectionAdmissionMachine>(
        initialState: ConnectionAdmissionMachine()
    )

    func recordReady() -> ReadyTransition {
        machine.withLock { machine in
            machine.recordReady().effect
        }
    }

    /// Records the server actor's ready-connection result. When cancellation
    /// arrived while the actor was accepting the socket, returns the accepted
    /// client id so the caller can remove that just-registered client.
    func recordAcceptance(_ acceptance: ReadyConnectionAcceptance) -> AcceptanceTransition {
        machine.withLock { machine in
            machine.recordAcceptance(acceptance).effect
        }
    }

    /// Marks the connection cancelled/failed. Returns an already-accepted
    /// client id when cleanup must be scheduled on the server actor.
    func recordCancellation() -> CancellationTransition {
        machine.withLock { machine in
            machine.recordCancellation().effect
        }
    }
}

private struct ConnectionAdmissionMachine {
    enum State: Equatable, Sendable {
        case waitingForReady
        case acceptingReadyConnection
        case accepted(clientId: Int)
        case rejected
        case cancelledBeforeAcceptance
        case cancelledDuringAcceptance
        case cancelled
    }

    struct ReadyChange: Equatable, Sendable {
        let state: State
        let effect: ConnectionAdmission.ReadyTransition
    }

    struct AcceptanceChange: Equatable, Sendable {
        let state: State
        let effect: ConnectionAdmission.AcceptanceTransition
    }

    struct CancellationChange: Equatable, Sendable {
        let state: State
        let effect: ConnectionAdmission.CancellationTransition
    }

    private(set) var state: State = .waitingForReady

    mutating func recordReady() -> ReadyChange {
        let change = advanceReady(from: state)
        state = change.state
        return change
    }

    mutating func recordAcceptance(_ acceptance: ReadyConnectionAcceptance) -> AcceptanceChange {
        let change = advanceAcceptance(acceptance, from: state)
        state = change.state
        return change
    }

    mutating func recordCancellation() -> CancellationChange {
        let change = advanceCancellation(from: state)
        state = change.state
        return change
    }

    private func advanceReady(from state: State) -> ReadyChange {
        switch state {
        case .waitingForReady:
            return ReadyChange(state: .acceptingReadyConnection, effect: .accept)
        case .acceptingReadyConnection,
             .accepted,
             .rejected,
             .cancelledBeforeAcceptance,
             .cancelledDuringAcceptance,
             .cancelled:
            return ReadyChange(state: state, effect: .ignore)
        }
    }

    private func advanceAcceptance(
        _ acceptance: ReadyConnectionAcceptance,
        from state: State
    ) -> AcceptanceChange {
        switch (state, acceptance) {
        case (.acceptingReadyConnection, .registered(let clientId)):
            return AcceptanceChange(
                state: .accepted(clientId: clientId),
                effect: .keepRegisteredClient
            )
        case (.acceptingReadyConnection, .rejected):
            return AcceptanceChange(state: .rejected, effect: .noRegisteredClient)
        case (.cancelledDuringAcceptance, .registered(let clientId)):
            return AcceptanceChange(
                state: .cancelled,
                effect: .removeRegisteredClient(clientId)
            )
        case (.cancelledDuringAcceptance, .rejected):
            return AcceptanceChange(state: .cancelled, effect: .noRegisteredClient)
        case (.waitingForReady, _),
             (.accepted, _),
             (.rejected, _),
             (.cancelledBeforeAcceptance, _),
             (.cancelled, _):
            return AcceptanceChange(state: state, effect: .noRegisteredClient)
        }
    }

    private func advanceCancellation(from state: State) -> CancellationChange {
        switch state {
        case .waitingForReady:
            return CancellationChange(state: .cancelledBeforeAcceptance, effect: .noRegisteredClient)
        case .acceptingReadyConnection:
            return CancellationChange(state: .cancelledDuringAcceptance, effect: .noRegisteredClient)
        case .accepted(let clientId):
            return CancellationChange(state: .cancelled, effect: .removeRegisteredClient(clientId))
        case .rejected, .cancelledBeforeAcceptance, .cancelledDuringAcceptance, .cancelled:
            return CancellationChange(state: state, effect: .noRegisteredClient)
        }
    }
}
