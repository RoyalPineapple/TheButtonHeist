import XCTest
@testable import TheInsideJob

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
}

private struct GateMachine: SimpleStateMachine {
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
