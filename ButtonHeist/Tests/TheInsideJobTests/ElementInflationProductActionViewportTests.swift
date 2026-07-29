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
        let result = try XCTUnwrap(heist.result.resultPayload)
        let step = try XCTUnwrap(result.steps.first)
        guard let actionEvidence = step.actionEvidence else {
            return XCTFail("Expected heist action evidence")
        }
        let stepResult = try XCTUnwrap(actionEvidence.result)

        XCTAssertTrue(single.result.outcome.isSuccess, single.result.message ?? "single activate failed")
        XCTAssertTrue(heist.result.outcome.isSuccess, heistFailureDescription(heist.result))
        guard single.result.outcome.isSuccess, heist.result.outcome.isSuccess else { return }
        XCTAssertEqual(single.activationCount, 1)
        XCTAssertEqual(heist.activationCount, 1)
        XCTAssertEqual(step.kind, .action)
        XCTAssertEqual(step.status, .passed)
        XCTAssertEqual(single.result.method, .activate)
        XCTAssertEqual(stepResult.method, .activate)
        XCTAssertEqual(stepResult.outcome.isSuccess, single.result.outcome.isSuccess)
        XCTAssertEqual(stepResult.method, single.result.method)
        XCTAssertEqual(stepResult.outcome.failureKind, single.result.outcome.failureKind)
    }

    func testDirectViewportScrollMovesTheRequestedViewport() async throws {
        let fixture = try installOffscreenActivationFixture(
            identifier: "explicit_scroll_revealed",
            label: "Explicit Scroll Revealed"
        )
        let visible = try XCTUnwrap(brains.vault.refreshLiveCapture())
        _ = await brains.vault.semanticObservationStream
            .commitVisibleObservationForTesting(visible)

        let result = await brains.executeRuntimeAction(
            try HeistActionCommand.scroll(ScrollTarget(
                target: .identifier("visible_anchor_explicit_scroll_revealed"),
                direction: .down
            )).resolve(in: .empty)
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
            let result = await brains.executeHeistPlan(plan)
            return (result, fixture.target.activationCount)
        }

        let result = await brains.executeRuntimeAction(
            try HeistActionCommand.activate(
                .element(.identifier(identifier), traits: [.button])
            ).resolve(in: .empty)
        )
        return (result, fixture.target.activationCount)
    }

    private func heistFailureDescription(_ result: ActionResult) -> String {
        guard let payload = result.resultPayload else {
            return result.message ?? "heist activate failed"
        }
        guard let failedStep = payload.firstFailedStep else {
            return result.message ?? "heist activate failed without a failed result step"
        }
        let actionMessage = failedStep.reportActionResult?.message
        return [
            result.message,
            "failedStep=\(failedStep.path)",
            "kind=\(failedStep.kind.rawValue)",
            failedStep.reportMessage.map { "message=\($0)" },
            actionMessage.map { "actionMessage=\($0)" },
        ]
        .compactMap(\.self)
        .joined(separator: "; ")
    }

}

private extension ActionResult {
    var resultPayload: HeistResult? {
        guard case .heist(let result) = payload else { return nil }
        return result
    }
}

#endif // canImport(UIKit)
