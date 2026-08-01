#if canImport(UIKit)
import XCTest

@testable import BHDemo
import ButtonHeistHostedTestSupport
import ButtonHeistTesting
import TheInsideJob
@_spi(AdversarialLab) import ThePlans
@_spi(ButtonHeistInternals) @testable import TheScore

@MainActor
final class AdversarialMutationTests: XCTestCase {

    func testAsyncRevealNotificationAndSilentVariantsPass() async throws {
        let notificationScenario = AdversarialScenarioCatalog.Scenario.asyncRevealNotificationPass
        let notification = try await runAdversarialScenario(
            .asyncRevealNotificationPass,
            opening: AdversarialLabRoute.open
        )
        let notificationEvidence = try actionEvidence(
            for: .activate(.label("Reveal with notification")),
            in: notification.result
        )
        XCTAssertEqual(
            try notifications(in: notificationEvidence).compactMap(\.text),
            [
                "Async reveal layout updated",
                notificationScenario.expectedEvidence[0].label,
                "Async reveal screen updated",
            ]
        )
        let notificationEvents = try XCTUnwrap(notificationEvidence.result?.observationEvidence).events
        let announcementIndex = try XCTUnwrap(notificationEvents.firstIndex {
            guard case .notification(let notification) = $0 else { return false }
            return notification.text == notificationScenario.expectedEvidence[0].label
        })
        let screenChangeIndex = try XCTUnwrap(notificationEvents.indices.first { index in
            guard index > announcementIndex else { return false }
            if case .screenChanged = notificationEvents[index] { return true }
            return false
        })
        let terminalNoChangeIndex = try XCTUnwrap(notificationEvents.lastIndex(of: .noChange))
        XCTAssertLessThan(announcementIndex, screenChangeIndex)
        XCTAssertLessThan(screenChangeIndex, terminalNoChangeIndex)

        let terminalWait = try waitEvidence(
            for: .exists(.element(.label("Silent terminal state"), .value("Generation 2"))),
            in: notification.result
        )
        let terminalInterface = try XCTUnwrap(terminalWait.observation.current?.interface)
        XCTAssertTrue(terminalInterface.containsElement(
            label: "Silent terminal state",
            value: "Generation 2"
        ))
        XCTAssertTrue(terminalInterface.containsElement(
            label: "Burst notification order: layout, announcement, screen"
        ))
        XCTAssertTrue(terminalWait.observation.events.allSatisfy { event in
            if case .noChange = event { return true }
            return false
        })

        let silent = try await runAdversarialScenario(
            .asyncRevealSilentPass,
            opening: AdversarialLabRoute.open
        )
        let silentEvidence = try actionEvidence(
            for: .activate(.label("Reveal silently")),
            in: silent.result
        )
        XCTAssertTrue(try notifications(in: silentEvidence).compactMap(\.text).isEmpty)
        let failure = try await runFailingAdversarialScenario(
            .asyncRevealWrongDestinationFails,
            opening: AdversarialLabRoute.open
        )
        XCTAssertEqual(failure.failedStepKind, .wait)
        XCTAssertEqual(failure.failedStepPath, "$.body[2]")
        XCTAssertEqual(failure.result.firstFailedStep?.failure?.category, .timeout)
        let finalInterface = try XCTUnwrap(failure.result.observedInterfaceAtFailure)
        XCTAssertTrue(finalInterface.containsElement(label: "Async Reveal"))
        XCTAssertFalse(finalInterface.containsElement(label: "Delayed code: 7429"))
        XCTAssertFalse(finalInterface.containsElement(label: "Delayed code: 9999"))
        let screenshotInterface = try XCTUnwrap(failure.result.failureScreenshotPayload?.interface)
        XCTAssertTrue(screenshotInterface.containsElement(label: "Async Reveal"))
        XCTAssertFalse(screenshotInterface.containsElement(label: "Delayed code: 7429"))
        XCTAssertEqual(screenshotInterface.projectedElements, finalInterface.projectedElements)
    }

    func testPromotedFixtureContracts() async throws {
        let contracts: [(
            success: AdversarialScenarioCatalog.Scenario,
            failure: AdversarialScenarioCatalog.Scenario
        )] = [
            (.offscreenCheckoutPass, .offscreenCheckoutDisabledFails),
            (.textFieldFallbackPass, .textFieldFallbackTargetlessFails),
        ]
        for contract in contracts {
            let success = try await runAdversarialScenario(
                contract.success,
                opening: AdversarialLabRoute.open
            )
            XCTAssertNil(success.result.firstFailedStep)
            let failure = try await runFailingAdversarialScenario(
                contract.failure,
                opening: AdversarialLabRoute.open
            )
            XCTAssertEqual(failure.failedStepKind, .action)
        }
    }

    func testDynamicCellGenerationRefreshReResolvesCurrentTarget() async throws {
        let heist = try await runAdversarialScenario(
            .dynamicCellsPass,
            opening: AdversarialLabRoute.open
        )

        XCTAssertNil(heist.result.firstFailedStep)
    }

    func testDynamicCellGenerationMismatchFailsClosedWithCurrentFailureEvidence() async throws {
        let failure = try await runFailingAdversarialScenario(
            .dynamicCellsStaleTargetFails,
            opening: AdversarialLabRoute.open
        )
        let failedStep = try XCTUnwrap(failure.result.firstFailedStep)
        let actionResult = try XCTUnwrap(failedStep.actionEvidence?.result)

        XCTAssertEqual(failure.failedStepKind, .action)
        XCTAssertEqual(failure.failedStepPath, "$.body[2]")
        XCTAssertEqual(failedStep.failure?.category, .targetResolution)
        XCTAssertEqual(actionResult.outcome, .failure(.elementNotFound))
        XCTAssertNil(actionResult.subjectEvidence)
        XCTAssertTrue(actionResult.message?.contains("element inflation failed [notFound]") == true)
        XCTAssertTrue(failedStep.failure?.observed.contains("Nebula Noodles") == true)

        let screenshotInterface = try XCTUnwrap(failure.result.failureScreenshotPayload?.interface)
        XCTAssertTrue(screenshotInterface.containsElement(label: "Dynamic Cells"))
        XCTAssertTrue(screenshotInterface.containsElement(label: "Menu churned"))
        XCTAssertTrue(screenshotInterface.containsElement(label: "Current target activations: 0"))
    }

    func testStaleLiveObjectReResolvesCurrentTarget() async throws {
        let heist = try await runAdversarialScenario(
            .staleLiveObjectPass,
            opening: AdversarialLabRoute.open
        )
        XCTAssertNil(heist.result.firstFailedStep)
        let failure = try await runFailingAdversarialScenario(
            .staleLiveObjectAmbiguousFails,
            opening: AdversarialLabRoute.open
        )
        let failedStep = try XCTUnwrap(failure.result.firstFailedStep)
        let actionResult = try XCTUnwrap(failedStep.actionEvidence?.result)

        XCTAssertEqual(failure.failedStepKind, .action)
        XCTAssertEqual(failure.failedStepPath, "$.body[3]")
        XCTAssertEqual(failedStep.failure?.category, .targetResolution)
        XCTAssertEqual(actionResult.outcome, .failure(.elementNotFound))
        XCTAssertNil(actionResult.subjectEvidence)
        XCTAssertTrue(actionResult.message?.contains("element inflation failed [ambiguous]") == true)
        XCTAssertTrue(failedStep.failure?.observed.localizedCaseInsensitiveContains("ambiguous") == true)
        XCTAssertTrue(failedStep.failure?.observed.contains("Submit Order") == true)

        let screenshotInterface = try XCTUnwrap(failure.result.failureScreenshotPayload?.interface)
        XCTAssertTrue(screenshotInterface.containsElement(label: "Stale Live Object"))
        XCTAssertTrue(screenshotInterface.containsElement(
            label: "Candidate actions: primary 0, duplicate 0"
        ))
        let candidates = screenshotInterface.projectedElements.filter {
            $0.semantics.assertable.label == "Submit Order"
        }
        XCTAssertEqual(candidates.count, 2)
        XCTAssertTrue(candidates.contains {
            $0.semantics.assertable.value?.contains("Generation 2, actions 0") == true
        })
        XCTAssertTrue(candidates.contains {
            $0.semantics.assertable.value?.contains("Generation 3, actions 0") == true
        })
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

    private func waitEvidence(
        for predicate: AccessibilityPredicate,
        in result: HeistResult,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> HeistExpectationEvidence {
        try XCTUnwrap(
            result.outputNodes.lazy.compactMap(\.waitEvidence)
                .first { $0.predicate == predicate },
            "Missing wait evidence for \(predicate)",
            file: file,
            line: line
        )
    }
}

#endif // canImport(UIKit)
