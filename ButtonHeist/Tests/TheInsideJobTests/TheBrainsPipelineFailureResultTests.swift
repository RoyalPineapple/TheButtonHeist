#if canImport(UIKit)
import Foundation
import XCTest
import ThePlans
import UIKit
@testable import AccessibilitySnapshotParser
@testable import TheInsideJob
@testable import TheScore

@MainActor
extension TheBrainsPipelineTests {

    // MARK: - Post-Action Failure Path

    func testActionEvidenceProjectorFailureIncludesAfterObservationTrace() async {
        let beforeScreen = makeScreen(elements: [("Sign In", .button, "button_sign_in")])
        brains.vault.installObservationForTesting(beforeScreen)
        let before = brains.actionEvidenceProjector.projectBaseline()
        let afterScreen = makeScreen(elements: [("Still Here", .button, "button_sign_in")])

        let result = await brains.interactionCoordinator.settleAfterAction(
            dispatchResult: failureOutcome(message: "target disappeared"),
            before: before,
            settleResult: settledResult(finalScreen: afterScreen, outcome: .settled(timeMs: 44))
        )

        XCTAssertFalse(result.outcome.isSuccess)
        XCTAssertEqual(result.method, .activate)
        XCTAssertEqual(result.message, "target disappeared")
        XCTAssertEqual(result.outcome.failureKind, .actionFailed,
                       "Without explicit failureKind, failures default to actionFailed")
        XCTAssertEqual(result.settled, true)
        XCTAssertEqual(result.settleTimeMs, 44)
        XCTAssertEqual(result.accessibilityTrace?.captures.first?.hash, before.capture.hash)
        XCTAssertNotNil(result.accessibilityTrace?.captures.last)
        XCTAssertTrue(result.accessibilityTrace?.changeFacts.contains {
            if case .elementsChanged = $0 { true } else { false }
        } == true)
    }

    func testSemanticStateCaptureProjectsFocusAndWindowSignals() {
        let screen = makeScreen(elements: [("Sign In", .button, "button_sign_in")])
        let windowOwner = NSObject()
        let tripwireSignal = TheTripwire.TripwireSignal(
            topmostVC: nil,
            navigation: .empty,
            windowStack: TheTripwire.WindowStackSignal(windows: [
                TheTripwire.WindowSignal(
                    id: ObjectIdentifier(windowOwner),
                    level: 7,
                    isKeyWindow: true
                ),
            ])
        )

        let state = brains.actionEvidenceProjector.projectBaseline(
            from: screen,
            tripwireSignal: tripwireSignal,
            settledObservationSequence: nil
        )

        XCTAssertEqual(state.capture.context.keyboardVisible, false)
        XCTAssertEqual(state.capture.context.windowStack, [
            AccessibilityTrace.WindowContext(index: 0, level: 7, isKeyWindow: true),
        ])
    }

    func testSemanticStateCaptureProjectsFirstResponderTarget() throws {
        let screen = InterfaceObservation.makeForTests(
            elements: [
                (AccessibilityElement.make(label: "Email", traits: [.textEntry]), "email_field"),
                (AccessibilityElement.make(label: "Submit", traits: [.button]), "submit_button"),
            ],
            firstResponderHeistId: "email_field"
        )

        let state = brains.actionEvidenceProjector.projectBaseline(
            from: screen,
            tripwireSignal: .empty,
            settledObservationSequence: nil
        )

        XCTAssertEqual(
            try XCTUnwrap(state.capture.context.firstResponder),
            AccessibilityTarget.label("Email")
        )
    }

    func testFallbackScreenChangeFinalStateKeepsPersistentVisibleElement() async throws {
        let persistent = AccessibilityElement.make(
            label: "Inbox",
            traits: .staticText,
            respondsToUserInteraction: false
        )
        let beforeScreen = InterfaceObservation.makeForTests(elements: [
            (
                AccessibilityElement.make(
                    label: "Home",
                    traits: .header,
                    respondsToUserInteraction: false
                ),
                HeistId(rawValue: "home_header")
            ),
            (persistent, HeistId(rawValue: "persistent_inbox"))
        ])
        brains.vault.installObservationForTesting(beforeScreen)
        let before = brains.actionEvidenceProjector.projectBaseline()
        let afterScreen = InterfaceObservation.makeForTests(elements: [
            (
                AccessibilityElement.make(
                    label: "Back",
                    traits: .backButton,
                    respondsToUserInteraction: false
                ),
                HeistId(rawValue: "back_button")
            ),
            (
                AccessibilityElement.make(
                    label: "Details",
                    traits: .header,
                    respondsToUserInteraction: false
                ),
                HeistId(rawValue: "details_header")
            ),
            (persistent, HeistId(rawValue: "persistent_inbox"))
        ])

        let result = await brains.interactionCoordinator.settleAfterAction(
            dispatchResult: successOutcome(),
            before: before,
            settleResult: settledResult(finalScreen: afterScreen)
        )

        XCTAssertTrue(result.outcome.isSuccess, result.message ?? "action unexpectedly failed")
        XCTAssertEqual(
            result.accessibilityTrace?.captures.last?.transition.fallbackReason,
            .navigationMarkerChanged
        )
        let labels = try XCTUnwrap(result.accessibilityTrace?.captures.last?.interface.projectedElements)
            .compactMap(\.label)
        XCTAssertTrue(labels.contains("Inbox"), "Persistent visible chrome must survive screen-change final evidence")
    }

    func testCommittedPostActionTraceUsesPublishedContinuity() {
        let before = brains.actionEvidenceProjector.projectBaseline(
            from: makeScreen(elements: [("Home", .header, "home_header")]),
            tripwireSignal: .empty,
            settledObservationSequence: nil
        )
        let finalScreen = makeScreen(elements: [("Details", .header, "details_header")])
        _ = brains.vault.semanticObservationStream.commitVisibleObservationForTesting(finalScreen)
        let sameGenerationEvent = brains.vault.semanticObservationStream.commitVisibleObservationForTesting(finalScreen)
        let observation = ObservationSettlement(
            settleResult: settledResult(finalScreen: finalScreen),
            commitOutcome: .committed(sameGenerationEvent)
        )

        guard case .committed(_, _, let trace) = brains.actionEvidenceProjector.projectResult(
            before: before,
            observation: observation
        ) else {
            return XCTFail("Expected a committed post-action observation")
        }

        XCTAssertEqual(sameGenerationEvent.continuity, .sameGeneration)
        XCTAssertNil(trace.captures.last?.transition.fallbackReason)
    }

    func testPostActionTraceKeepsFinalCaptureContextWithFinalInterface() throws {
        let before = brains.actionEvidenceProjector.projectBaseline(
            from: makeScreen(elements: [("Home", .header, "home_header")]),
            tripwireSignal: .empty,
            settledObservationSequence: nil
        )
        let windowOwner = NSObject()
        let final = brains.actionEvidenceProjector.projectBaseline(
            from: makeScreen(elements: [("Details", .header, "details_header")]),
            tripwireSignal: TheTripwire.TripwireSignal(
                topmostVC: nil,
                navigation: .empty,
                windowStack: TheTripwire.WindowStackSignal(windows: [
                    TheTripwire.WindowSignal(
                        id: ObjectIdentifier(windowOwner),
                        level: 9,
                        isKeyWindow: true
                    ),
                ])
            ),
            settledObservationSequence: nil
        )

        let trace = brains.actionEvidenceProjector.makeAccessibilityTrace(
            afterCapture: final.capture,
            parentCapture: before.capture,
            classification: .sameGeneration
        )

        XCTAssertEqual(try XCTUnwrap(trace.captures.first).context, before.capture.context)
        XCTAssertEqual(try XCTUnwrap(trace.captures.last).context, final.capture.context)
        XCTAssertNotEqual(trace.captures.last?.context, before.capture.context)
    }

    func testActionErrorKindClassifiesTargetUnavailableSeparatelyFromActionIdentity() throws {
        let result = TheSafecracker.ActionDispatchResult.failure(
            .activate,
            message: "target disappeared",
            failureKind: .targetUnavailable
        )

        XCTAssertEqual(
            TheBrains.actionFailureKind(for: try XCTUnwrap(result.failureKind)),
            .elementNotFound
        )
        XCTAssertEqual(result.method, .activate)
    }

    func testActionErrorKindPreservesTreeUnavailableFailureKind() throws {
        let result = TheSafecracker.ActionDispatchResult.failure(
            .activate,
            message: TheBrains.treeUnavailableMessage,
            failureKind: .treeUnavailable
        )

        XCTAssertEqual(
            TheBrains.actionFailureKind(for: try XCTUnwrap(result.failureKind)),
            .accessibilityTreeUnavailable
        )
    }

    func testActionDispatchResultDecoratorsPreserveExistingFieldsAndMergeTiming() throws {
        let element = HeistElement(
            description: "Checkout",
            label: "Checkout",
            value: nil,
            identifier: "checkout_button",
            traits: [.button],
            frameX: 0,
            frameY: 0,
            frameWidth: 100,
            frameHeight: 44,
            actions: [.activate]
        )
        let originalEvidence = ActionSubjectEvidence(
            source: .resolvedSemanticTarget,
            target: try AccessibilityTarget.element(
                .label("Checkout"),
                traits: [.button]
            ).resolve(in: .empty),
            element: element,
            resolution: ActionSubjectResolution(origin: .visible)
        )
        let replacementEvidence = ActionSubjectEvidence(
            source: .elementGestureTarget,
            target: try AccessibilityTarget.identifier("checkout_button").resolve(in: .empty),
            element: element,
            resolution: ActionSubjectResolution(origin: .visible)
        )
        let activationTrace = ActivationTrace(.activationPointFallback(
            axActivateReturned: false,
            tapActivationPoint: ScreenPoint(x: 50, y: 22),
            tapActivationSucceeded: true
        ))
        let success = TheSafecracker.ActionDispatchResult.success(
            payload: .setPasteboard("ok"),
            message: "completed",
            subjectEvidence: originalEvidence,
            resolvedElementId: "checkout_button"
        )
        .withTiming(ActionPerformanceTiming(beforeObservationMs: 5, totalMs: 20))
        .withSubjectEvidence(replacementEvidence)
        .withActivationTrace(activationTrace)
        .withTiming(ActionPerformanceTiming(totalMs: 30))

        XCTAssertTrue(success.success)
        XCTAssertEqual(success.method, .setPasteboard)
        XCTAssertEqual(success.message, "completed")
        XCTAssertEqual(success.payload, .setPasteboard("ok"))
        XCTAssertEqual(success.subjectEvidence, replacementEvidence)
        XCTAssertEqual(success.resolvedElementId, "checkout_button")
        XCTAssertEqual(success.activationTrace, activationTrace)
        XCTAssertEqual(success.timing, ActionPerformanceTiming(
            beforeObservationMs: 5,
            totalMs: 30
        ))

        let failure = TheSafecracker.ActionDispatchResult.failure(
            .activate,
            message: "missing",
            failureKind: .targetUnavailable
        )
        .withActivationTrace(activationTrace)
        .withTiming(ActionPerformanceTiming(targetResolutionMs: 11))

        XCTAssertFalse(failure.success)
        XCTAssertEqual(failure.payload, .activate)
        XCTAssertEqual(failure.activationTrace, activationTrace)
        XCTAssertEqual(failure.timing, ActionPerformanceTiming(targetResolutionMs: 11))
        guard case .targetUnavailable? = failure.failureKind else {
            return XCTFail("Expected targetUnavailable failure kind, got \(String(describing: failure.failureKind))")
        }
    }

    func testActionEvidenceProjectorFailureDoesNotInferNotFoundFromActionIdentity() async {
        let before = brains.actionEvidenceProjector.projectBaseline()

        let result = await brains.interactionCoordinator.settleAfterAction(
            dispatchResult: failureOutcome(),
            before: before,
            settleResult: settledResult(finalScreen: brains.vault.latestObservation)
        )

        XCTAssertEqual(result.outcome.failureKind, .actionFailed)
    }

    func testActionEvidenceProjectorFailureRespectsExplicitErrorKind() async {
        let before = brains.actionEvidenceProjector.projectBaseline()

        let result = await brains.interactionCoordinator.settleAfterAction(
            dispatchResult: failureOutcome(failureKind: .timeout),
            before: before,
            settleResult: settledResult(finalScreen: brains.vault.latestObservation)
        )

        XCTAssertEqual(result.outcome.failureKind, .timeout,
                       "An explicit failureKind must override the method-based inference")
    }

}

#endif
