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
        let destination: AccessibilityPredicate<RootContext> = .exists(.label("Delayed code: 7429"))
        let notification = try await runHeist("AdversarialAsyncRevealNotificationPass") {
            try DemoNavigation.openAdversarialScenario("Async Reveal")
            Activate(.label("Reveal with notification"))
                .expect(destination, timeout: .seconds(3))
        }
        let notificationReceipt = try XCTUnwrap(notification.result.steps.compactMap(\.actionEvidence).last)
        let notificationDispatch = try XCTUnwrap(notificationReceipt.dispatchResult)
        let notificationObservation = try XCTUnwrap(notificationReceipt.expectationResult)
        XCTAssertEqual(notificationDispatch.outcome, .success)
        XCTAssertEqual(notificationObservation.outcome, .success)
        XCTAssertEqual(notificationObservation.method, .wait)
        XCTAssertEqual(notificationReceipt.checkedExpectation?.predicate, destination)
        XCTAssertEqual(notificationReceipt.checkedExpectation?.met, true)
        XCTAssertTrue(notificationReceipt.receiptNotificationKinds.contains(.screenChanged))

        let silent = try await runHeist("AdversarialAsyncRevealSilentPass") {
            try DemoNavigation.openAdversarialScenario("Async Reveal")
            Activate(.label("Reveal silently"))
                .expect(destination, timeout: .seconds(3))
        }
        let silentReceipt = try XCTUnwrap(silent.result.steps.compactMap(\.actionEvidence).last)
        let silentDispatch = try XCTUnwrap(silentReceipt.dispatchResult)
        let silentObservation = try XCTUnwrap(silentReceipt.expectationResult)
        XCTAssertEqual(silentDispatch.outcome, .success)
        XCTAssertEqual(silentObservation.outcome, .success)
        XCTAssertEqual(silentObservation.method, .wait)
        XCTAssertEqual(silentReceipt.checkedExpectation?.predicate, destination)
        XCTAssertEqual(silentReceipt.checkedExpectation?.met, true)
        XCTAssertFalse(silentReceipt.receiptNotificationKinds.contains(.screenChanged))
    }

    func testAsyncRevealWrongDestinationFailsWithWaitEvidence() async throws {
        let visibleDestination: AccessibilityPredicate<RootContext> = .exists(.label("Delayed code: 7429"))
        let missingDestination: AccessibilityPredicate<RootContext> = .exists(.label("Delayed code: 9999"))
        let failure = try await expectHeistFailure("AdversarialAsyncRevealWrongDestinationFails") {
            try DemoNavigation.openAdversarialScenario("Async Reveal")
            Activate(.label("Reveal silently"))
                .expect(visibleDestination, timeout: .seconds(3))
            WaitFor(missingDestination, timeout: .seconds(0.2))
        }

        XCTAssertEqual(failure.failedStepKind, .wait)
        let revealReceipt = try XCTUnwrap(failure.result.steps.compactMap(\.actionEvidence).last)
        XCTAssertEqual(revealReceipt.checkedExpectation?.predicate, visibleDestination)
        XCTAssertEqual(revealReceipt.checkedExpectation?.met, true)
        XCTAssertEqual(revealReceipt.expectationResult?.outcome, .success)

        let failedStep = try XCTUnwrap(failure.result.firstFailedStep)
        let waitEvidence = try XCTUnwrap(failedStep.waitEvidence)
        XCTAssertEqual(failedStep.failure?.category, .wait)
        XCTAssertEqual(waitEvidence.outcome, .failed)
        XCTAssertEqual(waitEvidence.actionResult.method, .wait)
        XCTAssertEqual(waitEvidence.actionResult.outcome, .failure(.timeout))
        XCTAssertEqual(waitEvidence.expectation.predicate, missingDestination)
        XCTAssertEqual(waitEvidence.expectation.met, false)
    }

    func testDynamicCellsKeepSemanticIdentityAfterChurn() throws {
        let runtime = TheInsideJob.shared
        defer { assertInProcessRuntimeStopped(runtime) }

        let noodles = AccessibilityTarget.element(
            .label("Nebula Noodles"),
            .customContent(.init(label: "SKU", value: "SKU-72")),
            .customContent(.init(label: "Category", value: "Mains")),
            .customContent(.init(label: "Generation", value: "2")),
            .customContent(.init(label: "Action Count", value: "0")),
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
                    .label("Nebula Noodles"),
                    .customContent(.init(label: "SKU", value: "SKU-72")),
                    .customContent(.init(label: "Generation", value: "2")),
                    .customContent(.init(label: "Action Count", value: "1")),
                    .customContent(.init(label: "Quantity", value: "1")),
                    .customContent(.init(label: "Line Total", value: "$18.00")),
                    .actions([.custom("Remove from Cart")])
                )), timeout: .seconds(6))
        })

        XCTAssertNil(heist.result.firstFailedStep)
        let receipt = try XCTUnwrap(heist.result.steps.compactMap(\.actionEvidence).last)
        let dispatch = try XCTUnwrap(receipt.dispatchResult)
        let subject = try XCTUnwrap(dispatch.subjectEvidence)
        XCTAssertEqual(dispatch.outcome, .success)
        XCTAssertEqual(dispatch.method, .customAction)
        XCTAssertEqual(subject.source, .resolvedSemanticTarget)
        XCTAssertEqual(subject.target, noodles)

        let finalElements = try XCTUnwrap(
            receipt.expectationResult?.accessibilityTrace?.captures.last?.interface.projectedElements
        )
        let finalTarget = try XCTUnwrap(finalElements.first { $0.label == "Nebula Noodles" })
        XCTAssertEqual(finalTarget.customContentValue(label: "Generation"), "2")
        XCTAssertEqual(finalTarget.customContentValue(label: "Action Count"), "1")
        XCTAssertEqual(finalTarget.customContentValue(label: "Quantity"), "1")
    }

    func testDynamicCellsStalePreChurnSemanticTargetFails() async throws {
        let stale = AccessibilityTarget.element(
            .label("Nebula Noodles"),
            .customContent(.init(label: "SKU", value: "SKU-72")),
            .customContent(.init(label: "Generation", value: "1")),
            .customContent(.init(label: "Action Count", value: "0")),
            .actions([.custom("Add to Cart")])
        )

        let failure = try await expectHeistFailure("AdversarialDynamicCellsStaleTargetFails") {
            try DemoNavigation.openAdversarialScenario("Dynamic Cells")
            Activate(.label("Churn menu"))
                .expect(.exists(.label("Menu churned")), timeout: .seconds(4))
            CustomAction("Add to Cart", on: stale)
        }

        XCTAssertEqual(failure.failedStepKind, .action)
        let failedStep = try XCTUnwrap(failure.result.firstFailedStep)
        let dispatch = try XCTUnwrap(failedStep.actionEvidence?.dispatchResult)
        XCTAssertEqual(failedStep.failure?.category, .action)
        XCTAssertEqual(dispatch.method, .customAction)
        XCTAssertEqual(dispatch.outcome, .failure(.elementNotFound))
        XCTAssertNil(dispatch.subjectEvidence)

        let finalElements = try XCTUnwrap(
            dispatch.accessibilityTrace?.captures.last?.interface.projectedElements
        )
        let finalTarget = try XCTUnwrap(finalElements.first { $0.label == "Nebula Noodles" })
        XCTAssertEqual(finalTarget.customContentValue(label: "Generation"), "2")
        XCTAssertEqual(finalTarget.customContentValue(label: "Action Count"), "0")
        XCTAssertEqual(finalTarget.customContentValue(label: "Quantity"), "0")
        XCTAssertFalse(finalElements.contains {
            $0.label == "Nebula Noodles" && $0.customContentValue(label: "Generation") == "1"
        })
    }

    func testTextFieldFallbackTypesThroughTapActivation() async throws {
        let field = AccessibilityTarget.element(.label("Fallback field"), traits: [.textEntry])

        let heist = try await runHeist("AdversarialTextFieldFallbackPass") {
            try DemoNavigation.openAdversarialScenario("Text Field Fallback")
            TypeText("fallback typed", into: field)
                .expect(.exists(.element(
                    .label("Fallback field"),
                    .value("fallback typed"),
                    traits: [.textEntry]
                )), timeout: .seconds(3))
        }

        let receipt = try XCTUnwrap(heist.result.steps.compactMap(\.actionEvidence).last)
        let dispatch = try XCTUnwrap(receipt.dispatchResult)
        let subject = try XCTUnwrap(dispatch.subjectEvidence)
        XCTAssertEqual(dispatch.outcome, .success)
        XCTAssertEqual(dispatch.method, .typeText)
        XCTAssertEqual(dispatch.payload, .value("fallback typed"))
        XCTAssertEqual(subject.source, .textInputTarget)
        XCTAssertEqual(subject.target, field)
        XCTAssertEqual(subject.element.label, "Fallback field")

        let finalElements = try XCTUnwrap(
            receipt.expectationResult?.accessibilityTrace?.captures.last?.interface.projectedElements
        )
        let activity = try XCTUnwrap(finalElements.first { $0.label == "Fallback field activity" })
        XCTAssertEqual(activity.value, "Activation attempts 1, focus acquisitions 1, edits 14")
    }

    func testTextFieldFallbackTargetlessTypingFailsBeforeFocus() async throws {
        let failure = try await expectHeistFailure("AdversarialTextFieldFallbackTargetlessFails") {
            try DemoNavigation.openAdversarialScenario("Text Field Fallback")
            TypeText("orphan typed")
        }

        XCTAssertEqual(failure.failedStepKind, .action)
        let failedStep = try XCTUnwrap(failure.result.firstFailedStep)
        let dispatch = try XCTUnwrap(failedStep.actionEvidence?.dispatchResult)
        XCTAssertEqual(failedStep.failure?.category, .action)
        XCTAssertEqual(dispatch.method, .typeText)
        XCTAssertEqual(dispatch.outcome, .failure(.actionFailed))
        XCTAssertNil(dispatch.payload)
        XCTAssertNil(dispatch.subjectEvidence)

        let finalElements = try XCTUnwrap(
            dispatch.accessibilityTrace?.captures.last?.interface.projectedElements
        )
        let activity = try XCTUnwrap(finalElements.first { $0.label == "Fallback field activity" })
        XCTAssertEqual(activity.value, "Activation attempts 0, focus acquisitions 0, edits 0")
    }

    func testStaleLiveObjectReResolvesCurrentTarget() async throws {
        let finalValue = "Generation 2, actions 1, generation 1 actions 0"
        let heist = try await runHeist("AdversarialStaleLiveObjectPass") {
            try DemoNavigation.openAdversarialScenario("Stale Live Object")
            Activate(.label("Submit Order"))
                .expect(.exists(.element(
                    .label("Submit Order"),
                    .value(finalValue)
                )), timeout: .seconds(4))
        }

        XCTAssertNil(heist.result.firstFailedStep)
        let receipt = try XCTUnwrap(heist.result.steps.compactMap(\.actionEvidence).last)
        let dispatch = try XCTUnwrap(receipt.dispatchResult)
        let subject = try XCTUnwrap(dispatch.subjectEvidence)
        XCTAssertEqual(dispatch.outcome, .success)
        XCTAssertEqual(dispatch.method, .activate)
        XCTAssertEqual(subject.source, .resolvedSemanticTarget)
        XCTAssertEqual(subject.element.label, "Submit Order")
        let staleAdjustments: Set<ActionSubjectResolution.Adjustment> = [
            .objectDeallocationRefresh,
            .staleTargetRefresh,
        ]
        XCTAssertFalse(subject.resolution.adjustments.isDisjoint(with: staleAdjustments))

        let finalElements = try XCTUnwrap(
            receipt.expectationResult?.accessibilityTrace?.captures.last?.interface.projectedElements
        )
        XCTAssertEqual(finalElements.first { $0.label == "Submit Order" }?.value, finalValue)
    }

    func testStaleLiveObjectDuplicateCurrentTargetsFailAmbiguous() async throws {
        let primaryValue = "Generation 2, actions 0, generation 1 actions 0"
        let duplicateValue = "Generation 3, actions 0, generation 1 actions 0"
        let failure = try await expectHeistFailure("AdversarialStaleLiveObjectAmbiguousFails") {
            try DemoNavigation.openAdversarialScenario("Stale Live Object")
            Activate(.label("Show Duplicate Target"))
                .expect(.exists(.element(
                    .label("Submit Order"),
                    .value(primaryValue)
                )), timeout: .seconds(4))
            Activate(.label("Submit Order"))
        }

        XCTAssertEqual(failure.failedStepKind, .action)
        let failedStep = try XCTUnwrap(failure.result.firstFailedStep)
        let dispatch = try XCTUnwrap(failedStep.actionEvidence?.dispatchResult)
        XCTAssertEqual(failedStep.failure?.category, .action)
        XCTAssertEqual(dispatch.method, .activate)
        XCTAssertEqual(dispatch.outcome, .failure(.elementNotFound))
        XCTAssertNil(dispatch.subjectEvidence)

        let finalElements = try XCTUnwrap(
            dispatch.accessibilityTrace?.captures.last?.interface.projectedElements
        )
        let targets = finalElements.filter { $0.label == "Submit Order" }
        XCTAssertEqual(targets.count, 2)
        XCTAssertEqual(Set(targets.compactMap(\.value)), Set([primaryValue, duplicateValue]))
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

private extension HeistActionEvidence {
    var receiptNotificationKinds: [AccessibilityNotificationKind] {
        [dispatchResult, expectationResult]
            .compactMap { $0?.accessibilityTrace }
            .flatMap(\.captures)
            .flatMap(\.transition.accessibilityNotifications)
            .map(\.kind)
    }
}

private extension HeistElement {
    func customContentValue(label: String) -> String? {
        customContent?.first { $0.label == label }?.value
    }
}

#endif // canImport(UIKit)
