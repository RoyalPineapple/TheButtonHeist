import XCTest
import ThePlans
@testable import TheScore

final class HeistJUnitReportTests: XCTestCase {

    // MARK: - Report Construction

    func testAllPassedReport() {
        let report = makeReport(outcomes: [.passed, .passed, .passed])
        XCTAssertEqual(report.passedResultNodeCount, 3)
        XCTAssertEqual(report.failedResultNodeCount, 0)
        XCTAssertTrue(report.allPassed)
    }

    func testPartialFailureReport() {
        let report = makeReport(outcomes: [
            .passed,
            .failed(message: "element not found", failureKind: .action(.elementNotFound)),
            .skipped,
        ])
        XCTAssertEqual(report.passedResultNodeCount, 1)
        XCTAssertEqual(report.failedResultNodeCount, 1)
        XCTAssertFalse(report.allPassed)
    }

    func testSkippedNodesAreNotFailures() {
        let report = makeReport(outcomes: [.passed, .skipped])

        XCTAssertEqual(report.passedResultNodeCount, 1)
        XCTAssertEqual(report.failedResultNodeCount, 0)
        XCTAssertTrue(report.allPassed)
    }

    func testEmptyReport() {
        let report = HeistJUnitReport(
            heistName: "empty",
            app: "com.test.app",
            totalTimeSeconds: 0,
            steps: []
        )
        XCTAssertEqual(report.passedResultNodeCount, 0)
        XCTAssertEqual(report.failedResultNodeCount, 0)
        XCTAssertTrue(report.allPassed)
    }

    // MARK: - Step Display Name

    func testDisplayNameWithLabel() {
        let step = HeistJUnitReport.StepResult(
            index: 2,
            command: "activate",
            target: semanticTarget(label: "Submit"),
            timeSeconds: 0.5,
            outcome: .passed
        )
        XCTAssertEqual(step.displayName, "[2] activate label=\"Submit\"")
    }

    func testDisplayNameWithIdentifier() {
        let step = HeistJUnitReport.StepResult(
            index: 0,
            command: "swipe",
            target: semanticTarget(identifier: "scroll-view"),
            timeSeconds: 0.3,
            outcome: .passed
        )
        XCTAssertEqual(step.displayName, "[0] swipe identifier=\"scroll-view\"")
    }

    func testDisplayNameWithoutTarget() {
        let step = HeistJUnitReport.StepResult(
            index: 5,
            command: "type_text",
            target: nil,
            timeSeconds: 0.1,
            outcome: .passed
        )
        XCTAssertEqual(step.displayName, "[5] type_text")
    }

    func testDisplayNamePrefersLabelOverIdentifier() {
        let step = HeistJUnitReport.StepResult(
            index: 1,
            command: "activate",
            target: semanticTarget(label: "OK", identifier: "ok-button"),
            timeSeconds: 0.2,
            outcome: .passed
        )
        XCTAssertEqual(step.displayName, "[1] activate label=\"OK\"")
    }

    // MARK: - Outcome Properties

    func testOutcomePassedProperties() {
        let outcome = HeistJUnitReport.Outcome.passed
        XCTAssertNil(outcome.failureMessage)
        XCTAssertNil(outcome.failureType)
    }

    func testOutcomeFailedProperties() {
        let outcome = HeistJUnitReport.Outcome.failed(
            message: "timeout waiting for element",
            failureKind: .action(.timeout)
        )
        XCTAssertEqual(outcome.failureMessage, "timeout waiting for element")
        XCTAssertEqual(outcome.failureType, .action(.timeout))
    }

    func testOutcomeFailedWithNilErrorKind() {
        let outcome = HeistJUnitReport.Outcome.failed(
            message: "connection lost",
            failureKind: nil
        )
        XCTAssertEqual(outcome.failureMessage, "connection lost")
        XCTAssertNil(outcome.failureType)
    }

    // MARK: - JUnit XML: Structure

    func testJunitXMLAllPassed() {
        let report = makeReport(outcomes: [.passed, .passed])
        let xml = report.junitXML()

        XCTAssertTrue(xml.hasPrefix("<?xml version=\"1.0\" encoding=\"UTF-8\"?>"))
        assertContains(xml, "tests=\"1\"")
        assertContains(xml, "failures=\"0\"")
        assertContains(xml, "<testsuite name=\"test-heist\"")
        assertContains(xml, "classname=\"com.test.app\"")
        // No <failure> elements
        XCTAssertFalse(xml.contains("<failure"))
        // Single testcase, self-closing
        XCTAssertEqual(xml.components(separatedBy: "/>").count - 1, 1)
    }

    func testJunitXMLWithFailure() {
        let report = makeReport(
            outcomes: [
                .passed,
                .failed(message: "element not found", failureKind: .action(.elementNotFound)),
            ]
        )
        let xml = report.junitXML()

        assertContains(xml, "tests=\"1\"")
        assertContains(xml, "failures=\"1\"")
        assertContains(xml, "<failure message=\"element not found\"")
        assertContains(xml, "type=\"elementNotFound\"")
        assertContains(xml, "Completed 1/2 result node(s) before failure.")
        assertContains(xml, "step: [1] activate")
    }

    func testJunitXMLFailureWithNilErrorKind() {
        let report = makeReport(outcomes: [
            .failed(message: "unknown error", failureKind: nil),
        ])
        let xml = report.junitXML()

        assertContains(xml, "type=\"heistFailure\"")
    }

    func testJunitXMLUsesCanonicalFailureInsteadOfFirstFailedWrapper() {
        let wrapper = HeistJUnitReport.StepResult(
            index: 0,
            command: "invocation",
            target: nil,
            timeSeconds: 0.1,
            outcome: .failed(message: "wrapper failed", failureKind: .commandError)
        )
        let leaf = HeistJUnitReport.StepResult(
            index: 1,
            command: "activate",
            target: semanticTarget(label: "Pay"),
            timeSeconds: 0.2,
            outcome: .failed(message: "leaf failed", failureKind: .action(.actionFailed))
        )
        let report = HeistJUnitReport(
            heistName: "nested-failure",
            app: "com.test.app",
            totalTimeSeconds: 0.3,
            steps: [leaf, wrapper]
        )

        let xml = report.junitXML()

        assertContains(xml, "leaf failed")
        assertContains(xml, "step: [1] activate")
        XCTAssertFalse(xml.contains("wrapper failed"))
    }

    func testJunitXMLEmptySteps() {
        let report = HeistJUnitReport(
            heistName: "empty",
            app: "com.test.app",
            totalTimeSeconds: 0,
            steps: []
        )
        let xml = report.junitXML()

        assertContains(xml, "tests=\"1\"")
        assertContains(xml, "failures=\"0\"")
        assertContains(xml, "</testsuite>")
    }

    // MARK: - JUnit XML: Escaping

    func testJunitXMLEscapesSpecialCharacters() {
        let step = HeistJUnitReport.StepResult(
            index: 0,
            command: "activate",
            target: semanticTarget(label: "Save & Continue <now>"),
            timeSeconds: 0.1,
            outcome: .failed(
                message: "Element \"Save & Continue <now>\" not found",
                failureKind: nil
            )
        )
        let report = HeistJUnitReport(
            heistName: "escape-test",
            app: "com.test.app",
            totalTimeSeconds: 0.1,
            steps: [step]
        )
        let xml = report.junitXML()

        assertContains(xml, "&amp;")
        assertContains(xml, "&lt;")
        assertContains(xml, "&gt;")
        assertContains(xml, "&quot;")
    }

    // MARK: - JUnit XML: Timing

    func testJunitXMLIncludesTotalTiming() {
        let report = HeistJUnitReport(
            heistName: "timing",
            app: "com.test.app",
            totalTimeSeconds: 1.234,
            steps: [
                HeistJUnitReport.StepResult(
                    index: 0, command: "activate", target: nil,
                    timeSeconds: 1.234, outcome: .passed
                ),
            ]
        )
        let xml = report.junitXML()

        assertContains(xml, "time=\"1.234\"")
    }

    // MARK: - JUnit XML: Failure Body

    func testJunitXMLFailureBodyIncludesTarget() {
        let step = HeistJUnitReport.StepResult(
            index: 0,
            command: "swipe",
            target: semanticTarget(label: "List", identifier: "main-list"),
            timeSeconds: 0.5,
            outcome: .failed(message: "swipe failed", failureKind: .action(.actionFailed))
        )
        let report = HeistJUnitReport(
            heistName: "target-test",
            app: "com.test.app",
            totalTimeSeconds: 0.5,
            steps: [step]
        )
        let xml = report.junitXML()

        assertContains(xml, "Completed 0/1 result node(s) before failure.")
        assertContains(xml, "step: [0] swipe")
        assertContains(xml, "label=&quot;List&quot;")
        assertContains(xml, "identifier=&quot;main-list&quot;")
        assertContains(xml, "error: swipe failed")
    }

    func testJunitXMLHeistNameAsTestcaseName() {
        let report = makeReport(outcomes: [.passed])
        let xml = report.junitXML()

        assertContains(xml, "<testcase name=\"test-heist\"")
    }

    // MARK: - Helpers

    private func makeReport(outcomes: [HeistJUnitReport.Outcome]) -> HeistJUnitReport {
        let steps = outcomes.enumerated().map { index, outcome in
            HeistJUnitReport.StepResult(
                index: index,
                command: "activate",
                target: semanticTarget(label: "Button \(index)"),
                timeSeconds: Double(index) * 0.5 + 0.1,
                outcome: outcome
            )
        }
        return HeistJUnitReport(
            heistName: "test-heist",
            app: "com.test.app",
            totalTimeSeconds: steps.reduce(0) { $0 + $1.timeSeconds },
            steps: steps
        )
    }

    private func assertContains(
        _ string: String, _ substring: String,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertTrue(
            string.contains(substring),
            "Expected string to contain \"\(substring)\" but it did not.\nFull string:\n\(string)",
            file: file,
            line: line
        )
    }

    private func semanticTarget(label: String? = nil, identifier: String? = nil) -> AccessibilityTarget {
        .predicate(
            ElementPredicateTemplate(
                label: label.map(StringMatch.exact),
                identifier: identifier.map(StringMatch.exact)
            )
        )
    }
}
