import os

import ButtonHeistSupport

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

    private let driver = OSAllocatedUnfairLock<StateDriver<ConnectionAdmissionMachine>>(
        initialState: StateDriver(initial: .waitingForReady, machine: ConnectionAdmissionMachine())
    )

    func recordReady() -> ReadyTransition {
        driver.withLock { driver in
            let change = driver.send(.recordReady)
            switch change.singleEffect {
            case .ready(let transition)?:
                return transition
            default:
                preconditionFailure("ConnectionAdmissionMachine produced an unexpected ready effect")
            }
        }
    }

    /// Records the server actor's ready-connection result. When cancellation
    /// arrived while the actor was accepting the socket, returns the accepted
    /// client id so the caller can remove that just-registered client.
    func recordAcceptance(_ acceptance: ReadyConnectionAcceptance) -> AcceptanceTransition {
        driver.withLock { driver in
            let change = driver.send(.recordAcceptance(acceptance))
            switch change.singleEffect {
            case .acceptance(let transition)?:
                return transition
            default:
                preconditionFailure("ConnectionAdmissionMachine produced an unexpected acceptance effect")
            }
        }
    }

    /// Marks the connection cancelled/failed. Returns an already-accepted
    /// client id when cleanup must be scheduled on the server actor.
    func recordCancellation() -> CancellationTransition {
        driver.withLock { driver in
            let change = driver.send(.recordCancellation)
            switch change.singleEffect {
            case .cancellation(let transition)?:
                return transition
            default:
                preconditionFailure("ConnectionAdmissionMachine produced an unexpected cancellation effect")
            }
        }
    }
}

private struct ConnectionAdmissionMachine: SimpleStateMachine {
    enum State: Equatable, Sendable {
        case waitingForReady
        case acceptingReadyConnection
        case accepted(clientId: Int)
        case rejected
        case cancelledBeforeAcceptance
        case cancelledDuringAcceptance
        case cancelled
    }

    enum Event: Equatable, Sendable {
        case recordReady
        case recordAcceptance(ReadyConnectionAcceptance)
        case recordCancellation
    }

    enum Effect: Equatable, Sendable {
        case ready(ConnectionAdmission.ReadyTransition)
        case acceptance(ConnectionAdmission.AcceptanceTransition)
        case cancellation(ConnectionAdmission.CancellationTransition)
    }

    enum Rejection: Equatable, Sendable {}

    func advance(_ state: State, with event: Event) -> StateChange<State, Effect, Rejection> {
        switch event {
        case .recordReady:
            return advanceReady(from: state)
        case .recordAcceptance(let acceptance):
            return advanceAcceptance(acceptance, from: state)
        case .recordCancellation:
            return advanceCancellation(from: state)
        }
    }

    private func advanceReady(from state: State) -> StateChange<State, Effect, Rejection> {
        switch state {
        case .waitingForReady:
            return .changed(to: .acceptingReadyConnection, effects: [.ready(.accept)])
        case .acceptingReadyConnection,
             .accepted,
             .rejected,
             .cancelledBeforeAcceptance,
             .cancelledDuringAcceptance,
             .cancelled:
            return .changed(to: state, effects: [.ready(.ignore)])
        }
    }

    private func advanceAcceptance(
        _ acceptance: ReadyConnectionAcceptance,
        from state: State
    ) -> StateChange<State, Effect, Rejection> {
        switch (state, acceptance) {
        case (.acceptingReadyConnection, .registered(let clientId)):
            return .changed(
                to: .accepted(clientId: clientId),
                effects: [.acceptance(.keepRegisteredClient)]
            )
        case (.acceptingReadyConnection, .rejected):
            return .changed(to: .rejected, effects: [.acceptance(.noRegisteredClient)])
        case (.cancelledDuringAcceptance, .registered(let clientId)):
            return .changed(
                to: .cancelled,
                effects: [.acceptance(.removeRegisteredClient(clientId))]
            )
        case (.cancelledDuringAcceptance, .rejected):
            return .changed(to: .cancelled, effects: [.acceptance(.noRegisteredClient)])
        case (.waitingForReady, _),
             (.accepted, _),
             (.rejected, _),
             (.cancelledBeforeAcceptance, _),
             (.cancelled, _):
            return .changed(to: state, effects: [.acceptance(.noRegisteredClient)])
        }
    }

    private func advanceCancellation(from state: State) -> StateChange<State, Effect, Rejection> {
        switch state {
        case .waitingForReady:
            return .changed(to: .cancelledBeforeAcceptance, effects: [.cancellation(.noRegisteredClient)])
        case .acceptingReadyConnection:
            return .changed(to: .cancelledDuringAcceptance, effects: [.cancellation(.noRegisteredClient)])
        case .accepted(let clientId):
            return .changed(to: .cancelled, effects: [.cancellation(.removeRegisteredClient(clientId))])
        case .rejected, .cancelledBeforeAcceptance, .cancelledDuringAcceptance, .cancelled:
            return .changed(to: state, effects: [.cancellation(.noRegisteredClient)])
        }
    }
}
