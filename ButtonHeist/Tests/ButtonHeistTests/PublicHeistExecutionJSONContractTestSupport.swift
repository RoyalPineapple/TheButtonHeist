import ButtonHeistTestSupport
import Foundation
import ThePlans
import TheScore
@_spi(ButtonHeistInternals) @testable import ButtonHeist
import XCTest

enum PublicHeistJSONFixtureValue {
    static func object(_ fields: [String: JSONValue]) -> JSONValue {
        .object(fields)
    }

    static func array(_ values: [JSONValue]) -> JSONValue {
        .array(values)
    }

    static func string(_ value: String) -> JSONValue {
        .string(value)
    }

    static func int(_ value: Int) -> JSONValue {
        .int(value)
    }

    static func double(_ value: Double) -> JSONValue {
        .double(value)
    }

    static func bool(_ value: Bool) -> JSONValue {
        .bool(value)
    }

    static func actionResult(
        status: String = "ok",
        method: String,
        message: String
    ) -> JSONValue {
        object([
            "status": string(status),
            "method": string(method),
            "message": string(message),
        ])
    }

    static func labelCheck(_ value: String) -> JSONValue {
        object([
            "kind": string("label"),
            "match": object([
                "mode": string("exact"),
                "value": string(value),
            ]),
        ])
    }

    static func target(label: String) -> JSONValue {
        object([
            "checks": array([labelCheck(label)]),
        ])
    }

    static func existsPredicate(label: String) -> JSONValue {
        object([
            "type": string("exists"),
            "target": target(label: label),
        ])
    }

    static func expectation(label: String, actual: String) -> JSONValue {
        object([
            "met": bool(true),
            "actual": string(actual),
            "expected": existsPredicate(label: label),
        ])
    }

    static let doneExpectation = expectation(label: "Done", actual: "Done visible")

    static let readyCase = object([
        "predicate": existsPredicate(label: "Ready"),
        "met": bool(true),
        "actual": string("Ready visible"),
    ])

    static let matchedWaitEvidence = object([
        "outcome": string("matched"),
        "expectation": doneExpectation,
        "baselineSummary": string("screen: Loading; interface: 0 elements"),
        "finalSummary": string("screen: Done visible; interface: 0 elements"),
        "delta": object([
            "kind": string("noChange"),
            "elementCount": int(0),
        ]),
    ])
}

enum PublicHeistExecutionJSONContractFixture {
    static let donePredicate = AccessibilityPredicate.exists(.label("Done"))

    static func actionWithExpectation() -> HeistExecutionStepResult {
        HeistResultFixture.action(
            command: .dismiss,
            result: .success(payload: .dismiss, message: "dismissed"),
            expectation: ExpectationResult(
                met: true,
                predicate: donePredicate,
                actual: "Done visible"
            )
        )
    }

    static func wait() throws -> HeistExecutionStepResult {
        let evidence = try waitEvidence()
        return .wait(
            path: "$.body[0]",
            predicate: donePredicate,
            timeout: 1,
            completion: .passed(evidence: .matched(evidence))
        )
    }

    static func caseSelection() -> HeistExecutionStepResult {
        let cases = [
            HeistCaseMatchResult(predicate: .exists(.label("Ready")), met: true, actual: "Ready visible"),
            HeistCaseMatchResult(predicate: .exists(.label("Fallback")), met: false),
        ]
        return .conditional(
            path: "$.body[0]",
            completion: .passed(evidence: HeistCaseSelectionEvidence(
                selection: .selectingFirstMatch(
                    cases: cases,
                    ifNone: .noMatch,
                    elapsedMs: 4,
                    timeout: 0.25,
                    lastObservedSummary: "Ready visible"
                )
            ))
        )
    }

    static func forEachString() throws -> HeistExecutionStepResult {
        let declaration = try XCTUnwrap(HeistForEachStringDeclaration(parameter: "item", count: 2))
        let evidence = try XCTUnwrap(HeistForEachStringEvidence(
            iterationCount: 1,
            iterationOrdinal: 0,
            value: "Milk"
        ))
        let iteration = HeistResultFixture.forEachStringIteration(
            path: "$.body[0].for_each_string.iterations[0]",
            parameter: "item",
            count: 2,
            iterationCount: 1,
            ordinal: 0,
            value: "Milk",
            status: .passed,
            children: []
        )
        return .forEachString(
            path: "$.body[0]",
            declaration: declaration,
            completion: .passed(
                evidence: try XCTUnwrap(HeistPassedForEachStringEvidence(evidence)),
                children: try XCTUnwrap(HeistPassingChildren([iteration]))
            )
        )
    }

    static func forEachElement() throws -> HeistExecutionStepResult {
        let declaration = try XCTUnwrap(HeistForEachElementDeclaration(
            parameter: "row",
            matching: ElementPredicate(label: "Row"),
            limit: 3
        ))
        let evidence = try XCTUnwrap(HeistForEachElementEvidence(
            matchedCount: 2,
            iterationCount: 1,
            iterationOrdinal: 0,
            targetOrdinal: 1,
            targetSummary: "Row 2"
        ))
        let iteration = HeistExecutionStepResult.forEachElementIteration(
            path: "$.body[0].for_each_element.iterations[0]",
            declaration: declaration,
            completion: .passed(evidence: try XCTUnwrap(HeistPassedForEachElementEvidence(evidence)))
        )
        return .forEachElement(
            path: "$.body[0]",
            declaration: declaration,
            completion: .passed(
                evidence: try XCTUnwrap(HeistPassedForEachElementEvidence(evidence)),
                children: try XCTUnwrap(HeistPassingChildren([iteration]))
            )
        )
    }

    static func repeatUntil() throws -> HeistExecutionStepResult {
        let met = ExpectationResult.Met(
            predicate: donePredicate,
            actual: "Done visible"
        )
        let unmet = try XCTUnwrap(ExpectationResult.Unmet(ExpectationResult(
            met: false,
            predicate: donePredicate,
            actual: "Loading"
        )))
        let firstIterationEvidence = try XCTUnwrap(HeistRepeatUntilEvidence.continued(
            iterationCount: 2,
            iterationOrdinal: 0,
            expectation: unmet
        ))
        let secondIterationEvidence = try XCTUnwrap(HeistRepeatUntilEvidence.matched(
            iterationCount: 2,
            expectation: met,
            actionResult: .success(payload: .wait, message: "repeat matched"),
            lastObservedSummary: "Done visible"
        ))
        let evidence = try XCTUnwrap(HeistRepeatUntilEvidence.matched(
            iterationCount: 2,
            expectation: met,
            actionResult: .success(payload: .wait, message: "repeat matched"),
            lastObservedSummary: "Done visible"
        ))
        let declaration = HeistRepeatUntilDeclaration(predicate: donePredicate, timeout: 0.5)
        let iterations = [
            HeistExecutionStepResult.repeatUntilIteration(
                path: "$.body[0].repeat_until.iterations[0]",
                declaration: declaration,
                completion: .passed(evidence: try XCTUnwrap(
                    HeistPassedRepeatUntilIterationEvidence(firstIterationEvidence)
                ))
            ),
            HeistExecutionStepResult.repeatUntilIteration(
                path: "$.body[0].repeat_until.iterations[1]",
                declaration: declaration,
                completion: .passed(evidence: try XCTUnwrap(
                    HeistPassedRepeatUntilIterationEvidence(secondIterationEvidence)
                ))
            ),
        ]
        return .repeatUntil(
            path: "$.body[0]",
            declaration: declaration,
            completion: .passed(
                evidence: try XCTUnwrap(HeistPassedRepeatUntilEvidence(evidence)),
                children: try XCTUnwrap(HeistPassingChildren(iterations))
            )
        )
    }

    static func invocation() throws -> HeistExecutionStepResult {
        let evidence = HeistInvocationEvidence.completed(
            expectation: .waitPassed(.matched(try waitEvidence()))
        )
        return .invocation(
            path: "$.body[0]",
            invocationPath: "Cart.checkout",
            argument: .string("Milk"),
            completion: .passed(evidence: try XCTUnwrap(HeistPassedInvocationEvidence(evidence)))
        )
    }

    static func actionWithOmissions() throws -> HeistExecutionStepResult {
        let observation = makeObservationEvidence(
            before: makeTestInterface(elements: []),
            after: makeTestInterface(elements: [
                makeTestHeistElement(label: "Pay", identifier: "pay"),
            ])
        )
        let subject = makeTestHeistElement(label: "Pay", identifier: "pay")
        let subjectEvidence = ActionSubjectEvidence(
            source: .resolvedSemanticTarget,
            target: try AccessibilityTarget
                .predicate(ElementPredicate(label: "Pay"))
                .resolve(in: .empty),
            element: subject,
            resolution: ActionSubjectResolution(origin: .visible)
        )
        return HeistResultFixture.action(result: .success(
            payload: .activate,
            observation: .observed(observation),
            subjectEvidence: subjectEvidence
        ))
    }

    static func netDelta() -> PublicHeistNetDeltaFixture {
        let observation = makeObservationEvidence(
            before: makeTestInterface(elements: []),
            after: makeTestInterface(elements: [
                makeTestHeistElement(label: "Pay", identifier: "pay"),
            ]),
            completeness: .complete
        )
        let result = ActionResult.success(
            payload: .activate,
            observation: .observed(observation)
        )
        return PublicHeistNetDeltaFixture(
            step: HeistResultFixture.action(result: result)
        )
    }

    static var oneVisibleCaseProfile: ProjectionProfile {
        ProjectionProfile(
            kind: .summary,
            limits: .current(caseResults: 1)
        )
    }

    private static func waitEvidence() throws -> HeistWaitMatchedEvidence {
        let expectation = ExpectationResult.Met(
            predicate: donePredicate,
            actual: "Done visible"
        )
        let interface = makeTestInterface(elements: [])
        return HeistWaitMatchedEvidence(
            observation: Observation.Evidence(
                baseline: Observation.Snapshot(
                    interface: interface,
                    context: Observation.Context(screenId: "Loading")
                ),
                current: Observation.Snapshot(
                    interface: interface,
                    context: Observation.Context(screenId: "Done visible")
                ),
                events: [.noChange],
                completeness: .complete
            ),
            expectation: expectation
        )
    }
}

struct PublicHeistNetDeltaFixture {
    let step: HeistExecutionStepResult
}

func publicHeistExecutionJSON(
    step: HeistExecutionStepResult,
    profile: ProjectionProfile = .summary
) throws -> JSONProbe {
    let result = try HeistResult(steps: [step], durationMs: 1)
    let response = FenceResponse.heistExecution(
        plan: try HeistPlan(body: [.warn(WarnStep(message: "fixture"))]),
        report: HeistReport.project(result: result)
    )
    let data = try JSONEncoder().encode(PublicResponseModel(response: response, profile: profile))
    return try JSONProbe(data: data)
}

func publicHeistExecutionNodeJSON(
    step: HeistExecutionStepResult,
    profile: ProjectionProfile = .summary
) throws -> JSONProbe {
    let response = try publicHeistExecutionJSON(step: step, profile: profile)
    return try XCTUnwrap(try response.object("report").array("nodes").first)
}

func assertPublicHeistJSONContract(
    _ actual: JSONProbe,
    equals fixture: JSONValue,
    file: StaticString = #filePath,
    line: UInt = #line
) throws {
    XCTAssertEqual(
        try actual.decode(JSONValue.self),
        fixture,
        file: file,
        line: line
    )
}
