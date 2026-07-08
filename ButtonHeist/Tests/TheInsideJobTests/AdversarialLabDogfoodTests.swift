#if canImport(UIKit)
import XCTest

import ButtonHeistTesting
import ThePlans
@testable import TheInsideJob
@_spi(ButtonHeistInternals) @testable import TheScore

@MainActor
final class AdversarialLabDogfoodTests: XCTestCase {

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

    func testOffscreenCheckoutRevealsBottomAction() async throws {
        let heist = try await runHeist("AdversarialOffscreenCheckoutPass") {
            try DemoNavigation.openAdversarialScenario("Offscreen Checkout")
            Activate(.label("Add Espresso"))
                .expect(.exists(.label("Remove Espresso")), timeout: .seconds(2))
            Activate(.element(.label("Place order"), .traits([.button])))
                .expect(.exists(.label("Order placed")), timeout: .seconds(4))
        }

        XCTAssertNil(heist.result.firstFailedStep)
    }

    func testOffscreenCheckoutDisabledActionFails() async throws {
        let failure = try await expectHeistFailure("AdversarialOffscreenCheckoutDisabledFails") {
            try DemoNavigation.openAdversarialScenario("Offscreen Checkout")
            Activate(.element(.label("Place order"), .traits([.button])))
        }

        XCTAssertEqual(failure.failedStepKind, .action)
        XCTAssertNotNil(failure.result.firstFailedStep?.failure)
    }

    func testDuplicateLabelsRequireSemanticDisambiguation() async throws {
        let row = ElementTarget.element(
            .label("Review PR"),
            .value("Active"),
            .customContent(.match(label: "Category", value: "Work")),
            .customContent(.match(label: "Priority", value: "High")),
            .actions([.custom("Toggle")])
        )

        let heist = try await runHeist("AdversarialDuplicateLabelsPass") {
            try DemoNavigation.openAdversarialScenario("Duplicate Labels")
            CustomAction("Toggle", on: row)
                .expect(.exists(.element(
                    .label("Review PR"),
                    .value("Completed"),
                    .customContent(.match(label: "Category", value: "Work")),
                    .customContent(.match(label: "Priority", value: "High"))
                )), timeout: .seconds(2))
        }

        XCTAssertNil(heist.result.firstFailedStep)
    }

    func testDuplicateLabelsLabelOnlyActionFailsAmbiguous() async throws {
        let failure = try await expectHeistFailure("AdversarialDuplicateLabelsAmbiguousFails") {
            try DemoNavigation.openAdversarialScenario("Duplicate Labels")
            CustomAction("Toggle", on: .label("Review PR"))
        }

        XCTAssertEqual(failure.failedStepKind, .action)
        XCTAssertTrue(failure.description.localizedCaseInsensitiveContains("ambiguous"), failure.description)
    }

    func testDynamicCellsKeepSemanticIdentityAfterChurn() async throws {
        let noodles = ElementTarget.element(
            .label("Nebula Noodles Prime"),
            .customContent(.match(label: "SKU", value: "SKU-72")),
            .customContent(.match(label: "Category", value: "Mains")),
            .customContent(.match(label: "Churn State", value: "post-churn")),
            .customContent(.match(label: "Menu Slot", value: "deep target after churn")),
            .customContent(.match(label: "Unit Price", value: "$18.00")),
            .actions([.custom("Add to Cart")])
        )

        let heist = try await runHeist("AdversarialDynamicCellsPass") {
            try DemoNavigation.openAdversarialScenario("Dynamic Cells")
            Activate(.label("Churn menu"))
                .expect(.exists(.label("Menu churned")), timeout: .seconds(4))
            CustomAction("Add to Cart", on: noodles)
                .expect(.exists(.element(
                    .label("Nebula Noodles Prime"),
                    .customContent(.match(label: "SKU", value: "SKU-72")),
                    .customContent(.match(label: "Churn State", value: "post-churn")),
                    .customContent(.match(label: "Quantity", value: "1")),
                    .customContent(.match(label: "Line Total", value: "$18.00")),
                    .actions([.custom("Remove from Cart")])
                )), timeout: .seconds(6))
        }

        XCTAssertNil(heist.result.firstFailedStep)
    }

    func testDynamicCellsStalePreChurnSemanticTargetFails() async throws {
        let stale = ElementTarget.element(
            .label("Nebula Noodles"),
            .customContent(.match(label: "SKU", value: "SKU-72")),
            .customContent(.match(label: "Churn State", value: "pre-churn")),
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
        let field = ElementTarget.element(.label("Fallback field"), traits: [.textEntry])

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

    func testModalObstructionKeepsActionSurfaceExplicit() async throws {
        let heist = try await runHeist("AdversarialModalObstructionPass") {
            try DemoNavigation.openAdversarialScenario("Modal Obstruction")
            Activate(.label("Review order"))
                .expect(.exists(.label("Order review")), timeout: .seconds(4))
            Activate(.label("Confirm review"))
                .expect(.exists(.label("Status: Review confirmed")), timeout: .seconds(2))
            Activate(.label("Close"))
                .expect(.missing(.label("Order review")), timeout: .seconds(4))
        }

        XCTAssertNil(heist.result.firstFailedStep)
    }

    func testModalObstructionBlocksBackgroundActionSearch() async throws {
        let failure = try await expectHeistFailure("AdversarialModalObstructionBackgroundFails") {
            try DemoNavigation.openAdversarialScenario("Modal Obstruction")
            Activate(.label("Review order"))
                .expect(.exists(.label("Order review")), timeout: .seconds(4))
            Activate(.label("Archive order 100"))
        }
        _ = try? await runHeist("AdversarialModalObstructionCleanup") {
            Activate(.label("Close"))
                .expect(.missing(.label("Order review")), timeout: .seconds(4))
        }

        XCTAssertEqual(failure.failedStepKind, .action)
        XCTAssertNotNil(failure.result.firstFailedStep?.failure)
    }

    func testNestedScrollFindsDeepTarget() async throws {
        let heist = try await runHeist("AdversarialNestedScrollPass") {
            try DemoNavigation.openAdversarialScenario("Nested Scroll")
            Activate(.label("Verified by The Vibe Check"))
                .expect(.exists(.label("Selected Verified")), timeout: .seconds(6))
        }

        XCTAssertNil(heist.result.firstFailedStep)
    }

    func testNestedScrollImpossibleTargetFailsBoundedSearch() async throws {
        let failure = try await expectHeistFailure("AdversarialNestedScrollImpossibleFails") {
            try DemoNavigation.openAdversarialScenario("Nested Scroll")
            Activate(.label("Album That Does Not Exist"))
        }

        XCTAssertEqual(failure.failedStepKind, .action)
        XCTAssertNotNil(failure.result.firstFailedStep?.failure)
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
}

private struct ExpectedFailureDidNotFail: Error {}

#endif // canImport(UIKit)
