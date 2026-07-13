#if canImport(UIKit)
import XCTest

import ButtonHeistHostedTestSupport
import ButtonHeistTesting
import ThePlans
@testable import TheInsideJob
@_spi(ButtonHeistInternals) @testable import TheScore

@MainActor
final class AdversarialMutationTests: XCTestCase {

    func testAsyncRevealNotificationAndSilentVariantsPass() async throws {
        let notification = try await runHeist("AdversarialAsyncRevealNotificationPass") {
            try DemoNavigation.openAdversarialScenario("Async Reveal")
            Activate(.label("Reveal with notification"))
                .expect(.exists(.label("Delayed code: 7429")), timeout: .seconds(3))
        }
        XCTAssertNil(notification.result.firstFailedStep)

        let silent = try await runHeist("AdversarialAsyncRevealSilentPass") {
            try DemoNavigation.openAdversarialScenario("Async Reveal")
            Activate(.label("Reveal silently"))
                .expect(.exists(.label("Delayed code: 7429")), timeout: .seconds(3))
        }
        XCTAssertNil(silent.result.firstFailedStep)
    }

    func testAsyncRevealWrongDestinationFailsWithWaitEvidence() async throws {
        let failure = try await expectHeistFailure("AdversarialAsyncRevealWrongDestinationFails") {
            try DemoNavigation.openAdversarialScenario("Async Reveal")
            Activate(.label("Reveal silently"))
                .withoutExpectation("The failing wait below proves async destination diagnostics")
            WaitFor(.exists(.label("Delayed code: 9999")), timeout: .seconds(0.2))
        }

        XCTAssertEqual(failure.failedStepKind, .wait)
        XCTAssertTrue(failure.message.contains("Delayed code: 9999"), failure.description)
    }

    func testDynamicCellsKeepSemanticIdentityAfterChurn() throws {
        let runtime = TheInsideJob.shared
        defer { assertInProcessRuntimeStopped(runtime) }

        let noodles = AccessibilityTarget.element(
            .label("Nebula Noodles Prime"),
            .customContent(.init(label: "SKU", value: "SKU-72")),
            .customContent(.init(label: "Category", value: "Mains")),
            .customContent(.init(label: "Churn State", value: "post-churn")),
            .customContent(.init(label: "Menu Slot", value: "deep target after churn")),
            .customContent(.init(label: "Unit Price", value: "$18.00")),
            .actions([.custom("Add to Cart")])
        )

        let heist = try XCTUnwrap(runHeistSync("AdversarialDynamicCellsPass") {
            try DemoNavigation.openAdversarialScenario("Dynamic Cells")
            Activate(.label("Churn menu"))
                .expect(.exists(.label("Menu churned")), timeout: .seconds(4))
            CustomAction("Add to Cart", on: noodles)
                .expect(.exists(.element(
                    .label("Nebula Noodles Prime"),
                    .customContent(.init(label: "SKU", value: "SKU-72")),
                    .customContent(.init(label: "Churn State", value: "post-churn")),
                    .customContent(.init(label: "Quantity", value: "1")),
                    .customContent(.init(label: "Line Total", value: "$18.00")),
                    .actions([.custom("Remove from Cart")])
                )), timeout: .seconds(6))
        })

        XCTAssertNil(heist.result.firstFailedStep)
    }

    func testDynamicCellsStalePreChurnSemanticTargetFails() async throws {
        let stale = AccessibilityTarget.element(
            .label("Nebula Noodles"),
            .customContent(.init(label: "SKU", value: "SKU-72")),
            .customContent(.init(label: "Churn State", value: "pre-churn")),
            .actions([.custom("Add to Cart")])
        )

        let failure = try await expectHeistFailure("AdversarialDynamicCellsStaleTargetFails") {
            try DemoNavigation.openAdversarialScenario("Dynamic Cells")
            Activate(.label("Churn menu"))
                .expect(.exists(.label("Menu churned")), timeout: .seconds(4))
            CustomAction("Add to Cart", on: stale)
        }

        XCTAssertEqual(failure.failedStepKind, .action)
        XCTAssertTrue(failure.description.localizedCaseInsensitiveContains("pre-churn"), failure.description)
    }

    func testTextFieldFallbackTypesThroughTapActivation() async throws {
        let field = AccessibilityTarget.element(.label("Fallback field"), traits: [.textEntry])

        let heist = try await runHeist("AdversarialTextFieldFallbackPass") {
            try DemoNavigation.openAdversarialScenario("Text Field Fallback")
            TypeText("fallback typed", into: field, replacingExisting: true)
                .expect(.exists(.value("fallback typed")), timeout: .seconds(3))
        }

        let dispatch = try XCTUnwrap(heist.result.steps.last?.actionEvidence?.dispatchResult)
        XCTAssertTrue(dispatch.outcome.isSuccess, dispatch.message ?? "type text failed")
        XCTAssertEqual(dispatch.method, .typeText)
    }

    func testTextFieldFallbackTargetlessTypingFailsBeforeFocus() async throws {
        let failure = try await expectHeistFailure("AdversarialTextFieldFallbackTargetlessFails") {
            try DemoNavigation.openAdversarialScenario("Text Field Fallback")
            TypeText("orphan typed")
        }

        XCTAssertEqual(failure.failedStepKind, .action)
        XCTAssertNotNil(failure.result.firstFailedStep?.failure)
    }

    func testStaleLiveObjectReResolvesCurrentTarget() async throws {
        let heist = try await runHeist("AdversarialStaleLiveObjectPass") {
            try DemoNavigation.openAdversarialScenario("Stale Live Object")
            WaitFor(.exists(.element(.label("Submit Order"), .value("version 1"))), timeout: .seconds(2))
            Activate(.label("Replace Target"))
                .expect(.exists(.element(.label("Submit Order"), .value("version 2"))), timeout: .seconds(2))
            Activate(.element(.label("Submit Order"), .value("version 2")))
                .expect(.exists(.label("Result: submitted version 2")), timeout: .seconds(2))
        }

        XCTAssertNil(heist.result.firstFailedStep)
    }

    func testStaleLiveObjectDuplicateCurrentTargetsFailAmbiguous() async throws {
        let failure = try await expectHeistFailure("AdversarialStaleLiveObjectAmbiguousFails") {
            try DemoNavigation.openAdversarialScenario("Stale Live Object")
            Activate(.label("Replace Target"))
                .expect(.exists(.element(.label("Submit Order"), .value("version 2"))), timeout: .seconds(2))
            Activate(.label("Show Duplicate Target"))
                .expect(.exists(.element(.label("Submit Order"), .value("version duplicate"))), timeout: .seconds(2))
            Activate(.label("Submit Order"))
        }

        XCTAssertEqual(failure.failedStepKind, .action)
        XCTAssertTrue(failure.description.localizedCaseInsensitiveContains("ambiguous"), failure.description)
    }

    private func expectHeistFailure<Content: HeistContent>(
        _ name: String,
        @HeistBuilder content: @escaping () throws -> Content
    ) async throws -> Heist.Failure {
        do {
            _ = try await runHeist(name, content)
            XCTFail("Expected \(name) to fail")
            throw ExpectedFailureDidNotFail()
        } catch let failure as Heist.Failure {
            return failure
        }
    }

    private func assertInProcessRuntimeStopped(
        _ runtime: TheInsideJob,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let observationStream = runtime.brains.stash.semanticObservationStream
        XCTAssertFalse(runtime.isRunning, file: file, line: line)
        XCTAssertNil(runtime.listeningPort, file: file, line: line)
        XCTAssertFalse(runtime.tripwire.isPulseRunning, file: file, line: line)
        XCTAssertFalse(runtime.brains.semanticObservationIsActive, file: file, line: line)
        XCTAssertFalse(observationStream.isActive, file: file, line: line)
        XCTAssertEqual(observationStream.settledWaiterCount, 0, file: file, line: line)
        XCTAssertEqual(observationStream.cycleWaiterCount, 0, file: file, line: line)
        XCTAssertEqual(observationStream.activeObservationDemandCount, 0, file: file, line: line)
    }
}

private struct ExpectedFailureDidNotFail: Error {}

#endif // canImport(UIKit)
