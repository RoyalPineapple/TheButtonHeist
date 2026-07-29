#if canImport(UIKit)
import XCTest
import ThePlans

@testable import AccessibilitySnapshotParser
@testable import TheInsideJob
@_spi(ButtonHeistInternals) @testable import TheScore

@MainActor
extension ElementInflationProductTests {

    // MARK: - Action Equivalence and Viewport Behavior

    func testHeistSemanticActivateMatchesSingleActionResultSemantics() async throws {
        let single = try await runSemanticActivateThroughCommand(
            identifier: "single_semantic_heist_parity",
            label: "Heist Parity Single",
            heist: false
        )
        let heist = try await runSemanticActivateThroughCommand(
            identifier: "heist_semantic_heist_parity",
            label: "Heist Parity Heist",
            heist: true
        )
        XCTAssertTrue(single.result.outcome.isSuccess, single.result.message ?? "single activate failed")
        XCTAssertTrue(heist.result.outcome.isSuccess, heist.result.message ?? "heist activate failed")
        guard single.result.outcome.isSuccess, heist.result.outcome.isSuccess else { return }
        XCTAssertEqual(single.activationCount, 1)
        XCTAssertEqual(heist.activationCount, 1)
        XCTAssertEqual(single.result.method, .activate)
        XCTAssertEqual(heist.result.method, .activate)
        XCTAssertEqual(heist.result.outcome.isSuccess, single.result.outcome.isSuccess)
        XCTAssertEqual(heist.result.outcome.failureKind, single.result.outcome.failureKind)
    }

    func testDirectViewportScrollMovesTheRequestedViewport() async throws {
        let fixture = try installOffscreenActivationFixture(
            identifier: "explicit_scroll_revealed",
            label: "Explicit Scroll Revealed"
        )
        let visible = try await publishedVisibleObservation()
        _ = await brains.vault.semanticObservationStream
            .commitVisibleObservationForTesting(visible)

        let result = await brains.executeRuntimeAction(
            .scroll(ScrollTarget(
                target: .identifier("visible_anchor_explicit_scroll_revealed"),
                direction: .down
            ))
        )

        XCTAssertTrue(result.outcome.isSuccess, result.message ?? "explicit scroll failed")
        XCTAssertEqual(result.method, .scroll)
        XCTAssertGreaterThan(fixture.scrollView.contentOffset.y, 0)
    }

    private func runSemanticActivateThroughCommand(
        identifier: String,
        label: String,
        heist: Bool
    ) async throws -> (result: ActionResult, activationCount: Int) {
        let fixture = try installOffscreenActivationFixture(
            identifier: identifier,
            label: label
        )
        try await seedOffViewportTarget(fixture)

        if heist {
            let plan = try HeistPlan(body: [
                .action(ActionStep(command: .activate(
                    .element(.identifier(identifier), traits: [.button])
                ))),
            ])
            let result = try await brains.executeHeistPlan(plan).get()
            return (
                try XCTUnwrap(result.steps.first?.reportActionResult),
                fixture.target.activationCount
            )
        }

        let result = await brains.executeRuntimeAction(
            .activate(
                .element(.identifier(identifier), traits: [.button])
            )
        )
        return (result, fixture.target.activationCount)
    }

}

#endif // canImport(UIKit)
