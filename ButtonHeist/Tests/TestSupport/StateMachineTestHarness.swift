import ButtonHeistSupport

package struct StateMachineTestStep<Machine: SimpleStateMachine> {
    package let label: String
    package let event: Machine.Event
    package let expected: StateChange<Machine.State, Machine.Effect, Machine.Rejection>

    package init(
        _ label: String,
        event: Machine.Event,
        expected: StateChange<Machine.State, Machine.Effect, Machine.Rejection>
    ) {
        self.label = label
        self.event = event
        self.expected = expected
    }
}

package struct StateMachineIdempotenceInvariant<Machine: SimpleStateMachine> {
    package let label: String
    package let event: Machine.Event
    package let expected: StateChange<Machine.State, Machine.Effect, Machine.Rejection>

    package init(
        _ label: String,
        event: Machine.Event,
        expected: StateChange<Machine.State, Machine.Effect, Machine.Rejection>
    ) {
        self.label = label
        self.event = event
        self.expected = expected
    }
}

package struct StateMachineTestScenario<Machine: SimpleStateMachine> {
    package let label: String
    package let initialState: Machine.State
    package let steps: [StateMachineTestStep<Machine>]
    package let idempotenceInvariant: StateMachineIdempotenceInvariant<Machine>?

    package init(
        _ label: String,
        initialState: Machine.State,
        steps: [StateMachineTestStep<Machine>],
        idempotenceInvariant: StateMachineIdempotenceInvariant<Machine>? = nil
    ) {
        self.label = label
        self.initialState = initialState
        self.steps = steps
        self.idempotenceInvariant = idempotenceInvariant
    }
}

package struct StateMachineTestFailure: Error, Equatable, CustomStringConvertible {
    package let scenario: String
    package let step: String
    package let expectation: String
    package let expected: String
    package let actual: String

    package var description: String {
        "State machine scenario '\(scenario)', step '\(step)' failed \(expectation): "
            + "expected \(expected), got \(actual)"
    }
}

@discardableResult
package func runStateMachineScenario<Machine: SimpleStateMachine>(
    _ scenario: StateMachineTestScenario<Machine>,
    machine: Machine
) throws -> Machine.State {
    var driver = StateDriver(initial: scenario.initialState, machine: machine)

    for (index, step) in scenario.steps.enumerated() {
        try sendAndValidate(
            step.event,
            expected: step.expected,
            stepLabel: "\(index + 1). \(step.label)",
            scenarioLabel: scenario.label,
            driver: &driver
        )
    }

    if let invariant = scenario.idempotenceInvariant {
        for repetition in 1 ... 2 {
            try sendAndValidate(
                invariant.event,
                expected: invariant.expected,
                stepLabel: "idempotence invariant '\(invariant.label)' repetition \(repetition)",
                scenarioLabel: scenario.label,
                driver: &driver
            )
        }
    }

    return driver.state
}

private func sendAndValidate<Machine: SimpleStateMachine>(
    _ event: Machine.Event,
    expected: StateChange<Machine.State, Machine.Effect, Machine.Rejection>,
    stepLabel: String,
    scenarioLabel: String,
    driver: inout StateDriver<Machine>
) throws {
    let actual = driver.send(event)
    guard actual == expected else {
        throw StateMachineTestFailure(
            scenario: scenarioLabel,
            step: stepLabel,
            expectation: "transition",
            expected: String(describing: expected),
            actual: String(describing: actual)
        )
    }
    guard driver.state == expected.state else {
        throw StateMachineTestFailure(
            scenario: scenarioLabel,
            step: stepLabel,
            expectation: "driver state",
            expected: String(describing: expected.state),
            actual: String(describing: driver.state)
        )
    }
}
