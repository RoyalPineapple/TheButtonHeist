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
        let observationEvidence = try XCTUnwrap(evidence.result?.observationEvidence)

        XCTAssertEqual(try evidence.replayExpectation()?.met, true)
        XCTAssertTrue(observationEvidence.addedLabels.contains("Processing"))
        XCTAssertTrue(observationEvidence.removedLabels.contains("Submit"))

        let failure = try await expectHeistFailure("DogfoodStandaloneCannotReuseLifecycleEvidence") {
            WaitFor(TransientFlowScreen.lifecycle, timeout: 0.25)
        }
        XCTAssertEqual(try HeistReport.project(result: failure.result).failure?.actionKind, .timeout)
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

        XCTAssertEqual(try evidence.replayExpectation()?.met, true)
        XCTAssertEqual(try evidence.announcement, "Ticket saved.")

        let exactFailure = try await expectHeistFailure("DogfoodCombinedToastExactTextFails") {
            WaitFor(TransientFlowScreen.exactToastText, timeout: 0.5)
        }
        let exactReport = try HeistReport.project(result: exactFailure.result)
        let exactObservation = try XCTUnwrap(
            exactFailure.result.outputNodes.lazy.compactMap(\.waitObservation).last
        )
        let currentLabels = try XCTUnwrap(exactObservation.current)
            .interface.projectedElements.compactMap(\.semantics.assertable.label)

        XCTAssertEqual(exactReport.failure?.actionKind, .timeout)
        XCTAssertTrue(currentLabels.contains("Ticket saved., Dismiss"))
        XCTAssertFalse(currentLabels.contains("Ticket saved."))

        let standaloneFailure = try await expectHeistFailure(
            "DogfoodStandaloneCannotReuseAnnouncementEvidence"
        ) {
            WaitFor(TransientFlowScreen.announcement, timeout: 0.25)
        }
        XCTAssertEqual(try HeistReport.project(result: standaloneFailure.result).failure?.actionKind, .timeout)
    }

    private func actionEvidence(
        matching predicate: AccessibilityPredicate,
        in result: HeistResult,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> HeistActionEvidence {
        try XCTUnwrap(
            result.outputNodes.lazy.compactMap(\.actionEvidence)
                .first { try $0.replayExpectation()?.predicate == predicate },
            "Missing action evidence for \(predicate)",
            file: file,
            line: line
        )
    }
}

private extension Observation.Evidence {
    var addedLabels: [String] {
        elementEdits.flatMap(\.added).compactMap(\.semantics.assertable.label)
    }

    var removedLabels: [String] {
        elementEdits.flatMap(\.removed).compactMap(\.semantics.assertable.label)
    }

    private var elementEdits: [ElementEdits] {
        var previous = baseline?.interface
        return events.compactMap { event in
            guard case .elementsChanged(let snapshot) = event else { return nil }
            defer { previous = snapshot.interface }
            guard let previous else { return nil }
            return ElementEdits.between(previous, snapshot.interface)
        }
    }
}
#endif // canImport(UIKit)
