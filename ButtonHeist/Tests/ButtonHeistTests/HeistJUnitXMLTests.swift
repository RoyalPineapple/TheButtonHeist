import XCTest
import ButtonHeistTestSupport
import ThePlans
@testable import ButtonHeist
@testable import TheScore

final class HeistJUnitXMLTests: XCTestCase {
    @ButtonHeistActor
    func testJunitXMLAllPassed() async {
        let xml = junitXML(
            steps: [
                passingAction(path: "$.body[0]", label: "First"),
                passingAction(path: "$.body[1]", label: "Second"),
            ],
            durationMs: 1_200
        )

        XCTAssertTrue(xml.hasPrefix("<?xml version=\"1.0\" encoding=\"UTF-8\"?>"))
        assertContains(xml, "tests=\"1\"")
        assertContains(xml, "failures=\"0\"")
        assertContains(xml, "time=\"1.200\"")
        assertContains(xml, "<testsuite name=\"test-heist\"")
        assertContains(xml, "classname=\"unknown\"")
        XCTAssertFalse(xml.contains("<failure"))
        XCTAssertEqual(xml.components(separatedBy: "/>").count - 1, 1)
    }

    @ButtonHeistActor
    func testJunitXMLUsesCanonicalFailureDetails() async {
        let failed = failedAction(
            path: "$.body[1]",
            label: "Pay",
            message: "element not found"
        )
        let xml = junitXML(
            steps: [passingAction(path: "$.body[0]", label: "Cart"), failed],
            durationMs: 300
        )

        assertContains(xml, "failures=\"1\"")
        assertContains(xml, "<failure message=\"element not found")
        assertContains(xml, "code: request.element_not_found")
        assertContains(xml, "kind: request")
        assertContains(xml, "phase: request")
        assertContains(xml, "retryable: false")
        assertContains(xml, "\" type=\"elementNotFound\">")
        assertContains(xml, "Completed 1/2 result node(s) before failure.")
        assertContains(xml, "step: [1] activate")
        assertContains(xml, "target: label=&quot;Pay&quot;")
        assertContains(xml, "error: element not found")
    }

    @ButtonHeistActor
    func testJunitXMLUsesNestedLeafFailureInsteadOfAbortedWrapper() async {
        let failed = failedAction(
            path: "$.body[0].conditional.cases[0].body[0]",
            label: "Pay",
            message: "leaf failed"
        )
        let wrapper = HeistResultFixture.conditional(
            path: "$.body[0]",
            selection: .selectingFirstMatch(
                cases: [
                    HeistCaseMatchResult(
                        predicate: .exists(.label("Pay")),
                        met: true
                    ),
                ],
                ifNone: .noMatch,
                elapsedMs: 100
            ),
            children: [failed]
        )
        let xml = junitXML(
            steps: [wrapper],
            durationMs: 100
        )

        assertContains(xml, "step: [1] activate")
        assertContains(xml, "error: leaf failed")
        XCTAssertFalse(xml.contains("step: [0] conditional"))
    }

    @ButtonHeistActor
    func testJunitXMLEmptyReport() async {
        let xml = junitXML(steps: [], durationMs: 0)

        assertContains(xml, "tests=\"1\"")
        assertContains(xml, "failures=\"0\"")
        assertContains(xml, "time=\"0.000\"")
        assertContains(xml, "</testsuite>")
    }

    @ButtonHeistActor
    func testJunitXMLSkippedNodeIsNotFailure() async throws {
        let command = HeistActionCommand.activate(
            .predicate(ElementPredicateTemplate(label: "Skipped"))
        )
        let skipped = HeistExecutionStepResult.action(
            path: try HeistExecutionPath(validating: "$.body[1]"),
            durationMs: 0,
            execution: .skipped(command: command)
        )
        let xml = junitXML(
            steps: [passingAction(path: "$.body[0]", label: "First"), skipped],
            durationMs: 100
        )

        assertContains(xml, "failures=\"0\"")
        XCTAssertFalse(xml.contains("<failure"))
    }

    @ButtonHeistActor
    func testJunitXMLEscapesAttributesAndFailureBody() async {
        let message = #"Element "Save & Continue <now>" isn't available"#
        let failed = failedAction(
            path: "$.body[0]",
            label: "Save & Continue <now>",
            message: message
        )
        let xml = junitXML(
            steps: [failed],
            durationMs: 100
        )

        assertContains(xml, "&amp;")
        assertContains(xml, "&lt;")
        assertContains(xml, "&gt;")
        assertContains(xml, "&quot;")
        assertContains(xml, "&apos;")
    }

    @ButtonHeistActor
    private func junitXML(
        steps: [HeistExecutionStepResult],
        durationMs: ElapsedMilliseconds
    ) -> String {
        let result = HeistResultFixture.result(steps: steps, durationMs: durationMs)
        let (fence, _) = makeConnectedFence()
        return fence.junitXML(
            for: HeistReport.project(result: result),
            heistName: "test-heist"
        )
    }

    private func passingAction(path: String, label: String) -> HeistExecutionStepResult {
        HeistResultFixture.action(
            path: path,
            command: .activate(.predicate(ElementPredicateTemplate(label: .exact(label)))),
            durationMs: 100
        )
    }

    private func failedAction(
        path: String,
        label: String,
        message: String
    ) -> HeistExecutionStepResult {
        HeistResultFixture.action(
            path: path,
            command: .activate(.predicate(ElementPredicateTemplate(label: .exact(label)))),
            result: HeistResultFixture.actionResult(
                succeeded: false,
                message: message,
                failureKind: .elementNotFound
            ),
            durationMs: 100
        )
    }

    private func assertContains(
        _ string: String,
        _ substring: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertTrue(
            string.contains(substring),
            "Expected string to contain \"\(substring)\" but it did not.\nFull string:\n\(string)",
            file: file,
            line: line
        )
    }
}
