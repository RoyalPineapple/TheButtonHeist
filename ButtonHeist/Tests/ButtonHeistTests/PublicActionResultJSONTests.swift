import XCTest
@testable import ButtonHeist
import ThePlans
import TheScore

final class PublicActionResultJSONTests: XCTestCase {

    func testStandaloneActionResponseEncodesSuccessRotorPayload() throws {
        let response = FenceResponse.action(
            command: .rotor,
            result: rotorActionResult()
        )

        let json = publicJSONObject(response)

        try assertRotorSuccess(json, method: "rotor")
        XCTAssertNil(json["expectation"])
        XCTAssertNil(json["omitted"])
    }

    func testStandaloneActionResponseEncodesStructuredFailure() throws {
        let response = FenceResponse.action(
            command: .activate,
            result: treeUnavailableActionResult()
        )

        let json = publicJSONObject(response)

        try assertTreeUnavailableFailure(json, method: "activate")
        XCTAssertNil(json["expectation"])
        XCTAssertNil(json["omitted"])
    }

    func testNestedHeistActionResultEncodesSuccessRotorPayload() throws {
        let json = try nestedHeistActionResultJSON(result: rotorActionResult(), status: .passed)

        try assertRotorSuccess(json, method: "rotor")
        XCTAssertNil(json["expectation"])
        XCTAssertNil(json["omitted"])
    }

    func testNestedHeistActionResultEncodesStructuredFailureAndOmissions() throws {
        let result = treeUnavailableActionResult(
            accessibilityTrace: makeBackgroundElementsChangedTrace(elementCount: 2)
        )
        let json = try nestedHeistActionResultJSON(
            result: result,
            status: .failed,
            failure: HeistFailureDetail(
                category: .action,
                contract: "action dispatch succeeds",
                observed: ActionResult.accessibilityTreeUnavailableMessage
            )
        )

        try assertTreeUnavailableFailure(json, method: "activate")
        let omitted = try XCTUnwrap(json["omitted"] as? [String: Any])
        let accessibilityTrace = try XCTUnwrap(omitted["accessibilityTrace"] as? [String: Any])
        XCTAssertEqual(accessibilityTrace["projectedAs"] as? String, "delta")
    }

    private func rotorActionResult() -> ActionResult {
        ActionResult(
            success: true,
            method: .rotor,
            message: "moved to next heading",
            payload: .rotor(RotorResult(
                rotor: "Headings",
                direction: .next,
                textRange: RotorTextRange(
                    text: "Chapter 1",
                    startOffset: 0,
                    endOffset: 9,
                    rangeDescription: "0..<9"
                )
            ))
        )
    }

    private func treeUnavailableActionResult(accessibilityTrace: AccessibilityTrace? = nil) -> ActionResult {
        ActionResult(
            success: false,
            method: .activate,
            message: ActionResult.accessibilityTreeUnavailableMessage,
            errorKind: .actionFailed,
            accessibilityTrace: accessibilityTrace
        )
    }

    private func nestedHeistActionResultJSON(
        result: ActionResult,
        status: HeistExecutionStepStatus,
        failure: HeistFailureDetail? = nil
    ) throws -> [String: Any] {
        let step = HeistExecutionStepResult(
            path: "$.body[0]",
            kind: .action,
            status: status,
            durationMs: 7,
            evidence: .action(HeistActionEvidence(command: nil, actionResult: result)),
            failure: failure
        )
        let response = FenceResponse.heistExecution(
            plan: try minimalPlan(),
            result: HeistExecutionResult(steps: [step], durationMs: 7)
        )
        let root = publicJSONObject(response)
        let report = try XCTUnwrap(root["report"] as? [String: Any])
        let nodes = try XCTUnwrap(report["nodes"] as? [[String: Any]])
        let node = try XCTUnwrap(nodes.first)
        let evidence = try XCTUnwrap(node["evidence"] as? [String: Any])
        let action = try XCTUnwrap(evidence["action"] as? [String: Any])
        return try XCTUnwrap(action["result"] as? [String: Any])
    }

    private func minimalPlan() throws -> HeistPlan {
        try HeistPlan(body: [
            .action(try ActionStep(command: .activate(.target(.predicate(ElementPredicate(label: "Button")))))),
        ])
    }

    private func assertRotorSuccess(
        _ json: [String: Any],
        method: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        XCTAssertEqual(json["status"] as? String, "ok", file: file, line: line)
        XCTAssertEqual(json["method"] as? String, method, file: file, line: line)
        XCTAssertEqual(json["message"] as? String, "moved to next heading", file: file, line: line)
        XCTAssertNil(json["value"], file: file, line: line)
        XCTAssertNil(json["errorClass"], file: file, line: line)

        let rotor = try XCTUnwrap(json["rotor"] as? [String: Any], file: file, line: line)
        XCTAssertEqual(rotor["name"] as? String, "Headings", file: file, line: line)
        XCTAssertEqual(rotor["direction"] as? String, "next", file: file, line: line)
        let textRange = try XCTUnwrap(rotor["textRange"] as? [String: Any], file: file, line: line)
        XCTAssertEqual(textRange["rangeDescription"] as? String, "0..<9", file: file, line: line)
        XCTAssertEqual(textRange["text"] as? String, "Chapter 1", file: file, line: line)
        XCTAssertEqual(textRange["startOffset"] as? Int, 0, file: file, line: line)
        XCTAssertEqual(textRange["endOffset"] as? Int, 9, file: file, line: line)
    }

    private func assertTreeUnavailableFailure(
        _ json: [String: Any],
        method: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        XCTAssertEqual(json["status"] as? String, "error", file: file, line: line)
        XCTAssertEqual(json["method"] as? String, method, file: file, line: line)
        XCTAssertEqual(json["message"] as? String, ActionResult.accessibilityTreeUnavailableMessage, file: file, line: line)
        XCTAssertNil(json["value"], file: file, line: line)
        XCTAssertNil(json["rotor"], file: file, line: line)
        XCTAssertEqual(json["errorClass"] as? String, "actionFailed", file: file, line: line)
        XCTAssertEqual(
            json["errorCode"] as? String,
            "request.accessibility_tree_unavailable",
            file: file,
            line: line
        )
        XCTAssertEqual(json["phase"] as? String, "request", file: file, line: line)
        XCTAssertEqual(json["retryable"] as? Bool, true, file: file, line: line)
        XCTAssertTrue(
            (json["hint"] as? String)?.contains("traversable app window") == true,
            file: file,
            line: line
        )
    }
}
