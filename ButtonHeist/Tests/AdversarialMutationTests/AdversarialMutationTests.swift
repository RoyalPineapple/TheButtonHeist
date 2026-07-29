#if canImport(UIKit)
import XCTest

@testable import BHDemo
import ButtonHeistTesting
import TheInsideJob
@_spi(AdversarialLab) import ThePlans
@_spi(ButtonHeistInternals) @testable import TheScore

@MainActor
final class AdversarialMutationTests: XCTestCase {

    func testAsyncRevealNotificationAndSilentVariantsPass() async throws {
        let notificationScenario = AdversarialScenarioCatalog.Scenario.asyncRevealNotificationPass
        let notification = try await runScenario(.asyncRevealNotificationPass)
        let notificationEvidence = try actionEvidence(
            for: .activate(.label("Reveal with notification")),
            in: notification.result
        )
        XCTAssertEqual(
            try notifications(in: notificationEvidence).compactMap(\.text),
            notificationScenario.expectedEvidence.map(\.label)
        )

        let silent = try await runScenario(.asyncRevealSilentPass)
        let silentEvidence = try actionEvidence(
            for: .activate(.label("Reveal silently")),
            in: silent.result
        )
        XCTAssertTrue(try notifications(in: silentEvidence).compactMap(\.text).isEmpty)
        let failure = try await runFailingScenario(.asyncRevealWrongDestinationFails)
        XCTAssertEqual(failure.failedStepKind, .wait)
    }

    func testPromotedFixtureContracts() async throws {
        let contracts: [(
            success: AdversarialScenarioCatalog.Scenario,
            failure: AdversarialScenarioCatalog.Scenario
        )] = [
            (.offscreenCheckoutPass, .offscreenCheckoutDisabledFails),
            (.dynamicCellsPass, .dynamicCellsStaleTargetFails),
            (.textFieldFallbackPass, .textFieldFallbackTargetlessFails),
        ]
        for contract in contracts {
            XCTAssertNil(try await runScenario(contract.success).result.firstFailedStep)
            XCTAssertEqual(try await runFailingScenario(contract.failure).failedStepKind, .action)
        }
    }

    func testStaleLiveObjectReResolvesCurrentTarget() async throws {
        let heist = try await runScenario(.staleLiveObjectPass)
        XCTAssertNil(heist.result.firstFailedStep)
        let failure = try await runFailingScenario(.staleLiveObjectAmbiguousFails)
        XCTAssertEqual(failure.failedStepKind, .action)
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

    // MARK: - Result Evidence

    private func actionEvidence(
        for command: HeistActionCommand,
        in result: HeistResult,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> HeistActionEvidence {
        try XCTUnwrap(
            result.outputNodes.last { $0.actionCommand == command }?.actionEvidence,
            "Missing action evidence for \(command.wireType.rawValue)",
            file: file,
            line: line
        )
    }

    private func notifications(
        in evidence: HeistActionEvidence
    ) throws -> [Observation.Notification] {
        try XCTUnwrap(evidence.result?.observationEvidence).events.compactMap { event in
            guard case .notification(let notification) = event else { return nil }
            return notification
        }
    }

    private enum ContractError: Error {
        case expectedFailure(AdversarialScenarioCatalog.Scenario)
    }
}

#endif // canImport(UIKit)
