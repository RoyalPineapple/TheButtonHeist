#if canImport(UIKit)
import XCTest

@testable import AccessibilitySnapshotParser
@_spi(ButtonHeistInternals) @testable import ThePlans
@testable import TheInsideJob
@_spi(ButtonHeistInternals) @testable import TheScore

final class HeistMachineControlFlowTests: XCTestCase {
    func testConditionalRetainsSelectionActualAndSnapshotSummary() throws {
        let snapshot = heistSnapshot(labels: ["Home", "Login"])
        let plan = try HeistPlan(body: [
            .conditional(try ConditionalStep(cases: [
                PredicateCase(
                    predicate: .exists(.label("Home")),
                    body: [.warn(WarnStep(message: "home"))]
                ),
                PredicateCase(
                    predicate: .exists(.label("Login")),
                    body: [.fail(FailStep(message: "wrong branch"))]
                ),
            ])),
        ])
        var driver = try HeistMachineTestDriver(
            plan: plan,
            script: MachineRunScript(snapshots: [snapshot])
        )

        let completion = try driver.run()
        let step = try XCTUnwrap(completion.steps.first)
        let selection = try XCTUnwrap(step.caseSelectionEvidence?.selection)

        XCTAssertEqual(selection.outcome, .matchedCase(index: 0))
        XCTAssertEqual(selection.cases.map(\.met), [true, true])
        XCTAssertNotNil(selection.cases[0].actual)
        XCTAssertNotNil(selection.lastObservedSummary)
        XCTAssertEqual(step.children.map(\.kind), [.warn])
    }

    func testConditionalElsePreservesNoMatchReason() throws {
        let plan = try HeistPlan(body: [
            .conditional(try ConditionalStep(
                cases: [
                    PredicateCase(
                        predicate: .exists(.label("Home")),
                        body: [.fail(FailStep(message: "unreachable"))]
                    ),
                ],
                elseBody: [.warn(WarnStep(message: "fallback"))]
            )),
        ])
        var driver = try HeistMachineTestDriver(
            plan: plan,
            script: MachineRunScript(snapshots: [heistSnapshot(labels: ["Settings"])])
        )

        let completion = try driver.run()
        let step = try XCTUnwrap(completion.steps.first)

        XCTAssertEqual(
            step.caseSelectionEvidence?.selection.outcome,
            .elseBranch(reason: .noMatch)
        )
        XCTAssertEqual(step.children.map(\.kind), [.warn])
    }

    func testWaitElseRunsOnlyForLeafTimeout() throws {
        let plan = try waitWithElsePlan()
        var driver = try HeistMachineTestDriver(
            plan: plan,
            script: MachineRunScript(leafOutcomes: [.timedOut])
        )

        let completion = try driver.run()
        let wait = try XCTUnwrap(completion.steps.first)

        XCTAssertEqual(wait.status, .passed)
        XCTAssertEqual(wait.children.map(\.kind), [.warn])
        XCTAssertEqual(completion.steps.last?.kind, .warn)
        XCTAssertEqual(completion.steps.last?.status, .passed)
    }

    func testWaitElseDoesNotRunForHeistTimeoutCancellationOrUnavailableEvidence() throws {
        for outcome in [
            HeistExecution.LeafOutcome.heistTimedOut,
            .cancelled,
            .unavailable,
        ] {
            var driver = try HeistMachineTestDriver(
                plan: waitWithElsePlan(),
                script: MachineRunScript(leafOutcomes: [outcome])
            )

            let completion = try driver.run()
            let wait = try XCTUnwrap(completion.steps.first)

            XCTAssertEqual(wait.status, .failed)
            XCTAssertTrue(wait.children.isEmpty)
            XCTAssertEqual(completion.steps.last?.kind, .warn)
            XCTAssertEqual(completion.steps.last?.status, .skipped)
        }
    }

    func testFailedChildSkipsEveryLaterSibling() throws {
        let plan = try HeistPlan(body: [
            .conditional(try ConditionalStep(cases: [
                PredicateCase(
                    predicate: .exists(.label("Home")),
                    body: [
                        .fail(FailStep(message: "stop")),
                        .warn(WarnStep(message: "nested later")),
                    ]
                ),
            ])),
            .warn(WarnStep(message: "root later")),
        ])
        var driver = try HeistMachineTestDriver(
            plan: plan,
            script: MachineRunScript(snapshots: [heistSnapshot(labels: ["Home"])])
        )

        let completion = try driver.run()
        let conditional = try XCTUnwrap(completion.steps.first)

        XCTAssertEqual(conditional.status, .failed)
        XCTAssertEqual(conditional.children.map(\.status), [.failed, .skipped])
        XCTAssertEqual(completion.steps.map(\.status), [.failed, .skipped])
        XCTAssertEqual(completion.abortedAtPath, conditional.children.first?.path)
    }

    func testRepeatUntilExecutesBodyBeforeEvaluatingCompletion() throws {
        let plan = try HeistPlan(body: [
            .repeatUntil(try RepeatUntilStep(
                predicate: .exists(.label("Done")),
                timeout: try .seconds(1),
                body: [.warn(WarnStep(message: "attempt"))]
            )),
        ])
        var driver = try HeistMachineTestDriver(
            plan: plan,
            script: MachineRunScript(
                snapshots: [heistSnapshot(labels: ["Done"])],
                events: [.noChange]
            )
        )

        let completion = try driver.run()
        let loop = try XCTUnwrap(completion.steps.first)

        XCTAssertEqual(loop.status, .passed)
        XCTAssertEqual(loop.repeatUntilEvidence?.iterationCount, 1)
        XCTAssertEqual(loop.children.map(\.kind), [.repeatUntilIteration])
        XCTAssertEqual(loop.children.first?.children.map(\.kind), [.warn])
    }
}

private extension HeistMachineControlFlowTests {
    func waitWithElsePlan() throws -> HeistPlan {
        try HeistPlan(body: [
            .wait(WaitStep(
                predicate: .exists(.label("Ready")),
                timeout: try .milliseconds(1),
                elseBody: [.warn(WarnStep(message: "timed out"))]
            )),
            .warn(WarnStep(message: "continued")),
        ])
    }
}

#endif // canImport(UIKit)
