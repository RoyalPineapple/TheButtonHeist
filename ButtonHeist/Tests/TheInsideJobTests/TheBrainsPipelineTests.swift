#if canImport(UIKit)
import ButtonHeistSupport
import Foundation
import XCTest
import ThePlans
import UIKit
@testable import AccessibilitySnapshotParser
@testable import TheInsideJob
@testable import TheScore

/// Deterministic tests for post-action observation and exploration behavior
/// that operate purely against the current `InterfaceObservation` snapshot: failure result
/// assembly, wait-change guards, and semantic discovery observation.
///
/// Success-path post-action observation and `exploreScreen` container iteration
/// require a live window and are covered by integration/benchmark runs.
@MainActor
final class TheBrainsPipelineTests: XCTestCase {

    private var brains: TheBrains!

    override func setUp() async throws {
        try await super.setUp()
        brains = TheBrains(tripwire: TheTripwire())
    }

    override func tearDown() async throws {
        brains.stopSemanticObservation()
        brains = nil
        try await super.tearDown()
    }

    // MARK: - Post-Action Failure Path

    func testPostActionObservationFailureIncludesAfterObservationTrace() async {
        let beforeScreen = makeScreen(elements: [("Sign In", .button, "button_sign_in")])
        brains.stash.installScreenForTesting(beforeScreen)
        let before = brains.postActionObservation.captureSemanticState()
        let afterScreen = makeScreen(elements: [("Still Here", .button, "button_sign_in")])

        let result = await brains.interactionObservation.finishAfterAction(
            method: .activate,
            outcome: failureOutcome(),
            message: "target disappeared",
            before: before,
            settleOutcome: settledOutcome(finalScreen: afterScreen, outcome: .settled(timeMs: 44))
        )

        XCTAssertFalse(result.outcome.isSuccess)
        XCTAssertEqual(result.method, .activate)
        XCTAssertEqual(result.message, "target disappeared")
        XCTAssertEqual(result.outcome.errorKind, .actionFailed,
                       "Without explicit errorKind, failures default to actionFailed")
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

        let state = brains.postActionObservation.captureSemanticState(
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

        let state = brains.postActionObservation.captureSemanticState(
            from: screen,
            tripwireSignal: .empty,
            settledObservationSequence: nil
        )

        XCTAssertEqual(
            try XCTUnwrap(state.capture.context.firstResponder),
            literalTarget(ElementPredicate(label: "Email"))
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
        brains.stash.installScreenForTesting(beforeScreen)
        let before = brains.postActionObservation.captureSemanticState()
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

        let result = await brains.interactionObservation.finishAfterAction(
            method: .activate,
            outcome: successOutcome(),
            before: before,
            settleOutcome: settledOutcome(finalScreen: afterScreen)
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

    func testSameGenerationSettledEventDoesNotSuppressActionBaselineScreenChange() {
        let before = brains.postActionObservation.captureSemanticState(
            from: makeScreen(elements: [("Home", .header, "home_header")]),
            tripwireSignal: .empty,
            settledObservationSequence: nil
        )
        let finalScreen = makeScreen(elements: [("Details", .header, "details_header")])
        _ = brains.stash.semanticObservationStream.commitVisibleObservationForTesting(finalScreen)
        let sameGenerationEvent = brains.stash.semanticObservationStream.commitVisibleObservationForTesting(finalScreen)
        let observation = PostActionSettleObservation(
            settle: settledOutcome(finalScreen: finalScreen),
            result: .committed(sameGenerationEvent)
        )

        guard case .committed(_, _, let trace) = brains.postActionObservation.settledObservationResult(
            before: before,
            observation: observation
        ) else {
            return XCTFail("Expected a committed post-action observation")
        }

        XCTAssertEqual(trace.captures.last?.transition.fallbackReason, .primaryHeaderChanged)
    }

    func testActionErrorKindClassifiesTargetUnavailableSeparatelyFromActionIdentity() {
        let result = TheSafecracker.ActionDispatchOutcome.failure(
            .activate,
            message: "target disappeared",
            failureKind: .targetUnavailable
        )

        XCTAssertEqual(TheBrains.actionErrorKind(for: result), .elementNotFound)
        XCTAssertEqual(result.method, .activate)
    }

    func testActionErrorKindPreservesTreeUnavailableFailureKind() {
        let result = TheSafecracker.ActionDispatchOutcome.failure(
            .activate,
            message: TheBrains.treeUnavailableMessage,
            failureKind: .treeUnavailable
        )

        XCTAssertEqual(TheBrains.actionErrorKind(for: result), .accessibilityTreeUnavailable)
    }

    func testActionDispatchOutcomeDecoratorsPreserveExistingFieldsAndMergeTiming() {
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
            target: literalTarget(ElementPredicate(label: "Checkout", traits: [.button])),
            element: element,
            resolution: ActionSubjectResolution(origin: .visible)
        )
        let replacementEvidence = ActionSubjectEvidence(
            source: .elementGestureTarget,
            target: literalTarget(ElementPredicate(identifier: "checkout_button")),
            element: element,
            resolution: ActionSubjectResolution(origin: .visible)
        )
        let activationTrace = ActivationTrace(.activationPointFallback(
            axActivateReturned: false,
            tapActivationPoint: ScreenPoint(x: 50, y: 22),
            tapActivationSucceeded: true
        ))
        let success = TheSafecracker.ActionDispatchOutcome.success(
            payload: .setPasteboard("ok"),
            message: "completed",
            subjectEvidence: originalEvidence,
            resolvedElementId: "checkout_button"
        )
        .withTiming(ActionPerformanceTiming(beforeObservationMs: 5, totalMs: 20))
        .withSubjectEvidence(replacementEvidence)
        .withActivationTrace(activationTrace)
        .withTiming(ActionPerformanceTiming(settleMs: 7, totalMs: 30))

        XCTAssertTrue(success.success)
        XCTAssertEqual(success.method, .setPasteboard)
        XCTAssertEqual(success.message, "completed")
        XCTAssertEqual(success.payload, .setPasteboard("ok"))
        XCTAssertEqual(success.subjectEvidence, replacementEvidence)
        XCTAssertEqual(success.resolvedElementId, "checkout_button")
        XCTAssertEqual(success.activationTrace, activationTrace)
        XCTAssertEqual(success.timing, ActionPerformanceTiming(
            beforeObservationMs: 5,
            settleMs: 7,
            totalMs: 30
        ))

        let failure = TheSafecracker.ActionDispatchOutcome.failure(
            .activate,
            message: "missing",
            failureKind: .targetUnavailable
        )
        .withActivationTrace(activationTrace)
        .withTiming(ActionPerformanceTiming(targetResolutionMs: 11))

        XCTAssertFalse(failure.success)
        XCTAssertNil(failure.payload)
        XCTAssertEqual(failure.activationTrace, activationTrace)
        XCTAssertEqual(failure.timing, ActionPerformanceTiming(targetResolutionMs: 11))
        guard case .targetUnavailable? = failure.failureKind else {
            return XCTFail("Expected targetUnavailable failure kind, got \(String(describing: failure.failureKind))")
        }
    }

    func testPostActionObservationFailureDoesNotInferNotFoundFromActionIdentity() async {
        let before = brains.postActionObservation.captureSemanticState()

        let result = await brains.interactionObservation.finishAfterAction(
            method: .activate,
            outcome: failureOutcome(),
            before: before,
            settleOutcome: settledOutcome(finalScreen: brains.stash.latestObservation)
        )

        XCTAssertEqual(result.outcome.errorKind, .actionFailed)
    }

    func testPostActionObservationFailureRespectsExplicitErrorKind() async {
        let before = brains.postActionObservation.captureSemanticState()

        let result = await brains.interactionObservation.finishAfterAction(
            method: .activate,
            outcome: failureOutcome(errorKind: .timeout),
            before: before,
            settleOutcome: settledOutcome(finalScreen: brains.stash.latestObservation)
        )

        XCTAssertEqual(result.outcome.errorKind, .timeout,
                       "An explicit errorKind must override the method-based inference")
    }

    func testPostActionObservationFailureCarriesValueAndMessage() async {
        let before = brains.postActionObservation.captureSemanticState()

        let result = await brains.interactionObservation.finishAfterAction(
            method: .getPasteboard,
            outcome: failureOutcome(payload: .getPasteboard("")),
            message: "pasteboard empty",
            before: before,
            settleOutcome: settledOutcome(finalScreen: brains.stash.latestObservation)
        )

        XCTAssertEqual(result.message, "pasteboard empty")
        guard case .value(let value) = result.payload else {
            XCTFail("Expected .value payload, got \(String(describing: result.payload))")
            return
        }
        XCTAssertEqual(value, "")
    }

    // MARK: - Post-Action Success Path

    func testAdvertisedActivateNoChangeCanRemainSuccessful() async {
        let frame = CGRect(x: 424, y: 336, width: 928, height: 72)
        let element = AccessibilityElement.make(
            label: "Inert option",
            identifier: "inert_option",
            traits: .none,
            shape: .frame(AccessibilityRect(frame)),
            activationPoint: CGPoint(x: 888, y: 372),
            respondsToUserInteraction: true
        )
        let screen = InterfaceObservation.makeForTests(elements: [(element, HeistId(rawValue: "inert_option"))])
        brains.stash.installScreenForTesting(screen)
        let before = brains.postActionObservation.captureSemanticState()

        let result = await brains.interactionObservation.finishAfterAction(
            method: .activate,
            outcome: successOutcome(
                subjectEvidence: activationSubjectEvidence(
                    target: literalTarget(ElementPredicate(identifier: "inert_option")),
                    element: element,
                    settledObservationSequence: before.settledObservationSequence
                )
            ),
            before: before,
            settleOutcome: settledOutcome(finalScreen: screen)
        )

        XCTAssertTrue(result.outcome.isSuccess, result.message ?? "activate unexpectedly failed")
        XCTAssertEqual(result.method, .activate)
        XCTAssertNil(result.outcome.errorKind)
        XCTAssertNil(result.message)
        XCTAssertNotNil(result.accessibilityTrace)
        XCTAssertEqual(result.accessibilityTrace?.captures.first?.hash, before.capture.hash)
        XCTAssertNotNil(result.accessibilityTrace?.captures.last?.hash)
        XCTAssertEqual(result.accessibilityTrace?.captures.count, 2)
        XCTAssertEqual(result.accessibilityTrace?.changeFacts, [])
    }

    func testViewportPostActionCommitPreservesDiscoveryMemory() async {
        let topScreen = makeScreen(elements: [
            ("Widget 0, Hardware", .button, "top_row"),
            ("Long List", .header, "long_list_header"),
        ])
        brains.stash.installScreenForTesting(topScreen)
        let before = brains.postActionObservation.captureSemanticState()

        let bottomScreen = makeScreen(elements: [
            ("Widget 90, Hardware", .button, "bottom_row"),
            ("Long List", .header, "long_list_header"),
        ])
        let result = await brains.interactionObservation.finishAfterAction(
            method: .scrollToEdge,
            outcome: successOutcome(),
            before: before,
            postActionCommitScope: .discovery,
            settleOutcome: settledOutcome(finalScreen: bottomScreen)
        )

        let labels = Set(brains.stash.interfaceTree.elements.values.compactMap(\.element.label))
        XCTAssertTrue(result.outcome.isSuccess)
        XCTAssertTrue(labels.contains("Widget 0, Hardware"), "Discovery commit should retain the previously observed page")
        XCTAssertTrue(labels.contains("Widget 90, Hardware"), "Discovery commit should include the newly observed page")
    }

    func testSyntheticTapNoChangeCanRemainSuccessful() async {
        let beforeScreen = makeScreen(elements: [("Map", .button, "map_button")])
        brains.stash.installScreenForTesting(beforeScreen)
        let before = brains.postActionObservation.captureSemanticState()

        let result = await brains.interactionObservation.finishAfterAction(
            method: .syntheticTap,
            outcome: successOutcome(),
            before: before,
            settleOutcome: settledOutcome(finalScreen: beforeScreen)
        )

        XCTAssertTrue(result.outcome.isSuccess, result.message ?? "tap unexpectedly failed")
        XCTAssertEqual(result.method, .syntheticTap)
        XCTAssertNil(result.outcome.errorKind)
        XCTAssertEqual(result.accessibilityTrace?.captures.count, 2)
        XCTAssertEqual(result.accessibilityTrace?.changeFacts, [])
    }

    func testActivateNoChangeAfterTapActivationDispatchRemainsSuccessfulAndLegible() async {
        let frame = CGRect(x: 424, y: 336, width: 928, height: 72)
        let element = AccessibilityElement.make(
            label: "Tap activated option",
            identifier: "tap_activated_option",
            traits: .none,
            shape: .frame(AccessibilityRect(frame)),
            activationPoint: CGPoint(x: 888, y: 372),
            respondsToUserInteraction: true
        )
        let screen = InterfaceObservation.makeForTests(elements: [(element, HeistId(rawValue: "tap_activated_option"))])
        brains.stash.installScreenForTesting(screen)
        let before = brains.postActionObservation.captureSemanticState()
        let activationTrace = ActivationTrace(.activationPointFallback(
            axActivateReturned: false,
            tapActivationPoint: ScreenPoint(x: 888, y: 372),
            tapActivationSucceeded: true
        ))

        let result = await brains.interactionObservation.finishAfterAction(
            method: .activate,
            outcome: successOutcome(
                subjectEvidence: activationSubjectEvidence(
                    target: literalTarget(ElementPredicate(identifier: "tap_activated_option")),
                    element: element,
                    settledObservationSequence: before.settledObservationSequence
                ),
                activationTrace: activationTrace
            ),
            before: before,
            settleOutcome: settledOutcome(finalScreen: screen)
        )

        XCTAssertTrue(result.outcome.isSuccess, result.message ?? "activate unexpectedly failed")
        XCTAssertNil(result.outcome.errorKind)
        XCTAssertNil(result.message)
        XCTAssertEqual(result.activationTrace, activationTrace)
        XCTAssertEqual(result.accessibilityTrace?.captures.count, 2)
        XCTAssertEqual(result.accessibilityTrace?.changeFacts, [])
    }

    func testActionResultWithDeltaSuccessReturnsTraceAfterElementChange() async {
        let beforeScreen = makeScreen(elements: [("Total", .staticText, "total")])
        brains.stash.installScreenForTesting(beforeScreen)
        let before = brains.postActionObservation.captureSemanticState()
        let afterScreen = makeScreen(elements: [("Total $12.00", .staticText, "total")])

        let result = await brains.interactionObservation.finishAfterAction(
            method: .activate,
            outcome: successOutcome(),
            before: before,
            settleOutcome: settledOutcome(finalScreen: afterScreen, outcome: .settled(timeMs: 87))
        )

        XCTAssertTrue(result.outcome.isSuccess, result.message ?? "action unexpectedly failed")
        XCTAssertEqual(result.settled, true)
        XCTAssertEqual(result.settleTimeMs, 87)
        XCTAssertNotNil(result.accessibilityTrace)
        XCTAssertNotNil(result.accessibilityTrace?.captures.last)
    }

    func testActionResultWithDeltaPreservesSubjectEvidence() async {
        let beforeScreen = makeScreen(elements: [("Delete", .button, "delete_button")])
        brains.stash.installScreenForTesting(beforeScreen)
        let before = brains.postActionObservation.captureSemanticState()
        let evidence = ActionSubjectEvidence(
            source: .resolvedSemanticTarget,
            target: literalTarget(ElementPredicate(label: "Delete", traits: [.button])),
            element: HeistElement(
                description: "Delete",
                label: "Delete",
                value: nil,
                identifier: "delete_button",
                traits: [.button],
                frameX: 0,
                frameY: 0,
                frameWidth: 100,
                frameHeight: 44,
                actions: [.activate]
            ),
            resolution: ActionSubjectResolution(origin: .visible),
            settledObservationSequence: before.settledObservationSequence
        )

        let result = await brains.interactionObservation.finishAfterAction(
            method: .activate,
            outcome: successOutcome(subjectEvidence: evidence),
            before: before,
            settleOutcome: settledOutcome(finalScreen: beforeScreen)
        )

        XCTAssertTrue(result.outcome.isSuccess, result.message ?? "action unexpectedly failed")
        XCTAssertEqual(result.subjectEvidence, evidence)
    }

    func testActionFailurePreservesResolvedSubjectEvidence() async {
        let beforeScreen = makeScreen(elements: [("Delete", .button, "delete_button")])
        brains.stash.installScreenForTesting(beforeScreen)
        let before = brains.postActionObservation.captureSemanticState()
        let target = literalTarget(ElementPredicate(label: "Delete", traits: [.button]))
        let evidence = ActionSubjectEvidence(
            source: .resolvedSemanticTarget,
            target: target,
            element: HeistElement(
                description: "Delete",
                label: "Delete",
                value: nil,
                identifier: "delete_button",
                traits: [.button],
                frameX: 0,
                frameY: 0,
                frameWidth: 100,
                frameHeight: 44,
                actions: [.activate]
            ),
            resolution: ActionSubjectResolution(
                origin: .known,
                adjustments: [.staleTargetRefresh]
            )
        )

        let result = await brains.interactionObservation.finishAfterAction(
            method: .activate,
            outcome: .failure(.init(
                errorKind: .actionFailed,
                subjectEvidence: evidence
            )),
            before: before,
            settleOutcome: settledOutcome(finalScreen: beforeScreen)
        )

        XCTAssertFalse(result.outcome.isSuccess)
        XCTAssertEqual(result.subjectEvidence, evidence)
    }

    func testPostActionReceiptResolvesDeferredPayloadFromFinalSemanticState() async {
        let beforeScreen = makeScreen(elements: [("Status", .staticText, "status")])
        brains.stash.installScreenForTesting(beforeScreen)
        let before = brains.postActionObservation.captureSemanticState()
        let afterScreen = InterfaceObservation.makeForTests(elements: [
            (
                AccessibilityElement.make(
                    label: "Status",
                    value: "Saved",
                    traits: .staticText,
                    respondsToUserInteraction: false
                ),
                HeistId(rawValue: "status")
            ),
        ])
        let outcome = PostActionObservation.ActionOutcome.success(.init(
            payload: .afterState { state in
                guard let value = state.screen.findElement(heistId: "status")?.element.value else {
                    return .none
                }
                return .payload(.typeText(value))
            }
        ))

        let result = await brains.interactionObservation.finishAfterAction(
            method: .typeText,
            outcome: outcome,
            before: before,
            settleOutcome: settledOutcome(finalScreen: afterScreen)
        )

        XCTAssertTrue(result.outcome.isSuccess)
        XCTAssertEqual(result.method, .typeText)
        XCTAssertEqual(result.payload, .value("Saved"))
    }

    func testPostActionReceiptDoesNotResolveDeferredPayloadFromUnsettledDiagnosticEvidence() async {
        let beforeScreen = makeScreen(elements: [("Status", .staticText, "status")])
        brains.stash.installScreenForTesting(beforeScreen)
        let before = brains.postActionObservation.captureSemanticState()
        let diagnosticScreen = InterfaceObservation.makeForTests(elements: [
            (
                AccessibilityElement.make(
                    label: "Status",
                    value: "Saved",
                    traits: .staticText,
                    respondsToUserInteraction: false
                ),
                HeistId(rawValue: "status")
            ),
        ])
        let outcome = PostActionObservation.ActionOutcome.success(.init(
            payload: .afterState { state in
                guard let value = state.screen.findElement(heistId: "status")?.element.value else {
                    return .none
                }
                return .payload(.typeText(value))
            }
        ))

        let result = await brains.interactionObservation.finishAfterAction(
            method: .typeText,
            outcome: outcome,
            before: before,
            settleOutcome: settledOutcome(
                finalScreen: diagnosticScreen,
                outcome: .timedOut(timeMs: 250)
            )
        )

        XCTAssertTrue(result.outcome.isSuccess)
        XCTAssertEqual(result.method, .typeText)
        XCTAssertNil(result.payload)
        XCTAssertEqual(result.settled, false)
        XCTAssertEqual(
            result.accessibilityTrace?.captures.last?.interface.projectedElements.first?.value,
            "Saved"
        )
    }

    func testTypeTextPayloadUsesCommittedElementIdentity() {
        let selectedId: HeistId = "selected_message"
        let replacementId: HeistId = "replacement_message"
        let afterScreen = InterfaceObservation.makeForTests(elements: [
            (
                AccessibilityElement.make(
                    label: "Message",
                    value: "Selected",
                    traits: .textEntry,
                    respondsToUserInteraction: false
                ),
                selectedId
            ),
            (
                AccessibilityElement.make(
                    label: "Message",
                    value: "Replacement",
                    traits: .textEntry,
                    respondsToUserInteraction: false
                ),
                replacementId
            ),
        ])
        brains.stash.installScreenForTesting(afterScreen)
        let afterState = brains.postActionObservation.captureSemanticState()

        XCTAssertEqual(
            brains.actions.typeTextPayload(resolvedElementId: selectedId, in: afterState),
            .typeText("Selected")
        )
    }

    func testActionResultWithDeltaReportsTypedFallbackScreenChange() async {
        let beforeScreen = makeScreen(elements: [("Menu", .header, "menu_header")])
        brains.stash.installScreenForTesting(beforeScreen)
        let before = brains.postActionObservation.captureSemanticState()
        let afterScreen = makeScreen(elements: [("Checkout", .header, "checkout_header")])

        let result = await brains.interactionObservation.finishAfterAction(
            method: .activate,
            outcome: successOutcome(),
            before: before,
            settleOutcome: settledOutcome(finalScreen: afterScreen)
        )

        XCTAssertTrue(result.outcome.isSuccess, result.message ?? "action unexpectedly failed")
        XCTAssertEqual(
            result.accessibilityTrace?.changeFacts.map(\.kind),
            [.elementsChanged, .screenChanged, .elementsChanged]
        )
        XCTAssertEqual(
            result.accessibilityTrace?.captures.last?.transition.fallbackReason,
            .primaryHeaderChanged
        )
    }

    func testFallbackScreenChangeReceiptPublishesSettledReplacementSurface() async throws {
        let beforeScreen = makeScreen(elements: [
            ("ButtonHeist Demo", .header, "root_header"),
            ("Controls Demo", .button, "controls_demo"),
            ("Todo List", .button, "todo_list"),
            ("Words", .button, "words"),
        ])
        brains.stash.installScreenForTesting(beforeScreen)
        let before = brains.postActionObservation.captureSemanticState()

        let cleanSettledScreen = makeScreen(elements: [
            ("Section A", .header, "section_a_header"),
            ("A acid", .button, "a_acid"),
            ("abacus major", .button, "abacus_major"),
            ("ButtonHeist Demo", .backButton, "back_button"),
        ])
        let result = await brains.interactionObservation.finishAfterAction(
            method: .activate,
            outcome: successOutcome(),
            before: before,
            settleOutcome: settledOutcome(finalScreen: cleanSettledScreen)
        )

        XCTAssertTrue(result.outcome.isSuccess, result.message ?? "action unexpectedly failed")
        XCTAssertEqual(
            result.accessibilityTrace?.changeFacts.map(\.kind),
            [.elementsChanged, .screenChanged, .elementsChanged]
        )
        XCTAssertEqual(
            result.accessibilityTrace?.captures.last?.transition.fallbackReason,
            .navigationMarkerChanged
        )
        let labels = result.accessibilityTrace?.captures.last?.interface.projectedElements.compactMap { $0.label } ?? []
        XCTAssertTrue(labels.contains("Section A"), "Expected new screen labels: \(labels)")
        XCTAssertTrue(labels.contains("A acid"), "Expected new screen labels: \(labels)")
        XCTAssertTrue(labels.contains("abacus major"), "Expected new screen labels: \(labels)")
        XCTAssertTrue(labels.contains("ButtonHeist Demo"), "Expected back button to remain: \(labels)")
        XCTAssertFalse(labels.contains("Controls Demo"))
        XCTAssertFalse(labels.contains("Todo List"))
        XCTAssertEqual(
            brains.stash.interfaceTree.orderedElements.compactMap(\.element.label),
            ["Section A", "A acid", "abacus major", "ButtonHeist Demo"]
        )
    }

    func testGappedElementChangedNotificationReferencesAreRemappedToCommittedScreen() async throws {
        let beforeScreen = makeScreen(elements: [
            ("ButtonHeist Demo", .header, "root_header"),
            ("Controls Demo", .button, "controls_demo"),
            ("Todo List", .button, "todo_list"),
            ("Words", .button, "words"),
        ])
        brains.stash.installScreenForTesting(beforeScreen)
        let before = brains.postActionObservation.captureSemanticState()

        let section = AccessibilityElement.make(
            label: "Section A",
            traits: .header,
            respondsToUserInteraction: false
        )
        let acid = AccessibilityElement.make(
            label: "A acid",
            traits: .button,
            respondsToUserInteraction: false
        )
        let abacus = AccessibilityElement.make(
            label: "abacus major",
            traits: .button,
            respondsToUserInteraction: false
        )
        let back = AccessibilityElement.make(
            label: "ButtonHeist Demo",
            traits: .backButton,
            respondsToUserInteraction: false
        )
        let acidObject = NSObject()
        let cleanSettledScreen = InterfaceObservation.makeForTests([
            .init(section, heistId: "section_a_header"),
            .init(acid, heistId: "a_acid", object: acidObject),
            .init(abacus, heistId: "abacus_major"),
            .init(back, heistId: "back_button"),
        ])
        let notificationWindow = brains.stash.accessibilityNotifications.beginActionWindow()
        defer { notificationWindow.cancel() }
        brains.stash.accessibilityNotifications.record(
            code: 99_999,
            notificationData: .none,
            associatedElement: .none
        )
        brains.stash.accessibilityNotifications.clearPendingEvents()
        brains.stash.accessibilityNotifications.record(
            code: 1001,
            notificationData: CapturedAccessibilityNotificationPayload(acidObject),
            associatedElement: .none
        )

        let result = await brains.interactionObservation.finishAfterAction(
            method: .activate,
            outcome: successOutcome(),
            before: before,
            settleOutcome: settledOutcome(finalScreen: cleanSettledScreen),
            notificationWindow: notificationWindow
        )

        let notification = try XCTUnwrap(
            result.accessibilityTrace?.captures.last?.transition.accessibilityNotifications.first
        )
        XCTAssertEqual(notification.kind, .elementChanged(.layout))
        XCTAssertEqual(
            result.accessibilityTrace?.captures.last?.transition.fallbackReason,
            .navigationMarkerChanged
        )
        guard case .element(let reference) = notification.notificationData else {
            return XCTFail("Expected notification data to resolve to final trace element, got \(notification.notificationData)")
        }
        XCTAssertEqual(reference.path, TreePath([1]))
        XCTAssertEqual(reference.traversalIndex, 1)
        XCTAssertEqual(reference.resolution, .identity)
        XCTAssertEqual(result.accessibilityTrace?.captures.last?.interface.projectedElements[1].label, "A acid")
    }

    func testPassiveSemanticPublishDoesNotDrainPostActionAccessibilityNotifications() async throws {
        let beforeScreen = makeScreen(elements: [("Save", .button, "save")])
        brains.stash.installScreenForTesting(beforeScreen)
        let before = brains.postActionObservation.captureSemanticState()

        let notifiedObject = NSObject()
        let saved = AccessibilityElement.make(
            label: "Saved",
            traits: .staticText,
            respondsToUserInteraction: false
        )
        let finalScreen = InterfaceObservation.makeForTests([
            .init(saved, heistId: "saved", object: notifiedObject),
        ])
        let notificationWindow = brains.stash.accessibilityNotifications.beginActionWindow()
        defer { notificationWindow.cancel() }
        brains.stash.accessibilityNotifications.record(
            code: 1001,
            notificationData: CapturedAccessibilityNotificationPayload(notifiedObject),
            associatedElement: .none
        )

        brains.stash.semanticObservationStream.commitVisibleObservationForTesting(
            makeScreen(elements: [("Passive", .staticText, "passive")])
        )

        let result = await brains.interactionObservation.finishAfterAction(
            method: .activate,
            outcome: successOutcome(),
            before: before,
            settleOutcome: settledOutcome(finalScreen: finalScreen),
            notificationWindow: notificationWindow
        )

        let notification = try XCTUnwrap(
            result.accessibilityTrace?.captures.last?.transition.accessibilityNotifications.first
        )
        guard case .element(let reference) = notification.notificationData else {
            return XCTFail("Expected notification data to survive passive publish, got \(notification.notificationData)")
        }
        XCTAssertEqual(reference.resolution, .identity)
        XCTAssertEqual(result.accessibilityTrace?.captures.last?.interface.projectedElements.first?.label, "Saved")
    }

    func testActionResultFinalTraceUsesVisibleSettleNotLaterDiscovery() async throws {
        let beforeScreen = makeScreen(elements: [("Text Input", .header, "text_input")])
        brains.stash.installScreenForTesting(beforeScreen)
        let before = brains.postActionObservation.captureSemanticState()
        let visibleAfter = makeScreen(elements: [("Controls Demo", .header, "controls_demo")])
        let discoveredOnly = AccessibilityElement.make(
            label: "ButtonHeist Demo",
            traits: .button,
            respondsToUserInteraction: false
        )
        let discoveryAfter = InterfaceObservation.makeForTests(
            elements: [(AccessibilityElement.make(
                label: "Controls Demo",
                traits: .header,
                respondsToUserInteraction: false
                ), HeistId(rawValue: "controls_demo"))],
            offViewport: [
                InterfaceObservation.OffViewportEntry(
                    discoveredOnly,
                    heistId: HeistId(rawValue: "buttonheist_demo"),
                    scrollContainerPath: TreePath([0])
                ),
            ]
        )

        let resultTask = Task { @MainActor in
            await brains.interactionObservation.finishAfterAction(
                method: .activate,
                outcome: successOutcome(),
                before: before,
                settleOutcome: settledOutcome(finalScreen: visibleAfter)
            )
        }

        for _ in 0..<50 where brains.stash.semanticObservationStream.settledWaiterCount == 0 {
            await Task.yield()
        }
        brains.stash.semanticObservationStream.commitDiscoveryObservationForTesting(discoveryAfter)

        let result = await resultTask.value
        XCTAssertTrue(result.outcome.isSuccess, result.message ?? "action unexpectedly failed")

        let labels = try XCTUnwrap(result.accessibilityTrace?.captures.last)
            .interface
            .projectedElements
            .compactMap { $0.label }
        XCTAssertEqual(labels, ["Controls Demo"])
        XCTAssertFalse(labels.contains("ButtonHeist Demo"))
    }

    func testActionResultWithDeltaSettleTimeoutUsesObservedFinalEvidenceWithoutPublishingTruth() async {
        let beforeScreen = makeScreen(elements: [("Save", .button, "save")])
        brains.stash.installScreenForTesting(beforeScreen)
        let before = brains.postActionObservation.captureSemanticState()
        let settledSequence = brains.stash.latestSettledSemanticObservationEvent?.sequence
        let afterScreen = makeScreen(elements: [("Saved", .button, "save")])

        let result = await brains.interactionObservation.finishAfterAction(
            method: .activate,
            outcome: successOutcome(),
            before: before,
            settleOutcome: settledOutcome(finalScreen: afterScreen, outcome: .timedOut(timeMs: 250))
        )

        XCTAssertTrue(result.outcome.isSuccess, result.message ?? "action unexpectedly failed")
        XCTAssertNil(result.message)
        XCTAssertEqual(result.settled, false)
        XCTAssertEqual(result.settleTimeMs, 250)
        XCTAssertEqual(
            brains.stash.latestSettledSemanticObservationEvent?.sequence,
            settledSequence,
            "timeout evidence must not be published as a new settled observation"
        )
        XCTAssertEqual(
            brains.stash.latestSettledSemanticObservationEvent?.observation.screen.orderedElements.first?.element.label,
            "Save"
        )
        XCTAssertTrue(brains.stash.latestSettledSemanticObservationInvalidated)
        XCTAssertEqual(brains.stash.interfaceTree.orderedElements.first?.element.label, "Save")
        XCTAssertEqual(brains.stash.latestFailedSettleDiagnosticEvidence?.orderedElements.first?.element.label, "Saved")
        XCTAssertEqual(result.accessibilityTrace?.captures.count, 2)
        XCTAssertEqual(result.accessibilityTrace?.captures.last?.interface.projectedElements.first?.label, "Saved")
    }

    func testActionBaselineDoesNotPromoteDiagnosticOnlyEvidence() {
        let diagnosticScreen = makeScreen(elements: [("Timeout", .staticText, "timeout")])
        brains.stash.recordFailedSettleDiagnosticEvidence(diagnosticScreen)

        let baseline = brains.interactionObservation.baselineState(from: nil)

        XCTAssertNil(baseline)
        XCTAssertEqual(
            brains.stash.latestFailedSettleDiagnosticEvidence?.orderedElements.first?.element.label,
            "Timeout"
        )
    }

    func testActionResultWithDeltaCancelledSettleFailsActionResult() async {
        let beforeScreen = makeScreen(elements: [("Save", .button, "save")])
        brains.stash.installScreenForTesting(beforeScreen)
        let before = brains.postActionObservation.captureSemanticState()
        let settledSequence = brains.stash.latestSettledSemanticObservationEvent?.sequence

        let result = await brains.interactionObservation.finishAfterAction(
            method: .activate,
            outcome: successOutcome(),
            before: before,
            settleOutcome: settledOutcome(finalScreen: beforeScreen, outcome: .cancelled(timeMs: 125))
        )

        XCTAssertFalse(result.outcome.isSuccess)
        XCTAssertEqual(result.message, "cancelled after 125ms")
        XCTAssertEqual(result.outcome.errorKind, .actionFailed)
        XCTAssertEqual(result.settled, false)
        XCTAssertEqual(result.settleTimeMs, 125)
        XCTAssertEqual(brains.stash.latestSettledSemanticObservationEvent?.sequence, settledSequence)
        XCTAssertTrue(brains.stash.latestSettledSemanticObservationInvalidated)
        XCTAssertEqual(brains.stash.interfaceTree.orderedElements.first?.element.label, "Save")
        XCTAssertEqual(result.accessibilityTrace?.captures.count, 1)
        XCTAssertEqual(result.accessibilityTrace?.captures.first?.interface.projectedElements.first?.label, "Save")
    }

    func testActionResultWithDeltaParseFailureFailsActionResult() async {
        seedScreen(elements: [("Save", .button, "save")])
        let before = brains.postActionObservation.captureSemanticState()
        brains.stash.installScreenForTesting(.empty)

        let result = await brains.interactionObservation.finishAfterAction(
            method: .activate,
            outcome: successOutcome(),
            before: before,
            settleOutcome: settledOutcome(finalScreen: nil, outcome: .timedOut(timeMs: 300))
        )

        XCTAssertFalse(result.outcome.isSuccess)
        XCTAssertEqual(result.message, "Could not parse post-action accessibility tree")
        XCTAssertEqual(result.outcome.errorKind, .actionFailed)
        XCTAssertEqual(result.settled, false)
        XCTAssertEqual(result.settleTimeMs, 300)
        XCTAssertEqual(result.accessibilityTrace?.captures.count, 1)
        XCTAssertEqual(result.accessibilityTrace?.captures.first?.interface.projectedElements.first?.label, "Save")
    }

    // MARK: - Wait Evidence Path

    func testWaitCurrentSuccessUsesSettledObservationEvidence() async throws {
        let isolatedBrains = TheBrains(tripwire: TheTripwire())
        defer { isolatedBrains.stopSemanticObservation() }
        let matchedScreen = InterfaceObservation.makeForTests(elements: [
            (makeElement(label: "Home"), HeistId(rawValue: "home")),
        ])

        let receiptTask = Task { @MainActor in
            await isolatedBrains.interactionObservation.waitForPredicate(WaitStep(
                predicate: .exists(literalTarget(ElementPredicate(label: "Home"))),
                timeout: 1
            ))
        }

        await waitForSettledSemanticWaiter(on: isolatedBrains.stash)
        _ = isolatedBrains.stash.semanticObservationStream.commitDiscoveryObservationForTesting(matchedScreen)

        let receipt = await receiptTask.value
        let trace = try XCTUnwrap(receipt.actionResult.accessibilityTrace)

        XCTAssertTrue(receipt.actionResult.outcome.isSuccess)
        XCTAssertEqual(trace.captures.last?.interface.projectedElements.map(\.label), ["Home"])
        XCTAssertEqual(receipt.expectation.met, true)
    }

    func testWaitCurrentTimeoutWithoutSettledObservationFails() async {
        let isolatedBrains = TheBrains(tripwire: TheTripwire())
        defer { isolatedBrains.stopSemanticObservation() }

        let receipt = await isolatedBrains.interactionObservation.waitForPredicate(WaitStep(
            predicate: .exists(literalTarget(ElementPredicate(label: "Home"))),
            timeout: 0.01
        ))

        XCTAssertFalse(receipt.actionResult.outcome.isSuccess)
        XCTAssertEqual(receipt.actionResult.outcome.errorKind, .timeout)
        XCTAssertEqual(receipt.expectation.met, false)
        XCTAssertTrue(receipt.actionResult.message?.contains("no settled semantic observation available") == true)
    }

    func testWaitSuccessEvidenceUsesSettledObservationTrace() async throws {
        let isolatedBrains = TheBrains(tripwire: TheTripwire())
        defer { isolatedBrains.stopSemanticObservation() }
        let beforeScreen = InterfaceObservation.makeForTests(elements: [
            (makeElement(label: "Before"), HeistId(rawValue: "before")),
        ])
        let matchedScreen = InterfaceObservation.makeForTests(elements: [
            (makeElement(label: "Before"), HeistId(rawValue: "before")),
            (makeElement(label: "Loaded"), HeistId(rawValue: "loaded")),
        ])

        let receiptTask = Task { @MainActor in
            await isolatedBrains.interactionObservation.waitForPredicate(WaitStep(
                predicate: .exists(literalTarget(ElementPredicate(label: "Loaded"))),
                timeout: 1
            ))
        }

        await waitForSettledSemanticWaiter(on: isolatedBrains.stash)
        _ = isolatedBrains.stash.semanticObservationStream.commitDiscoveryObservationForTesting(beforeScreen)
        await waitForSettledSemanticWaiter(on: isolatedBrains.stash)
        _ = isolatedBrains.stash.semanticObservationStream.commitDiscoveryObservationForTesting(matchedScreen)

        let receipt = await receiptTask.value
        let trace = try XCTUnwrap(receipt.actionResult.accessibilityTrace)

        XCTAssertTrue(receipt.actionResult.outcome.isSuccess)
        XCTAssertEqual(trace.captures.first?.interface.projectedElements.map(\.label), ["Before"])
        XCTAssertEqual(trace.captures.last?.interface.projectedElements.map(\.label), ["Before", "Loaded"])
        XCTAssertTrue(trace.changeFacts.contains { if case .elementsChanged = $0 { true } else { false } })
    }

    func testWaitTimeoutEvidenceUsesLastSettledObservationTrace() async throws {
        let isolatedBrains = TheBrains(tripwire: TheTripwire())
        defer { isolatedBrains.stopSemanticObservation() }
        let observedScreen = InterfaceObservation.makeForTests(elements: [
            (makeElement(label: "Known"), HeistId(rawValue: "known")),
        ])

        let receiptTask = Task { @MainActor in
            await isolatedBrains.interactionObservation.waitForPredicate(WaitStep(
                predicate: .exists(literalTarget(ElementPredicate(label: "Missing"))),
                timeout: 0.05
            ))
        }

        await waitForSettledSemanticWaiter(on: isolatedBrains.stash)
        _ = isolatedBrains.stash.semanticObservationStream.commitDiscoveryObservationForTesting(observedScreen)

        let receipt = await receiptTask.value
        let trace = try XCTUnwrap(receipt.actionResult.accessibilityTrace)

        XCTAssertFalse(receipt.actionResult.outcome.isSuccess)
        XCTAssertEqual(receipt.actionResult.outcome.errorKind, .timeout)
        XCTAssertEqual(trace.captures.last?.interface.projectedElements.map(\.label), ["Known"])
        XCTAssertTrue(receipt.actionResult.message?.contains("interface: 1 elements") == true)
        XCTAssertTrue(receipt.actionResult.message?.contains("last result:") == true)
    }

    func testDisappearedWaitRequiresObservedTransitionWhenFinalStateIsAlreadyAbsent() async throws {
        let isolatedBrains = TheBrains(tripwire: TheTripwire())
        defer { isolatedBrains.stopSemanticObservation() }
        let emptyScreen = InterfaceObservation.makeForTests(elements: [])

        let receiptTask = Task { @MainActor in
            await isolatedBrains.interactionObservation.waitForPredicate(WaitStep(
                predicate: .changed(.elements([.disappeared(.label("Loading"))])),
                timeout: 0.05
            ))
        }

        await waitForSettledSemanticWaiter(on: isolatedBrains.stash)
        _ = isolatedBrains.stash.semanticObservationStream.commitDiscoveryObservationForTesting(emptyScreen)

        let receipt = await receiptTask.value

        XCTAssertFalse(receipt.actionResult.outcome.isSuccess)
        XCTAssertEqual(receipt.actionResult.outcome.errorKind, .timeout)
        XCTAssertFalse(receipt.expectation.met)
    }

    func testAppearedWaitRequiresObservedTransitionWhenFinalStateIsAlreadyPresent() async throws {
        let isolatedBrains = TheBrains(tripwire: TheTripwire())
        defer { isolatedBrains.stopSemanticObservation() }
        let readyScreen = InterfaceObservation.makeForTests(elements: [
            (makeElement(label: "Ready"), HeistId(rawValue: "ready")),
        ])

        let receiptTask = Task { @MainActor in
            await isolatedBrains.interactionObservation.waitForPredicate(WaitStep(
                predicate: .changed(.elements([.appeared(.label("Ready"))])),
                timeout: 0.05
            ))
        }

        await waitForSettledSemanticWaiter(on: isolatedBrains.stash)
        _ = isolatedBrains.stash.semanticObservationStream.commitDiscoveryObservationForTesting(readyScreen)

        let receipt = await receiptTask.value

        XCTAssertFalse(receipt.actionResult.outcome.isSuccess)
        XCTAssertEqual(receipt.actionResult.outcome.errorKind, .timeout)
        XCTAssertFalse(receipt.expectation.met)
    }

    func testUpdatedWaitRequiresObservedTransitionWhenFinalStateAlreadyMatches() async throws {
        let isolatedBrains = TheBrains(tripwire: TheTripwire())
        defer { isolatedBrains.stopSemanticObservation() }
        let quantity = AccessibilityElement.make(
            label: "Quantity",
            value: "3",
            traits: .staticText,
            respondsToUserInteraction: false
        )
        let quantityScreen = InterfaceObservation.makeForTests(elements: [
            (quantity, HeistId(rawValue: "quantity")),
        ])

        let receiptTask = Task { @MainActor in
            await isolatedBrains.interactionObservation.waitForPredicate(WaitStep(
                predicate: .changed(.elements([.updated(.label("Quantity"), .value("3"))])),
                timeout: 0.05
            ))
        }

        await waitForSettledSemanticWaiter(on: isolatedBrains.stash)
        _ = isolatedBrains.stash.semanticObservationStream.commitDiscoveryObservationForTesting(quantityScreen)

        let receipt = await receiptTask.value

        XCTAssertFalse(receipt.actionResult.outcome.isSuccess)
        XCTAssertEqual(receipt.actionResult.outcome.errorKind, .timeout)
        XCTAssertFalse(receipt.expectation.met)
    }

    func testFromToUpdatedWaitRequiresObservedTransitionWhenFinalStateAlreadyMatches() async throws {
        let isolatedBrains = TheBrains(tripwire: TheTripwire())
        defer { isolatedBrains.stopSemanticObservation() }
        let quantity = AccessibilityElement.make(
            label: "Quantity",
            value: "3",
            traits: .staticText,
            respondsToUserInteraction: false
        )
        let quantityScreen = InterfaceObservation.makeForTests(elements: [
            (quantity, HeistId(rawValue: "quantity")),
        ])

        let receiptTask = Task { @MainActor in
            await isolatedBrains.interactionObservation.waitForPredicate(WaitStep(
                predicate: .changed(.elements([.updated(
                    .label("Quantity"),
                    .value(before: "2", after: "3")
                )])),
                timeout: 0.05
            ))
        }

        await waitForSettledSemanticWaiter(on: isolatedBrains.stash)
        _ = isolatedBrains.stash.semanticObservationStream.commitDiscoveryObservationForTesting(quantityScreen)

        let receipt = await receiptTask.value

        XCTAssertFalse(receipt.actionResult.outcome.isSuccess)
        XCTAssertEqual(receipt.actionResult.outcome.errorKind, .timeout)
        XCTAssertEqual(receipt.expectation.met, false)
    }

    func testDisappearedWaitSucceedsWhenTransitionIsObserved() async throws {
        let isolatedBrains = TheBrains(tripwire: TheTripwire())
        defer { isolatedBrains.stopSemanticObservation() }
        let loadingScreen = InterfaceObservation.makeForTests(elements: [
            (makeElement(label: "Loading"), HeistId(rawValue: "loading")),
        ])
        let emptyScreen = InterfaceObservation.makeForTests(elements: [])

        let receiptTask = Task { @MainActor in
            await isolatedBrains.interactionObservation.waitForPredicate(WaitStep(
                predicate: .changed(.elements([.disappeared(.label("Loading"))])),
                timeout: 1
            ))
        }

        await waitForSettledSemanticWaiter(on: isolatedBrains.stash)
        _ = isolatedBrains.stash.semanticObservationStream.commitDiscoveryObservationForTesting(loadingScreen)
        await waitForSettledSemanticWaiter(on: isolatedBrains.stash)
        _ = isolatedBrains.stash.semanticObservationStream.commitDiscoveryObservationForTesting(
            emptyScreen,
            notificationBatch: notificationBatch(kind: .screenChanged)
        )

        let receipt = await receiptTask.value

        XCTAssertTrue(receipt.actionResult.outcome.isSuccess)
        XCTAssertEqual(receipt.expectation.met, true)
    }

    func testPredicatePollingEngineKeepsVisibleTicksBetweenDiscoveryProbes() async {
        let predicate = AccessibilityPredicate<RootContext>.exists(literalTarget(ElementPredicate(label: "Never")))
        var observedScopes: [SemanticObservationScope] = []
        var sequence: SettledObservationSequence = 0
        let engine = PredicatePollingEngine<ExpectationResult> { scope, _, _ in
            observedScopes.append(scope)
            sequence += 1
            return self.pollingObservation(
                label: scope == .visible ? "Visible" : "Discovery-\(sequence.rawValue)",
                scope: scope,
                sequence: sequence
            )
        }

        let result = await engine.poll(
            scope: .discovery,
            timeout: 0.25,
            evaluate: { observation in
                PredicateEvaluation.evaluate(predicate, in: observation)
            },
            isMatched: \.met
        )

        XCTAssertFalse(result.last?.evaluation.met ?? true)
        XCTAssertEqual(observedScopes.prefix(2), [.visible, .discovery])
        XCTAssertEqual(observedScopes.filter { $0 == .discovery }.count, 1)
        XCTAssertGreaterThanOrEqual(observedScopes.filter { $0 == .visible }.count, 2)
    }

    func testPredicatePollingEngineReturnsVisibleMatchBeforeDiscoveryProbe() async {
        let predicate = AccessibilityPredicate<RootContext>.exists(literalTarget(ElementPredicate(label: "Ready")))
        var observedScopes: [SemanticObservationScope] = []
        var sequence: SettledObservationSequence = 1
        let engine = PredicatePollingEngine<ExpectationResult> { scope, _, _ in
            observedScopes.append(scope)
            sequence += 1
            return self.pollingObservation(
                label: scope == .visible ? "Ready" : "Discovery",
                scope: scope,
                sequence: sequence
            )
        }

        let result = await engine.poll(
            scope: .discovery,
            timeout: 1,
            after: 1,
            initialVisibleFingerprint: .known("previous-visible-fingerprint"),
            discoveryBootstrap: .afterInitialDiscoveryAttempt,
            evaluate: { observation in
                PredicateEvaluation.evaluate(predicate, in: observation)
            },
            isMatched: \.met
        )

        XCTAssertTrue(result.last?.evaluation.met == true)
        XCTAssertEqual(observedScopes, [.visible])
    }

    func testPredicatePollingEngineDefersDiscoveryAfterInitialDiscoveryAttempt() async {
        let predicate = AccessibilityPredicate<RootContext>.exists(literalTarget(ElementPredicate(label: "Ready")))
        var observedScopes: [SemanticObservationScope] = []
        var observedTimeouts: [Double?] = []
        var sequence: SettledObservationSequence = 1
        let engine = PredicatePollingEngine<ExpectationResult> { scope, _, timeout in
            observedScopes.append(scope)
            observedTimeouts.append(timeout)
            guard scope == .discovery else { return nil }
            sequence += 1
            return self.pollingObservation(
                label: "Still Loading",
                scope: scope,
                sequence: sequence
            )
        }

        let result = await engine.poll(
            scope: .discovery,
            timeout: 0.25,
            after: 1,
            initialVisibleFingerprint: .known("visible-seed"),
            discoveryBootstrap: .afterInitialDiscoveryAttempt,
            evaluate: { observation in
                PredicateEvaluation.evaluate(predicate, in: observation)
            },
            isMatched: \.met
        )

        XCTAssertNil(result.last)
        XCTAssertFalse(observedScopes.contains(.discovery))
        XCTAssertEqual(observedTimeouts.first.flatMap { $0 }, 0)
    }

    func testPredicateWaitStartsWithDiscoveryThenUsesVisibleTicks() async {
        let predicate = AccessibilityPredicate<RootContext>.exists(literalTarget(ElementPredicate(label: "Ready")))
        var observedScopes: [SemanticObservationScope] = []
        var sequence: SettledObservationSequence = 0
        let wait = PredicateWait(
            observeEvent: { scope, _, _ in
                observedScopes.append(scope)
                sequence += 1
                return self.pollingObservation(
                    label: scope == .discovery ? "Loading" : "Ready",
                    scope: scope,
                    sequence: sequence
                ).event
            },
            latestEvent: { nil },
            latestSettleFailure: { nil },
            semanticObservation: { event in
                self.brains.postActionObservation.semanticObservation(from: event)
            },
            presenceTimeoutMessage: { _, _ in nil },
            announcementCursor: { _ in .origin },
            waitForAnnouncement: { _, _, _ in nil }
        )

        let receipt = await wait.wait(
            for: WaitStep(predicate: predicate, timeout: 1)
        )

        XCTAssertTrue(receipt.actionResult.outcome.isSuccess)
        XCTAssertTrue(receipt.expectation.met)
        XCTAssertEqual(Array(observedScopes.prefix(2)), [.discovery, .visible])
    }

    func testPredicateWaitReturnsFromInitialDiscoveryMatch() async {
        let predicate = AccessibilityPredicate<RootContext>.exists(literalTarget(ElementPredicate(label: "Ready")))
        var observedScopes: [SemanticObservationScope] = []
        var sequence: SettledObservationSequence = 0
        let wait = PredicateWait(
            observeEvent: { scope, _, _ in
                observedScopes.append(scope)
                sequence += 1
                return self.pollingObservation(
                    label: "Ready",
                    scope: scope,
                    sequence: sequence
                ).event
            },
            latestEvent: { nil },
            latestSettleFailure: { nil },
            semanticObservation: { event in
                self.brains.postActionObservation.semanticObservation(from: event)
            },
            presenceTimeoutMessage: { _, _ in nil },
            announcementCursor: { _ in .origin },
            waitForAnnouncement: { _, _, _ in nil }
        )

        let receipt = await wait.wait(
            for: WaitStep(predicate: predicate, timeout: 1)
        )

        XCTAssertTrue(receipt.actionResult.outcome.isSuccess)
        XCTAssertTrue(receipt.expectation.met)
        XCTAssertEqual(observedScopes, [.discovery])
    }

    func testPredicateWaitAcceptsSatisfiedChangeFromInitialTraceBeforeObserving() async {
        let before = brains.postActionObservation.captureSemanticState(
            from: makeScreen(elements: [
                ("Checkout", .staticText, "checkout"),
            ]),
            tripwireSignal: .empty,
            settledObservationSequence: 41
        )
        let after = brains.postActionObservation.captureSemanticState(
            from: makeScreen(elements: [
                ("Checkout", .staticText, "checkout"),
                ("More", .button, "more"),
            ]),
            tripwireSignal: .empty,
            settledObservationSequence: 42
        )
        let initialTrace = AccessibilityTrace(captures: [before.capture, after.capture])
        var didObserve = false
        let staleObservation = makeStaleObservation(from: before, sequence: 42)
        let wait = PredicateWait(
            observeEvent: { _, _, _ in
                didObserve = true
                return staleObservation.event
            },
            latestEvent: { nil },
            latestSettleFailure: { nil },
            semanticObservation: { event in
                event.sequence == staleObservation.event.sequence
                    ? staleObservation
                    : self.brains.postActionObservation.semanticObservation(from: event)
            },
            presenceTimeoutMessage: { _, _ in nil },
            announcementCursor: { _ in .origin },
            waitForAnnouncement: { _, _, _ in nil }
        )

        let receipt = await wait.wait(
            for: WaitStep(predicate: .changed(.elements()), timeout: 0),
            initialTrace: initialTrace
        )

        XCTAssertTrue(receipt.actionResult.outcome.isSuccess)
        XCTAssertTrue(receipt.expectation.met)
        XCTAssertFalse(didObserve)
        XCTAssertTrue(receipt.actionResult.accessibilityTrace?.changeFacts.contains {
            if case .elementsChanged = $0 { true } else { false }
        } == true)
    }

    func testPredicateWaitMatchesChangeFromSuppliedBaselineAndNextObservation() async {
        let before = brains.postActionObservation.captureSemanticState(
            from: makeScreen(elements: [
                ("Volume", .adjustable, "volume"),
            ]),
            tripwireSignal: .empty,
            settledObservationSequence: 1
        )
        let after = brains.postActionObservation.captureSemanticState(
            from: makeScreen(elements: [
                ("Volume 60", .adjustable, "volume"),
            ]),
            tripwireSignal: .empty,
            settledObservationSequence: 2
        )
        let afterObservation = makeStaleObservation(from: after, sequence: 2)
        let baselineTrace = AccessibilityTrace(capture: before.capture)
        var observedAfterSequence: SettledObservationSequence?
        let wait = PredicateWait(
            observeEvent: { _, after, _ in
                observedAfterSequence = after
                return afterObservation.event
            },
            latestEvent: { nil },
            latestSettleFailure: { nil },
            semanticObservation: { event in
                event.sequence == afterObservation.event.sequence
                    ? afterObservation
                    : self.brains.postActionObservation.semanticObservation(from: event)
            },
            presenceTimeoutMessage: { _, _ in nil },
            announcementCursor: { _ in .origin },
            waitForAnnouncement: { _, _, _ in nil }
        )

        let receipt = await wait.wait(
            for: WaitStep(predicate: .changed(.elements()), timeout: 1),
            initialTrace: baselineTrace,
            after: 1
        )

        XCTAssertTrue(receipt.actionResult.outcome.isSuccess)
        XCTAssertTrue(receipt.expectation.met)
        XCTAssertEqual(observedAfterSequence, 1)
        XCTAssertTrue(receipt.actionResult.accessibilityTrace?.changeFacts.contains {
            if case .elementsChanged = $0 { true } else { false }
        } == true)
    }

    func testPredicateWaitPreservesSuppliedScreenChangeUntilDestinationAssertionAppears() async {
        let before = brains.postActionObservation.captureSemanticState(
            from: makeScreen(elements: [("ButtonHeist Demo", .header, "root")]),
            tripwireSignal: .empty,
            settledObservationSequence: 1
        )
        let actionEndpoint = brains.postActionObservation.captureSemanticState(
            from: makeScreen(elements: [("Order Summary", .header, "summary")]),
            tripwireSignal: .empty,
            settledObservationSequence: 2
        )
        let screenChanged = AccessibilityNotificationEvidence(
            sequence: 1,
            kind: .screenChanged,
            timestamp: Date(timeIntervalSince1970: 0),
            notificationData: .none,
            associatedElement: .none
        )
        let actionEndpointCapture = AccessibilityTrace.Capture(
            sequence: 2,
            interface: actionEndpoint.interface,
            transition: AccessibilityTrace.Transition(accessibilityNotifications: [screenChanged])
        )
        let actionTrace = AccessibilityTrace(captures: [before.capture, actionEndpointCapture])
        let destination = brains.postActionObservation.captureSemanticState(
            from: makeScreen(elements: [
                ("Order Summary", .header, "summary"),
                ("Menu", .header, "menu"),
            ]),
            tripwireSignal: .empty,
            settledObservationSequence: 3
        )
        let destinationObservation = makeStaleObservation(from: destination, sequence: 3)
        let wait = PredicateWait(
            observeEvent: { _, _, _ in destinationObservation.event },
            latestEvent: { nil },
            latestSettleFailure: { nil },
            semanticObservation: { event in
                event.sequence == destinationObservation.event.sequence
                    ? destinationObservation
                    : self.brains.postActionObservation.semanticObservation(from: event)
            },
            presenceTimeoutMessage: { _, _ in nil },
            announcementCursor: { _ in .origin },
            waitForAnnouncement: { _, _, _ in nil }
        )

        let receipt = await wait.wait(
            for: WaitStep(
                predicate: .changed(.screen([.exists(.label("Menu"))])),
                timeout: 0
            ),
            initialTrace: actionTrace
        )

        XCTAssertTrue(receipt.actionResult.outcome.isSuccess)
        XCTAssertTrue(receipt.expectation.met)
        XCTAssertEqual(receipt.actionResult.accessibilityTrace?.captures.last?.interface.projectedElements.last?.label, "Menu")
        XCTAssertTrue(receipt.actionResult.accessibilityTrace?.changeFacts.contains {
            if case .screenChanged = $0 { true } else { false }
        } == true)
    }

    func testPredicateWaitPreservesActionBaselineWhenCaptureIsNotInObservationHistory() async throws {
        let beforeScreen = volumeScreen(value: "50%")
        let afterScreen = volumeScreen(value: "60%")
        _ = brains.stash.semanticObservationStream.commitDiscoveryObservationForTesting(beforeScreen)
        let afterEvent = brains.stash.semanticObservationStream.commitDiscoveryObservationForTesting(afterScreen)
        let actionBaseline = AccessibilityTrace.Capture(
            sequence: 1,
            interface: brains.stash.discoveryInterfaceWithHash(
                for: volumeScreen(value: "40%")
            ).interface,
            hash: "sha256:unmatched-post-transition-capture"
        )
        let staleActionTrace = AccessibilityTrace(captures: [actionBaseline, actionBaseline])
        let wait = PredicateWait(
            observeEvent: { _, _, _ in afterEvent },
            latestEvent: { nil },
            latestSettleFailure: { nil },
            semanticObservation: { event in
                self.brains.postActionObservation.semanticObservation(from: event)
            },
            presenceTimeoutMessage: { _, _ in nil },
            announcementCursor: { _ in .origin },
            waitForAnnouncement: { _, _, _ in nil }
        )

        let receipt = await wait.wait(
            for: WaitStep(predicate: .changed(.elements()), timeout: 0),
            initialTrace: staleActionTrace
        )

        XCTAssertTrue(receipt.actionResult.outcome.isSuccess)
        XCTAssertTrue(receipt.expectation.met)
        XCTAssertEqual(receipt.actionResult.accessibilityTrace?.captures.first?.hash, actionBaseline.hash)
        XCTAssertTrue(receipt.actionResult.accessibilityTrace?.changeFacts.contains {
            if case .elementsChanged = $0 { true } else { false }
        } == true)
    }

    func testObservationWindowRetainsFastRoundTripTransition() throws {
        let baselineEvent = brains.stash.semanticObservationStream.commitDiscoveryObservationForTesting(
            volumeScreen(value: "50%")
        )
        _ = brains.stash.semanticObservationStream.commitDiscoveryObservationForTesting(
            volumeScreen(value: "60%")
        )
        let finalEvent = brains.stash.semanticObservationStream.commitDiscoveryObservationForTesting(
            volumeScreen(value: "50%")
        )
        let baseline = try XCTUnwrap(baselineEvent.settledCapture)
        let window = try XCTUnwrap(brains.stash.semanticObservationStream.observationWindow(
            from: baseline,
            through: finalEvent
        ))

        XCTAssertEqual(window.completeness, .complete)
        XCTAssertEqual(window.trace.captures.count, 3)
        XCTAssertEqual(window.trace.changeFacts.count, 2)
        XCTAssertTrue(window.trace.changeFacts.allSatisfy {
            if case .elementsChanged = $0 { return true }
            return false
        })
    }

    func testObservationWindowExtendsSuppliedTraceFromMatchingEndpoint() throws {
        let baselineEvent = brains.stash.semanticObservationStream.commitDiscoveryObservationForTesting(
            volumeScreen(value: "50%")
        )
        let actionEndpointEvent = brains.stash.semanticObservationStream.commitDiscoveryObservationForTesting(
            volumeScreen(value: "60%")
        )
        _ = brains.stash.semanticObservationStream.commitDiscoveryObservationForTesting(
            volumeScreen(value: "70%")
        )
        let finalEvent = brains.stash.semanticObservationStream.commitDiscoveryObservationForTesting(
            volumeScreen(value: "80%")
        )
        let baseline = try XCTUnwrap(baselineEvent.settledCapture)
        let actionEndpoint = try XCTUnwrap(actionEndpointEvent.settledCapture)
        let window = try XCTUnwrap(brains.stash.semanticObservationStream.observationWindow(
            from: baseline,
            through: finalEvent
        ))
        let suppliedTrace = AccessibilityTrace(captures: [baseline.capture, actionEndpoint.capture])

        let extended = window.preserving(suppliedTrace).trace

        XCTAssertEqual(extended.captures.map(\.hash), window.trace.captures.map(\.hash))
        XCTAssertEqual(extended.changeFacts.count, 3)
    }

    func testCompleteObservationWindowProducesUnchangedProof() throws {
        let baselineEvent = brains.stash.semanticObservationStream.commitDiscoveryObservationForTesting(
            volumeScreen(value: "50%")
        )
        let currentEvent = brains.stash.semanticObservationStream.commitDiscoveryObservationForTesting(
            volumeScreen(value: "50%")
        )
        let baseline = try XCTUnwrap(baselineEvent.settledCapture)
        let window = try XCTUnwrap(brains.stash.semanticObservationStream.observationWindow(
            from: baseline,
            through: currentEvent
        ))

        XCTAssertEqual(window.completeness, .complete)
        XCTAssertTrue(window.trace.changeFacts.isEmpty)

        let observation = brains.postActionObservation.semanticObservation(from: currentEvent)
        let predicateResult = PredicateObservationEvidence(
            observation: observation,
            baseline: baseline,
            window: window
        ).evaluate(.noChange)
        XCTAssertTrue(predicateResult.met)

        let receipt = predicateWaitForReceiptProofTests().waitReceipt(
            for: ResolvedWaitStep(predicate: .noChange, timeout: 0),
            trace: window.trace,
            observationSummary: observation.summary,
            expectation: predicateResult,
            start: CFAbsoluteTimeGetCurrent(),
            success: true,
            baseline: baseline,
            window: window,
            observedSequence: currentEvent.sequence
        )

        XCTAssertEqual(receipt.traceEvidence?.completeness, .complete)
        XCTAssertEqual(receipt.actionResult.traceEvidence?.completeness, .complete)
        XCTAssertTrue(AccessibilityPredicate<RootContext>.noChange.validate(against: receipt.actionResult).met)
    }

    func testIncompleteObservationWindowDoesNotProduceUnchangedVerdict() throws {
        let baselineEvent = brains.stash.semanticObservationStream.commitDiscoveryObservationForTesting(
            volumeScreen(value: "50%")
        )
        let baseline = try XCTUnwrap(baselineEvent.settledCapture)
        brains.stash.semanticObservationStream.clearSettledObservationHistory()
        let currentEvent = brains.stash.semanticObservationStream.commitDiscoveryObservationForTesting(
            volumeScreen(value: "50%")
        )
        let window = try XCTUnwrap(brains.stash.semanticObservationStream.observationWindow(
            from: baseline,
            through: currentEvent
        ))

        guard case .incomplete = window.completeness else {
            return XCTFail("Expected generation reset to make the window incomplete")
        }
        XCTAssertTrue(window.trace.changeFacts.isEmpty)

        let observation = brains.postActionObservation.semanticObservation(from: currentEvent)
        let predicateResult = PredicateObservationEvidence(
            observation: observation,
            baseline: baseline,
            window: window
        ).evaluate(.noChange)
        XCTAssertFalse(predicateResult.met)
        XCTAssertEqual(predicateResult.actual, "observation history incomplete")

        let receipt = predicateWaitForReceiptProofTests().waitReceipt(
            for: ResolvedWaitStep(predicate: .noChange, timeout: 0),
            trace: window.trace,
            observationSummary: observation.summary,
            expectation: predicateResult,
            start: CFAbsoluteTimeGetCurrent(),
            success: false,
            baseline: baseline,
            window: window,
            observedSequence: currentEvent.sequence
        )
        let laterValidation = AccessibilityPredicate<RootContext>.noChange.validate(
            against: receipt.actionResult
        )

        XCTAssertEqual(receipt.traceEvidence?.completeness, .incomplete)
        XCTAssertEqual(receipt.actionResult.traceEvidence?.completeness, .incomplete)
        XCTAssertFalse(laterValidation.met)
        XCTAssertEqual(laterValidation.actual, "observation history incomplete")
    }

    func testIncompleteObservationWindowStillProvesEndpointElementChange() throws {
        let baselineEvent = brains.stash.semanticObservationStream.commitDiscoveryObservationForTesting(
            volumeScreen(value: "50%")
        )
        let baseline = try XCTUnwrap(baselineEvent.settledCapture)
        brains.stash.semanticObservationStream.clearSettledObservationHistory()
        let currentEvent = brains.stash.semanticObservationStream.commitDiscoveryObservationForTesting(
            volumeScreen(value: "60%")
        )
        let window = try XCTUnwrap(brains.stash.semanticObservationStream.observationWindow(
            from: baseline,
            through: currentEvent
        ))

        guard case .incomplete = window.completeness else {
            return XCTFail("Expected generation reset to make the window incomplete")
        }
        XCTAssertTrue(window.trace.changeFacts.contains {
            if case .elementsChanged = $0 { return true }
            return false
        })
    }

    func testNoChangePredicateRequiresCompleteObservationWindow() throws {
        let baselineEvent = brains.stash.semanticObservationStream.commitDiscoveryObservationForTesting(
            volumeScreen(value: "50%")
        )
        let baseline = try XCTUnwrap(baselineEvent.settledCapture)
        brains.stash.semanticObservationStream.clearSettledObservationHistory()
        let currentEvent = brains.stash.semanticObservationStream.commitDiscoveryObservationForTesting(
            volumeScreen(value: "50%")
        )
        let window = try XCTUnwrap(brains.stash.semanticObservationStream.observationWindow(
            from: baseline,
            through: currentEvent
        ))
        let observation = brains.postActionObservation.semanticObservation(from: currentEvent)

        let predicateResult = PredicateObservationEvidence(
            observation: observation,
            baseline: baseline,
            window: window
        ).evaluate(.noChange)

        XCTAssertFalse(predicateResult.met)
        XCTAssertEqual(predicateResult.actual, "observation history incomplete")
    }

    func testScopedScreenChangedStartsNewObservationGeneration() throws {
        let oldScreenEvent = brains.stash.semanticObservationStream.commitDiscoveryObservationForTesting(
            makeScreen(elements: [("Checkout", .header, "checkout_header")])
        )
        let newScreenEvent = brains.stash.semanticObservationStream.commitDiscoveryObservationForTesting(
            makeScreen(elements: [("Checkout", .header, "checkout_header")]),
            notificationBatch: notificationBatch(kind: .screenChanged)
        )
        let oldBaseline = try XCTUnwrap(oldScreenEvent.settledCapture)
        let transitionWindow = try XCTUnwrap(brains.stash.semanticObservationStream.observationWindow(
            from: oldBaseline,
            through: newScreenEvent
        ))

        XCTAssertNotEqual(newScreenEvent.generation, oldScreenEvent.generation)
        XCTAssertNil(newScreenEvent.trace.captures.last?.transition.fallbackReason)
        XCTAssertEqual(
            newScreenEvent.trace.captures.last?.transition.accessibilityNotifications.map(\.kind),
            [.screenChanged]
        )
        XCTAssertEqual(transitionWindow.completeness, .complete)
        XCTAssertEqual(
            transitionWindow.trace.changeFacts.map(\.kind),
            [.elementsChanged, .screenChanged, .elementsChanged]
        )

        let newBaseline = try XCTUnwrap(newScreenEvent.settledCapture)
        let nextEvent = brains.stash.semanticObservationStream.commitDiscoveryObservationForTesting(
            makeScreen(elements: [("Checkout", .header, "checkout_header")])
        )
        let newScreenWindow = try XCTUnwrap(brains.stash.semanticObservationStream.observationWindow(
            from: newBaseline,
            through: nextEvent
        ))

        XCTAssertEqual(nextEvent.generation, newScreenEvent.generation)
        XCTAssertEqual(newScreenWindow.completeness, .complete)
    }

    func testPassiveCommitConsumesScopedScreenChangedSinceLastCommit() {
        let notifications = brains.stash.accessibilityNotifications
        let heistScope = notifications.beginHeistScope()
        defer { heistScope.cancel() }
        let before = brains.stash.semanticObservationStream.commitDiscoveryObservationForTesting(
            makeScreen(elements: [("Checkout", .header, "checkout_header")])
        )

        notifications.record(code: 1000, notificationData: .none, associatedElement: .none)
        let after = brains.stash.semanticObservationStream.commitDiscoveryObservationForTesting(
            makeScreen(elements: [("Checkout", .header, "checkout_header")])
        )

        XCTAssertNotEqual(after.generation, before.generation)
        XCTAssertEqual(
            after.trace.captures.last?.transition.accessibilityNotifications.map(\.kind),
            [.screenChanged]
        )
    }

    func testPassiveCommitIgnoresAmbientScreenChangedBetweenHeistScopes() {
        let notifications = brains.stash.accessibilityNotifications
        let before = brains.stash.semanticObservationStream.commitDiscoveryObservationForTesting(
            makeScreen(elements: [("Checkout", .header, "checkout_header")])
        )
        let firstScope = notifications.beginHeistScope()
        firstScope.cancel()
        notifications.record(code: 1000, notificationData: .none, associatedElement: .none)
        let secondScope = notifications.beginHeistScope()
        defer { secondScope.cancel() }

        let after = brains.stash.semanticObservationStream.commitDiscoveryObservationForTesting(
            makeScreen(elements: [("Checkout", .header, "checkout_header")])
        )

        XCTAssertEqual(after.generation, before.generation)
        XCTAssertTrue(after.trace.captures.last?.transition.accessibilityNotifications.isEmpty == true)
        XCTAssertTrue(after.trace.changeFacts.isEmpty)
    }

    func testElementChangedNotificationDoesNotSuppressSnapshotFallback() throws {
        let before = brains.stash.semanticObservationStream.commitDiscoveryObservationForTesting(
            makeScreen(elements: [("Menu", .header, "menu_header")])
        )
        let after = brains.stash.semanticObservationStream.commitDiscoveryObservationForTesting(
            makeScreen(elements: [("Checkout", .header, "checkout_header")]),
            notificationBatch: notificationBatch(kind: .elementChanged(.layout))
        )

        XCTAssertNotEqual(after.generation, before.generation)
        XCTAssertEqual(after.trace.captures.last?.transition.fallbackReason, .primaryHeaderChanged)
        XCTAssertEqual(
            after.trace.captures.last?.transition.accessibilityNotifications.map(\.kind),
            [.elementChanged(.layout)]
        )
        XCTAssertEqual(
            after.trace.changeFacts.map(\.kind),
            [.elementsChanged, .screenChanged, .elementsChanged]
        )
    }

    func testNotificationGapFallsBackToSnapshotClassification() throws {
        let before = brains.stash.semanticObservationStream.commitDiscoveryObservationForTesting(
            makeScreen(elements: [("Menu", .header, "menu_header")])
        )
        let after = brains.stash.semanticObservationStream.commitDiscoveryObservationForTesting(
            makeScreen(elements: [("Checkout", .header, "checkout_header")]),
            notificationBatch: notificationBatch(
                kind: .elementChanged(.layout),
                gap: AccessibilityNotificationGap(droppedThroughSequence: 1)
            )
        )

        XCTAssertNotEqual(after.generation, before.generation)
        XCTAssertEqual(after.trace.captures.last?.transition.fallbackReason, .primaryHeaderChanged)
    }

    func testScreenChangedReplacesDiscoveryOnlyTargetableTruthBeforePublication() {
        brains.stash.semanticObservationStream.commitDiscoveryObservationForTesting(
            makeScreen(elements: [
                ("Checkout", .header, "checkout_header"),
                ("Old offscreen row", .staticText, "old_offscreen_row"),
            ])
        )

        brains.stash.semanticObservationStream.commitVisibleObservationForTesting(
            makeScreen(elements: [
                ("Checkout", .header, "checkout_header"),
                ("New visible row", .staticText, "new_visible_row"),
            ]),
            notificationBatch: notificationBatch(kind: .screenChanged)
        )

        XCTAssertNil(brains.stash.interfaceTree.elements["old_offscreen_row"])
        XCTAssertNotNil(brains.stash.interfaceTree.elements["new_visible_row"])
    }

    func testScreenChangedReplacesDiscoveryCommitInsteadOfMergingOldTruth() {
        brains.stash.semanticObservationStream.commitDiscoveryObservationForTesting(
            makeScreen(elements: [
                ("Checkout", .header, "checkout_header"),
                ("Old discovered row", .staticText, "old_discovered_row"),
            ])
        )

        brains.stash.semanticObservationStream.commitDiscoveryObservationForTesting(
            makeScreen(elements: [
                ("Checkout", .header, "checkout_header"),
                ("New discovered row", .staticText, "new_discovered_row"),
            ]),
            notificationBatch: notificationBatch(kind: .screenChanged)
        )

        XCTAssertNil(brains.stash.interfaceTree.elements["old_discovered_row"])
        XCTAssertNotNil(brains.stash.interfaceTree.elements["new_discovered_row"])
    }

    func testExplicitScreenChangedPublishesSettledCandidateExactly() {
        brains.stash.semanticObservationStream.commitVisibleObservationForTesting(
            makeScreen(elements: [
                ("Home", .header, "home_header"),
                ("Old control", .button, "old_control"),
            ])
        )

        brains.stash.semanticObservationStream.commitVisibleObservationForTesting(
            makeScreen(elements: [
                ("Old control", .button, "old_control"),
                ("Details", .header, "details_header"),
                ("Persistent status", .staticText, "persistent_status"),
            ]),
            notificationBatch: notificationBatch(kind: .screenChanged)
        )

        XCTAssertNotNil(brains.stash.interfaceTree.elements["old_control"])
        XCTAssertNotNil(brains.stash.interfaceTree.elements["details_header"])
        XCTAssertNotNil(brains.stash.interfaceTree.elements["persistent_status"])
    }

    func testUnknownNotificationRequiresExplicitSnapshotFallbackForScreenChange() throws {
        let before = brains.stash.semanticObservationStream.commitDiscoveryObservationForTesting(
            makeScreen(elements: [("Menu", .header, "menu_header")])
        )
        let after = brains.stash.semanticObservationStream.commitDiscoveryObservationForTesting(
            makeScreen(elements: [("Checkout", .header, "checkout_header")]),
            notificationBatch: notificationBatch(kind: .unknown(4_002))
        )

        XCTAssertNotEqual(after.generation, before.generation)
        XCTAssertEqual(after.trace.captures.last?.transition.fallbackReason, .primaryHeaderChanged)
        XCTAssertEqual(
            after.trace.captures.last?.transition.accessibilityNotifications.map(\.kind),
            [.unknown(4_002)]
        )
        XCTAssertEqual(after.trace.changeFacts.map(\.kind), [.elementsChanged, .screenChanged, .elementsChanged])
    }

    func testChangePredicatesReadScreenAndElementFactsSeparately() throws {
        let oldScreenEvent = brains.stash.semanticObservationStream.commitDiscoveryObservationForTesting(
            makeScreen(elements: [("Menu", .header, "menu_header")])
        )
        let newScreenEvent = brains.stash.semanticObservationStream.commitDiscoveryObservationForTesting(
            makeScreen(elements: [("Checkout", .header, "checkout_header")]),
            notificationBatch: notificationBatch(kind: .screenChanged)
        )
        let oldScreenBaseline = try XCTUnwrap(oldScreenEvent.settledCapture)
        let screenWindow = try XCTUnwrap(brains.stash.semanticObservationStream.observationWindow(
            from: oldScreenBaseline,
            through: newScreenEvent
        ))
        let screenEvidence = PredicateObservationEvidence(
            observation: brains.postActionObservation.semanticObservation(from: newScreenEvent),
            baseline: oldScreenBaseline,
            window: screenWindow
        )

        let screenPredicate = screenEvidence.evaluate(.changed(.screen()))
        let elementPredicateAgainstScreen = screenEvidence.evaluate(.changed(.elements()))
        XCTAssertTrue(screenPredicate.met)
        XCTAssertTrue(elementPredicateAgainstScreen.met)

        let elementBaselineEvent = brains.stash.semanticObservationStream.commitDiscoveryObservationForTesting(
            volumeScreen(value: "50%")
        )
        let elementCurrentEvent = brains.stash.semanticObservationStream.commitDiscoveryObservationForTesting(
            volumeScreen(value: "60%")
        )
        let elementBaseline = try XCTUnwrap(elementBaselineEvent.settledCapture)
        let elementWindow = try XCTUnwrap(brains.stash.semanticObservationStream.observationWindow(
            from: elementBaseline,
            through: elementCurrentEvent
        ))
        let elementEvidence = PredicateObservationEvidence(
            observation: brains.postActionObservation.semanticObservation(from: elementCurrentEvent),
            baseline: elementBaseline,
            window: elementWindow
        )

        let elementPredicate = elementEvidence.evaluate(.changed(.elements()))
        let screenPredicateAgainstElement = elementEvidence.evaluate(.changed(.screen()))
        XCTAssertTrue(elementPredicate.met)
        XCTAssertFalse(screenPredicateAgainstElement.met)
        XCTAssertEqual(screenPredicateAgainstElement.actual, "elementsChanged")
    }

    func testPredicateObservationStreamPreservesChangeBaselineAcrossReductions() throws {
        let baselineEvent = brains.stash.semanticObservationStream.commitDiscoveryObservationForTesting(
            volumeScreen(value: "50%")
        )
        let intermediateEvent = brains.stash.semanticObservationStream.commitDiscoveryObservationForTesting(
            volumeScreen(value: "60%")
        )
        let finalEvent = brains.stash.semanticObservationStream.commitDiscoveryObservationForTesting(
            volumeScreen(value: "70%")
        )

        var stream = PredicateObservationStreamState()
        let seeded = stream.reducing(
            brains.postActionObservation.semanticObservation(from: baselineEvent),
            predicate: .changed(.elements()),
            baselineSeed: .currentObservation
        )
        stream = seeded.state

        let intermediate = stream.reducing(
            brains.postActionObservation.semanticObservation(from: intermediateEvent),
            predicate: .changed(.elements()),
            baselineSeed: .preserve
        )
        stream = intermediate.state
        let final = stream.reducing(
            brains.postActionObservation.semanticObservation(from: finalEvent),
            predicate: .changed(.elements()),
            baselineSeed: .preserve
        )

        XCTAssertEqual(intermediate.reduction.changeBaseline?.cursor.sequence, baselineEvent.sequence)
        XCTAssertEqual(final.reduction.changeBaseline?.cursor.sequence, baselineEvent.sequence)
        XCTAssertEqual(final.reduction.observationWindow?.baseline.cursor.sequence, baselineEvent.sequence)
        XCTAssertEqual(final.reduction.observationWindow?.current.cursor.sequence, finalEvent.sequence)
    }

    func testWaitObservationPlanUsesDiscoveryForElementAndContainerPredicates() {
        XCTAssertEqual(
            WaitObservationPlan(predicate: .exists(literalTarget(ElementPredicate(label: "Ready")))).scope,
            .discovery
        )
        XCTAssertEqual(
            WaitObservationPlan(predicate: .exists(.container(.identifier("CheckoutList")))).scope,
            .discovery
        )
    }

    // MARK: - Semantic Capture

    func testCaptureSemanticStateKeepsKnownElementsInCanonicalInterface() {
        let visible = AccessibilityElement.make(
            label: "Visible",
            traits: .button,
            respondsToUserInteraction: false
        )
        let offViewport = AccessibilityElement.make(
            label: "Below fold",
            traits: .button,
            respondsToUserInteraction: false
        )
        brains.stash.installScreenForTesting(.makeForTests(
            elements: [(visible, HeistId(rawValue: "button_visible"))],
            offViewport: [.init(offViewport, heistId: HeistId(rawValue: "button_below_fold"))]
        ))
        let state = brains.postActionObservation.captureSemanticState()

        XCTAssertEqual(
            Set(state.screen.orderedElements.map(\.heistId)),
            ["button_visible", "button_below_fold"]
        )
        XCTAssertEqual(
            Set(state.interface.projectedElements.compactMap { $0.label }),
            ["Visible", "Below fold"]
        )
    }

    func testBeforeStateDerivesNeededSemanticProjectionsFromCanonicalInputs() {
        let screen = makeScreen(elements: [("Save", .button, "save")])
        brains.stash.installScreenForTesting(screen)
        let captured = brains.postActionObservation.captureSemanticState()

        let state = PostActionObservation.BeforeState(
            screen: captured.screen,
            capture: captured.capture,
            tripwireSignal: captured.tripwireSignal,
            settledObservationSequence: captured.settledObservationSequence
        )

        XCTAssertEqual(state.elements, screen.orderedElements.map(\.element))
        XCTAssertEqual(state.interface, captured.capture.interface)
        XCTAssertEqual(state.interfaceHash, screen.tree.interfaceHash)
        XCTAssertEqual(state.screenSnapshot, ScreenClassifier.snapshot(of: screen.tree))
        XCTAssertEqual(state.screenId, screen.id)
    }

    func testNotificationRemapPreservesUnknownNotificationKind() throws {
        let screen = makeScreen(elements: [("Save", .button, "save")])
        brains.stash.installScreenForTesting(screen)
        let state = brains.postActionObservation.captureSemanticState()
        let notification = AccessibilityNotificationEvidence(
            sequence: 1,
            kind: .unknown(4_242),
            timestamp: Date(timeIntervalSince1970: 0),
            notificationData: .none,
            associatedElement: .none
        )

        let remapped = PostActionObservation.remapAccessibilityNotifications(
            [notification],
            from: state,
            to: state
        )

        let result = try XCTUnwrap(remapped.first)
        XCTAssertEqual(result.kind, .unknown(4_242))
    }

    func testDiscoveryObservationStateUsesDiscoveryInterfaceWhileTraceStaysSemantic() {
        let fixture = makeDiscoveryObservationProjectionFixture()
        let screen = fixture.screen
        let discoveryInterface = TheStash.WireConversion.toDiscoveryInterface(from: screen.tree)
        let semanticInterface = TheStash.WireConversion.toSemanticInterface(from: screen.tree)
        let traceCapture = brains.postActionObservation.makeTraceCapture(
            interface: semanticInterface,
            sequence: 1,
            screen: screen,
            tripwireSignal: .empty,
            screenId: screen.id
        )
        let trace = AccessibilityTrace(capture: traceCapture)
        let settled = SettledSemanticObservation(
            sequence: 7,
            scope: .discovery,
            screen: screen,
            semanticSignal: .empty
        )
        let event = SettledSemanticObservationEvent(
            sequence: 7,
            scope: .discovery,
            observation: settled,
            previous: nil,
            trace: trace
        )
        let observation = brains.postActionObservation.semanticObservation(from: event)

        XCTAssertNotEqual(discoveryInterface.tree, semanticInterface.tree)
        XCTAssertEqual(observation.state.interface.tree, discoveryInterface.tree)
        XCTAssertEqual(observation.state.interface.annotations, discoveryInterface.annotations)
        XCTAssertEqual(observation.accessibilityTrace.captures.last?.interface.tree, semanticInterface.tree)
        XCTAssertEqual(observation.accessibilityTrace.captures.last?.interface.annotations, semanticInterface.annotations)
        XCTAssertNotNil(observation.state.interface.annotations.elementByPath[fixture.visiblePath])
        XCTAssertEqual(
            observation.state.interface.annotations.containerByPath[TreePath([0, 1])]?.containerName,
            "offscreen_group"
        )
        XCTAssertEqual(
            observation.accessibilityTrace.captures.last?.interface.annotations.containerByPath[TreePath([0, 0])]?
                .containerName,
            "offscreen_group"
        )
        let predicate = AccessibilityPredicate<RootContext>.exists(.container(.identifier("OffscreenGroup")))
        XCTAssertEqual(
            PredicateEvaluation.evaluate(predicate, in: observation),
            ExpectationResult(met: true, predicate: predicate)
        )
    }

    private func makeDiscoveryObservationProjectionFixture() -> (screen: InterfaceObservation, visiblePath: TreePath) {
        let rootPath = TreePath([0])
        let visiblePath = TreePath([0, 0])
        let offscreenContainerPath = TreePath([0, 2])
        let rootContainer = AccessibilityContainer(
            type: .none,
            identifier: "RootViewController",
            frame: AccessibilityRect(CGRect(x: 0, y: 0, width: 320, height: 480))
        )
        let offscreenContainer = AccessibilityContainer(
            type: .semanticGroup(label: "OffscreenGroup", value: nil),
            identifier: "OffscreenGroup",
            frame: AccessibilityRect(CGRect(x: 0, y: 480, width: 320, height: 240))
        )
        let visible = AccessibilityElement.make(
            label: "Visible",
            traits: .button,
            respondsToUserInteraction: false
        )
        let offscreen = AccessibilityElement.make(
            label: "Offscreen",
            traits: .button,
            respondsToUserInteraction: false
        )
        let screen = InterfaceObservation.makeForTests(
            tree: InterfaceTree(
                elements: [
                    "visible_button": InterfaceTree.Element(
                        heistId: "visible_button",
                        path: visiblePath,
                        scrollMembership: nil,
                        element: visible
                    ),
                    "offscreen_button": InterfaceTree.Element(
                        heistId: "offscreen_button",
                        path: TreePath([0, 2, 0]),
                        scrollMembership: InterfaceTree.ScrollMembership(
                            containerPath: offscreenContainerPath,
                            index: 0
                        ),
                        element: offscreen
                    ),
                ],
                containers: [
                    rootPath: InterfaceTree.Container(
                        container: rootContainer,
                        path: rootPath,
                        containerName: "root",
                        contentFrame: nil
                    ),
                    offscreenContainerPath: InterfaceTree.Container(
                        container: offscreenContainer,
                        path: offscreenContainerPath,
                        containerName: "offscreen_group",
                        contentFrame: nil,
                        scrollMembership: InterfaceTree.ScrollMembership(
                            containerPath: rootPath,
                            index: 0
                        )
                    ),
                ]
            ),
            liveCapture: LiveCapture.makeForTests(
                hierarchy: [
                    .container(rootContainer, children: [
                        .element(visible, traversalIndex: 0),
                    ]),
                ],
                containerNamesByPath: [rootPath: "root"],
                heistIdsByPath: [visiblePath: "visible_button"],
                elementRefs: [:],
                firstResponderHeistId: nil
            )
        )
        return (screen, visiblePath)
    }

    func testShouldRecordAccessibilityTraceIgnoresViewportOnlyMovement() {
        let beforeElement = AccessibilityElement.make(
            label: "Chicken Tikka",
            traits: .button,
            shape: .frame(AccessibilityRect(CGRect(x: 0, y: 0, width: 200, height: 44))),
            activationPoint: CGPoint(x: 100, y: 22),
            respondsToUserInteraction: false
        )
        brains.stash.installScreenForTesting(.makeForTests(
            elements: [(beforeElement, HeistId(rawValue: "chicken_tikka_button"))]
        ))
        let baseline = brains.postActionObservation.captureSemanticState()

        let afterElement = AccessibilityElement.make(
            label: "Chicken Tikka",
            traits: .button,
            shape: .frame(AccessibilityRect(CGRect(x: 0, y: -300, width: 200, height: 44))),
            activationPoint: CGPoint(x: 100, y: -278),
            respondsToUserInteraction: false
        )
        brains.stash.installScreenForTesting(.makeForTests(
            elements: [(afterElement, HeistId(rawValue: "chicken_tikka_button"))]
        ))
        let current = brains.postActionObservation.captureSemanticState()
        let classification = ScreenClassifier.classify(
            before: baseline.screenSnapshot,
            after: current.screenSnapshot,
            notifications: []
        )

        XCTAssertFalse(
            PostActionObservation.shouldRecordAccessibilityTrace(
                baseline: baseline,
                current: current,
                classification: classification
            ),
            "Viewport-only geometry movement updates interaction state but does not become trace history"
        )
    }

    func testShouldRecordAccessibilityTraceRecordsSameScreenSemanticChange() {
        let beforeElement = AccessibilityElement.make(
            label: "Total",
            value: "$4.00",
            traits: .staticText,
            respondsToUserInteraction: false
        )
        brains.stash.installScreenForTesting(.makeForTests(
            elements: [(beforeElement, HeistId(rawValue: "total_staticText"))]
        ))
        let baseline = brains.postActionObservation.captureSemanticState()

        let afterElement = AccessibilityElement.make(
            label: "Total",
            value: "$8.00",
            traits: .staticText,
            respondsToUserInteraction: false
        )
        brains.stash.installScreenForTesting(.makeForTests(
            elements: [(afterElement, HeistId(rawValue: "total_staticText"))]
        ))
        let current = brains.postActionObservation.captureSemanticState()
        let classification = ScreenClassifier.classify(
            before: baseline.screenSnapshot,
            after: current.screenSnapshot,
            notifications: []
        )

        XCTAssertTrue(
            PostActionObservation.shouldRecordAccessibilityTrace(
                baseline: baseline,
                current: current,
                classification: classification
            ),
            "Same-screen value changes are semantic patches"
        )
    }

    // MARK: - Semantic Discovery Observation

    func testSemanticDiscoveryObservationCommitsUnion() async {
        // Exploration seeds the local union from the interface tree and merges each
        // parse into it. The observation stream commits the completed union as
        // settled discovery truth. There is no pruning — the union is the
        // canonical "all elements seen this cycle".
        // With no scrollable containers in the host hierarchy, semantic discovery
        // reduces to refresh-and-commit, and the seeded entry merges into the
        // live parse rather than being pruned.
        seedScreen(elements: [("Seed", .button, "button_seed")])
        XCTAssertEqual(brains.stash.interfaceTree.elements.count, 1)

        brains.startSemanticObservation()
        let observation = await brains.stash.observeSettledSemanticObservation(scope: .discovery, after: nil, timeout: 2)

        // Either the seed survives (no live parse landed and the union still
        // holds it) or it merges with new live entries — either way, the
        // settled screen reflects the committed union, not the pre-explore
        // value alone.
        XCTAssertNotNil(observation)
        XCTAssertGreaterThanOrEqual(brains.stash.interfaceTree.elements.count, 1)
    }

    func testExploreScreenStopsEarlyWhenTargetAlreadyResolved() async throws {
        guard let screen = brains.stash.refreshLiveCapture(),
              let label = screen.viewportElementIDs
                  .compactMap({ screen.findElement(heistId: $0)?.element.label })
                  .first(where: { !$0.isEmpty }) else {
            throw XCTSkip("No live labeled element available for target short-circuit test")
        }

        guard let exploration = await brains.navigation.exploreScreen(
            target: literalTarget(ElementPredicate(label: .exact(label)))
        ) else {
            return XCTFail("Expected target exploration to settle")
        }

        XCTAssertEqual(exploration.manifest.scrollCount, 0)
        XCTAssertTrue(exploration.manifest.pendingScrollPaths.isEmpty)
        XCTAssertTrue(exploration.manifest.exploredScrollPaths.isEmpty)
    }

    func testSemanticExplorationAbsorbsSameIdElementChange() {
        let before = AccessibilityElement.make(
            label: "Total",
            value: "$4.00",
            traits: .staticText,
            respondsToUserInteraction: false
        )
        let after = AccessibilityElement.make(
            label: "Total",
            value: "$8.00",
            traits: .staticText,
            respondsToUserInteraction: false
        )
        var exploration = Navigation.SemanticExploration(
            baseline: .interfaceMemory(
                InterfaceObservation.makeForTests(elements: [(before, HeistId(rawValue: "total_staticText"))])
            )
        )

        exploration.absorb(InterfaceObservation.makeForTests(elements: [(after, HeistId(rawValue: "total_staticText"))]))

        XCTAssertEqual(
            exploration.screen.findElement(heistId: "total_staticText")?.element.value,
            "$8.00"
        )
    }

    func testSemanticExplorationAddsNestedContainersAfterOuterContainerIsExplored() {
        let outer = makeScrollableContainer(
            frame: CGRect(x: 0, y: 0, width: 320, height: 400),
            contentSize: CGSize(width: 320, height: 1_200)
        )
        let nested = makeScrollableContainer(
            frame: CGRect(x: 20, y: 520, width: 280, height: 240),
            contentSize: CGSize(width: 280, height: 900)
        )
        let outerPath = TreePath([0])
        let nestedPath = TreePath([0, 0])
        let outerEntry = semanticContainer(outer, path: outerPath)
        let nestedEntry = semanticContainer(nested, path: nestedPath)
        var exploration = Navigation.SemanticExploration(baseline: .interfaceMemory(.empty))
        exploration.manifest.addPendingContainers([outerEntry])

        exploration.markExplored(outerEntry)
        exploration.addDiscoveredContainers([outerEntry, nestedEntry])

        XCTAssertTrue(exploration.manifest.exploredScrollPaths.contains(outerPath))
        XCTAssertFalse(exploration.manifest.pendingScrollPaths.contains(outerPath))
        XCTAssertTrue(exploration.manifest.pendingScrollPaths.contains(nestedPath))
    }

    func testSemanticExplorationAbsorbQueuesScrollContainersFromParsedPage() {
        let outer = makeScrollableContainer(
            frame: CGRect(x: 0, y: 0, width: 320, height: 400),
            contentSize: CGSize(width: 320, height: 1_200)
        )
        let nested = makeScrollableContainer(
            frame: CGRect(x: 20, y: 180, width: 280, height: 240),
            contentSize: CGSize(width: 280, height: 900)
        )
        let page = InterfaceObservation.makeForTests(
            elements: [:],
            hierarchy: [
                .container(outer, children: [
                    .container(nested, children: [])
                ])
            ],
            firstResponderHeistId: nil,
        )
        var exploration = Navigation.SemanticExploration(baseline: .interfaceMemory(.empty))

        exploration.absorb(page)

        XCTAssertTrue(exploration.manifest.pendingScrollPaths.contains(TreePath([0])))
        XCTAssertTrue(exploration.manifest.pendingScrollPaths.contains(TreePath([0, 0])))
    }

    func testSemanticExplorationAbsorbQueuesNestedContainerWithoutRequeuingExploredOuter() {
        let outer = makeScrollableContainer(
            frame: CGRect(x: 0, y: 0, width: 320, height: 400),
            contentSize: CGSize(width: 320, height: 1_200)
        )
        let nested = makeScrollableContainer(
            frame: CGRect(x: 20, y: 520, width: 280, height: 240),
            contentSize: CGSize(width: 280, height: 900)
        )
        let page = InterfaceObservation.makeForTests(
            elements: [:],
            hierarchy: [
                .container(outer, children: [
                    .container(nested, children: [])
                ])
            ],
            firstResponderHeistId: nil,
        )
        let outerPath = TreePath([0])
        let nestedPath = TreePath([0, 0])
        let outerEntry = semanticContainer(outer, path: outerPath)
        var exploration = Navigation.SemanticExploration(baseline: .interfaceMemory(.empty))
        exploration.manifest.addPendingContainers([outerEntry])
        exploration.markExplored(outerEntry)

        exploration.absorbScrolledPage(page, notificationBatch: nil)

        XCTAssertTrue(exploration.manifest.exploredScrollPaths.contains(outerPath))
        XCTAssertFalse(exploration.manifest.pendingScrollPaths.contains(outerPath))
        XCTAssertTrue(exploration.manifest.pendingScrollPaths.contains(nestedPath))
    }

    func testSemanticExplorationFinishOwnsExplorationTimestamp() {
        var exploration = Navigation.SemanticExploration(baseline: .interfaceMemory(.empty))

        let result = exploration.finish(startTime: CACurrentMediaTime() - 0.01)

        XCTAssertGreaterThan(result.manifest.explorationTime, 0)
        XCTAssertEqual(result.screen.tree, InterfaceObservation.empty.tree)
        XCTAssertEqual(result.screen.liveCapture.snapshot, InterfaceObservation.empty.liveCapture.snapshot)
    }

    func testExploreScreenExploresSwipeableContainer() async throws {
        guard brains.stash.refreshLiveCapture() != nil else {
            throw XCTSkip("No live hierarchy available for swipeable explore test")
        }
        guard let container = brains.stash.latestObservedLiveHierarchy.scrollablePathIndexedContainers.first(where: {
            brains.stash.liveScrollableContainerView(forPath: $0.path) == nil
        }) else {
            throw XCTSkip("No semantic-only scrollable container in host UI")
        }

        guard let exploration = await brains.navigation.exploreScreen() else {
            return XCTFail("Expected swipeable-container exploration to settle")
        }
        let manifest = exploration.manifest

        XCTAssertTrue(manifest.exploredScrollPaths.contains(container.path))
    }

    // MARK: - Helpers

    private func successOutcome(
        payload: ActionResultPayload? = nil,
        subjectEvidence: ActionSubjectEvidence? = nil,
        activationTrace: ActivationTrace? = nil
    ) -> PostActionObservation.ActionOutcome {
        .success(PostActionObservation.ActionOutcomeSuccess(
            payload: payload.map(PostActionObservation.ActionOutcomePayload.immediate) ?? .none,
            subjectEvidence: subjectEvidence,
            activationTrace: activationTrace
        ))
    }

    private func failureOutcome(
        errorKind: ErrorKind = .actionFailed,
        payload: ActionResultPayload? = nil,
        activationTrace: ActivationTrace? = nil
    ) -> PostActionObservation.ActionOutcome {
        .failure(PostActionObservation.ActionOutcomeFailure(
            errorKind: errorKind,
            payload: payload.map(PostActionObservation.ActionOutcomePayload.immediate) ?? .none,
            activationTrace: activationTrace
        ))
    }

    private func seedScreen(elements: [(label: String, traits: UIAccessibilityTraits, heistId: HeistId)]) {
        brains.stash.installScreenForTesting(makeScreen(elements: elements))
    }

    private func notificationBatch(
        kind: AccessibilityNotificationKind,
        gap: AccessibilityNotificationGap? = nil
    ) -> AccessibilityNotificationBatch {
        AccessibilityNotificationBatch(
            events: [PendingAccessibilityNotificationEvent(
                sequence: 1,
                kind: kind,
                timestamp: Date(timeIntervalSince1970: 0),
                notificationData: .none,
                associatedElement: .none,
                provenance: .scoped
            )],
            through: AccessibilityNotificationCursor(sequence: 1),
            scopedScreenChangedThrough: kind == .screenChanged ? 1 : 0,
            gap: gap
        )
    }

    private func waitForSettledSemanticWaiter(
        on stash: TheStash,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        let deadline = CFAbsoluteTimeGetCurrent() + 1
        while stash.semanticObservationStream.settledWaiterCount == 0,
              CFAbsoluteTimeGetCurrent() < deadline {
            await Task.yield()
            guard await Task.cancellableSleep(for: .milliseconds(5)) else { break }
        }
        XCTAssertEqual(stash.semanticObservationStream.settledWaiterCount, 1, file: file, line: line)
    }

    private func makeElement(label: String) -> AccessibilityElement {
        AccessibilityElement.make(label: label, respondsToUserInteraction: false)
    }

    private func volumeScreen(value: String) -> InterfaceObservation {
        InterfaceObservation.makeForTests(elements: [
            (
                AccessibilityElement.make(
                    label: "Volume",
                    value: value,
                    traits: .adjustable,
                    respondsToUserInteraction: false
                ),
                "volume"
            ),
        ])
    }

    private func predicateWaitForReceiptProofTests() -> PredicateWait {
        PredicateWait(
            observeEvent: { _, _, _ in nil },
            latestEvent: { nil },
            latestSettleFailure: { nil },
            semanticObservation: { event in
                self.brains.postActionObservation.semanticObservation(from: event)
            },
            presenceTimeoutMessage: { _, _ in nil },
            announcementCursor: { _ in .origin },
            waitForAnnouncement: { _, _, _ in nil }
        )
    }

    private func makeScreen(elements: [(label: String, traits: UIAccessibilityTraits, heistId: HeistId)]) -> InterfaceObservation {
        let pairs: [(AccessibilityElement, HeistId)] = elements.map { entry in
            let element = AccessibilityElement.make(
                label: entry.label,
                traits: entry.traits,
                respondsToUserInteraction: false
            )
            return (element, entry.heistId)
        }
        return .makeForTests(elements: pairs)
    }

    private func pollingObservation(
        label: String,
        scope: SemanticObservationScope,
        sequence: SettledObservationSequence
    ) -> HeistSemanticObservation {
        let screen = makeScreen(elements: [
            (label, .staticText, HeistId(rawValue: "polling_\(label)")),
        ])
        let settled = SettledSemanticObservation(
            sequence: sequence,
            scope: scope,
            screen: screen,
            semanticSignal: .empty
        )
        let state = brains.postActionObservation.captureSemanticState(from: settled)
        let trace = AccessibilityTrace(capture: state.capture)
        let event = SettledSemanticObservationEvent(
            sequence: sequence,
            scope: scope,
            observation: settled,
            previous: nil,
            trace: trace
        )
        return HeistSemanticObservation(
            event: event,
            state: state,
            accessibilityTrace: trace,
            summary: "interface: \(state.interface.projectedElements.count) elements"
        )
    }

    private func makeStaleObservation(
        from state: PostActionObservation.BeforeState,
        sequence: SettledObservationSequence
    ) -> HeistSemanticObservation {
        let trace = AccessibilityTrace(capture: state.capture)
        let settled = SettledSemanticObservation(
            sequence: sequence,
            scope: .discovery,
            screen: state.screen,
            semanticSignal: .empty
        )
        let event = SettledSemanticObservationEvent(
            sequence: sequence,
            scope: .discovery,
            observation: settled,
            previous: nil,
            trace: trace
        )
        return HeistSemanticObservation(
            event: event,
            state: state,
            accessibilityTrace: trace,
            summary: "interface: \(state.interface.projectedElements.count) elements"
        )
    }

    private func activationSubjectEvidence(
        target: AccessibilityTarget,
        element: AccessibilityElement,
        settledObservationSequence: SettledObservationSequence?
    ) -> ActionSubjectEvidence {
        ActionSubjectEvidence(
            source: .resolvedSemanticTarget,
            target: target,
            element: TheStash.WireConversion.convert(element),
            resolution: ActionSubjectResolution(origin: .visible),
            settledObservationSequence: settledObservationSequence
        )
    }

    private func makeScrollableContainer(frame: CGRect, contentSize: CGSize) -> AccessibilityContainer {
        AccessibilityContainer(
            type: .none, scrollableContentSize: AccessibilitySize(contentSize),
            frame: AccessibilityRect(frame)
        )
    }

    private func semanticContainer(
        _ container: AccessibilityContainer,
        path: TreePath
    ) -> InterfaceTree.Container {
        InterfaceTree.Container(
            container: container,
            path: path,
            containerName: nil,
            contentFrame: container.frame.cgRect
        )
    }

    private func settledOutcome(
        finalScreen: InterfaceObservation?,
        outcome: SettleOutcome = .settled(timeMs: 0)
    ) -> SettleSession.Outcome {
        if let finalScreen {
            brains.stash.recordParsedObservedEvidence(finalScreen)
        }
        let elements = finalScreen?.liveCapture.hierarchy.sortedElements ?? []
        let elementsByKey = Dictionary(uniqueKeysWithValues: elements.map { ($0.timelineKey, $0) })
        return SettleSession.Outcome(
            outcome: outcome,
            events: [],
            finalObservation: finalScreen.map { SettleSessionFinalObservation(screen: $0) },
            elementsByKey: elementsByKey
        )
    }

}

#endif
