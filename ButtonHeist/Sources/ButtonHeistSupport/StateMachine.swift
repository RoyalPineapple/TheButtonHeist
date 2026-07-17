package protocol SimpleStateMachine {
    associatedtype State: Equatable
    associatedtype Event: Equatable
    associatedtype Effect: Equatable
    associatedtype Rejection: Equatable

    func advance(_ state: State, with event: Event) -> StateChange<State, Effect, Rejection>
}

package enum StateChange<State, Effect, Rejection>: Equatable
where State: Equatable, Effect: Equatable, Rejection: Equatable {
    case changed(to: State, effects: [Effect] = [])
    case rejected(Rejection, stayingIn: State)

    package var state: State {
        switch self {
        case .changed(let state, _), .rejected(_, let state):
            return state
        }
    }

    package var effects: [Effect] {
        switch self {
        case .changed(_, let effects):
            return effects
        case .rejected:
            return []
        }
    }
}

extension StateChange: Sendable where State: Sendable, Effect: Sendable, Rejection: Sendable {}

package struct StateDriver<Machine: SimpleStateMachine> {
    package private(set) var state: Machine.State
    package let machine: Machine

    package init(initial state: Machine.State, machine: Machine) {
        self.state = state
        self.machine = machine
    }

    @discardableResult
    package mutating func send(_ event: Machine.Event) -> StateChange<Machine.State, Machine.Effect, Machine.Rejection> {
        let change = machine.advance(state, with: event)
        state = change.state
        return change
    }
}

extension StateDriver: Sendable where Machine: Sendable, Machine.State: Sendable {}
