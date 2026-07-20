import ButtonHeistTestSupport
import Foundation
import ThePlans
import TheScore
@_spi(ButtonHeistInternals) @testable import ButtonHeist
import XCTest

enum PublicHeistExecutionJSONContractFixture {
    static let donePredicate = AccessibilityPredicate.exists(.label("Done"))

    static func actionWithExpectation() -> HeistExecutionStepResult {
        HeistResultFixture.action(
            command: .dismiss,
            result: .success(payload: .dismiss, message: "dismissed"),
            expectationActionResult: .success(payload: .wait, message: "matched"),
            expectation: ExpectationResult(
                met: true,
                predicate: donePredicate,
                actual: "Done visible"
            ),
            durationMs: 3
        )
    }

    static func wait() throws -> HeistExecutionStepResult {
        let evidence = try waitEvidence()
        return .wait(
            path: "$.body[0]",
            durationMs: 5,
            predicate: donePredicate,
            timeout: 1,
            completion: .passed(evidence: try XCTUnwrap(HeistPassedWaitEvidence(evidence)))
        )
    }

    static func caseSelection() -> HeistExecutionStepResult {
        let cases = [
            HeistCaseMatchResult(predicate: .exists(.label("Ready")), met: true, actual: "Ready visible"),
            HeistCaseMatchResult(predicate: .exists(.label("Fallback")), met: false),
        ]
        return .conditional(
            path: "$.body[0]",
            durationMs: 4,
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
        return .forEachString(
            path: "$.body[0]",
            durationMs: 2,
            declaration: declaration,
            completion: .passed(evidence: try XCTUnwrap(HeistPassedForEachStringEvidence(evidence)))
        )
    }

    static func forEachElement() throws -> HeistExecutionStepResult {
        let declaration = try XCTUnwrap(HeistForEachElementDeclaration(
            parameter: "row",
            matching: ElementPredicateTemplate(label: "Row"),
            limit: 3
        ))
        let evidence = try XCTUnwrap(HeistForEachElementEvidence(
            matchedCount: 2,
            iterationCount: 1,
            iterationOrdinal: 0,
            targetOrdinal: 1,
            targetSummary: "Row 2"
        ))
        return .forEachElement(
            path: "$.body[0]",
            durationMs: 2,
            declaration: declaration,
            completion: .passed(evidence: try XCTUnwrap(HeistPassedForEachElementEvidence(evidence)))
        )
    }

    static func repeatUntil() throws -> HeistExecutionStepResult {
        let evidence = try XCTUnwrap(HeistRepeatUntilEvidence.matched(
            iterationCount: 2,
            expectation: ExpectationResult.Met(
                predicate: donePredicate,
                actual: "Done visible"
            ),
            actionResult: .success(payload: .wait, message: "repeat matched"),
            lastObservedSummary: "Done visible"
        ))
        return .repeatUntil(
            path: "$.body[0]",
            durationMs: 6,
            declaration: HeistRepeatUntilDeclaration(predicate: donePredicate, timeout: 0.5),
            completion: .passed(evidence: try XCTUnwrap(HeistPassedRepeatUntilEvidence(evidence)))
        )
    }

    static func invocation() throws -> HeistExecutionStepResult {
        let evidence = HeistInvocationEvidence.completed(expectation: .wait(try waitEvidence()))
        return .invocation(
            path: "$.body[0]",
            durationMs: 7,
            invocationPath: "Cart.checkout",
            argument: .string("Milk"),
            completion: .passed(evidence: try XCTUnwrap(HeistPassedInvocationEvidence(evidence)))
        )
    }

    static func actionWithOmissions() throws -> HeistExecutionStepResult {
        let trace = makeTestTrace(
            before: makeTestInterface(elements: []),
            after: makeTestInterface(elements: [
                makeTestHeistElement(label: "Pay", identifier: "pay"),
            ])
        )
        let subject = makeTestHeistElement(label: "Pay", identifier: "pay")
        let subjectEvidence = ActionSubjectEvidence(
            source: .resolvedSemanticTarget,
            target: try AccessibilityTarget
                .predicate(ElementPredicateTemplate(label: "Pay"))
                .resolve(in: .empty),
            element: subject,
            resolution: ActionSubjectResolution(origin: .visible)
        )
        return HeistResultFixture.action(result: .success(
            payload: .activate,
            observation: .trace(makeTestTraceEvidence(trace, completeness: .incomplete)),
            subjectEvidence: subjectEvidence
        ))
    }

    static func netDelta() -> PublicHeistNetDeltaFixture {
        let trace = makeTestTrace(
            before: makeTestInterface(elements: []),
            after: makeTestInterface(elements: [
                makeTestHeistElement(label: "Pay", identifier: "pay"),
            ])
        )
        let result = ActionResult.success(
            payload: .activate,
            observation: .trace(makeTestTraceEvidence(trace, completeness: .complete))
        )
        return PublicHeistNetDeltaFixture(
            step: HeistResultFixture.action(result: result),
            trace: trace
        )
    }

    static var oneVisibleCaseProfile: ProjectionProfile {
        ProjectionProfile(
            kind: .summary,
            limits: .current(caseResults: 1)
        )
    }

    private static func waitEvidence() throws -> HeistWaitEvidence {
        let expectation = ExpectationResult.Met(
            predicate: donePredicate,
            actual: "Done visible"
        )
        let check = try XCTUnwrap(HeistWaitEvidence.MatchedCheck(
            actionResult: .success(payload: .wait, message: "waited"),
            expectation: expectation
        ))
        return .matched(
            check,
            baselineSummary: "Loading",
            finalSummary: "Done visible"
        )
    }
}

struct PublicHeistNetDeltaFixture {
    let step: HeistExecutionStepResult
    let trace: AccessibilityTrace
}

func publicHeistExecutionJSON(
    step: HeistExecutionStepResult,
    profile: ProjectionProfile = .summary
) throws -> JSONProbe {
    let result = try HeistResult(steps: [step], durationMs: step.durationMs)
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
    equals fixture: String,
    file: StaticString = #filePath,
    line: UInt = #line
) throws {
    let expected = try JSONProbe(data: Data(fixture.utf8))
    XCTAssertEqual(
        try actual.decode(JSONValue.self),
        try expected.decode(JSONValue.self),
        file: file,
        line: line
    )
}
