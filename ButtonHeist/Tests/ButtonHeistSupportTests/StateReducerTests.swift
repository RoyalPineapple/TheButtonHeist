import XCTest
@testable import ButtonHeistSupport

final class StateReducerTests: XCTestCase {
    func testStoreAppliesChangedTransitionEffectsAndState() {
        var store = StateStore(initial: GateState.locked, reducer: GateReducer())

        let transition = store.reduce(.insertCoin)

        XCTAssertEqual(transition, .changed(to: .unlocked, effects: [.unlocked]))
        XCTAssertEqual(store.state, .unlocked)
        XCTAssertEqual(transition.effects, [.unlocked])
    }

    func testStoreLeavesStateUntouchedWhenTransitionIsRejected() {
        var store = StateStore(initial: GateState.locked, reducer: GateReducer())

        let transition = store.reduce(.push)

        XCTAssertEqual(transition, .rejected(.coinRequired, stayingIn: .locked))
        XCTAssertEqual(store.state, .locked)
        XCTAssertEqual(transition.effects, [])
    }

    func testChangedTransitionCanBeEffectFree() {
        let transition = StateTransition<GateState, GateEffect, GateRejection>.changed(to: .locked)

        XCTAssertEqual(transition.state, .locked)
        XCTAssertEqual(transition.effects, [])
    }

    func testStoreSupportsNonSendableState() {
        let initial = LocalState(value: 1)
        let replacement = LocalState(value: 2)
        var store = StateStore(initial: initial, reducer: LocalReducer())

        let transition = store.reduce(.replacementRequested(replacement))

        XCTAssertEqual(transition, .changed(to: replacement, effects: [replacement]))
        XCTAssertEqual(store.state, replacement)
    }

}

private struct GateReducer: StateReducer, Sendable {
    func reduce(_ state: GateState, event: GateEvent) -> StateTransition<GateState, GateEffect, GateRejection> {
        switch (state, event) {
        case (.locked, .insertCoin):
            return .changed(to: .unlocked, effects: [.unlocked])
        case (.locked, .push):
            return .rejected(.coinRequired, stayingIn: .locked)
        case (.unlocked, .push):
            return .changed(to: .locked, effects: [.locked])
        case (.unlocked, .insertCoin):
            return .changed(to: .unlocked)
        }
    }
}

private enum GateState: Equatable, Sendable {
    case locked
    case unlocked
}

private enum GateEvent: Equatable, Sendable {
    case insertCoin
    case push
}

private enum GateEffect: Equatable, Sendable {
    case locked
    case unlocked
}

private enum GateRejection: Equatable, Sendable {
    case coinRequired
}

private struct LocalReducer: StateReducer {
    enum Event: Equatable {
        case replacementRequested(LocalState)
    }

    enum Rejection: Equatable {}

    func reduce(
        _ state: LocalState,
        event: Event
    ) -> StateTransition<LocalState, LocalState, Rejection> {
        switch event {
        case .replacementRequested(let replacement):
            return .changed(to: replacement, effects: [replacement])
        }
    }
}

private final class LocalState: Equatable {
    let value: Int

    init(value: Int) {
        self.value = value
    }

    static func == (lhs: LocalState, rhs: LocalState) -> Bool {
        lhs.value == rhs.value
    }
}
