#if canImport(UIKit)
import XCTest

@testable import BHDemo
import ButtonHeistHostedTestSupport
import ButtonHeistTesting
import ThePlans
@_spi(ButtonHeistInternals) @testable import TheScore

@MainActor
final class AdversarialNavigationTests: XCTestCase {

    func testModalObstructionBlocksBackgroundActionSearch() async throws {
        try await AdversarialLabRoute.open(.modalObstruction)
        let failure = try await expectHeistFailure("AdversarialModalObstructionBackgroundFails") {
            Activate(.label("Review order"))
                .expect(.exists(.label("Order review")), timeout: .seconds(4))
            Activate(.label("Archive order 3"))
        }

        let failedStep = try XCTUnwrap(failure.result.firstFailedStep)
        let actionResult = try XCTUnwrap(failedStep.actionEvidence?.dispatchResult)
        XCTAssertEqual(failure.failedStepKind, .action)
        XCTAssertEqual(failedStep.failure?.category, .targetResolution)
        XCTAssertEqual(actionResult.outcome, .failure(.elementNotFound))
        XCTAssertNil(actionResult.subjectEvidence)

        let cleanup = try await runHeist("AdversarialModalObstructionCleanup") {
            WaitFor(.exists(.element(.label("Archived orders"), .value("0"))), timeout: .seconds(2))
            WaitFor(.exists(.element(
                .label("Background archive actions"),
                .value("0")
            )), timeout: .seconds(2))
            WaitFor(.exists(.element(
                .label("Background scroll attempts"),
                .value("0")
            )), timeout: .seconds(2))
            WaitFor(.exists(.element(
                .label("Background scroll movements"),
                .value("0")
            )), timeout: .seconds(2))
            Activate(.label("Close"))
                .expect(.missing(.label("Order review")), timeout: .seconds(4))
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
            Activate(target)
                .expect(.exists(.label("Selected Verified")), timeout: .seconds(6))
            WaitFor(.exists(.element(
                .label("Nested target activations"),
                .value("1")
            )), timeout: .seconds(2))
        }

        XCTAssertNil(heist.result.firstFailedStep)
        let actionResult = try XCTUnwrap(
            heist.result.evidenceRollup.outputReceiptNodes.lazy
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

    // MARK: - Receipt Evidence

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
