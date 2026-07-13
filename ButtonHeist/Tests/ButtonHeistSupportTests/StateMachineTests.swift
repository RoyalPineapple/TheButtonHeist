import XCTest
@testable import ButtonHeistSupport

final class StateMachineTests: XCTestCase {
    func testDriverAppliesChangedTransitionEffectsAndState() {
        var driver = StateDriver(initial: GateState.locked, machine: GateMachine())

        let change = driver.send(.insertCoin)

        XCTAssertEqual(change, .changed(to: .unlocked, effects: [.unlocked]))
        XCTAssertEqual(driver.state, .unlocked)
        XCTAssertEqual(change.effects, [.unlocked])
        XCTAssertEqual(change.singleEffect, .unlocked)
    }

    func testDriverLeavesStateUntouchedWhenEventIsRejected() {
        var driver = StateDriver(initial: GateState.locked, machine: GateMachine())

        let change = driver.send(.push)

        XCTAssertEqual(change, .rejected(.coinRequired, stayingIn: .locked))
        XCTAssertEqual(driver.state, .locked)
        XCTAssertEqual(change.effects, [])
        XCTAssertNil(change.singleEffect)
    }

    func testChangedTransitionCanBeEffectFree() {
        let change = StateChange<GateState, GateEffect, GateRejection>.changed(to: .locked)

        XCTAssertEqual(change.state, .locked)
        XCTAssertEqual(change.effects, [])
    }

    func testDriverSupportsNonSendableState() {
        let initial = LocalState(value: 1)
        let replacement = LocalState(value: 2)
        var driver = StateDriver(initial: initial, machine: LocalMachine())

        let change = driver.send(.replace(with: replacement))

        XCTAssertEqual(change, .changed(to: replacement, effects: [replacement]))
        XCTAssertEqual(driver.state, replacement)
    }

    func testPureMachineValuesRemainSendable() {
        assertSendable(StateChange<GateState, GateEffect, GateRejection>.self)
        assertSendable(StateDriver<GateMachine>.self)
    }
}

private struct GateMachine: SimpleStateMachine, Sendable {
    func advance(_ state: GateState, with event: GateEvent) -> StateChange<GateState, GateEffect, GateRejection> {
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

private struct LocalMachine: SimpleStateMachine {
    enum Event: Equatable {
        case replace(with: LocalState)
    }

    enum Rejection: Equatable {}

    func advance(
        _ state: LocalState,
        with event: Event
    ) -> StateChange<LocalState, LocalState, Rejection> {
        switch event {
        case .replace(let replacement):
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

private func assertSendable<Value: Sendable>(_: Value.Type) {}
