import XCTest
@testable import TheScore

final class HeistPlaybackReportTests: XCTestCase {

    // MARK: - Report Construction

    func testAllPassedReport() {
        let report = makeReport(outcomes: [.passed, .passed, .passed])
        XCTAssertEqual(report.passedCount, 3)
        XCTAssertEqual(report.failedCount, 0)
        XCTAssertTrue(report.allPassed)
    }

    func testPartialFailureReport() {
        let report = makeReport(outcomes: [
            .passed,
            .failed(message: "element not found", errorKind: .elementNotFound),
        ])
        XCTAssertEqual(report.passedCount, 1)
        XCTAssertEqual(report.failedCount, 1)
        XCTAssertFalse(report.allPassed)
    }

    func testEmptyReport() {
        let report = HeistPlaybackReport(
            heistName: "empty",
            app: "com.test.app",
            totalTimeSeconds: 0,
            steps: []
        )
        XCTAssertEqual(report.passedCount, 0)
        XCTAssertEqual(report.failedCount, 0)
        XCTAssertTrue(report.allPassed)
    }

    // MARK: - Step Display Name

    func testDisplayNameWithLabel() {
        let step = HeistPlaybackReport.StepResult(
            index: 2,
            command: "activate",
            target: ElementMatcher(label: "Submit"),
            timeSeconds: 0.5,
            outcome: .passed
        )
        XCTAssertEqual(step.displayName, "[2] activate label=\"Submit\"")
    }

    func testDisplayNameWithIdentifier() {
        let step = HeistPlaybackReport.StepResult(
            index: 0,
            command: "swipe",
            target: ElementMatcher(identifier: "scroll-view"),
            timeSeconds: 0.3,
            outcome: .passed
        )
        XCTAssertEqual(step.displayName, "[0] swipe identifier=\"scroll-view\"")
    }

    func testDisplayNameWithoutTarget() {
        let step = HeistPlaybackReport.StepResult(
            index: 5,
            command: "type_text",
            target: nil,
            timeSeconds: 0.1,
            outcome: .passed
        )
        XCTAssertEqual(step.displayName, "[5] type_text")
    }

    func testDisplayNamePrefersLabelOverIdentifier() {
        let step = HeistPlaybackReport.StepResult(
            index: 1,
            command: "activate",
            target: ElementMatcher(label: "OK", identifier: "ok-button"),
            timeSeconds: 0.2,
            outcome: .passed
        )
        XCTAssertEqual(step.displayName, "[1] activate label=\"OK\"")
    }

    // MARK: - Outcome Properties

    func testOutcomePassedProperties() {
        let outcome = HeistPlaybackReport.Outcome.passed
        XCTAssertNil(outcome.failureMessage)
        XCTAssertNil(outcome.failureType)
    }

    func testOutcomeFailedProperties() {
        let outcome = HeistPlaybackReport.Outcome.failed(
            message: "timeout waiting for element",
            errorKind: .timeout
        )
        XCTAssertEqual(outcome.failureMessage, "timeout waiting for element")
        XCTAssertEqual(outcome.failureType, .timeout)
    }

    func testOutcomeFailedWithNilErrorKind() {
        let outcome = HeistPlaybackReport.Outcome.failed(
            message: "connection lost",
            errorKind: nil
        )
        XCTAssertEqual(outcome.failureMessage, "connection lost")
        XCTAssertNil(outcome.failureType)
    }

    // MARK: - JUnit XML: Structure

    func testJunitXMLAllPassed() {
        let report = makeReport(outcomes: [.passed, .passed])
        let xml = report.junitXML()

        XCTAssertTrue(xml.hasPrefix("<?xml version=\"1.0\" encoding=\"UTF-8\"?>"))
        assertContains(xml, "tests=\"2\"")
        assertContains(xml, "failures=\"0\"")
        assertContains(xml, "<testsuite name=\"test-heist\"")
        // No <failure> elements
        XCTAssertFalse(xml.contains("<failure"))
        // All testcases self-close
        XCTAssertEqual(xml.components(separatedBy: "/>").count - 1, 2)
    }

    func testJunitXMLWithFailure() {
        let report = makeReport(outcomes: [
            .passed,
            .failed(message: "element not found", errorKind: .elementNotFound),
        ])
        let xml = report.junitXML()

        assertContains(xml, "tests=\"2\"")
        assertContains(xml, "failures=\"1\"")
        assertContains(xml, "<failure message=\"element not found\"")
        assertContains(xml, "type=\"elementNotFound\"")
        assertContains(xml, "command: activate")
    }

    func testJunitXMLFailureWithNilErrorKind() {
        let report = makeReport(outcomes: [
            .failed(message: "unknown error", errorKind: nil),
        ])
        let xml = report.junitXML()

        assertContains(xml, "type=\"playbackFailure\"")
    }

    func testJunitXMLEmptySteps() {
        let report = HeistPlaybackReport(
            heistName: "empty",
            app: "com.test.app",
            totalTimeSeconds: 0,
            steps: []
        )
        let xml = report.junitXML()

        assertContains(xml, "tests=\"0\"")
        assertContains(xml, "failures=\"0\"")
        assertContains(xml, "</testsuite>")
    }

    // MARK: - JUnit XML: Escaping

    func testJunitXMLEscapesSpecialCharacters() {
        let step = HeistPlaybackReport.StepResult(
            index: 0,
            command: "activate",
            target: ElementMatcher(label: "Save & Continue <now>"),
            timeSeconds: 0.1,
            outcome: .failed(
                message: "Element \"Save & Continue <now>\" not found",
                errorKind: nil
            )
        )
        let report = HeistPlaybackReport(
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
        // Raw special chars should not appear in attribute values
        XCTAssertFalse(xml.contains("name=\"[0] activate label=\"Save"))
    }

    // MARK: - JUnit XML: Timing

    func testJunitXMLIncludesStepTiming() {
        let step = HeistPlaybackReport.StepResult(
            index: 0,
            command: "activate",
            target: nil,
            timeSeconds: 1.234,
            outcome: .passed
        )
        let report = HeistPlaybackReport(
            heistName: "timing",
            app: "com.test.app",
            totalTimeSeconds: 1.234,
            steps: [step]
        )
        let xml = report.junitXML()

        assertContains(xml, "time=\"1.234\"")
    }

    // MARK: - JUnit XML: Failure Body

    func testJunitXMLFailureBodyIncludesTarget() {
        let step = HeistPlaybackReport.StepResult(
            index: 0,
            command: "swipe",
            target: ElementMatcher(label: "List", identifier: "main-list"),
            timeSeconds: 0.5,
            outcome: .failed(message: "swipe failed", errorKind: .actionFailed)
        )
        let report = HeistPlaybackReport(
            heistName: "target-test",
            app: "com.test.app",
            totalTimeSeconds: 0.5,
            steps: [step]
        )
        let xml = report.junitXML()

        assertContains(xml, "command: swipe")
        assertContains(xml, "label=&quot;List&quot;")
        assertContains(xml, "identifier=&quot;main-list&quot;")
        assertContains(xml, "error: swipe failed")
    }

    // MARK: - Equatable

    func testEquatable() {
        let report1 = makeReport(outcomes: [.passed])
        let report2 = makeReport(outcomes: [.passed])
        XCTAssertEqual(report1, report2)

        let report3 = makeReport(outcomes: [.failed(message: "error", errorKind: nil)])
        XCTAssertNotEqual(report1, report3)
    }

    // MARK: - Helpers

    private func makeReport(outcomes: [HeistPlaybackReport.Outcome]) -> HeistPlaybackReport {
        let steps = outcomes.enumerated().map { index, outcome in
            HeistPlaybackReport.StepResult(
                index: index,
                command: "activate",
                target: ElementMatcher(label: "Button \(index)"),
                timeSeconds: Double(index) * 0.5 + 0.1,
                outcome: outcome
            )
        }
        return HeistPlaybackReport(
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
}
