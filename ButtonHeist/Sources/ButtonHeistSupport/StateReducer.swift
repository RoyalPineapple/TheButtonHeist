package protocol StateReducer {
    associatedtype State: Equatable
    associatedtype Event: Equatable
    associatedtype Effect: Equatable
    associatedtype Rejection: Equatable

    func reduce(_ state: State, event: Event) -> StateTransition<State, Effect, Rejection>
}

package enum StateTransition<State, Effect, Rejection>: Equatable
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

extension StateTransition: Sendable where State: Sendable, Effect: Sendable, Rejection: Sendable {}

package struct StateStore<Reducer: StateReducer> {
    package private(set) var state: Reducer.State
    package let reducer: Reducer

    package init(initial state: Reducer.State, reducer: Reducer) {
        self.state = state
        self.reducer = reducer
    }

    @discardableResult
    package mutating func reduce(
        _ event: Reducer.Event
    ) -> StateTransition<Reducer.State, Reducer.Effect, Reducer.Rejection> {
        let transition = reducer.reduce(state, event: event)
        state = transition.state
        return transition
    }
}

extension StateStore: Sendable where Reducer: Sendable, Reducer.State: Sendable {}
