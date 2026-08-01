#if canImport(UIKit)
import XCTest

@testable import BHDemo
import ButtonHeistHostedTestSupport
import ButtonHeistTesting
@_spi(AdversarialLab) import ThePlans
@_spi(ButtonHeistInternals) @testable import TheScore

@MainActor
final class KeyboardViewportReplacementTests: XCTestCase {

    func testKeyboardViewportReplacesTheOffscreenFieldAndCommitsOnlyToItsSemanticSuccessor() async throws {
        let heist = try await runAdversarialScenario(
            .keyboardViewportReplacementPass,
            opening: AdversarialLabRoute.open
        )
        XCTAssertNil(heist.result.firstFailedStep)

        let textResult = try XCTUnwrap(
            heist.result.outputNodes.lazy
                .compactMap { $0.actionEvidence?.result }
                .first { $0.method == .typeText }
        )
        let textSubject = try XCTUnwrap(textResult.subjectEvidence)
        XCTAssertEqual(textSubject.source, .textInputTarget)
        XCTAssertEqual(textSubject.element.semantics.assertable.label, "Viewport note")
        XCTAssertTrue(textSubject.element.semantics.assertable.customContent.contains {
            $0.label == "Semantic role" && $0.value == "body"
        })
        XCTAssertEqual(textSubject.resolution.origin, .known)
        XCTAssertTrue(textSubject.resolution.adjustments.contains(.semanticReveal))
        guard case .typeText(let finalValue?) = textResult.payload else {
            return XCTFail("Expected the text interaction payload to contain its final value")
        }
        XCTAssertEqual(finalValue, "admitted viewport text")

        let postInteractionCapture = try XCTUnwrap(
            heist.result.outputNodes.lazy
                .compactMap(\.waitEvidence)
                .compactMap { $0.observation.current?.interface }
                .first { $0.containsElement(
                    label: "Post interaction viewport value",
                    value: "admitted viewport text"
                ) }
        )
        XCTAssertTrue(postInteractionCapture.containsElement(
            label: "Original viewport edits",
            value: "0"
        ))
        XCTAssertTrue(postInteractionCapture.containsElement(
            label: "Replacement viewport value",
            value: "admitted viewport text"
        ))

        let continuation = try XCTUnwrap(
            heist.result.outputNodes.lazy
                .compactMap { $0.actionEvidence?.result }
                .first { result in
                    result.subjectEvidence?.element.semantics.assertable.customContent.contains {
                        $0.label == "Action role" && $0.value == "commit"
                    } == true
                }
        )
        XCTAssertEqual(continuation.subjectEvidence?.source, .resolvedSemanticTarget)
        let finalCapture = try XCTUnwrap(
            heist.result.outputNodes.reversed().lazy
                .compactMap { $0.waitEvidence?.observation.current?.interface }
                .first
        )
        XCTAssertTrue(finalCapture.containsElement(label: "Keyboard continuation actions", value: "1"))
        XCTAssertTrue(finalCapture.containsElement(label: "Decoy continuation actions", value: "0"))
    }

    func testKeyboardViewportAmbiguityFailsBeforeEitherReplacementCanReceiveText() async throws {
        let failure = try await runFailingAdversarialScenario(
            .keyboardViewportAmbiguousReplacementFails,
            opening: AdversarialLabRoute.open
        )
        let failedStep = try XCTUnwrap(failure.result.firstFailedStep)

        XCTAssertEqual(failure.failedStepKind, .action)
        XCTAssertEqual(failure.failedStepPath, "$.body[2]")
        XCTAssertEqual(failedStep.failure?.category, .targetResolution)
        try assertUndispatchedTextFailure(in: failedStep)
        XCTAssertTrue(failedStep.failure?.observed.localizedCaseInsensitiveContains("ambiguous") == true)
        assertUntouchedReplacementFields(in: try XCTUnwrap(failure.result.observedInterfaceAtFailure))
        XCTAssertTrue(failure.result.observedInterfaceAtFailure?.containsElement(
            label: "Viewport replacement mode",
            value: "ambiguous"
        ) == true)
    }

    func testKeyboardViewportIdentityMismatchFailsBeforeTheNonAdmittedFieldCanReceiveText() async throws {
        let failure = try await runFailingAdversarialScenario(
            .keyboardViewportIdentityMismatchFails,
            opening: AdversarialLabRoute.open
        )
        let failedStep = try XCTUnwrap(failure.result.firstFailedStep)

        XCTAssertEqual(failure.failedStepKind, .action)
        XCTAssertEqual(failure.failedStepPath, "$.body[2]")
        XCTAssertEqual(failedStep.failure?.category, .targetResolution)
        try assertUndispatchedTextFailure(in: failedStep)
        XCTAssertTrue(failedStep.failure?.observed.contains("Viewport note") == true)
        let finalInterface = try XCTUnwrap(failure.result.observedInterfaceAtFailure)
        assertUntouchedReplacementFields(in: finalInterface)
        XCTAssertTrue(finalInterface.containsElement(
            label: "Viewport replacement mode",
            value: "mismatched"
        ))
        XCTAssertTrue(finalInterface.containsElement(label: "Mismatched viewport edits", value: "0"))
    }

    private func assertUntouchedReplacementFields(in interface: Interface) {
        XCTAssertTrue(interface.containsElement(label: "Original viewport edits", value: "0"))
        XCTAssertTrue(interface.containsElement(label: "Replacement viewport edits", value: "0"))
        XCTAssertTrue(interface.containsElement(label: "Replacement viewport value", value: ""))
        XCTAssertTrue(interface.containsElement(label: "Ambiguous viewport edits", value: "0, 0"))
        XCTAssertTrue(interface.containsElement(label: "Mismatched viewport edits", value: "0"))
        XCTAssertTrue(interface.containsElement(label: "Post interaction viewport value", value: ""))
    }

    private func assertUndispatchedTextFailure(in failedStep: HeistExecutionStepResult) throws {
        let actionResult = try XCTUnwrap(failedStep.actionEvidence?.result)
        XCTAssertEqual(actionResult.method, .typeText)
        XCTAssertEqual(actionResult.outcome.failureKind, .elementNotFound)
        guard case .typeText(nil) = actionResult.payload else {
            return XCTFail("Text resolution failure must not carry a dispatched text payload")
        }
    }
}

#endif // canImport(UIKit)
