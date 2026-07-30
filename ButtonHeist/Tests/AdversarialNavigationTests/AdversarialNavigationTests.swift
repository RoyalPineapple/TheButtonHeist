#if canImport(UIKit)
import XCTest

@testable import BHDemo
import ButtonHeistTesting
import TheInsideJob
@_spi(AdversarialLab) import ThePlans
@_spi(ButtonHeistInternals) @testable import TheScore

@MainActor
final class AdversarialNavigationTests: XCTestCase {

    func testModalReviewBecomesInteractiveOnlyAfterPresentationCompletes() async throws {
        let heist = try await runScenario(.modalObstructionPass)
        XCTAssertNil(heist.result.firstFailedStep)
    }

    func testModalObstructionBlocksBackgroundActionSearch() async throws {
        let failure = try await runFailingScenario(.modalObstructionBackgroundFails)
        let failedStep = try XCTUnwrap(failure.result.firstFailedStep)
        let actionResult = try XCTUnwrap(failedStep.actionEvidence?.result)
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
        let heist = try await runScenario(.nestedScrollPass)
        XCTAssertNil(heist.result.firstFailedStep)
        let actionResult = try XCTUnwrap(
            heist.result.outputNodes.lazy
                .compactMap { $0.actionEvidence?.result }
                .first {
                    $0.subjectEvidence?.element.semantics.assertable.label
                        == "Verified by The Vibe Check"
                }
        )
        let subject = try XCTUnwrap(actionResult.subjectEvidence)
        XCTAssertEqual(subject.source, .resolvedSemanticTarget)
        XCTAssertEqual(
            subject.element.semantics.assertable.label,
            "Verified by The Vibe Check"
        )
        XCTAssertEqual(subject.resolution.origin, .discovered)
        XCTAssertTrue(subject.resolution.adjustments.contains(.semanticReveal))
        let activationTrace = try XCTUnwrap(actionResult.activationTrace)
        XCTAssertTrue(
            activationTrace.axActivateReturned == true
                || activationTrace.tapActivationSucceeded == true
        )
        let failure = try await runFailingScenario(.nestedScrollImpossibleFails)
        XCTAssertEqual(failure.failedStepKind, .action)
    }

    func testDuplicateLabelIdentitySurvivesBothViewportDirectionsAndCandidateReordering() async throws {
        let heist = try await runScenario(.duplicateLabelIdentityPass)
        XCTAssertNil(heist.result.firstFailedStep)
    }

    // MARK: - Scenario Execution

    private func runScenario(
        _ scenario: AdversarialScenarioCatalog.Scenario
    ) async throws -> Heist {
        XCTAssertEqual(scenario.expectedOutcome, .commandSucceeds)
        try await AdversarialLabRoute.open(scenario.route)
        return try await runHeist(scenario.plan())
    }

    private func runFailingScenario(
        _ scenario: AdversarialScenarioCatalog.Scenario
    ) async throws -> Heist.Failure {
        XCTAssertEqual(scenario.expectedOutcome, .commandFailsWithDiagnostic)
        try await AdversarialLabRoute.open(scenario.route)
        do {
            _ = try await runHeist(scenario.plan())
            throw ContractError.expectedFailure(scenario)
        } catch let failure as Heist.Failure {
            let diagnostic = try XCTUnwrap(
                scenario.expectedEvidence.first { $0.kind == .diagnostic }?.label
            )
            XCTAssertTrue(failure.description.localizedCaseInsensitiveContains(diagnostic))
            return failure
        }
    }

    private enum ContractError: Error {
        case expectedFailure(AdversarialScenarioCatalog.Scenario)
    }
}
#endif // canImport(UIKit)
