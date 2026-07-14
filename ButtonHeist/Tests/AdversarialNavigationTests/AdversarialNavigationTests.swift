#if canImport(UIKit)
import XCTest

import AccessibilitySnapshotModel
@testable import BHDemo
import ButtonHeistHostedTestSupport
import ButtonHeistTesting
import ThePlans
@testable import TheInsideJob
@_spi(ButtonHeistInternals) @testable import TheScore

@MainActor
final class AdversarialNavigationTests: XCTestCase {

    func testOffscreenCheckoutRevealsBottomAction() async throws {
        let target = AccessibilityTarget.element(.label("Place order"), .traits([.button]))
        try await AdversarialLabRoute.open(.offscreenCheckout)
        XCTAssertEqual(try parsedElement(label: "Place order").visibility, .offscreen)
        let heist = try await runHeist("AdversarialOffscreenCheckoutPass") {
            Activate(target)
                .expect(.exists(.label("Order placed")), timeout: .seconds(4))
            WaitFor(.exists(.element(
                .label("Checkout target visibility"),
                .value("Visible")
            )), timeout: .seconds(2))
            WaitFor(.exists(.element(
                .label("Checkout activations"),
                .value("1")
            )), timeout: .seconds(2))
        }

        XCTAssertNil(heist.result.firstFailedStep)
        let actionResult = try XCTUnwrap(
            heist.result.steps.lazy
                .compactMap { $0.actionEvidence?.dispatchResult }
                .first { $0.subjectEvidence?.element.label == "Place order" }
        )
        XCTAssertEqual(actionResult.outcome, .success)
        XCTAssertEqual(actionResult.method, .activate)
        let subject = try XCTUnwrap(actionResult.subjectEvidence)
        XCTAssertEqual(subject.source, .resolvedSemanticTarget)
        XCTAssertEqual(subject.phase, .resolvedBeforeDispatch)
        XCTAssertEqual(subject.element.label, "Place order")
        XCTAssertNotEqual(subject.resolution.origin, .visible)
        XCTAssertTrue(subject.resolution.adjustments.contains(.semanticReveal))
        let activationTrace = try XCTUnwrap(actionResult.activationTrace)
        XCTAssertTrue(
            activationTrace.axActivateReturned == true
                || activationTrace.tapActivationSucceeded == true
        )
        XCTAssertGreaterThan(try counterValue(named: "Checkout scroll attempts", in: actionResult), 0)
        XCTAssertGreaterThan(try counterValue(named: "Checkout scroll movements", in: actionResult), 0)
        XCTAssertEqual(try counterValue(named: "Checkout activations", in: actionResult), 1)
    }

    func testOffscreenCheckoutDisabledActionFailsWithoutActivation() async throws {
        try await AdversarialLabRoute.open(.offscreenCheckout)
        let failure = try await expectHeistFailure("AdversarialOffscreenCheckoutDisabledFails") {
            Activate(.element(.label("Unavailable order"), .traits([.button])))
        }

        let failedStep = try XCTUnwrap(failure.result.firstFailedStep)
        let actionResult = try XCTUnwrap(failedStep.actionEvidence?.dispatchResult)
        XCTAssertEqual(failure.failedStepKind, .action)
        XCTAssertEqual(failedStep.failure?.category, .action)
        XCTAssertEqual(actionResult.outcome, .failure(.actionFailed))

        let verification = try await runHeist("AdversarialOffscreenCheckoutDisabledVerification") {
            WaitFor(.exists(.element(
                .label("Checkout activations"),
                .value("0")
            )), timeout: .seconds(2))
            WaitFor(.exists(.label("Cart ready")), timeout: .seconds(2))
        }
        XCTAssertNil(verification.result.firstFailedStep)
    }

    func testDuplicateLabelsRequireSemanticDisambiguation() async throws {
        let workHigh = AccessibilityTarget.element(
            .label("Review PR"),
            .value("Active"),
            .customContent(.init(label: "Category", value: "Work")),
            .customContent(.init(label: "Priority", value: "High")),
            .actions([.custom("Toggle")])
        )
        let workLowActive = AccessibilityTarget.element(
            .label("Review PR"),
            .value("Active"),
            .customContent(.init(label: "Category", value: "Work")),
            .customContent(.init(label: "Priority", value: "Low"))
        )
        let homeHighActive = AccessibilityTarget.element(
            .label("Review PR"),
            .value("Active"),
            .customContent(.init(label: "Category", value: "Home")),
            .customContent(.init(label: "Priority", value: "High"))
        )

        try await AdversarialLabRoute.open(.duplicateLabels)
        let heist = try await runHeist("AdversarialDuplicateLabelsPass") {
            WaitFor(.exists(.element(
                .label("Task mutation count"),
                .value("0")
            )), timeout: .seconds(2))
            CustomAction("Toggle", on: workHigh)
                .expect(.exists(.element(
                    .label("Review PR"),
                    .value("Completed"),
                    .customContent(.init(label: "Category", value: "Work")),
                    .customContent(.init(label: "Priority", value: "High"))
                )), timeout: .seconds(2))
            WaitFor(.exists(workLowActive), timeout: .seconds(2))
            WaitFor(.exists(homeHighActive), timeout: .seconds(2))
            WaitFor(.exists(.element(
                .label("Task mutation count"),
                .value("1")
            )), timeout: .seconds(2))
        }

        XCTAssertNil(heist.result.firstFailedStep)
        let actionResult = try XCTUnwrap(
            heist.result.steps.lazy
                .compactMap { $0.actionEvidence?.dispatchResult }
                .first { $0.method == .customAction }
        )
        let subject = try XCTUnwrap(actionResult.subjectEvidence)
        XCTAssertEqual(subject.source, .resolvedSemanticTarget)
        XCTAssertEqual(subject.element.label, "Review PR")
        XCTAssertEqual(subject.element.value, "Active")
        XCTAssertEqual(subject.resolution, ActionSubjectResolution(origin: .visible))
        XCTAssertEqual(
            subject.element.customContent?.first { $0.label == "Category" }?.value,
            "Work"
        )
        XCTAssertEqual(
            subject.element.customContent?.first { $0.label == "Priority" }?.value,
            "High"
        )
    }

    func testDuplicateLabelsLabelOnlyActionFailsAmbiguousWithoutMutation() async throws {
        let workHighActive = AccessibilityTarget.element(
            .label("Review PR"),
            .value("Active"),
            .customContent(.init(label: "Category", value: "Work")),
            .customContent(.init(label: "Priority", value: "High"))
        )
        let workLowActive = AccessibilityTarget.element(
            .label("Review PR"),
            .value("Active"),
            .customContent(.init(label: "Category", value: "Work")),
            .customContent(.init(label: "Priority", value: "Low"))
        )
        let homeHighActive = AccessibilityTarget.element(
            .label("Review PR"),
            .value("Active"),
            .customContent(.init(label: "Category", value: "Home")),
            .customContent(.init(label: "Priority", value: "High"))
        )

        try await AdversarialLabRoute.open(.duplicateLabels)
        let failure = try await expectHeistFailure("AdversarialDuplicateLabelsAmbiguousFails") {
            WaitFor(.exists(workHighActive), timeout: .seconds(2))
            WaitFor(.exists(workLowActive), timeout: .seconds(2))
            WaitFor(.exists(homeHighActive), timeout: .seconds(2))
            WaitFor(.exists(.element(
                .label("Task mutation count"),
                .value("0")
            )), timeout: .seconds(2))
            CustomAction("Toggle", on: .label("Review PR"))
        }

        let failedStep = try XCTUnwrap(failure.result.firstFailedStep)
        let actionResult = try XCTUnwrap(failedStep.actionEvidence?.dispatchResult)
        XCTAssertEqual(failure.failedStepKind, .action)
        XCTAssertEqual(failedStep.failure?.category, .targetResolution)
        XCTAssertEqual(actionResult.outcome, .failure(.elementNotFound))
        XCTAssertNil(actionResult.subjectEvidence)

        let verification = try await runHeist("AdversarialDuplicateLabelsAmbiguousVerification") {
            WaitFor(.exists(workHighActive), timeout: .seconds(2))
            WaitFor(.exists(workLowActive), timeout: .seconds(2))
            WaitFor(.exists(homeHighActive), timeout: .seconds(2))
            WaitFor(.exists(.element(
                .label("Task mutation count"),
                .value("0")
            )), timeout: .seconds(2))
        }
        XCTAssertNil(verification.result.firstFailedStep)
    }

    func testModalObstructionKeepsActionSurfaceExplicit() async throws {
        try await AdversarialLabRoute.open(.modalObstruction)
        let heist = try await runHeist("AdversarialModalObstructionPass") {
            WaitFor(.exists(.element(.label("Archived orders"), .value("0"))), timeout: .seconds(2))
            WaitFor(.exists(.element(
                .label("Background archive actions"),
                .value("0")
            )), timeout: .seconds(2))
            Activate(.label("Review order"))
                .expect(.exists(.label("Order review")), timeout: .seconds(4))
            WaitFor(.exists(.element(
                .label("Background scroll attempts"),
                .value("0")
            )), timeout: .seconds(2))
            Activate(.label("Confirm review"))
                .expect(.exists(.label("Status: Review confirmed")), timeout: .seconds(2))
            Activate(.label("Close"))
                .expect(.missing(.label("Order review")), timeout: .seconds(4))
        }

        XCTAssertNil(heist.result.firstFailedStep)
    }

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
            heist.result.steps.lazy
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

    func testNestedScrollImpossibleTargetFailsBoundedSearch() async throws {
        try await AdversarialLabRoute.open(.nestedScroll)
        let failure = try await expectHeistFailure("AdversarialNestedScrollImpossibleFails") {
            Activate(.label("Album That Does Not Exist"))
        }

        let failedStep = try XCTUnwrap(failure.result.firstFailedStep)
        let actionResult = try XCTUnwrap(failedStep.actionEvidence?.dispatchResult)
        XCTAssertEqual(failure.failedStepKind, .action)
        XCTAssertEqual(failedStep.failure?.category, .targetResolution)
        XCTAssertEqual(actionResult.outcome, .failure(.elementNotFound))
        XCTAssertNil(actionResult.subjectEvidence)

        let outerAttempts = try counterValue(named: "Nested outer scroll attempts", in: actionResult)
        let outerMovements = try counterValue(named: "Nested outer scroll movements", in: actionResult)
        let innerAttempts = try counterValue(named: "Nested inner scroll attempts", in: actionResult)
        let innerMovements = try counterValue(named: "Nested inner scroll movements", in: actionResult)
        XCTAssertGreaterThan(outerAttempts, 0)
        XCTAssertGreaterThan(outerMovements, 0)
        XCTAssertGreaterThan(innerAttempts, 0)
        XCTAssertGreaterThan(innerMovements, 0)
        XCTAssertLessThanOrEqual(outerAttempts, Navigation.ScreenManifest.maxScrollsPerContainer)
        XCTAssertLessThanOrEqual(innerAttempts, Navigation.ScreenManifest.maxScrollsPerContainer)
        XCTAssertLessThanOrEqual(
            outerAttempts + innerAttempts,
            Navigation.ScreenManifest.maxScrollsPerDiscovery
        )
        XCTAssertEqual(try counterValue(named: "Nested target activations", in: actionResult), 0)
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

    private func parsedElement(label: String) throws -> AccessibilityElement {
        let burglar = TheBurglar(tripwire: TheTripwire())
        let result = try XCTUnwrap(burglar.parse())
        return try XCTUnwrap(
            result.hierarchy.sortedElements.first { $0.label == label },
            "Expected a parsed element labelled \(label)"
        )
    }

}
#endif // canImport(UIKit)
