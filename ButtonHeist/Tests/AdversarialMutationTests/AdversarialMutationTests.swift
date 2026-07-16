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
        try await AdversarialLabRoute.open(.asyncReveal)
        let notification = try await runHeist("AdversarialAsyncRevealNotificationPass") {
            Activate(.label("Reveal with notification"))
                .expect(destination, timeout: 3)
        }
        let notificationReceipt = try actionEvidence(for: notificationCommand, in: notification.result)
        let notificationDispatch = try XCTUnwrap(notificationReceipt.dispatchResult)
        let notificationObservation = try XCTUnwrap(notificationReceipt.expectationResult)
        XCTAssertEqual(notificationDispatch.outcome, .success)
        XCTAssertEqual(notificationObservation.outcome, .success)
        XCTAssertEqual(notificationObservation.method, .wait)
        XCTAssertEqual(notificationReceipt.checkedExpectation?.predicate, destination)
        XCTAssertEqual(notificationReceipt.checkedExpectation?.met, true)
        XCTAssertTrue(notificationReceipt.receiptNotificationKinds.contains(.screenChanged))

        let silentCommand = HeistActionCommand.activate(.label("Reveal silently"))
        try await AdversarialLabRoute.open(.asyncReveal)
        let silent = try await runHeist("AdversarialAsyncRevealSilentPass") {
            Activate(.label("Reveal silently"))
                .expect(destination, timeout: 3)
        }
        let silentReceipt = try actionEvidence(for: silentCommand, in: silent.result)
        let silentDispatch = try XCTUnwrap(silentReceipt.dispatchResult)
        let silentObservation = try XCTUnwrap(silentReceipt.expectationResult)
        XCTAssertEqual(silentDispatch.outcome, .success)
        XCTAssertEqual(silentObservation.outcome, .success)
        XCTAssertEqual(silentObservation.method, .wait)
        XCTAssertEqual(silentReceipt.checkedExpectation?.predicate, destination)
        XCTAssertEqual(silentReceipt.checkedExpectation?.met, true)
        XCTAssertFalse(silentReceipt.receiptNotificationKinds.contains(.screenChanged))
    }

    func testStaleLiveObjectReResolvesCurrentTarget() async throws {
        let beforeValue = "Generation 2, actions 0, generation 1 actions 0"
        let finalValue = "Generation 2, actions 1, generation 1 actions 0"
        try await AdversarialLabRoute.open(.staleLiveObject)
        let heist = try await runHeist("AdversarialStaleLiveObjectPass") {
            Activate(.label("Submit Order"))
                .expect(.exists(.element(
                    .label("Submit Order"),
                    .value(finalValue)
                )), timeout: 4)
        }

        XCTAssertNil(heist.result.firstFailedStep)
        let receipt = try actionEvidence(
            for: .activate(.label("Submit Order")),
            in: heist.result
        )
        let dispatch = try XCTUnwrap(receipt.dispatchResult)
        let subject = try XCTUnwrap(dispatch.subjectEvidence)
        XCTAssertEqual(dispatch.outcome, .success)
        XCTAssertEqual(dispatch.method, .activate)
        XCTAssertEqual(subject.source, .resolvedSemanticTarget)
        XCTAssertEqual(subject.element.label, "Submit Order")
        XCTAssertEqual(subject.element.value, beforeValue)

        let finalElements = try XCTUnwrap(
            receipt.expectationResult?.accessibilityTrace?.captures.last?.interface.projectedElements
        )
        XCTAssertEqual(finalElements.first { $0.label == "Submit Order" }?.value, finalValue)
    }

    private func actionEvidence(
        for command: HeistActionCommand,
        in result: HeistExecutionResult,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> HeistActionEvidence {
        try XCTUnwrap(
            result.outputReceiptNodes.last { $0.actionCommand == command }?.actionEvidence,
            "Missing action receipt for \(command.wireType.rawValue)",
            file: file,
            line: line
        )
    }

}

private extension HeistActionEvidence {
    var receiptNotificationKinds: [AccessibilityNotificationKind] {
        [dispatchResult, expectationResult]
            .compactMap { $0?.accessibilityTrace }
            .flatMap(\.captures)
            .flatMap(\.transition.accessibilityNotifications)
            .map(\.kind)
    }
}

#endif // canImport(UIKit)
