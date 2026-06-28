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

        let result = try publicJSONProbe(response).decode(PublicHeistActionResultDTO.self)

        try assertRotorSuccess(result, method: "rotor")
        XCTAssertNil(result.expectation)
        XCTAssertNil(result.omitted)
    }

    func testStandaloneActionResponseEncodesStructuredFailure() throws {
        let response = FenceResponse.action(
            command: .activate,
            result: treeUnavailableActionResult()
        )

        let result = try publicJSONProbe(response).decode(PublicHeistActionResultDTO.self)

        try assertTreeUnavailableFailure(result, method: "activate")
        XCTAssertNil(result.expectation)
        XCTAssertNil(result.omitted)
    }

    func testNestedHeistActionResultEncodesSuccessRotorPayload() throws {
        let result = try nestedHeistActionResultDTO(result: rotorActionResult(), status: .passed)

        try assertRotorSuccess(result, method: "rotor")
        XCTAssertNil(result.expectation)
        XCTAssertNil(result.omitted)
    }

    func testNestedHeistActionResultEncodesStructuredFailureAndOmissions() throws {
        let actionResult = treeUnavailableActionResult(
            accessibilityTrace: makeBackgroundElementsChangedTrace(elementCount: 2)
        )
        let result = try nestedHeistActionResultDTO(
            result: actionResult,
            status: .failed,
            failure: HeistFailureDetail(
                category: .action,
                contract: "action dispatch succeeds",
                observed: ActionResult.accessibilityTreeUnavailableMessage
            )
        )

        try assertTreeUnavailableFailure(result, method: "activate")
        let accessibilityTrace = try XCTUnwrap(result.omitted?.accessibilityTrace)
        XCTAssertEqual(accessibilityTrace.reason, ProjectionOmissionReason.rawAccessibilityTrace.rawValue)
        XCTAssertEqual(accessibilityTrace.projectedAs, "delta")
        XCTAssertEqual(accessibilityTrace.omittedCount, 2)
    }

    func testNestedHeistActionResultEncodesSubjectEvidenceOmissionReason() throws {
        let subject = makeReceiptTestElement(label: "Pay", identifier: "pay")
        let actionResult = ActionResult(
            success: true,
            method: .activate,
            subjectEvidence: ActionSubjectEvidence(
                source: .resolvedSemanticTarget,
                target: .predicate(ElementPredicate(label: "Pay")),
                element: subject
            )
        )

        let result = try nestedHeistActionResultDTO(result: actionResult, status: .passed)

        let subjectEvidence = try XCTUnwrap(result.omitted?.subjectEvidence)
        XCTAssertEqual(subjectEvidence.reason, ProjectionOmissionReason.rawSubjectEvidence.rawValue)
        XCTAssertNil(subjectEvidence.projectedAs)
        XCTAssertNil(subjectEvidence.omittedCount)
    }

    func testNestedHeistActionResultEncodesElementEditOmissions() throws {
        let addedRows = (0..<8).map { index in
            makeReceiptTestElement(label: "Lazy Row \(index)", identifier: "lazy_row_\(index)")
        }
        let actionResult = ActionResult(
            success: true,
            method: .activate,
            accessibilityTrace: makeReceiptTestTrace(
                before: makeReceiptTestInterface([]),
                after: makeReceiptTestInterface(addedRows)
            )
        )

        let result = try nestedHeistActionResultDTO(result: actionResult, status: .passed)

        let delta = try XCTUnwrap(result.delta)
        let edits = try XCTUnwrap(delta.edits)
        let added = try XCTUnwrap(edits.added)
        let omitted = try XCTUnwrap(edits.omitted)
        XCTAssertEqual(delta.kind, "elementsChanged")
        XCTAssertEqual(added.count, 5)
        XCTAssertEqual(omitted.added, 3)
        XCTAssertEqual(
            omitted.addedKeys,
            ["identifier:lazy_row_5", "identifier:lazy_row_6", "identifier:lazy_row_7"]
        )
    }

    func testNestedHeistActionResultEncodesTransientOmissions() throws {
        let interface = makeReceiptTestInterface([
            makeReceiptTestElement(label: "Ready", identifier: "ready"),
        ])
        let before = AccessibilityTrace.Capture(
            sequence: 1,
            interface: interface,
            context: AccessibilityTrace.Context(screenId: "home")
        )
        let transient = (0..<8).map { index in
            makeReceiptTestElement(label: "Toast \(index)", identifier: "toast_\(index)")
        }
        let after = AccessibilityTrace.Capture(
            sequence: 2,
            interface: interface,
            parentHash: before.hash,
            context: AccessibilityTrace.Context(screenId: "home"),
            transition: AccessibilityTrace.Transition(transient: transient)
        )
        let actionResult = ActionResult(
            success: true,
            method: .activate,
            accessibilityTrace: AccessibilityTrace(captures: [before, after])
        )

        let result = try nestedHeistActionResultDTO(result: actionResult, status: .passed)

        let delta = try XCTUnwrap(result.delta)
        let encodedTransient = try XCTUnwrap(delta.transient)
        let omitted = try XCTUnwrap(delta.omitted)
        XCTAssertEqual(delta.kind, "noChange")
        XCTAssertEqual(encodedTransient.count, 5)
        XCTAssertEqual(omitted.transient, 3)
        XCTAssertEqual(
            omitted.transientKeys,
            ["identifier:toast_5", "identifier:toast_6", "identifier:toast_7"]
        )
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

    private func nestedHeistActionResultDTO(
        result: ActionResult,
        status: HeistExecutionStepStatus,
        failure: HeistFailureDetail? = nil
    ) throws -> PublicHeistActionResultDTO {
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
        let report = try publicHeistReportResponseDTO(response).report
        let node = try XCTUnwrap(report.nodes.first)
        let action = try XCTUnwrap(node.evidence?.action)
        return try XCTUnwrap(action.result)
    }

    private func minimalPlan() throws -> HeistPlan {
        try HeistPlan(body: [
            .action(try ActionStep(command: .activate(.target(.predicate(ElementPredicate(label: "Button")))))),
        ])
    }

    private func assertRotorSuccess(
        _ result: PublicHeistActionResultDTO,
        method: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        XCTAssertEqual(result.status, "ok", file: file, line: line)
        XCTAssertEqual(result.method, method, file: file, line: line)
        XCTAssertEqual(result.message, "moved to next heading", file: file, line: line)
        XCTAssertNil(result.value, file: file, line: line)
        XCTAssertNil(result.errorClass, file: file, line: line)

        let rotor = try XCTUnwrap(result.rotor, file: file, line: line)
        XCTAssertEqual(rotor.name, "Headings", file: file, line: line)
        XCTAssertEqual(rotor.direction, "next", file: file, line: line)
        let textRange = try XCTUnwrap(rotor.textRange, file: file, line: line)
        XCTAssertEqual(textRange.rangeDescription, "0..<9", file: file, line: line)
        XCTAssertEqual(textRange.text, "Chapter 1", file: file, line: line)
        XCTAssertEqual(textRange.startOffset, 0, file: file, line: line)
        XCTAssertEqual(textRange.endOffset, 9, file: file, line: line)
    }

    private func assertTreeUnavailableFailure(
        _ result: PublicHeistActionResultDTO,
        method: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        XCTAssertEqual(result.status, "error", file: file, line: line)
        XCTAssertEqual(result.method, method, file: file, line: line)
        XCTAssertEqual(result.message, ActionResult.accessibilityTreeUnavailableMessage, file: file, line: line)
        XCTAssertNil(result.value, file: file, line: line)
        XCTAssertNil(result.rotor, file: file, line: line)
        XCTAssertEqual(result.errorClass, "actionFailed", file: file, line: line)
        XCTAssertEqual(
            result.errorCode,
            "request.accessibility_tree_unavailable",
            file: file,
            line: line
        )
        XCTAssertEqual(result.phase, "request", file: file, line: line)
        XCTAssertEqual(result.retryable, true, file: file, line: line)
        XCTAssertTrue(
            result.hint?.contains("traversable app window") == true,
            file: file,
            line: line
        )
    }
}
