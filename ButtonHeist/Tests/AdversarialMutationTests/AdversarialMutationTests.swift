#if canImport(UIKit)
import XCTest

@testable import BHDemo
import ButtonHeistHostedTestSupport
import ButtonHeistTesting
import ThePlans
@_spi(ButtonHeistInternals) @testable import TheScore

@MainActor
final class AdversarialMutationTests: XCTestCase {

    func testAsyncRevealNotificationAndSilentVariantsPass() async throws {
        let destination: AccessibilityPredicate = .exists(.label("Delayed code: 7429"))
        let notificationCommand = HeistActionCommand.activate(.label("Reveal with notification"))
        try await openScenario(.asyncReveal, readyHeistPath: "AdversarialAsyncRevealNotificationReady")
        let notification = try await runHeist("AdversarialAsyncRevealNotificationPass") {
            Activate(.label("Reveal with notification"))
                .expect(destination, timeout: 3)
        }
        let notificationEvidence = try actionEvidence(for: notificationCommand, in: notification.result)
        let notificationDispatch = try XCTUnwrap(notificationEvidence.dispatchResult)
        let notificationObservation = try XCTUnwrap(notificationEvidence.expectationResult)
        XCTAssertEqual(notificationDispatch.outcome, .success)
        XCTAssertEqual(notificationObservation.outcome, .success)
        XCTAssertEqual(notificationObservation.method, .wait)
        XCTAssertEqual(notificationEvidence.checkedExpectation?.predicate, destination)
        XCTAssertEqual(notificationEvidence.checkedExpectation?.met, true)
        XCTAssertTrue(notificationEvidence.notificationKinds.contains(.screenChanged))

        let silentCommand = HeistActionCommand.activate(.label("Reveal silently"))
        try await openScenario(.asyncReveal, readyHeistPath: "AdversarialAsyncRevealSilentReady")
        let silent = try await runHeist("AdversarialAsyncRevealSilentPass") {
            Activate(.label("Reveal silently"))
                .expect(destination, timeout: 3)
        }
        let silentEvidence = try actionEvidence(for: silentCommand, in: silent.result)
        let silentDispatch = try XCTUnwrap(silentEvidence.dispatchResult)
        let silentObservation = try XCTUnwrap(silentEvidence.expectationResult)
        XCTAssertEqual(silentDispatch.outcome, .success)
        XCTAssertEqual(silentObservation.outcome, .success)
        XCTAssertEqual(silentObservation.method, .wait)
        XCTAssertEqual(silentEvidence.checkedExpectation?.predicate, destination)
        XCTAssertEqual(silentEvidence.checkedExpectation?.met, true)
        XCTAssertFalse(
            silentEvidence.notificationKinds.contains(.screenChanged),
            "Silent trace notifications: \(silentEvidence.notificationEvents)"
        )
    }

    func testStaleLiveObjectReResolvesCurrentTarget() async throws {
        let beforeValue = "Generation 2, actions 0, generation 1 actions 0"
        let finalValue = "Generation 2, actions 1, generation 1 actions 0"
        try await openScenario(.staleLiveObject, readyHeistPath: "AdversarialStaleLiveObjectReady")
        let heist = try await runHeist("AdversarialStaleLiveObjectPass") {
            Activate(.label("Submit Order"))
                .expect(.exists(.element(
                    .label("Submit Order"),
                    .value(finalValue)
                )), timeout: 4)
        }

        XCTAssertNil(heist.result.firstFailedStep)
        let evidence = try actionEvidence(
            for: .activate(.label("Submit Order")),
            in: heist.result
        )
        let dispatch = try XCTUnwrap(evidence.dispatchResult)
        let subject = try XCTUnwrap(dispatch.subjectEvidence)
        XCTAssertEqual(dispatch.outcome, .success)
        XCTAssertEqual(dispatch.method, .activate)
        XCTAssertEqual(subject.source, .resolvedSemanticTarget)
        XCTAssertEqual(subject.element.label, "Submit Order")
        XCTAssertEqual(subject.element.value, beforeValue)

        let finalElements = try XCTUnwrap(
            evidence.expectationResult?.accessibilityTrace?.captures.last?.interface.projectedElements
        )
        XCTAssertEqual(finalElements.first { $0.label == "Submit Order" }?.value, finalValue)
    }

    private func openScenario(
        _ scenario: AdversarialScenario,
        readyHeistPath: HeistDefinitionPath
    ) async throws {
        try await AdversarialLabRoute.open(scenario)
        let ready = try await runHeist(readyHeistPath) {
            WaitFor(.exists(.label(scenario.title)), timeout: 3)
        }
        XCTAssertNil(ready.result.firstFailedStep)
    }

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

}

private extension HeistActionEvidence {
    var notificationEvents: [AccessibilityNotificationEvidence] {
        [dispatchResult, expectationResult]
            .compactMap { $0?.accessibilityTrace }
            .flatMap(\.captures)
            .flatMap(\.transition.accessibilityNotifications)
    }

    var notificationKinds: [AccessibilityNotificationKind] {
        notificationEvents.map(\.kind)
    }
}

#endif // canImport(UIKit)
