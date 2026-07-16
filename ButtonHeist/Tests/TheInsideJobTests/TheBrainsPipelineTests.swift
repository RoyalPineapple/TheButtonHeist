#if canImport(UIKit)
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

    private enum WaitCheck: Equatable {
        case visible
        case discovery
    }

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
            outcome: failureOutcome(message: "target disappeared"),
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

    func testCommittedPostActionTraceUsesPublishedContinuity() {
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

        XCTAssertEqual(sameGenerationEvent.continuity, .sameGeneration)
        XCTAssertNil(trace.captures.last?.transition.fallbackReason)
    }

    func testActionErrorKindClassifiesTargetUnavailableSeparatelyFromActionIdentity() throws {
        let result = TheSafecracker.ActionDispatchOutcome.failure(
            .activate,
            message: "target disappeared",
            failureKind: .targetUnavailable
        )

        XCTAssertEqual(
            TheBrains.actionErrorKind(for: try XCTUnwrap(result.failureKind)),
            .elementNotFound
        )
        XCTAssertEqual(result.method, .activate)
    }

    func testActionErrorKindPreservesTreeUnavailableFailureKind() throws {
        let result = TheSafecracker.ActionDispatchOutcome.failure(
            .activate,
            message: TheBrains.treeUnavailableMessage,
            failureKind: .treeUnavailable
        )

        XCTAssertEqual(
            TheBrains.actionErrorKind(for: try XCTUnwrap(result.failureKind)),
            .accessibilityTreeUnavailable
        )
    }

    func testActionDispatchOutcomeDecoratorsPreserveExistingFieldsAndMergeTiming() throws {
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
            outcome: failureOutcome(),
            before: before,
            settleOutcome: settledOutcome(finalScreen: brains.stash.latestObservation)
        )

        XCTAssertEqual(result.outcome.errorKind, .actionFailed)
    }

    func testPostActionObservationFailureRespectsExplicitErrorKind() async {
        let before = brains.postActionObservation.captureSemanticState()

        let result = await brains.interactionObservation.finishAfterAction(
            outcome: failureOutcome(failureKind: .timeout),
            before: before,
            settleOutcome: settledOutcome(finalScreen: brains.stash.latestObservation)
        )

        XCTAssertEqual(result.outcome.errorKind, .timeout,
                       "An explicit errorKind must override the method-based inference")
    }

    // MARK: - Post-Action Success Path

    func testAdvertisedActivateNoChangeCanRemainSuccessful() async throws {
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
            outcome: successOutcome(
                subjectEvidence: try activationSubjectEvidence(
                    target: .identifier("inert_option"),
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
        XCTAssertTrue(result.accessibilityTrace?.changeFacts.isEmpty == true)
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
            outcome: successOutcome(method: .scrollToEdge),
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
            outcome: successOutcome(method: .syntheticTap),
            before: before,
            settleOutcome: settledOutcome(finalScreen: beforeScreen)
        )

        XCTAssertTrue(result.outcome.isSuccess, result.message ?? "tap unexpectedly failed")
        XCTAssertEqual(result.method, .syntheticTap)
        XCTAssertNil(result.outcome.errorKind)
        XCTAssertEqual(result.accessibilityTrace?.captures.count, 2)
        XCTAssertTrue(result.accessibilityTrace?.changeFacts.isEmpty == true)
    }

    func testActivateNoChangeAfterTapActivationDispatchRemainsSuccessfulAndLegible() async throws {
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
            outcome: successOutcome(
                subjectEvidence: try activationSubjectEvidence(
                    target: .identifier("tap_activated_option"),
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
        XCTAssertTrue(result.accessibilityTrace?.changeFacts.isEmpty == true)
    }

    func testActionResultWithDeltaSuccessReturnsTraceAfterElementChange() async {
        let beforeScreen = makeScreen(elements: [("Total", .staticText, "total")])
        brains.stash.installScreenForTesting(beforeScreen)
        let before = brains.postActionObservation.captureSemanticState()
        let afterScreen = makeScreen(elements: [("Total $12.00", .staticText, "total")])

        let result = await brains.interactionObservation.finishAfterAction(
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

    func testActionResultWithDeltaPreservesSubjectEvidence() async throws {
        let beforeScreen = makeScreen(elements: [("Delete", .button, "delete_button")])
        brains.stash.installScreenForTesting(beforeScreen)
        let before = brains.postActionObservation.captureSemanticState()
        let evidence = ActionSubjectEvidence(
            source: .resolvedSemanticTarget,
            target: try AccessibilityTarget.element(
                .label("Delete"),
                traits: [.button]
            ).resolve(in: .empty),
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
            outcome: successOutcome(subjectEvidence: evidence),
            before: before,
            settleOutcome: settledOutcome(finalScreen: beforeScreen)
        )

        XCTAssertTrue(result.outcome.isSuccess, result.message ?? "action unexpectedly failed")
        XCTAssertEqual(result.subjectEvidence, evidence)
    }

    func testActionFailurePreservesResolvedSubjectEvidence() async throws {
        let beforeScreen = makeScreen(elements: [("Delete", .button, "delete_button")])
        brains.stash.installScreenForTesting(beforeScreen)
        let before = brains.postActionObservation.captureSemanticState()
        let target = try AccessibilityTarget.element(
            .label("Delete"),
            traits: [.button]
        ).resolve(in: .empty)
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
            outcome: failureOutcome(subjectEvidence: evidence),
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
        let outcome = TheSafecracker.ActionDispatchOutcome.success(method: .typeText)

        let result = await brains.interactionObservation.finishAfterAction(
            outcome: outcome,
            afterStatePayload: { context in
                guard let value = context.afterState.screen.findElement(heistId: "status")?.element.value else {
                    return nil
                }
                return .typeText(value)
            },
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
        let outcome = TheSafecracker.ActionDispatchOutcome.success(method: .typeText)

        let result = await brains.interactionObservation.finishAfterAction(
            outcome: outcome,
            afterStatePayload: { context in
                guard let value = context.afterState.screen.findElement(heistId: "status")?.element.value else {
                    return nil
                }
                return .typeText(value)
            },
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
        for _ in 0..<64 {
            brains.stash.accessibilityNotifications.recordForTesting(
                code: 99_999,
                notificationData: .none,
                associatedElement: .none
            )
        }
        brains.stash.accessibilityNotifications.recordForTesting(
            code: 1001,
            notificationData: CapturedAccessibilityNotificationPayload(acidObject),
            associatedElement: .none
        )

        let result = await brains.interactionObservation.finishAfterAction(
            outcome: successOutcome(),
            before: before,
            settleOutcome: settledOutcome(finalScreen: cleanSettledScreen),
            notificationWindow: notificationWindow
        )

        let notification = try XCTUnwrap(
            result.accessibilityTrace?.captures.last?.transition.accessibilityNotifications.last {
                $0.kind == .elementChanged(.layout)
            }
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
        brains.stash.accessibilityNotifications.recordForTesting(
            code: 1001,
            notificationData: CapturedAccessibilityNotificationPayload(notifiedObject),
            associatedElement: .none
        )

        brains.stash.semanticObservationStream.commitVisibleObservationForTesting(
            makeScreen(elements: [("Passive", .staticText, "passive")])
        )

        let result = await brains.interactionObservation.finishAfterAction(
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
                outcome: successOutcome(),
                before: before,
                settleOutcome: settledOutcome(finalScreen: visibleAfter)
            )
        }

        for _ in 0..<50 where brains.stash.semanticObservationStream.observationReplayWaiterCount == 0 {
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
        let beforeScreen = makeScreen(elements: [("Menu", .header, "menu_header")])
        brains.stash.installScreenForTesting(beforeScreen)
        let before = brains.postActionObservation.captureSemanticState()
        let settledSequence = brains.stash.latestSettledSemanticObservationEvent?.sequence
        let afterScreen = makeScreen(elements: [("Details", .header, "details_header")])

        let result = await brains.interactionObservation.finishAfterAction(
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
            "Menu"
        )
        XCTAssertTrue(brains.stash.latestSettledSemanticObservationInvalidated)
        XCTAssertEqual(brains.stash.interfaceTree.orderedElements.first?.element.label, "Menu")
        XCTAssertEqual(brains.stash.latestFailedSettleDiagnosticEvidence?.orderedElements.first?.element.label, "Details")
        XCTAssertEqual(result.accessibilityTrace?.captures.count, 2)
        XCTAssertEqual(result.accessibilityTrace?.captures.last?.interface.projectedElements.first?.label, "Details")
        XCTAssertEqual(
            result.accessibilityTrace?.captures.last?.transition.fallbackReason,
            .primaryHeaderChanged
        )
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

    func testWaitSuccessReceiptUsesSettledVisibleObservation() async throws {
        let event = brains.stash.semanticObservationStream.commitVisibleObservationForTesting(
            makeScreen(elements: [("Home", .header, "home")])
        )
        let wait = makeStreamBackedPredicateWait(
            settleVisible: { _ in event }
        )

        let receipt = await wait.wait(
            for: try resolvedWait(WaitStep(predicate: .exists(.label("Home")), timeout: .milliseconds(1)))
        )
        let trace = try XCTUnwrap(receipt.actionResult.accessibilityTrace)

        XCTAssertTrue(receipt.actionResult.outcome.isSuccess)
        XCTAssertEqual(trace.captures.last?.interface.projectedElements.map(\.label), ["Home"])
        XCTAssertTrue(receipt.expectation.met)
    }

    func testWaitTimeoutReceiptUsesLastSettledVisibleObservation() async throws {
        let event = brains.stash.semanticObservationStream.commitVisibleObservationForTesting(
            makeScreen(elements: [("Known", .staticText, "known")])
        )
        let wait = makeStreamBackedPredicateWait(
            settleVisible: { _ in event }
        )

        let receipt = await wait.wait(
            for: try resolvedWait(WaitStep(predicate: .exists(.label("Missing")), timeout: .milliseconds(1)))
        )
        let trace = try XCTUnwrap(receipt.actionResult.accessibilityTrace)

        XCTAssertFalse(receipt.actionResult.outcome.isSuccess)
        XCTAssertEqual(receipt.actionResult.outcome.errorKind, .timeout)
        XCTAssertEqual(trace.captures.last?.interface.projectedElements.map(\.label), ["Known"])
        XCTAssertTrue(receipt.actionResult.message?.contains("interface: 1 elements") == true)
        XCTAssertTrue(receipt.actionResult.message?.contains("last result:") == true)
    }

    func testVisibleMissRunsDiscoveryAfterVisibleSettle() async throws {
        let visible = brains.stash.semanticObservationStream.commitVisibleObservationForTesting(
            makeScreen(elements: [("Loading", .staticText, "loading")])
        )
        let discovered = brains.stash.semanticObservationStream.commitDiscoveryObservationForTesting(
            makeScreen(elements: [("Ready", .staticText, "ready")])
        )
        var checks: [WaitCheck] = []
        let wait = makeStreamBackedPredicateWait(
            settleVisible: { _ in
                checks.append(.visible)
                return visible
            },
            discover: { _, _, observer in
                checks.append(.discovery)
                _ = observer(discovered)
                return discovered
            }
        )

        let receipt = await wait.wait(
            for: try resolvedWait(WaitStep(predicate: .exists(.label("Ready")), timeout: 1))
        )

        XCTAssertTrue(receipt.actionResult.outcome.isSuccess)
        XCTAssertEqual(checks, [.visible, .discovery])
    }

    func testAppearedWaitRequiresObservedTransitionWhenFinalStateIsAlreadyPresent() async throws {
        let ready = makeScreen(elements: [("Ready", .staticText, "ready")])
        let receipt = try await temporalWaitReceipt(
            predicate: .changed(.elements([.appeared(.label("Ready"))])),
            baseline: ready,
            final: ready
        )

        XCTAssertFalse(receipt.actionResult.outcome.isSuccess)
        XCTAssertEqual(receipt.actionResult.outcome.errorKind, .timeout)
        XCTAssertFalse(receipt.expectation.met)
        XCTAssertTrue(elementChanges(in: receipt).isEmpty)
    }

    func testAppearedWaitSucceedsFromCanonicalTransition() async throws {
        let receipt = try await temporalWaitReceipt(
            predicate: .changed(.elements([.appeared(.label("Ready"))])),
            baseline: .empty,
            final: makeScreen(elements: [("Ready", .staticText, "ready")])
        )
        let changes = try XCTUnwrap(elementChanges(in: receipt).first)

        XCTAssertTrue(receipt.actionResult.outcome.isSuccess)
        XCTAssertTrue(receipt.expectation.met)
        XCTAssertEqual(changes.appeared.count, 1)
        XCTAssertTrue(changes.disappeared.isEmpty)
        XCTAssertTrue(changes.updated.isEmpty)
    }

    func testDisappearedWaitRequiresObservedTransitionWhenFinalStateIsAlreadyAbsent() async throws {
        let receipt = try await temporalWaitReceipt(
            predicate: .changed(.elements([.disappeared(.label("Loading"))])),
            baseline: .empty,
            final: .empty
        )

        XCTAssertFalse(receipt.actionResult.outcome.isSuccess)
        XCTAssertEqual(receipt.actionResult.outcome.errorKind, .timeout)
        XCTAssertFalse(receipt.expectation.met)
        XCTAssertTrue(elementChanges(in: receipt).isEmpty)
    }

    func testDisappearedWaitSucceedsFromCanonicalTransition() async throws {
        let receipt = try await temporalWaitReceipt(
            predicate: .changed(.elements([.disappeared(.label("Loading"))])),
            baseline: makeScreen(elements: [("Loading", .staticText, "loading")]),
            final: .empty
        )
        let changes = try XCTUnwrap(elementChanges(in: receipt).first)

        XCTAssertTrue(receipt.actionResult.outcome.isSuccess)
        XCTAssertTrue(receipt.expectation.met)
        XCTAssertTrue(changes.appeared.isEmpty)
        XCTAssertEqual(changes.disappeared.count, 1)
        XCTAssertTrue(changes.updated.isEmpty)
    }

    func testUpdatedWaitRequiresObservedTransitionWhenFinalStateAlreadyMatches() async throws {
        let quantity = volumeScreen(value: "3")
        let receipt = try await temporalWaitReceipt(
            predicate: .changed(.elements([.updated(
                .label("Volume"),
                .value(before: "2", after: "3")
            )])),
            baseline: quantity,
            final: quantity
        )

        XCTAssertFalse(receipt.actionResult.outcome.isSuccess)
        XCTAssertEqual(receipt.actionResult.outcome.errorKind, .timeout)
        XCTAssertFalse(receipt.expectation.met)
        XCTAssertTrue(elementChanges(in: receipt).isEmpty)
    }

    func testUpdatedWaitSucceedsFromCanonicalTransition() async throws {
        let receipt = try await temporalWaitReceipt(
            predicate: .changed(.elements([.updated(
                .label("Volume"),
                .value(before: "2", after: "3")
            )])),
            baseline: volumeScreen(value: "2"),
            final: volumeScreen(value: "3")
        )
        let changes = try XCTUnwrap(elementChanges(in: receipt).first)

        XCTAssertTrue(receipt.actionResult.outcome.isSuccess)
        XCTAssertTrue(receipt.expectation.met)
        XCTAssertTrue(changes.appeared.isEmpty)
        XCTAssertTrue(changes.disappeared.isEmpty)
        XCTAssertEqual(changes.updated.count, 1)
    }

    func testCanonicalInitialTraceCanProveCompletedChangeWithoutAnotherObservation() async throws {
        _ = brains.stash.semanticObservationStream.commitVisibleObservationForTesting(
            volumeScreen(value: "2")
        )
        let after = brains.stash.semanticObservationStream.commitVisibleObservationForTesting(
            volumeScreen(value: "3")
        )
        var settleCount = 0
        let wait = makeStreamBackedPredicateWait(
            settleVisible: { _ in
                settleCount += 1
                return after
            }
        )

        let receipt = await wait.wait(
            for: try resolvedWait(WaitStep(predicate: .changed(.elements()), timeout: .milliseconds(1))),
            initialTrace: after.trace
        )

        XCTAssertTrue(receipt.actionResult.outcome.isSuccess)
        XCTAssertTrue(receipt.expectation.met)
        XCTAssertEqual(settleCount, 0)
    }

    func testSuppliedCanonicalBaselineOverridesStaleInitialTrace() async throws {
        let stream = brains.stash.semanticObservationStream
        let beforeEvent = stream.commitVisibleObservationForTesting(volumeScreen(value: "2"))
        let afterEvent = stream.commitVisibleObservationForTesting(volumeScreen(value: "3"))
        let before = try XCTUnwrap(beforeEvent.settledCapture)
        let after = try XCTUnwrap(afterEvent.settledCapture)
        let staleBrains = TheBrains(tripwire: TheTripwire())
        defer { staleBrains.stopSemanticObservation() }
        let staleEvent = staleBrains.stash.semanticObservationStream.commitVisibleObservationForTesting(
            volumeScreen(value: "1")
        )
        let staleHash = try XCTUnwrap(staleEvent.trace.captures.last?.hash)
        let wait = makeStreamBackedPredicateWait(
            settleVisible: { _ in afterEvent }
        )

        let receipt = await wait.wait(
            for: try resolvedWait(WaitStep(predicate: .changed(.elements()), timeout: .milliseconds(1))),
            initialTrace: staleEvent.trace,
            changeBaseline: .supplied(before)
        )

        XCTAssertTrue(receipt.actionResult.outcome.isSuccess)
        XCTAssertTrue(receipt.expectation.met)
        XCTAssertEqual(
            receipt.actionResult.accessibilityTrace?.captures.map(\.hash),
            [before.capture.hash, after.capture.hash]
        )
        XCTAssertFalse(receipt.actionResult.accessibilityTrace?.captures.contains { $0.hash == staleHash } == true)
    }

    func testPredicateWaitBuildsScreenChangeHistoryOnlyFromCanonicalObservationLog() async throws {
        let stream = brains.stash.semanticObservationStream
        let beforeEvent = stream.commitVisibleObservationForTesting(
            makeScreen(elements: [("ButtonHeist Demo", .header, "root")])
        )
        let actionEndpointEvent = stream.commitVisibleObservationForTesting(
            makeScreen(elements: [("Order Summary", .header, "summary")]),
            notificationBatch: notificationBatch(kind: .screenChanged)
        )
        let destinationEvent = stream.commitVisibleObservationForTesting(
            makeScreen(elements: [
                ("Order Summary", .header, "summary"),
                ("Menu", .button, "menu"),
            ])
        )
        let before = try XCTUnwrap(beforeEvent.settledCapture)
        let actionEndpoint = try XCTUnwrap(actionEndpointEvent.settledCapture)
        let destination = try XCTUnwrap(destinationEvent.settledCapture)
        let wait = makeStreamBackedPredicateWait(
            settleVisible: { _ in destinationEvent }
        )

        let receipt = await wait.wait(
            for: try resolvedWait(WaitStep(
                predicate: .changed(.screen([.exists(.label("Menu"))])),
                timeout: .milliseconds(1)
            )),
            changeBaseline: .supplied(before)
        )

        XCTAssertTrue(receipt.actionResult.outcome.isSuccess)
        XCTAssertTrue(receipt.expectation.met)
        XCTAssertEqual(receipt.traceEvidence?.completeness, .complete)
        let receiptTrace = try XCTUnwrap(receipt.actionResult.accessibilityTrace)
        XCTAssertEqual(
            receiptTrace.captures.map(\.hash),
            [before.capture.hash, actionEndpoint.capture.hash, destination.capture.hash]
        )
        XCTAssertEqual(receiptTrace.captures.last?.interface.projectedElements.last?.label, "Menu")
        XCTAssertTrue(receiptTrace.changeFacts.contains {
            if case .screenChanged = $0 { true } else { false }
        })
    }

    func testCanonicalObservationWindowsKeepScreenAndElementFactsDistinct() throws {
        let elementStream = brains.stash.semanticObservationStream
        let elementBeforeEvent = elementStream.commitVisibleObservationForTesting(volumeScreen(value: "2"))
        let elementAfterEvent = elementStream.commitVisibleObservationForTesting(volumeScreen(value: "3"))
        let elementBefore = try XCTUnwrap(elementBeforeEvent.settledCapture)
        let elementWindow = try XCTUnwrap(elementStream.observationWindow(
            from: elementBefore,
            through: elementAfterEvent
        ))

        let screenBrains = TheBrains(tripwire: TheTripwire())
        defer { screenBrains.stopSemanticObservation() }
        let screenStream = screenBrains.stash.semanticObservationStream
        let screenBeforeEvent = screenStream.commitVisibleObservationForTesting(
            makeScreen(elements: [("Home", .header, "home")])
        )
        let screenAfterEvent = screenStream.commitVisibleObservationForTesting(
            makeScreen(elements: [("Details", .header, "details")]),
            notificationBatch: notificationBatch(kind: .screenChanged)
        )
        let screenBefore = try XCTUnwrap(screenBeforeEvent.settledCapture)
        let screenWindow = try XCTUnwrap(screenStream.observationWindow(
            from: screenBefore,
            through: screenAfterEvent
        ))

        XCTAssertEqual(elementWindow.trace.changeFacts.map(\.kind), [.elementsChanged])
        XCTAssertEqual(
            screenWindow.trace.changeFacts.map(\.kind),
            [.elementsChanged, .screenChanged, .elementsChanged]
        )
        XCTAssertNil(screenAfterEvent.trace.captures.last?.transition.fallbackReason)
    }

    func testObservationWindowRetainsFastRoundTripTransition() throws {
        let baselineEvent = brains.stash.semanticObservationStream.commitVisibleObservationForTesting(
            volumeScreen(value: "50%")
        )
        _ = brains.stash.semanticObservationStream.commitVisibleObservationForTesting(
            volumeScreen(value: "60%")
        )
        let finalEvent = brains.stash.semanticObservationStream.commitVisibleObservationForTesting(
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

    func testObservationWindowTraceContainsExactlyRetainedLogCaptures() throws {
        let baselineEvent = brains.stash.semanticObservationStream.commitDiscoveryObservationForTesting(
            volumeScreen(value: "50%")
        )
        let actionEndpointEvent = brains.stash.semanticObservationStream.commitDiscoveryObservationForTesting(
            volumeScreen(value: "60%")
        )
        let intermediateEvent = brains.stash.semanticObservationStream.commitDiscoveryObservationForTesting(
            volumeScreen(value: "70%")
        )
        let finalEvent = brains.stash.semanticObservationStream.commitDiscoveryObservationForTesting(
            volumeScreen(value: "80%")
        )
        let baseline = try XCTUnwrap(baselineEvent.settledCapture)
        let actionEndpoint = try XCTUnwrap(actionEndpointEvent.settledCapture)
        let intermediate = try XCTUnwrap(intermediateEvent.settledCapture)
        let final = try XCTUnwrap(finalEvent.settledCapture)
        let window = try XCTUnwrap(brains.stash.semanticObservationStream.observationWindow(
            from: baseline,
            through: finalEvent
        ))

        XCTAssertEqual(
            window.trace.captures.map(\.hash),
            [baseline.capture.hash, actionEndpoint.capture.hash, intermediate.capture.hash, final.capture.hash]
        )
        XCTAssertEqual(window.trace.changeFacts.count, 3)
    }

    func testCompleteObservationWindowProducesUnchangedWaitProof() async throws {
        let baselineEvent = brains.stash.semanticObservationStream.commitVisibleObservationForTesting(
            volumeScreen(value: "50%")
        )
        let currentEvent = brains.stash.semanticObservationStream.commitVisibleObservationForTesting(
            volumeScreen(value: "50%")
        )
        let baseline = try XCTUnwrap(baselineEvent.settledCapture)
        let window = try XCTUnwrap(brains.stash.semanticObservationStream.observationWindow(
            from: baseline,
            through: currentEvent
        ))

        XCTAssertEqual(window.completeness, .complete)
        XCTAssertTrue(window.trace.changeFacts.isEmpty)

        let expression = AccessibilityPredicate.noChange
        let predicate = try resolvedPredicate(expression)
        let wait = makeStreamBackedPredicateWait(
            settleVisible: { _ in currentEvent }
        )
        let receipt = await wait.wait(
            for: try resolvedWait(WaitStep(predicate: expression, timeout: .milliseconds(1))),
            changeBaseline: .supplied(baseline)
        )

        XCTAssertTrue(receipt.actionResult.outcome.isSuccess)
        XCTAssertTrue(receipt.expectation.met)
        XCTAssertEqual(receipt.traceEvidence?.completeness, .complete)
        XCTAssertEqual(receipt.actionResult.traceEvidence?.completeness, .complete)
        XCTAssertTrue(predicate.validate(against: receipt.actionResult).met)
    }

    func testIncompleteObservationWindowTimesOutUnchangedWait() async throws {
        let baselineEvent = brains.stash.semanticObservationStream.commitVisibleObservationForTesting(
            volumeScreen(value: "50%")
        )
        let baseline = try XCTUnwrap(baselineEvent.settledCapture)
        var currentEvent = baselineEvent
        for _ in 0...SemanticObservationLog.defaultRetentionLimit {
            currentEvent = brains.stash.semanticObservationStream.commitVisibleObservationForTesting(
                volumeScreen(value: "50%")
            )
        }
        let window = try XCTUnwrap(brains.stash.semanticObservationStream.observationWindow(
            from: baseline,
            through: currentEvent
        ))

        guard case .incomplete = window.completeness else {
            return XCTFail("Expected evicted baseline history to make the window incomplete")
        }
        XCTAssertTrue(window.trace.changeFacts.isEmpty)

        let expression = AccessibilityPredicate.noChange
        let predicate = try resolvedPredicate(expression)
        let wait = makeStreamBackedPredicateWait(
            settleVisible: { _ in currentEvent }
        )
        let receipt = await wait.wait(
            for: try resolvedWait(WaitStep(predicate: expression, timeout: .milliseconds(1))),
            changeBaseline: .supplied(baseline)
        )
        let laterValidation = predicate.validate(
            against: receipt.actionResult
        )

        XCTAssertFalse(receipt.actionResult.outcome.isSuccess)
        XCTAssertEqual(receipt.actionResult.outcome.errorKind, .timeout)
        XCTAssertFalse(receipt.expectation.met)
        XCTAssertEqual(receipt.expectation.actual, "observation history incomplete")
        XCTAssertEqual(receipt.traceEvidence?.completeness, .incomplete)
        XCTAssertEqual(receipt.actionResult.traceEvidence?.completeness, .incomplete)
        XCTAssertFalse(laterValidation.met)
        XCTAssertEqual(laterValidation.actual, "observation history incomplete")
    }

    func testIncompleteObservationWindowUsesOnlyRetainedElementEdges() throws {
        let baselineEvent = brains.stash.semanticObservationStream.commitVisibleObservationForTesting(
            volumeScreen(value: "50%")
        )
        let baseline = try XCTUnwrap(baselineEvent.settledCapture)
        for _ in 0...SemanticObservationLog.defaultRetentionLimit {
            _ = brains.stash.semanticObservationStream.commitVisibleObservationForTesting(
                volumeScreen(value: "50%")
            )
        }
        let currentEvent = brains.stash.semanticObservationStream.commitVisibleObservationForTesting(
            volumeScreen(value: "60%")
        )
        let window = try XCTUnwrap(brains.stash.semanticObservationStream.observationWindow(
            from: baseline,
            through: currentEvent
        ))

        guard case .incomplete = window.completeness else {
            return XCTFail("Expected evicted baseline history to make the window incomplete")
        }
        XCTAssertNotEqual(window.captures.first?.cursor, baseline.cursor)
        XCTAssertEqual(window.trace.changeFacts.count, 1)

        let observation = brains.postActionObservation.semanticObservation(from: currentEvent)
        let expression = AccessibilityPredicate.changed(.elements())
        let predicateResult = PredicateObservationEvidence(
            observation: observation,
            baseline: baseline,
            window: window
        ).evaluate(try resolvedPredicate(expression), expression: expression)
        XCTAssertTrue(predicateResult.met)
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
        let boundaryElementFacts = transitionWindow.trace.changeFacts.compactMap { fact -> AccessibilityTrace.ElementsChangeFact? in
            guard case .elementsChanged(let elements) = fact else { return nil }
            return elements
        }
        XCTAssertEqual(boundaryElementFacts.count, 2)
        XCTAssertFalse(boundaryElementFacts[0].disappeared.isEmpty)
        XCTAssertTrue(boundaryElementFacts[0].appeared.isEmpty)
        XCTAssertFalse(boundaryElementFacts[1].appeared.isEmpty)
        XCTAssertTrue(boundaryElementFacts[1].disappeared.isEmpty)
        XCTAssertTrue(boundaryElementFacts.allSatisfy(\.updated.isEmpty))

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

        notifications.recordForTesting(code: 1000, notificationData: .none, associatedElement: .none)
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
        notifications.recordForTesting(code: 1000, notificationData: .none, associatedElement: .none)
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

        let screenExpression = AccessibilityPredicate.changed(.screen())
        let elementExpression = AccessibilityPredicate.changed(.elements())
        let screenPredicate = screenEvidence.evaluate(
            try resolvedPredicate(screenExpression),
            expression: screenExpression
        )
        let elementPredicateAgainstScreen = screenEvidence.evaluate(
            try resolvedPredicate(elementExpression),
            expression: elementExpression
        )
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

        let elementPredicate = elementEvidence.evaluate(
            try resolvedPredicate(elementExpression),
            expression: elementExpression
        )
        let screenPredicateAgainstElement = elementEvidence.evaluate(
            try resolvedPredicate(screenExpression),
            expression: screenExpression
        )
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
        let expression = AccessibilityPredicate.changed(.elements())
        let predicate = try resolvedPredicate(expression)
        let seeded = stream.reducing(
            brains.postActionObservation.semanticObservation(from: baselineEvent),
            predicate: predicate,
            predicateExpression: expression,
            baselineSeed: .currentObservation
        )
        stream = seeded.state

        let intermediate = stream.reducing(
            brains.postActionObservation.semanticObservation(from: intermediateEvent),
            predicate: predicate,
            predicateExpression: expression,
            baselineSeed: .preserve,
            observationWindow: try XCTUnwrap(brains.stash.semanticObservationStream.observationWindow(
                from: try XCTUnwrap(baselineEvent.settledCapture),
                through: intermediateEvent
            ))
        )
        stream = intermediate.state
        let final = stream.reducing(
            brains.postActionObservation.semanticObservation(from: finalEvent),
            predicate: predicate,
            predicateExpression: expression,
            baselineSeed: .preserve,
            observationWindow: try XCTUnwrap(brains.stash.semanticObservationStream.observationWindow(
                from: try XCTUnwrap(baselineEvent.settledCapture),
                through: finalEvent
            ))
        )

        XCTAssertEqual(intermediate.reduction.changeBaseline?.cursor.sequence, baselineEvent.sequence)
        XCTAssertEqual(final.reduction.changeBaseline?.cursor.sequence, baselineEvent.sequence)
        XCTAssertEqual(final.reduction.observationWindow?.baseline.cursor.sequence, baselineEvent.sequence)
        XCTAssertEqual(final.reduction.observationWindow?.current.cursor.sequence, finalEvent.sequence)
    }

    func testPredicateObservationStreamDoesNotOwnWindowForCurrentStateWait() throws {
        let predicate: AccessibilityPredicate = .missing(
            .label("Removed")
        )
        let baselineEvent = brains.stash.semanticObservationStream.commitVisibleObservationForTesting(
            makeScreen(elements: [
                ("Anchor", .staticText, "anchor"),
                ("Removed", .staticText, "removed"),
            ])
        )
        let finalEvent = brains.stash.semanticObservationStream.commitVisibleObservationForTesting(
            makeScreen(elements: [("Anchor", .staticText, "anchor")])
        )

        var stream = PredicateObservationStreamState()
        let resolved = try resolvedPredicate(predicate)
        let seeded = stream.reducing(
            brains.postActionObservation.semanticObservation(from: baselineEvent),
            predicate: resolved,
            predicateExpression: predicate,
            baselineSeed: .currentObservation
        )
        stream = seeded.state
        let final = stream.reducing(
            brains.postActionObservation.semanticObservation(from: finalEvent),
            predicate: resolved,
            predicateExpression: predicate,
            baselineSeed: .preserve
        )

        XCTAssertTrue(final.reduction.expectation.met)
        XCTAssertNil(final.reduction.changeBaseline)
        XCTAssertNil(final.reduction.observationWindow)
        XCTAssertTrue(final.reduction.trace?.changeFacts.contains {
            if case .elementsChanged = $0 { true } else { false }
        } == true)
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

    func testDiscoveryObservationStateUsesDiscoveryInterfaceWhileTraceStaysSemantic() throws {
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
            continuity: .sameGeneration,
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
        let predicate = AccessibilityPredicate.exists(.container(.identifier("OffscreenGroup")))
        let resolved = try resolvedPredicate(predicate)
        XCTAssertEqual(
            PredicateEvaluation.evaluate(resolved, expression: predicate, in: observation),
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
            target: try AccessibilityTarget.label(label).resolve(in: .empty)
        ) else {
            return XCTFail("Expected target exploration to settle")
        }

        XCTAssertEqual(exploration.manifest.scrollCount, 0)
        XCTAssertTrue(exploration.manifest.pendingScrollPaths.isEmpty)
        XCTAssertTrue(exploration.manifest.exploredScrollPaths.isEmpty)
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

        exploration.recordCommittedObservation(
            continuity: .sameGeneration,
            scrollableContainers: page.tree.orderedContainers.filter { $0.container.isScrollable }
        )

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

        exploration.recordCommittedObservation(
            continuity: .sameGeneration,
            scrollableContainers: page.tree.orderedContainers.filter { $0.container.isScrollable }
        )

        XCTAssertTrue(exploration.manifest.exploredScrollPaths.contains(outerPath))
        XCTAssertFalse(exploration.manifest.pendingScrollPaths.contains(outerPath))
        XCTAssertTrue(exploration.manifest.pendingScrollPaths.contains(nestedPath))
    }

    func testSemanticExplorationFinishOwnsExplorationTimestamp() {
        var exploration = Navigation.SemanticExploration(baseline: .interfaceMemory(.empty))
        let event = brains.stash.semanticObservationStream.commitDiscoveryObservationForTesting(.empty)

        let result = exploration.finish(
            startTime: CACurrentMediaTime() - 0.01,
            event: event,
            didMoveViewport: false
        )

        XCTAssertGreaterThan(result.manifest.explorationTime, 0)
        XCTAssertFalse(result.didMoveViewport)
        XCTAssertEqual(result.event.observation.screen.tree, InterfaceObservation.empty.tree)
        XCTAssertEqual(
            result.event.observation.screen.liveCapture.snapshot,
            InterfaceObservation.empty.liveCapture.snapshot
        )
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
        method: ActionMethod = .activate,
        subjectEvidence: ActionSubjectEvidence? = nil,
        activationTrace: ActivationTrace? = nil
    ) -> TheSafecracker.ActionDispatchOutcome {
        .success(
            method: method,
            subjectEvidence: subjectEvidence,
            activationTrace: activationTrace
        )
    }

    private func failureOutcome(
        method: ActionMethod = .activate,
        message: String = "action failed",
        subjectEvidence: ActionSubjectEvidence? = nil,
        failureKind: TheSafecracker.FailureKind = .actionFailed,
        activationTrace: ActivationTrace? = nil
    ) -> TheSafecracker.ActionDispatchOutcome {
        .failure(
            method,
            message: message,
            subjectEvidence: subjectEvidence,
            activationTrace: activationTrace,
            failureKind: failureKind
        )
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

    private func makeStreamBackedPredicateWait(
        settleVisible: @escaping PredicateWait.SettleVisible,
        discover: @escaping PredicateWait.Discover = { _, _, _ in nil }
    ) -> PredicateWait {
        let stream = brains.stash.semanticObservationStream
        return PredicateWait(
            observeEvent: { _, _, _ in nil },
            latestEvent: { stream.latestEvent },
            latestSettleFailure: { stream.latestSettleFailureDiagnostic },
            semanticObservation: { event in
                self.brains.postActionObservation.semanticObservation(from: event)
            },
            buildObservationWindow: { baseline, event in
                stream.observationWindow(from: baseline, through: event)
            },
            presenceTimeoutMessage: { _, _ in nil },
            announcementCursor: { _ in .origin },
            waitForAnnouncement: { _, _, _ in nil },
            settleVisible: settleVisible,
            discover: discover
        )
    }

    private func temporalWaitReceipt(
        predicate: AccessibilityPredicate,
        baseline: InterfaceObservation,
        final: InterfaceObservation
    ) async throws -> HeistWaitReceipt {
        let stream = brains.stash.semanticObservationStream
        let baselineEvent = stream.commitVisibleObservationForTesting(baseline)
        let finalEvent = stream.commitVisibleObservationForTesting(final)
        let baselineCapture = try XCTUnwrap(baselineEvent.settledCapture)
        let wait = makeStreamBackedPredicateWait(
            settleVisible: { _ in finalEvent }
        )
        return await wait.wait(
            for: try resolvedWait(WaitStep(predicate: predicate, timeout: .milliseconds(1))),
            changeBaseline: .supplied(baselineCapture)
        )
    }

    private func elementChanges(
        in receipt: HeistWaitReceipt
    ) -> [AccessibilityTrace.ElementsChangeFact] {
        receipt.actionResult.accessibilityTrace?.changeFacts.compactMap { fact in
            guard case .elementsChanged(let changes) = fact else { return nil }
            return changes
        } ?? []
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

    private func activationSubjectEvidence(
        target: AccessibilityTarget,
        element: AccessibilityElement,
        settledObservationSequence: SettledObservationSequence?
    ) throws -> ActionSubjectEvidence {
        ActionSubjectEvidence(
            source: .resolvedSemanticTarget,
            target: try target.resolve(in: .empty),
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
