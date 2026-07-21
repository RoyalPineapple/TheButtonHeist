#if canImport(UIKit)
import XCTest

import ButtonHeistHostedTestSupport
import ButtonHeistTesting
import TheScore

@MainActor
final class DogfoodFeatureFlowTests: XCTestCase {

    func testPublicHeistCanMutateAndVerifyDemoAppState() async throws {
        try await runHeist("DogfoodSemanticFeatureCanary") {
            try DogfoodHome.openScreen("Todo List")
            try TodoScreen.completeItem("Buy groceries, High priority")
            try DemoNavigation.backToRoot()
        }
    }

    func testActionExpectationUsesTransientLifecycleEvidenceOnlyFromItsOwnAction() async throws {
        let heist = try await runHeist("DogfoodTransientLifecycleEvidence") {
            try DemoNavigation.backToRoot()
            try DogfoodHome.openScreen("Transient Flow")
            Activate(.label("Submit"))
                .expect(TransientFlowScreen.lifecycle, timeout: 8)
        }
        let evidence = try actionEvidence(
            matching: TransientFlowScreen.lifecycle,
            in: heist.result
        )
        let trace = try XCTUnwrap(evidence.expectationResult?.accessibilityTrace)

        XCTAssertEqual(evidence.checkedExpectation?.met, true)
        XCTAssertTrue(trace.appearedLabels.contains("Processing"))
        XCTAssertTrue(trace.disappearedLabels.contains("Submit"))

        let failure = try await expectHeistFailure("DogfoodStandaloneCannotReuseLifecycleEvidence") {
            WaitFor(TransientFlowScreen.lifecycle, timeout: 0.25)
        }
        XCTAssertEqual(HeistReport.project(result: failure.result).failure?.actionKind, .timeout)
    }

    func testActionExpectationUsesAnnouncementWhileStandaloneWaitCannotReuseIt() async throws {
        let heist = try await runHeist("DogfoodActionAnnouncementEvidence") {
            try DemoNavigation.backToRoot()
            try DogfoodHome.openScreen("Transient Flow")
            Activate(.label("Submit"))
                .expect(TransientFlowScreen.announcement, timeout: 8)
        }
        let evidence = try actionEvidence(
            matching: TransientFlowScreen.announcement,
            in: heist.result
        )

        XCTAssertEqual(evidence.checkedExpectation?.met, true)
        XCTAssertEqual(evidence.expectationResult?.announcement, "Ticket saved.")

        let exactFailure = try await expectHeistFailure("DogfoodCombinedToastExactTextFails") {
            WaitFor(TransientFlowScreen.exactToastText, timeout: 0.5)
        }
        let exactReport = HeistReport.project(result: exactFailure.result)
        let failureMessage = try XCTUnwrap(exactReport.failure?.message)

        XCTAssertEqual(exactReport.failure?.actionKind, .timeout)
        XCTAssertTrue(
            failureMessage.contains(#"observed accessibility candidate label="Ticket saved., Dismiss""#),
            failureMessage
        )
        XCTAssertFalse(
            failureMessage.contains(#"observed accessibility candidate label="Ticket saved." traits="#),
            failureMessage
        )

        let standaloneFailure = try await expectHeistFailure(
            "DogfoodStandaloneCannotReuseAnnouncementEvidence"
        ) {
            WaitFor(TransientFlowScreen.announcement, timeout: 0.25)
        }
        XCTAssertEqual(HeistReport.project(result: standaloneFailure.result).failure?.actionKind, .timeout)
    }

    private func actionEvidence(
        matching predicate: AccessibilityPredicate,
        in result: HeistResult,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> HeistActionEvidence {
        try XCTUnwrap(
            result.outputNodes.lazy.compactMap(\.actionEvidence)
                .first { $0.checkedExpectation?.predicate == predicate },
            "Missing action evidence for \(predicate)",
            file: file,
            line: line
        )
    }
}

private extension AccessibilityTrace {
    var appearedLabels: [String] {
        changeFacts.flatMap { fact -> [String] in
            guard case .elementsChanged(let elements) = fact else { return [] }
            return elements.appeared.compactMap(\.elementLabel)
        }
    }

    var disappearedLabels: [String] {
        changeFacts.flatMap { fact -> [String] in
            guard case .elementsChanged(let elements) = fact else { return [] }
            return elements.disappeared.compactMap(\.elementLabel)
        }
    }
}

private extension AccessibilityTrace.InterfaceChangeNode {
    var elementLabel: String? {
        guard case .element(let element, _) = node else { return nil }
        return element.label
    }
}
#endif // canImport(UIKit)
