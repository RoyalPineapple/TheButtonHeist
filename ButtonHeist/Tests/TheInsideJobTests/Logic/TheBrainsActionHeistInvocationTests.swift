#if canImport(UIKit)
import ButtonHeistTestSupport
import XCTest

@testable import AccessibilitySnapshotParser
@_spi(ButtonHeistInternals) @testable import ThePlans
@testable import TheInsideJob
@_spi(ButtonHeistInternals) @testable import TheScore

final class HeistMachineInvocationTests: XCTestCase {
    func testInvocationExecutesDefinitionBodyAndRetainsStructure() throws {
        let definition = try HeistPlan(
            name: "OpenCart",
            body: [.warn(WarnStep(message: "opened"))]
        )
        let plan = try HeistPlan(
            definitions: [definition],
            body: [.invoke(HeistInvocationStep(path: "OpenCart"))]
        )
        var driver = try HeistMachineTestDriver(plan: plan)

        let completion = try driver.run()
        let invocation = try XCTUnwrap(completion.steps.first)

        XCTAssertEqual(invocation.kind, .invoke)
        XCTAssertEqual(invocation.status, .passed)
        XCTAssertEqual(invocation.children.map(\.kind), [.warn])
        XCTAssertEqual(invocation.children.map(\.status), [.passed])
    }

    func testNestedInvocationOrderIsRepresentedByNestedResultNodes() throws {
        let inner = try HeistPlan(
            name: "Inner",
            body: [.warn(WarnStep(message: "inner"))]
        )
        let outer = try HeistPlan(
            name: "Outer",
            definitions: [inner],
            body: [
                .warn(WarnStep(message: "before")),
                .invoke(HeistInvocationStep(path: "Inner")),
                .warn(WarnStep(message: "after")),
            ]
        )
        let plan = try HeistPlan(
            definitions: [outer],
            body: [.invoke(HeistInvocationStep(path: "Outer"))]
        )
        var driver = try HeistMachineTestDriver(plan: plan)

        let completion = try driver.run()
        let outerInvocation = try XCTUnwrap(completion.steps.first)

        XCTAssertEqual(outerInvocation.children.map(\.kind), [.warn, .invoke, .warn])
        XCTAssertEqual(
            outerInvocation.children[1].children.map(\.kind),
            [.warn]
        )
        XCTAssertEqual(
            outerInvocation.children.map(\.path.description),
            [
                "$.body[0].invoke.body[0]",
                "$.body[0].invoke.body[1]",
                "$.body[0].invoke.body[2]",
            ]
        )
    }

    func testInvocationExpectationUsesTheSameWaitLeaf() throws {
        let policy = ActionExpectationTimeoutPolicy(standard: 3, screenTransition: 12)
        let definition = try HeistPlan(
            name: "Submit",
            body: [.warn(WarnStep(message: "submitted"))]
        )
        let plan = try HeistPlan(
            definitions: [definition],
            body: [
                .invoke(HeistInvocationStep(
                    path: "Submit",
                    expectation: ActionExpectation(
                        predicate: .screenChanged
                    )
                )),
            ]
        )
        var driver = try HeistMachineTestDriver(
            plan: plan,
            actionExpectationTimeoutPolicy: policy,
            script: MachineRunScript(
                snapshots: [makeTestObservationSnapshot(labels: ["Done"])],
                events: [.screenChanged(ScreenFacts(idAfter: nil)), .noChange]
            )
        )

        let completion = try driver.run()
        let invocation = try XCTUnwrap(completion.steps.first)
        let expectation = try XCTUnwrap(invocation.children.last)

        XCTAssertEqual(invocation.status, .passed)
        XCTAssertEqual(expectation.kind, .wait)
        XCTAssertEqual(try expectation.replayExpectation()?.met, true)
        XCTAssertEqual(invocation.children.map(\.kind), [.warn, .wait])
        XCTAssertEqual(
            driver.requests.compactMap(\.observationScope),
            [.visible]
        )
        XCTAssertEqual(
            driver.requests.compactMap(\.observationTimeout),
            [.seconds(policy.screenTransition.seconds)]
        )
    }

    func testInvocationFailureSkipsDefinitionAndCallerSiblings() throws {
        let definition = try HeistPlan(
            name: "Failing",
            body: [
                .fail(FailStep(message: "stop")),
                .warn(WarnStep(message: "definition later")),
            ]
        )
        let plan = try HeistPlan(
            definitions: [definition],
            body: [
                .invoke(HeistInvocationStep(path: "Failing")),
                .warn(WarnStep(message: "caller later")),
            ]
        )
        var driver = try HeistMachineTestDriver(plan: plan)

        let completion = try driver.run()
        let invocation = try XCTUnwrap(completion.steps.first)

        XCTAssertEqual(invocation.status, .failed)
        XCTAssertEqual(invocation.children.map(\.status), [.failed, .skipped])
        XCTAssertEqual(completion.steps.last?.status, .skipped)
        XCTAssertEqual(completion.abortedAtPath, invocation.children.first?.path)
    }

    func testInvocationReferenceMustResolveBeforeMachineConstruction() throws {
        XCTAssertThrowsError(try HeistPlan(body: [
            .invoke(HeistInvocationStep(path: "Missing")),
        ]))
    }
}

private extension HeistExecution.MainActorRequest {
    var observationScope: SemanticObservationScope? {
        guard case .beginObservation(_, let request) = self else { return nil }
        return request.scope
    }

    var observationTimeout: Duration? {
        guard case .beginObservation(_, let request) = self else { return nil }
        return request.timeout
    }
}

#endif // canImport(UIKit)
