package protocol SimpleStateMachine: Sendable {
    associatedtype State: Sendable & Equatable
    associatedtype Event: Sendable & Equatable
    associatedtype Effect: Sendable & Equatable
    associatedtype Rejection: Sendable & Equatable

    func advance(_ state: State, with event: Event) -> StateChange<State, Effect, Rejection>
}

package enum StateChange<State, Effect, Rejection>: Sendable, Equatable
where State: Sendable & Equatable, Effect: Sendable & Equatable, Rejection: Sendable & Equatable {
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

    package var singleEffect: Effect? {
        guard effects.count == 1 else { return nil }
        return effects[0]
    }
}

package struct StateDriver<Machine: SimpleStateMachine>: Sendable {
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
