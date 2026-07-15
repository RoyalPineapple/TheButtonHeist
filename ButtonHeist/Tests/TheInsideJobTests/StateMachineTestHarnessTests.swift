#if canImport(UIKit)
import ButtonHeistSupport
import ButtonHeistTestSupport
import XCTest

final class StateMachineTestHarnessTests: XCTestCase {
    func testScenarioDrivesTransitionsAndChecksIdempotence() throws {
        let finalState = try runStateMachineScenario(
            StateMachineTestScenario<GateMachine>(
                "unlock and relock",
                initialState: .locked,
                steps: [
                    StateMachineTestStep(
                        "coin unlocks gate",
                        event: .insertCoin,
                        expected: .changed(to: .unlocked, effects: [.unlocked])
                    ),
                    StateMachineTestStep(
                        "push relocks gate",
                        event: .push,
                        expected: .changed(to: .locked, effects: [.locked])
                    ),
                ],
                idempotenceInvariant: StateMachineIdempotenceInvariant(
                    "locked gate rejects pushes",
                    event: .push,
                    expected: .rejected(.coinRequired, stayingIn: .locked)
                )
            ),
            machine: GateMachine()
        )

        XCTAssertEqual(finalState, .locked)
    }

    func testScenarioFailureNamesScenarioAndExactStep() {
        let scenario = StateMachineTestScenario<GateMachine>(
            "bad gate table",
            initialState: .locked,
            steps: [
                StateMachineTestStep(
                    "incorrect expectation",
                    event: .insertCoin,
                    expected: .changed(to: .locked)
                ),
            ]
        )

        XCTAssertThrowsError(try runStateMachineScenario(scenario, machine: GateMachine())) { error in
            let failure = error as? StateMachineTestFailure
            XCTAssertEqual(failure?.scenario, "bad gate table")
            XCTAssertEqual(failure?.step, "1. incorrect expectation")
            XCTAssertEqual(failure?.expectation, "transition")
        }
    }
}

private struct GateMachine: SimpleStateMachine {
    func advance(
        _ state: GateState,
        with event: GateEvent
    ) -> StateChange<GateState, GateEffect, GateRejection> {
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

private enum GateState: Equatable {
    case locked
    case unlocked
}

private enum GateEvent: Equatable {
    case insertCoin
    case push
}

private enum GateEffect: Equatable {
    case locked
    case unlocked
}

private enum GateRejection: Equatable {
    case coinRequired
}
#endif // canImport(UIKit)
