#if canImport(UIKit)
import XCTest

import ButtonHeistHostedTestSupport
import ButtonHeistTesting
import ThePlans
@_spi(ButtonHeistInternals) @testable import TheScore

@MainActor
final class AdversarialNavigationTests: XCTestCase {

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
        let row = AccessibilityTarget.element(
            .label("Review PR"),
            .value("Active"),
            .customContent(.init(label: "Category", value: "Work")),
            .customContent(.init(label: "Priority", value: "High")),
            .actions([.custom("Toggle")])
        )

        let heist = try await runHeist("AdversarialDuplicateLabelsPass") {
            try DemoNavigation.openAdversarialScenario("Duplicate Labels")
            CustomAction("Toggle", on: row)
                .expect(.exists(.element(
                    .label("Review PR"),
                    .value("Completed"),
                    .customContent(.init(label: "Category", value: "Work")),
                    .customContent(.init(label: "Priority", value: "High"))
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
