#if canImport(UIKit)
import XCTest

@testable import BHDemo
import ButtonHeistHostedTestSupport
import ButtonHeistTesting
import ThePlans
@_spi(ButtonHeistInternals) @testable import TheScore

@MainActor
final class AdversarialNavigationTests: XCTestCase {

    func testModalReviewBecomesInteractiveOnlyAfterPresentationCompletes() async throws {
        try await AdversarialLabRoute.open(.modalObstruction)
        let heist = try await runHeist("AdversarialModalObstructionPass") {
            WaitFor(.exists(.label("Modal Obstruction")), timeout: 4)

            Activate(.label("Review order"))
                .expect(.exists(.element(
                    .label("Order review"),
                    .value("Ready")
                )), timeout: 4)
            Activate(.label("Confirm review"))
                .expect(.exists(.label("Status: Review confirmed")), timeout: 2)
            Activate(.label("Close"))
                .expect(.missing(.label("Order review")), timeout: 4)
        }

        XCTAssertNil(heist.result.firstFailedStep)
    }

    func testModalObstructionBlocksBackgroundActionSearch() async throws {
        try await AdversarialLabRoute.open(.modalObstruction)
        let failure = try await expectHeistFailure("AdversarialModalObstructionBackgroundFails") {
            WaitFor(.exists(.label("Modal Obstruction")), timeout: 4)

            Activate(.label("Review order"))
                .expect(.exists(.element(
                    .label("Order review"),
                    .value("Ready")
                )), timeout: 4)
            Activate(.label("Archive order 3"))
        }

        let failedStep = try XCTUnwrap(failure.result.firstFailedStep)
        let actionResult = try XCTUnwrap(failedStep.actionEvidence?.dispatchResult)
        XCTAssertEqual(failure.failedStepKind, .action)
        XCTAssertEqual(failedStep.failure?.category, .targetResolution)
        XCTAssertEqual(actionResult.outcome, .failure(.elementNotFound))
        XCTAssertNil(actionResult.subjectEvidence)

        let cleanup = try await runHeist("AdversarialModalObstructionCleanup") {
            If {
                Case(.exists(.label("Close"))) {
                    Activate(.label("Close"))
                        .expect(.missing(.label("Order review")), timeout: 4)
                }
                Case(.exists(.label("Modal Obstruction"))) {
                    WaitFor(.exists(.label("Modal Obstruction")), timeout: 1)
                }
                Else {
                    WaitFor(.exists(.label("ButtonHeist Demo")), timeout: 1)
                }
            }

            WaitFor(.exists(.element(.label("Archived orders"), .value("0"))), timeout: 2)
            WaitFor(.exists(.element(.label("Background archive actions"), .value("0"))), timeout: 2)
            WaitFor(.exists(.element(.label("Background scroll attempts"), .value("0"))), timeout: 2)
            WaitFor(.exists(.element(.label("Background scroll movements"), .value("0"))), timeout: 2)
        }
        XCTAssertNil(cleanup.result.firstFailedStep)
    }

    func testNestedScrollFindsDeepTargetAcrossBothAxes() async throws {
        let target = AccessibilityTarget.element(
            .label("Verified by The Vibe Check"),
            .value("The Vibe Check"),
            .traits([.button])
        )
        try await AdversarialLabRoute.open(.nestedScroll)
        let heist = try await runHeist("AdversarialNestedScrollPass") {
            WaitFor(.exists(.label("Nested Scroll")), timeout: 4)

            Activate(target)
                .expect(.exists(.label("Selected Verified")), timeout: 6)
            WaitFor(.exists(.element(
                .label("Nested target activations"),
                .value("1")
            )), timeout: 2)
        }

        XCTAssertNil(heist.result.firstFailedStep)
        let actionResult = try XCTUnwrap(
            heist.result.outputNodes.lazy
                .compactMap { $0.actionEvidence?.dispatchResult }
                .first { $0.subjectEvidence?.element.label == "Verified by The Vibe Check" }
        )
        let subject = try XCTUnwrap(actionResult.subjectEvidence)
        XCTAssertEqual(subject.source, .resolvedSemanticTarget)
        XCTAssertEqual(subject.element.label, "Verified by The Vibe Check")
        XCTAssertEqual(subject.resolution.origin, .discovered)
        XCTAssertTrue(subject.resolution.adjustments.contains(.semanticReveal))
        let activationTrace = try XCTUnwrap(actionResult.activationTrace)
        XCTAssertTrue(
            activationTrace.axActivateReturned == true
                || activationTrace.tapActivationSucceeded == true
        )
        XCTAssertGreaterThan(try counterValue(named: "Nested outer scroll attempts", in: actionResult), 0)
        XCTAssertGreaterThan(try counterValue(named: "Nested outer scroll movements", in: actionResult), 0)
        XCTAssertGreaterThan(try counterValue(named: "Nested inner scroll attempts", in: actionResult), 0)
        XCTAssertGreaterThan(try counterValue(named: "Nested inner scroll movements", in: actionResult), 0)
        XCTAssertEqual(try counterValue(named: "Nested target activations", in: actionResult), 1)
    }

    func testDuplicateLabelIdentitySurvivesBothViewportDirectionsAndCandidateReordering() async throws {
        let target = AccessibilityTarget.label("Review PR").and(
            .customContent(.init(label: "Category", value: "Home")),
            .customContent(.init(label: "Priority", value: "High"))
        )
        try await AdversarialLabRoute.open(.duplicateLabels)
        let heist = try await runHeist("AdversarialDuplicateLabelsPass") {
            WaitFor(.exists(target), timeout: 4)

            Activate(target)
                .expect(.exists(.element(
                    .label("Home High activations"),
                    .value("1")
                )), timeout: 6)
            WaitFor(.exists(.element(
                .label("Duplicate candidate order"),
                .value("Reordered")
            )), timeout: 2)

            Activate(.label("Return to duplicate top"))
                .expect(.exists(.element(
                    .label("Duplicate target visibility"),
                    .value("Offscreen")
                )), timeout: 6)
            WaitFor(.exists(target), timeout: 2)

            Activate(target)
                .expect(.exists(.element(
                    .label("Home High activations"),
                    .value("2")
                )), timeout: 6)
            WaitFor(.exists(.element(
                .label("Work High activations"),
                .value("0")
            )), timeout: 2)
            WaitFor(.exists(.element(
                .label("Work Low activations"),
                .value("0")
            )), timeout: 2)
        }

        XCTAssertNil(heist.result.firstFailedStep)
        let targetActivations = heist.result.outputNodes.lazy
            .compactMap { $0.actionEvidence?.dispatchResult }
            .filter { result in
                guard let subject = result.subjectEvidence,
                      subject.element.label == "Review PR"
                else { return false }
                let customContent = subject.element.customContent ?? []
                return customContent.contains {
                    $0.label == "Category" && $0.value == "Home"
                } && customContent.contains {
                    $0.label == "Priority" && $0.value == "High"
                }
            }
        XCTAssertEqual(targetActivations.count, 2)
        for actionResult in targetActivations {
            let subject = try XCTUnwrap(actionResult.subjectEvidence)
            XCTAssertEqual(subject.source, .resolvedSemanticTarget)
        }
        let finalActionResult = try XCTUnwrap(targetActivations.last)
        XCTAssertEqual(try counterValue(named: "Home High activations", in: finalActionResult), 2)
        XCTAssertEqual(try counterValue(named: "Work High activations", in: finalActionResult), 0)
        XCTAssertEqual(try counterValue(named: "Work Low activations", in: finalActionResult), 0)
    }

    // MARK: - Result Evidence

    private func counterValue(
        named label: String,
        in result: ActionResult,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> Int {
        let interface = try XCTUnwrap(
            result.accessibilityTrace?.captures.last?.interface,
            "Missing final interface for \(label)",
            file: file,
            line: line
        )
        let value = try XCTUnwrap(
            interface.projectedElements.first { $0.label == label }?.value,
            "Missing accessibility value for \(label)",
            file: file,
            line: line
        )
        return try XCTUnwrap(
            Int(value),
            "Expected integer accessibility value for \(label), got \(value)",
            file: file,
            line: line
        )
    }
}
#endif // canImport(UIKit)
