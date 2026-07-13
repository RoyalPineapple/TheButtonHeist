import ButtonHeistTestSupport
import XCTest
@_spi(ButtonHeistInternals) @testable import ButtonHeist
import ThePlans
import TheScore

final class PublicActionResultJSONTests: XCTestCase {
    private static let treeUnavailableMessage = "Could not access accessibility tree: no traversable app windows"

    func testStandaloneActionResponseEncodesSuccessRotorPayload() throws {
        let response = FenceResponse.action(
            command: .rotor,
            result: rotorActionResult()
        )

        let result = try publicJSONProbe(response).object()

        try assertRotorSuccess(result, method: "rotor")
        try result.assertMissing("expectation")
        try result.assertMissing("omitted")
    }

    func testStandaloneActionResponseEncodesValuePayload() throws {
        let response = FenceResponse.action(
            command: .typeText,
            result: ActionResult.success(
                payload: .typeText("Hello"),
                message: "typed",
                evidence: .none
            )
        )

        let result = try publicJSONProbe(response).object()

        XCTAssertEqual(try result.string("value"), "Hello")
        try result.assertMissing("rotor")
        try result.assertMissing("omitted")
    }

    func testStandaloneActionResponseEncodesScreenshotPayloadSummary() throws {
        let response = FenceResponse.action(
            command: .getScreen,
            result: ActionResult.success(
                payload: .screenshot(ScreenPayload(pngData: "abc", width: 393, height: 852)),
                message: "captured",
                evidence: .none
            )
        )

        let result = try publicJSONProbe(response).object()
        let screenshot = try result.object("screenshot")

        XCTAssertEqual(try screenshot.double("width"), 393)
        XCTAssertEqual(try screenshot.double("height"), 852)
        try result.assertMissing("value")
        try result.assertMissing("rotor")
        try result.assertMissing("heistExecution")
    }

    func testStandaloneActionResponseEncodesHeistExecutionPayloadSummary() throws {
        let heistResult = HeistExecutionResult(
            steps: [
                .passed(
                    path: "$.body[0]",
                    receiptKind: .warning,
                    durationMs: 1,
                    evidence: HeistExecutionWarning(path: "$.body[0]", message: "heads up")
                ),
            ],
            durationMs: 1
        )
        let response = FenceResponse.action(
            command: .runHeist,
            result: ActionResult.success(
                payload: .heistExecution(heistResult),
                message: "ran",
                evidence: .none
            )
        )

        let result = try publicJSONProbe(response).object()

        XCTAssertEqual(try result.object("heistExecution").int("stepCount"), 1)
        try result.assertMissing("value")
        try result.assertMissing("rotor")
        try result.assertMissing("screenshot")
    }

    func testStandaloneActionResponseOmitsPayloadFieldsWhenAbsent() throws {
        let response = FenceResponse.action(
            command: .activate,
            result: ActionResult.success(
                method: .activate,
                message: "activated",
                evidence: .none
            )
        )

        let result = try publicJSONProbe(response).object()

        try result.assertMissing("value")
        try result.assertMissing("rotor")
        try result.assertMissing("screenshot")
        try result.assertMissing("heistExecution")
    }

    func testStandaloneActionResponseProjectsOwnedWarning() throws {
        let response = FenceResponse.action(
            command: .activate,
            result: ActionResult.success(
                method: .activate,
                evidence: ActionResultSuccessEvidence(
                    observation: .none,
                    warning: .activationWeakAffordance(evidence: "label=Continue")
                )
            )
        )

        let warning = try publicJSONProbe(response).object().object("warning")

        XCTAssertEqual(try warning.string("code"), "activation_weak_affordance_evidence")
        XCTAssertEqual(try warning.string("evidence"), "label=Continue")
    }

    func testStandaloneAndNestedActionsShareWarningProjection() throws {
        let actionResult = ActionResult.success(
            method: .activate,
            evidence: ActionResultSuccessEvidence(
                observation: .none,
                warning: .activationWeakAffordance(evidence: "label=Continue")
            )
        )

        let standalone = try publicJSONProbe(FenceResponse.action(
            command: .activate,
            result: actionResult
        )).object().object("warning")
        let nested = try nestedHeistActionResultJSON(
            result: actionResult,
            status: .passed
        ).object("warning")

        XCTAssertEqual(
            try standalone.decode(JSONValue.self),
            try nested.decode(JSONValue.self)
        )
    }

    func testStandaloneActionResponseEncodesStructuredFailure() throws {
        let response = FenceResponse.action(
            command: .activate,
            result: treeUnavailableActionResult()
        )

        let result = try publicJSONProbe(response).object()

        try assertTreeUnavailableFailure(result, method: "activate")
        try result.assertMissing("expectation")
        try result.assertMissing("omitted")
    }

    func testNestedHeistActionResultEncodesSuccessRotorPayload() throws {
        let result = try nestedHeistActionResultJSON(result: rotorActionResult(), status: .passed)

        try assertRotorSuccess(result, method: "rotor")
        try result.assertMissing("expectation")
        try result.assertMissing("omitted")
    }

    func testNestedHeistActionResultEncodesStructuredFailureAndOmissions() throws {
        let actionResult = treeUnavailableActionResult(
            traceEvidence: makeTestTraceEvidence(
                makeBackgroundElementsChangedTrace(elementCount: 2),
                completeness: .incomplete
            )
        )
        let result = try nestedHeistActionResultJSON(
            result: actionResult,
            status: .failed,
            failure: HeistFailureDetail(
                category: .action,
                contract: "action dispatch succeeds",
                observed: Self.treeUnavailableMessage
            )
        )

        try assertTreeUnavailableFailure(result, method: "activate")
        try assertAccessibilityTraceProjectedAsDelta(result, omittedCount: 2)
    }

    func testHeistReportNodeFailureEncodesCanonicalFailureDetails() throws {
        let actionResult = ActionResult.failure(
            method: .activate,
            errorKind: .elementNotFound,
            message: "Delete not found", evidence: .none)
        let response = FenceResponse.heistExecution(
            plan: try minimalPlan(),
            result: HeistExecutionResult.failed(
                steps: [
                    .failed(
                        path: "$.body[0]",
                        receiptKind: .action,
                        durationMs: 7,
                        evidence: .commandlessDispatch(dispatchResult: actionResult),
                        failure: HeistFailureDetail(
                            category: .targetResolution,
                            contract: "action dispatch succeeds",
                            observed: "Delete not found"
                        )
                    ),
                ],
                durationMs: 7,
                abortedAtPath: "$.body[0]"
            )
        )

        let report = try publicHeistReportJSON(response)
        let node = try XCTUnwrap(try report.array("nodes").first)
        let failure = try node.object("failure")
        let action = try node.object("evidence").object("action").object("result")

        XCTAssertEqual(try failure.string("code"), "request.element_not_found")
        XCTAssertEqual(try failure.string("kind"), "request")
        XCTAssertEqual(try failure.string("phase"), "request")
        XCTAssertEqual(try failure.bool("retryable"), false)
        XCTAssertEqual(try action.string("code"), try failure.string("code"))
        XCTAssertEqual(try action.string("kind"), try failure.string("kind"))
        XCTAssertEqual(try action.string("phase"), try failure.string("phase"))
        XCTAssertEqual(try action.bool("retryable"), try failure.bool("retryable"))
    }

    func testHeistReportProjectionIsDeterministicAcrossInterleavedProfiles() throws {
        let checkoutRows = (0..<4).map { index in
            makeReceiptTestElement(
                label: "Checkout Row \(index)",
                identifier: "checkout_row_\(index)"
            )
        }
        let trace = makeReceiptTestTrace(
            before: makeReceiptTestInterface([]),
            after: makeReceiptTestInterface(checkoutRows),
            beforeScreenId: "cart",
            afterScreenId: "checkout",
            afterTransition: makeReceiptScreenChangedTransition()
        )
        let actionResult = ActionResult.failure(
            method: .activate,
            errorKind: .elementNotFound,
            message: "Pay not found",
            evidence: ActionResultFailureEvidence(
                observation: .trace(makeTestTraceEvidence(trace, completeness: .incomplete))
            )
        )
        let response = FenceResponse.heistExecution(
            plan: try minimalPlan(),
            result: HeistExecutionResult.failed(
                steps: [
                    .failed(
                        path: "$.body[0]",
                        receiptKind: .action,
                        durationMs: 7,
                        evidence: .commandlessDispatch(dispatchResult: actionResult),
                        failure: HeistFailureDetail(
                            category: .targetResolution,
                            contract: "action dispatch succeeds",
                            observed: "Pay not found"
                        )
                    ),
                ],
                durationMs: 7,
                abortedAtPath: "$.body[0]"
            )
        )
        let narrowProfile = summaryProfile(screenPreviewElements: 1)
        let wideProfile = summaryProfile(screenPreviewElements: 4)

        let firstNarrow = try heistReportJSON(response, profile: narrowProfile)
        let wide = try heistReportJSON(response, profile: wideProfile)
        let secondNarrow = try heistReportJSON(response, profile: narrowProfile)

        XCTAssertEqual(
            try firstNarrow.decode(JSONValue.self),
            try secondNarrow.decode(JSONValue.self)
        )
        XCTAssertEqual(try nestedScreenElements(firstNarrow).count, 1)
        XCTAssertEqual(try nestedScreenElements(wide).count, 4)
        let failure = try XCTUnwrap(try firstNarrow.array("nodes").first).object("failure")
        XCTAssertEqual(try failure.string("code"), "request.element_not_found")
    }

    func testNestedHeistActionResultEncodesSubjectEvidenceOmissionReason() throws {
        let subject = makeReceiptTestElement(label: "Pay", identifier: "pay")
        let actionResult = ActionResult.success(
            method: .activate,
            evidence: ActionResultSuccessEvidence(
                observation: .none,
                subjectEvidence: ActionSubjectEvidence(
                    source: .resolvedSemanticTarget,
                    target: .predicate(ElementPredicateTemplate(label: "Pay")),
                    element: subject
                )
            )
        )

        let result = try nestedHeistActionResultJSON(result: actionResult, status: .passed)

        try assertPublicProjectionOmission(
            result.object("omitted").object("subjectEvidence"),
            reason: ProjectionOmissionReason.rawSubjectEvidence.rawValue,
            projectedAs: nil,
            omittedCount: nil
        )
    }

    func testIncompleteFactFreeActionDoesNotProjectNoChange() throws {
        let interface = makeReceiptTestInterface([
            makeReceiptTestElement(label: "Ready", identifier: "ready"),
        ])
        let result = try standaloneActionResultJSON(
            result: ActionResult.success(
                method: .activate,
                evidence: ActionResultSuccessEvidence(
                    observation: .settledTrace(
                        makeTestTraceEvidence(
                            makeReceiptTestTrace(before: interface, after: interface),
                            completeness: .incomplete
                        ),
                        .timedOut(durationMs: 0)
                    )
                )
            ),
            profile: .mcp
        )

        try result.assertMissing("delta")
    }

    func testNestedHeistActionResultEncodesElementEditOmissions() throws {
        let addedRows = (0..<8).map { index in
            makeReceiptTestElement(label: "Lazy Row \(index)", identifier: "lazy_row_\(index)")
        }
        let actionResult = ActionResult.success(
            method: .activate,
            evidence: ActionResultSuccessEvidence(
                observation: .trace(makeTestTraceEvidence(
                    makeReceiptTestTrace(
                        before: makeReceiptTestInterface([]),
                        after: makeReceiptTestInterface(addedRows)
                    ),
                    completeness: .incomplete
                ))
            )
        )

        let result = try nestedHeistActionResultJSON(result: actionResult, status: .passed)

        let delta = try result.object("delta")
        let edits = try delta.object("edits")
        let added = try edits.array("added")
        let omitted = try edits.object("omitted")
        XCTAssertEqual(try delta.string("kind"), "elementsChanged")
        XCTAssertEqual(added.count, 5)
        XCTAssertEqual(try omitted.int("added"), 3)
        XCTAssertEqual(
            try omitted.strings("addedKeys"),
            ["identifier:lazy_row_5", "identifier:lazy_row_6", "identifier:lazy_row_7"]
        )
    }

    func testStandaloneAndNestedActionDeltasShareElementEditOmissions() throws {
        let addedRows = (0..<8).map { index in
            makeReceiptTestElement(label: "Lazy Row \(index)", identifier: "lazy_row_\(index)")
        }
        let actionResult = ActionResult.success(
            method: .activate,
            evidence: ActionResultSuccessEvidence(
                observation: .trace(makeTestTraceEvidence(
                    makeReceiptTestTrace(
                        before: makeReceiptTestInterface([]),
                        after: makeReceiptTestInterface(addedRows)
                    ),
                    completeness: .incomplete
                ))
            )
        )

        let standalone = try standaloneActionResultJSON(result: actionResult, profile: .mcp)
        let nested = try nestedHeistActionResultJSON(result: actionResult, status: .passed)

        XCTAssertEqual(
            try standalone.object("delta").decode(JSONValue.self),
            try nested.object("delta").decode(JSONValue.self)
        )
        try standalone.assertMissing("omitted")
        try assertAccessibilityTraceProjectedAsDelta(nested, omittedCount: 2)
    }

    func testNestedHeistActionResultEncodesTransientElementChangeOmissions() throws {
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
        let actionResult = ActionResult.success(
            method: .activate,
            evidence: ActionResultSuccessEvidence(
                observation: .trace(makeTestTraceEvidence(
                    AccessibilityTrace(captures: [before, after]),
                    completeness: .incomplete
                ))
            )
        )

        let result = try nestedHeistActionResultJSON(result: actionResult, status: .passed)

        let delta = try result.object("delta")
        let encodedTransient = try delta.array("transient")
        let omitted = try delta.object("omitted")
        XCTAssertEqual(try delta.string("kind"), "elementsChanged")
        XCTAssertEqual(encodedTransient.count, 5)
        XCTAssertEqual(try omitted.int("transient"), 3)
        XCTAssertEqual(
            try omitted.strings("transientKeys"),
            ["identifier:toast_5", "identifier:toast_6", "identifier:toast_7"]
        )
    }

    func testStandaloneAndNestedActionDeltasShareTransientOmissions() throws {
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
        let actionResult = ActionResult.success(
            method: .activate,
            evidence: ActionResultSuccessEvidence(
                observation: .trace(makeTestTraceEvidence(
                    AccessibilityTrace(captures: [before, after]),
                    completeness: .incomplete
                ))
            )
        )

        let standalone = try standaloneActionResultJSON(result: actionResult, profile: .mcp)
        let nested = try nestedHeistActionResultJSON(result: actionResult, status: .passed)

        XCTAssertEqual(
            try standalone.object("delta").decode(JSONValue.self),
            try nested.object("delta").decode(JSONValue.self)
        )
        try standalone.assertMissing("omitted")
        try assertAccessibilityTraceProjectedAsDelta(nested, omittedCount: 2)
    }

    private func rotorActionResult() -> ActionResult {
        ActionResult.success(
            payload: .rotor(RotorResult(
                rotor: "Headings",
                direction: .next,
                textRange: RotorTextRange(
                    text: "Chapter 1",
                    startOffset: 0,
                    endOffset: 9,
                    rangeDescription: "0..<9"
                )
            )),
            message: "moved to next heading",
            evidence: .none
        )
    }

    private func treeUnavailableActionResult(traceEvidence: AccessibilityTraceEvidence? = nil) -> ActionResult {
        let observation = traceEvidence.map(ActionResultObservationEvidence.trace) ?? .none
        return ActionResult.failure(
            method: .activate,
            errorKind: .accessibilityTreeUnavailable,
            message: Self.treeUnavailableMessage,
            evidence: ActionResultFailureEvidence(observation: observation)
        )
    }

    private func nestedHeistActionResultJSON(
        result: ActionResult,
        status: HeistExecutionStepStatus,
        failure: HeistFailureDetail? = nil
    ) throws -> JSONProbe {
        let evidence = HeistActionEvidence.commandlessDispatch(dispatchResult: result)
        let step = status == .failed
            ? HeistExecutionStepResult.failed(
                path: "$.body[0]",
                receiptKind: .action,
                durationMs: 7,
                evidence: evidence,
                failure: failure ?? HeistFailureDetail(
                    category: result.outcome.errorKind == .elementNotFound ? .targetResolution : .action,
                    contract: "action dispatch succeeds",
                    observed: result.message ?? "action failed"
                )
            )
            : HeistExecutionStepResult.passed(
                path: "$.body[0]",
                receiptKind: .action,
                durationMs: 7,
                evidence: evidence
            )
        let execution = status == .failed
            ? HeistExecutionResult.failed(
                steps: [step],
                durationMs: 7,
                abortedAtPath: step.path
            )
            : HeistExecutionResult.passed(steps: [step], durationMs: 7)
        let response = FenceResponse.heistExecution(
            plan: try minimalPlan(),
            result: execution
        )
        let report = try publicHeistReportJSON(response)
        let node = try XCTUnwrap(try report.array("nodes").first)
        return try node.object("evidence").object("action").object("result")
    }

    private func standaloneActionResultJSON(
        result: ActionResult,
        profile: ProjectionProfile
    ) throws -> JSONProbe {
        let response = PublicResponseModel(
            response: FenceResponse.action(command: .activate, result: result),
            profile: profile
        )
        let data = try JSONEncoder().encode(response)
        return try JSONProbe(data: data).object()
    }

    private func heistReportJSON(
        _ response: FenceResponse,
        profile: ProjectionProfile
    ) throws -> JSONProbe {
        let data = try JSONEncoder().encode(PublicResponseModel(response: response, profile: profile))
        return try JSONProbe(data: data).object("report")
    }

    private func nestedScreenElements(_ report: JSONProbe) throws -> [JSONProbe] {
        let node = try XCTUnwrap(try report.array("nodes").first)
        return try node
            .object("evidence")
            .object("action")
            .object("result")
            .object("delta")
            .object("screen")
            .array("elements")
    }

    private func summaryProfile(screenPreviewElements: Int) -> ProjectionProfile {
        ProjectionProfile(
            kind: .summary,
            limits: ProjectionLimits(
                visibleElementBudget: 300,
                totalNodeBudget: 5_000,
                deltaElementsPerBucket: 5,
                screenPreviewElements: screenPreviewElements,
                caseResults: 10,
                failureInterfaceElements: HeistFailureDiagnostics.defaultElementLimit
            )
        )
    }

    private func minimalPlan() throws -> HeistPlan {
        try HeistPlan(body: [
            .action(try ActionStep(command: .activate(.predicate(ElementPredicateTemplate(label: "Button"))))),
        ])
    }

    private func assertRotorSuccess(
        _ result: JSONProbe,
        method: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        XCTAssertEqual(try result.string("status"), "ok", file: file, line: line)
        XCTAssertEqual(try result.string("method"), method, file: file, line: line)
        XCTAssertEqual(try result.string("message"), "moved to next heading", file: file, line: line)
        try result.assertMissing("value")
        try result.assertMissing("errorClass")

        let rotor = try result.object("rotor")
        XCTAssertEqual(try rotor.string("name"), "Headings", file: file, line: line)
        XCTAssertEqual(try rotor.string("direction"), "next", file: file, line: line)
        let textRange = try rotor.object("textRange")
        XCTAssertEqual(try textRange.string("rangeDescription"), "0..<9", file: file, line: line)
        XCTAssertEqual(try textRange.string("text"), "Chapter 1", file: file, line: line)
        XCTAssertEqual(try textRange.int("startOffset"), 0, file: file, line: line)
        XCTAssertEqual(try textRange.int("endOffset"), 9, file: file, line: line)
    }

    private func assertTreeUnavailableFailure(
        _ result: JSONProbe,
        method: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        XCTAssertEqual(try result.string("status"), "error", file: file, line: line)
        XCTAssertEqual(try result.string("method"), method, file: file, line: line)
        XCTAssertEqual(try result.string("message"), Self.treeUnavailableMessage, file: file, line: line)
        try result.assertMissing("value")
        try result.assertMissing("rotor")
        XCTAssertEqual(try result.string("errorClass"), "accessibilityTreeUnavailable", file: file, line: line)
        XCTAssertEqual(try result.string("code"), "request.accessibility_tree_unavailable", file: file, line: line)
        XCTAssertEqual(try result.string("kind"), "request", file: file, line: line)
        XCTAssertEqual(try result.string("phase"), "request", file: file, line: line)
        XCTAssertEqual(try result.bool("retryable"), true, file: file, line: line)
        XCTAssertTrue(
            try result.string("hint").contains("traversable app window"),
            file: file,
            line: line
        )
    }
}
