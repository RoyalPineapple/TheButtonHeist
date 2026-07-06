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
/// that operate purely against the current `Screen` snapshot: failure result
/// assembly, classified trace projections, wait-change guards, and
/// semantic discovery observation.
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

        XCTAssertFalse(result.success)
        XCTAssertEqual(result.method, .activate)
        XCTAssertEqual(result.message, "target disappeared")
        XCTAssertEqual(result.errorKind, .actionFailed,
                       "Without explicit errorKind, failures default to actionFailed")
        XCTAssertEqual(result.settled, true)
        XCTAssertEqual(result.settleTimeMs, 44)
        XCTAssertEqual(result.accessibilityTrace?.captures.first?.hash, before.capture.hash)
        XCTAssertNotNil(result.accessibilityTrace?.captures.last)
        guard case .elementsChanged? = result.accessibilityTrace?.endpointDelta else {
            return XCTFail("Expected elementsChanged delta, got \(String(describing: result.accessibilityTrace?.endpointDelta))")
        }
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
        let screen = Screen.makeForTests(
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
            .predicate(ElementPredicate(label: "Email"))
        )
    }

    func testScreenChangeFinalStateKeepsPersistentVisibleElement() async throws {
        let persistent = AccessibilityElement.make(
            label: "Inbox",
            traits: .staticText,
            respondsToUserInteraction: false
        )
        let beforeScreen = Screen.makeForTests(elements: [
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
        let afterScreen = Screen.makeForTests(elements: [
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

        XCTAssertTrue(result.success, result.message ?? "action unexpectedly failed")
        XCTAssertEqual(
            result.accessibilityTrace?.captures.last?.transition.screenChangeReason,
            "navigationMarkerChanged"
        )
        let labels = try XCTUnwrap(result.accessibilityTrace?.captures.last?.interface.projectedElements)
            .compactMap(\.label)
        XCTAssertTrue(labels.contains("Inbox"), "Persistent visible chrome must survive screen-change final evidence")
    }

    func testActionErrorKindClassifiesTargetUnavailableSeparatelyFromActionIdentity() {
        let result = TheSafecracker.InteractionResult.failure(
            .activate,
            message: "target disappeared",
            failureKind: .targetUnavailable
        )

        XCTAssertEqual(TheBrains.actionErrorKind(for: result), .elementNotFound)
        XCTAssertEqual(result.method, .activate)
    }

    func testActionErrorKindPreservesTreeUnavailableFailureKind() {
        let result = TheSafecracker.InteractionResult.failure(
            .activate,
            message: TheBrains.treeUnavailableMessage,
            failureKind: .treeUnavailable
        )

        XCTAssertEqual(TheBrains.actionErrorKind(for: result), .accessibilityTreeUnavailable)
    }

    func testInteractionResultDecoratorsPreserveExistingFieldsAndMergeTiming() {
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
            target: .predicate(ElementPredicate(label: "Checkout", traits: [.button])),
            element: element
        )
        let replacementEvidence = ActionSubjectEvidence(
            source: .elementGestureTarget,
            target: .predicate(ElementPredicate(identifier: "checkout_button")),
            element: element
        )
        let activationTrace = ActivationTrace(.activationPointFallback(
            axActivateReturned: false,
            tapActivationPoint: ScreenPoint(x: 50, y: 22),
            tapActivationSucceeded: true
        ))
        let success = TheSafecracker.InteractionResult.success(
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

        let failure = TheSafecracker.InteractionResult.failure(
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
            settleOutcome: settledOutcome(finalScreen: brains.stash.settledSemanticScreen)
        )

        XCTAssertEqual(result.errorKind, .actionFailed)
    }

    func testPostActionObservationFailureRespectsExplicitErrorKind() async {
        let before = brains.postActionObservation.captureSemanticState()

        let result = await brains.interactionObservation.finishAfterAction(
            method: .activate,
            outcome: failureOutcome(errorKind: .timeout),
            before: before,
            settleOutcome: settledOutcome(finalScreen: brains.stash.settledSemanticScreen)
        )

        XCTAssertEqual(result.errorKind, .timeout,
                       "An explicit errorKind must override the method-based inference")
    }

    func testPostActionObservationFailureCarriesValueAndMessage() async {
        let before = brains.postActionObservation.captureSemanticState()

        let result = await brains.interactionObservation.finishAfterAction(
            method: .getPasteboard,
            outcome: failureOutcome(payload: .getPasteboard("")),
            message: "pasteboard empty",
            before: before,
            settleOutcome: settledOutcome(finalScreen: brains.stash.settledSemanticScreen)
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
        let screen = Screen.makeForTests(elements: [(element, HeistId(rawValue: "inert_option"))])
        brains.stash.installScreenForTesting(screen)
        let before = brains.postActionObservation.captureSemanticState()

        let result = await brains.interactionObservation.finishAfterAction(
            method: .activate,
            outcome: successOutcome(
                subjectEvidence: activationSubjectEvidence(
                    target: .predicate(ElementPredicate(identifier: "inert_option")),
                    element: element,
                    settledObservationSequence: before.settledObservationSequence
                )
            ),
            before: before,
            settleOutcome: settledOutcome(finalScreen: screen)
        )

        XCTAssertTrue(result.success, result.message ?? "activate unexpectedly failed")
        XCTAssertEqual(result.method, .activate)
        XCTAssertNil(result.errorKind)
        XCTAssertNil(result.message)
        XCTAssertNotNil(result.accessibilityTrace)
        XCTAssertEqual(result.accessibilityTrace?.captures.first?.hash, before.capture.hash)
        XCTAssertNotNil(result.accessibilityTrace?.captures.last?.hash)
        guard case .noChange? = result.accessibilityTrace?.endpointDelta else {
            return XCTFail("Expected noChange delta, got \(String(describing: result.accessibilityTrace?.endpointDelta))")
        }
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

        let labels = Set(brains.stash.settledSemanticScreen.semantic.elements.values.compactMap(\.element.label))
        XCTAssertTrue(result.success)
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

        XCTAssertTrue(result.success, result.message ?? "tap unexpectedly failed")
        XCTAssertEqual(result.method, .syntheticTap)
        XCTAssertNil(result.errorKind)
        guard case .noChange? = result.accessibilityTrace?.endpointDelta else {
            return XCTFail("Expected noChange delta, got \(String(describing: result.accessibilityTrace?.endpointDelta))")
        }
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
        let screen = Screen.makeForTests(elements: [(element, HeistId(rawValue: "tap_activated_option"))])
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
                    target: .predicate(ElementPredicate(identifier: "tap_activated_option")),
                    element: element,
                    settledObservationSequence: before.settledObservationSequence
                ),
                activationTrace: activationTrace
            ),
            before: before,
            settleOutcome: settledOutcome(finalScreen: screen)
        )

        XCTAssertTrue(result.success, result.message ?? "activate unexpectedly failed")
        XCTAssertNil(result.errorKind)
        XCTAssertNil(result.message)
        XCTAssertEqual(result.activationTrace, activationTrace)
        guard case .noChange? = result.accessibilityTrace?.endpointDelta else {
            return XCTFail("Expected noChange delta, got \(String(describing: result.accessibilityTrace?.endpointDelta))")
        }
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

        XCTAssertTrue(result.success, result.message ?? "action unexpectedly failed")
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
            target: .predicate(ElementPredicate(label: "Delete", traits: [.button])),
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
            settledObservationSequence: before.settledObservationSequence
        )

        let result = await brains.interactionObservation.finishAfterAction(
            method: .activate,
            outcome: successOutcome(subjectEvidence: evidence),
            before: before,
            settleOutcome: settledOutcome(finalScreen: beforeScreen)
        )

        XCTAssertTrue(result.success, result.message ?? "action unexpectedly failed")
        XCTAssertEqual(result.subjectEvidence, evidence)
    }

    func testActionResultWithDeltaSuccessReportsScreenChange() async {
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

        XCTAssertTrue(result.success, result.message ?? "action unexpectedly failed")
        guard case .screenChanged? = result.accessibilityTrace?.endpointDelta else {
            return XCTFail("Expected screenChanged delta, got \(String(describing: result.accessibilityTrace?.endpointDelta))")
        }
    }

    func testScreenChangeReceiptRefinesMixedTransitionSurface() async throws {
        let beforeScreen = makeScreen(elements: [
            ("ButtonHeist Demo", .header, "root_header"),
            ("Controls Demo", .button, "controls_demo"),
            ("Todo List", .button, "todo_list"),
            ("Words", .button, "words"),
        ])
        brains.stash.installScreenForTesting(beforeScreen)
        let before = brains.postActionObservation.captureSemanticState()

        let mixedTransitionScreen = makeScreen(elements: [
            ("Controls Demo", .button, "controls_demo"),
            ("Todo List", .button, "todo_list"),
            ("Words", .button, "words"),
            ("Section A", .header, "section_a_header"),
            ("A acid", .button, "a_acid"),
            ("abacus major", .button, "abacus_major"),
            ("ButtonHeist Demo", .backButton, "back_button"),
        ])
        let cleanSettledScreen = makeScreen(elements: [
            ("Section A", .header, "section_a_header"),
            ("A acid", .button, "a_acid"),
            ("abacus major", .button, "abacus_major"),
            ("ButtonHeist Demo", .backButton, "back_button"),
        ])
        brains.stash.nextVisibleRefreshScreenForTesting = cleanSettledScreen

        let result = await brains.interactionObservation.finishAfterAction(
            method: .activate,
            outcome: successOutcome(),
            before: before,
            settleOutcome: settledOutcome(finalScreen: mixedTransitionScreen)
        )

        XCTAssertTrue(result.success, result.message ?? "action unexpectedly failed")
        guard case .screenChanged(let payload)? = result.accessibilityTrace?.endpointDelta else {
            return XCTFail("Expected screenChanged delta, got \(String(describing: result.accessibilityTrace?.endpointDelta))")
        }

        let labels = payload.newInterface.projectedElements.compactMap { $0.label }
        XCTAssertTrue(labels.contains("Section A"), "Expected new screen labels: \(labels)")
        XCTAssertTrue(labels.contains("A acid"), "Expected new screen labels: \(labels)")
        XCTAssertTrue(labels.contains("abacus major"), "Expected new screen labels: \(labels)")
        XCTAssertTrue(labels.contains("ButtonHeist Demo"), "Expected back button to remain: \(labels)")
        XCTAssertFalse(labels.contains("Controls Demo"))
        XCTAssertFalse(labels.contains("Todo List"))
        XCTAssertEqual(
            brains.stash.settledSemanticScreen.orderedElements.compactMap(\.element.label),
            ["Section A", "A acid", "abacus major", "ButtonHeist Demo"]
        )
    }

    func testScreenChangeNotificationReferencesAreRemappedAfterPruning() async throws {
        let beforeScreen = makeScreen(elements: [
            ("ButtonHeist Demo", .header, "root_header"),
            ("Controls Demo", .button, "controls_demo"),
            ("Todo List", .button, "todo_list"),
            ("Words", .button, "words"),
        ])
        brains.stash.installScreenForTesting(beforeScreen)
        let before = brains.postActionObservation.captureSemanticState()

        let controls = AccessibilityElement.make(
            label: "Controls Demo",
            traits: .button,
            respondsToUserInteraction: false
        )
        let todos = AccessibilityElement.make(
            label: "Todo List",
            traits: .button,
            respondsToUserInteraction: false
        )
        let words = AccessibilityElement.make(
            label: "Words",
            traits: .button,
            respondsToUserInteraction: false
        )
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
        let mixedTransitionScreen = Screen.makeForTests([
            .init(controls, heistId: "controls_demo"),
            .init(todos, heistId: "todo_list"),
            .init(words, heistId: "words"),
            .init(section, heistId: "section_a_header"),
            .init(acid, heistId: "a_acid", object: acidObject),
            .init(abacus, heistId: "abacus_major"),
            .init(back, heistId: "back_button"),
        ])
        let cleanSettledScreen = Screen.makeForTests([
            .init(section, heistId: "section_a_header"),
            .init(acid, heistId: "a_acid"),
            .init(abacus, heistId: "abacus_major"),
            .init(back, heistId: "back_button"),
        ])
        brains.stash.nextVisibleRefreshScreenForTesting = cleanSettledScreen
        let notificationWindow = brains.stash.accessibilityNotifications.beginActionWindow()
        defer { notificationWindow.cancel() }
        brains.stash.accessibilityNotifications.record(
            code: 1001,
            notificationData: CapturedAccessibilityNotificationPayload(acidObject),
            associatedElement: .none
        )

        let result = await brains.interactionObservation.finishAfterAction(
            method: .activate,
            outcome: successOutcome(),
            before: before,
            settleOutcome: settledOutcome(finalScreen: mixedTransitionScreen),
            notificationWindow: notificationWindow
        )

        let notification = try XCTUnwrap(
            result.accessibilityTrace?.captures.last?.transition.accessibilityNotifications.first
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
        let finalScreen = Screen.makeForTests([
            .init(saved, heistId: "saved", object: notifiedObject),
        ])
        let notificationWindow = brains.stash.accessibilityNotifications.beginActionWindow()
        defer { notificationWindow.cancel() }
        brains.stash.accessibilityNotifications.record(
            code: 1001,
            notificationData: CapturedAccessibilityNotificationPayload(notifiedObject),
            associatedElement: .none
        )

        brains.stash.semanticObservationStream.commitSettledVisibleObservation(
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
        let discoveryAfter = Screen.makeForTests(
            elements: [(AccessibilityElement.make(
                label: "Controls Demo",
                traits: .header,
                respondsToUserInteraction: false
                ), HeistId(rawValue: "controls_demo"))],
            offViewport: [
                Screen.OffViewportEntry(
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
        brains.stash.semanticObservationStream.commitSettledDiscoveryObservation(discoveryAfter)

        let result = await resultTask.value
        XCTAssertTrue(result.success, result.message ?? "action unexpectedly failed")

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

        XCTAssertTrue(result.success, result.message ?? "action unexpectedly failed")
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
        XCTAssertEqual(brains.stash.settledSemanticScreen.orderedElements.first?.element.label, "Save")
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

        XCTAssertFalse(result.success)
        XCTAssertEqual(result.message, "cancelled after 125ms")
        XCTAssertEqual(result.errorKind, .actionFailed)
        XCTAssertEqual(result.settled, false)
        XCTAssertEqual(result.settleTimeMs, 125)
        XCTAssertEqual(brains.stash.latestSettledSemanticObservationEvent?.sequence, settledSequence)
        XCTAssertTrue(brains.stash.latestSettledSemanticObservationInvalidated)
        XCTAssertEqual(brains.stash.settledSemanticScreen.orderedElements.first?.element.label, "Save")
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

        XCTAssertFalse(result.success)
        XCTAssertEqual(result.message, "Could not parse post-action accessibility tree")
        XCTAssertEqual(result.errorKind, .actionFailed)
        XCTAssertEqual(result.settled, false)
        XCTAssertEqual(result.settleTimeMs, 300)
    }

    // MARK: - Wait Evidence Path

    func testWaitCurrentSuccessUsesSettledObservationEvidence() async throws {
        let isolatedBrains = TheBrains(tripwire: TheTripwire())
        defer { isolatedBrains.stopSemanticObservation() }
        let matchedScreen = Screen.makeForTests(elements: [
            (makeElement(label: "Home"), HeistId(rawValue: "home")),
        ])

        let receiptTask = Task { @MainActor in
            await isolatedBrains.interactionObservation.waitForPredicate(WaitStep(
                predicate: .state(.exists(ElementPredicate(label: "Home"))),
                timeout: 1
            ))
        }

        await waitForSettledSemanticWaiter(on: isolatedBrains.stash)
        _ = isolatedBrains.stash.semanticObservationStream.commitSettledDiscoveryObservation(matchedScreen)

        let receipt = await receiptTask.value
        let trace = try XCTUnwrap(receipt.actionResult.accessibilityTrace)

        XCTAssertTrue(receipt.actionResult.success)
        XCTAssertEqual(trace.captures.last?.interface.projectedElements.map(\.label), ["Home"])
        XCTAssertEqual(receipt.expectation.met, true)
    }

    func testWaitCurrentTimeoutWithoutSettledObservationFails() async {
        let isolatedBrains = TheBrains(tripwire: TheTripwire())
        defer { isolatedBrains.stopSemanticObservation() }

        let receipt = await isolatedBrains.interactionObservation.waitForPredicate(WaitStep(
            predicate: .state(.exists(ElementPredicate(label: "Home"))),
            timeout: 0.01
        ))

        XCTAssertFalse(receipt.actionResult.success)
        XCTAssertEqual(receipt.actionResult.errorKind, .timeout)
        XCTAssertEqual(receipt.expectation.met, false)
        XCTAssertTrue(receipt.actionResult.message?.contains("no settled semantic observation available") == true)
    }

    func testWaitSuccessEvidenceUsesSettledObservationTrace() async throws {
        let isolatedBrains = TheBrains(tripwire: TheTripwire())
        defer { isolatedBrains.stopSemanticObservation() }
        let beforeScreen = Screen.makeForTests(elements: [
            (makeElement(label: "Before"), HeistId(rawValue: "before")),
        ])
        let matchedScreen = Screen.makeForTests(elements: [
            (makeElement(label: "Before"), HeistId(rawValue: "before")),
            (makeElement(label: "Loaded"), HeistId(rawValue: "loaded")),
        ])

        let receiptTask = Task { @MainActor in
            await isolatedBrains.interactionObservation.waitForPredicate(WaitStep(
                predicate: .exists(ElementPredicate(label: "Loaded")),
                timeout: 1
            ))
        }

        await waitForSettledSemanticWaiter(on: isolatedBrains.stash)
        _ = isolatedBrains.stash.semanticObservationStream.commitSettledDiscoveryObservation(beforeScreen)
        await waitForSettledSemanticWaiter(on: isolatedBrains.stash)
        _ = isolatedBrains.stash.semanticObservationStream.commitSettledDiscoveryObservation(matchedScreen)

        let receipt = await receiptTask.value
        let trace = try XCTUnwrap(receipt.actionResult.accessibilityTrace)

        XCTAssertTrue(receipt.actionResult.success)
        XCTAssertEqual(trace.captures.first?.interface.projectedElements.map(\.label), ["Before"])
        XCTAssertEqual(trace.captures.last?.interface.projectedElements.map(\.label), ["Before", "Loaded"])
        guard case .elementsChanged? = trace.endpointDelta else {
            return XCTFail("Expected elementsChanged delta, got \(String(describing: trace.endpointDelta))")
        }
    }

    func testWaitTimeoutEvidenceUsesLastSettledObservationTrace() async throws {
        let isolatedBrains = TheBrains(tripwire: TheTripwire())
        defer { isolatedBrains.stopSemanticObservation() }
        let observedScreen = Screen.makeForTests(elements: [
            (makeElement(label: "Known"), HeistId(rawValue: "known")),
        ])

        let receiptTask = Task { @MainActor in
            await isolatedBrains.interactionObservation.waitForPredicate(WaitStep(
                predicate: .exists(ElementPredicate(label: "Missing")),
                timeout: 0.05
            ))
        }

        await waitForSettledSemanticWaiter(on: isolatedBrains.stash)
        _ = isolatedBrains.stash.semanticObservationStream.commitSettledDiscoveryObservation(observedScreen)

        let receipt = await receiptTask.value
        let trace = try XCTUnwrap(receipt.actionResult.accessibilityTrace)

        XCTAssertFalse(receipt.actionResult.success)
        XCTAssertEqual(receipt.actionResult.errorKind, .timeout)
        XCTAssertEqual(trace.captures.last?.interface.projectedElements.map(\.label), ["Known"])
        XCTAssertTrue(receipt.actionResult.message?.contains("known: 1 elements") == true)
        XCTAssertTrue(receipt.actionResult.message?.contains("last result:") == true)
    }

    func testDisappearedWaitWarnsWhenFinalStateIsAlreadyAbsent() async throws {
        let isolatedBrains = TheBrains(tripwire: TheTripwire())
        defer { isolatedBrains.stopSemanticObservation() }
        let emptyScreen = Screen.makeForTests(elements: [])

        let receiptTask = Task { @MainActor in
            await isolatedBrains.interactionObservation.waitForPredicate(WaitStep(
                predicate: .disappeared(.label("Loading")),
                timeout: 0.05
            ))
        }

        await waitForSettledSemanticWaiter(on: isolatedBrains.stash)
        _ = isolatedBrains.stash.semanticObservationStream.commitSettledDiscoveryObservation(emptyScreen)

        let receipt = await receiptTask.value

        XCTAssertTrue(receipt.actionResult.success)
        XCTAssertEqual(receipt.expectation.met, true)
        XCTAssertEqual(receipt.warning?.code, "transition_not_observed_final_state_satisfied")
        XCTAssertTrue(receipt.warning?.message.contains("already absent") == true)
        XCTAssertEqual(receipt.warning?.evidence, "Loading")
    }

    func testAppearedWaitWarnsWhenFinalStateIsAlreadyPresent() async throws {
        let isolatedBrains = TheBrains(tripwire: TheTripwire())
        defer { isolatedBrains.stopSemanticObservation() }
        let readyScreen = Screen.makeForTests(elements: [
            (makeElement(label: "Ready"), HeistId(rawValue: "ready")),
        ])

        let receiptTask = Task { @MainActor in
            await isolatedBrains.interactionObservation.waitForPredicate(WaitStep(
                predicate: .appeared(.label("Ready")),
                timeout: 0.05
            ))
        }

        await waitForSettledSemanticWaiter(on: isolatedBrains.stash)
        _ = isolatedBrains.stash.semanticObservationStream.commitSettledDiscoveryObservation(readyScreen)

        let receipt = await receiptTask.value

        XCTAssertTrue(receipt.actionResult.success)
        XCTAssertEqual(receipt.expectation.met, true)
        XCTAssertEqual(receipt.warning?.code, "transition_not_observed_final_state_satisfied")
        XCTAssertEqual(receipt.warning?.evidence, "label=Ready")
        XCTAssertTrue(receipt.warning?.message.contains("already present") == true)
    }

    func testUpdatedWaitWarnsWhenFinalStateAlreadyMatches() async throws {
        let isolatedBrains = TheBrains(tripwire: TheTripwire())
        defer { isolatedBrains.stopSemanticObservation() }
        let quantity = AccessibilityElement.make(
            label: "Quantity",
            value: "3",
            traits: .staticText,
            respondsToUserInteraction: false
        )
        let quantityScreen = Screen.makeForTests(elements: [
            (quantity, HeistId(rawValue: "quantity")),
        ])

        let receiptTask = Task { @MainActor in
            await isolatedBrains.interactionObservation.waitForPredicate(WaitStep(
                predicate: .change(.updated(.label("Quantity"), .value("3"))),
                timeout: 0.05
            ))
        }

        await waitForSettledSemanticWaiter(on: isolatedBrains.stash)
        _ = isolatedBrains.stash.semanticObservationStream.commitSettledDiscoveryObservation(quantityScreen)

        let receipt = await receiptTask.value

        XCTAssertTrue(receipt.actionResult.success)
        XCTAssertEqual(receipt.expectation.met, true)
        XCTAssertEqual(receipt.warning?.code, "transition_not_observed_final_state_satisfied")
        XCTAssertEqual(receipt.warning?.finalStateTiming, "baseline")
        XCTAssertTrue(receipt.warning?.impliedPredicate?.contains("destination_state") == true)
        XCTAssertEqual(receipt.warning?.evidence, "label=Quantity")
        XCTAssertTrue(receipt.warning?.message.contains("no update transition was observed") == true)
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
        let quantityScreen = Screen.makeForTests(elements: [
            (quantity, HeistId(rawValue: "quantity")),
        ])

        let receiptTask = Task { @MainActor in
            await isolatedBrains.interactionObservation.waitForPredicate(WaitStep(
                predicate: .change(.updated(.label("Quantity"), .value(before: "2", after: "3"))),
                timeout: 0.05
            ))
        }

        await waitForSettledSemanticWaiter(on: isolatedBrains.stash)
        _ = isolatedBrains.stash.semanticObservationStream.commitSettledDiscoveryObservation(quantityScreen)

        let receipt = await receiptTask.value

        XCTAssertFalse(receipt.actionResult.success)
        XCTAssertEqual(receipt.actionResult.errorKind, .timeout)
        XCTAssertEqual(receipt.expectation.met, false)
        XCTAssertNil(receipt.warning)
    }

    func testFromToUpdatedWaitWarningCanBeDisabledForActionExpectationSemantics() async throws {
        let isolatedBrains = TheBrains(tripwire: TheTripwire())
        defer { isolatedBrains.stopSemanticObservation() }
        let quantity = AccessibilityElement.make(
            label: "Quantity",
            value: "3",
            traits: .staticText,
            respondsToUserInteraction: false
        )
        let quantityScreen = Screen.makeForTests(elements: [
            (quantity, HeistId(rawValue: "quantity")),
        ])

        let receiptTask = Task { @MainActor in
            await isolatedBrains.interactionObservation.waitForPredicate(
                WaitStep(
                    predicate: .change(.updated(.label("Quantity"), .value(before: "2", after: "3"))),
                    timeout: 0.05
                ),
                allowsTransitionFinalStateWarning: false
            )
        }

        await waitForSettledSemanticWaiter(on: isolatedBrains.stash)
        _ = isolatedBrains.stash.semanticObservationStream.commitSettledDiscoveryObservation(quantityScreen)

        let receipt = await receiptTask.value

        XCTAssertFalse(receipt.actionResult.success)
        XCTAssertEqual(receipt.expectation.met, false)
        XCTAssertNil(receipt.warning)
    }

    func testTransitionFinalStateWarningCanBeDisabledForActionExpectationSemantics() async throws {
        let isolatedBrains = TheBrains(tripwire: TheTripwire())
        defer { isolatedBrains.stopSemanticObservation() }
        let emptyScreen = Screen.makeForTests(elements: [])

        let receiptTask = Task { @MainActor in
            await isolatedBrains.interactionObservation.waitForPredicate(
                WaitStep(
                    predicate: .disappeared(.label("Loading")),
                    timeout: 0.05
                ),
                allowsTransitionFinalStateWarning: false
            )
        }

        await waitForSettledSemanticWaiter(on: isolatedBrains.stash)
        _ = isolatedBrains.stash.semanticObservationStream.commitSettledDiscoveryObservation(emptyScreen)

        let receipt = await receiptTask.value

        XCTAssertFalse(receipt.actionResult.success)
        XCTAssertEqual(receipt.expectation.met, false)
        XCTAssertNil(receipt.warning)
    }

    func testDisappearedWaitDoesNotWarnWhenTransitionIsObserved() async throws {
        let isolatedBrains = TheBrains(tripwire: TheTripwire())
        defer { isolatedBrains.stopSemanticObservation() }
        let loadingScreen = Screen.makeForTests(elements: [
            (makeElement(label: "Loading"), HeistId(rawValue: "loading")),
        ])
        let emptyScreen = Screen.makeForTests(elements: [])

        let receiptTask = Task { @MainActor in
            await isolatedBrains.interactionObservation.waitForPredicate(WaitStep(
                predicate: .disappeared(.label("Loading")),
                timeout: 1
            ))
        }

        await waitForSettledSemanticWaiter(on: isolatedBrains.stash)
        _ = isolatedBrains.stash.semanticObservationStream.commitSettledDiscoveryObservation(loadingScreen)
        await waitForSettledSemanticWaiter(on: isolatedBrains.stash)
        _ = isolatedBrains.stash.semanticObservationStream.commitSettledDiscoveryObservation(emptyScreen)

        let receipt = await receiptTask.value

        XCTAssertTrue(receipt.actionResult.success)
        XCTAssertEqual(receipt.expectation.met, true)
        XCTAssertNil(receipt.warning)
    }

    func testPredicatePollingReducerFinishesVisibleMatch() {
        let reducer = PredicatePollingReducer(timeout: 1, pollWhenTimeoutZero: true)
        var reduction = reducer.start(scope: .visible, initialObservedSequence: nil)

        XCTAssertEqual(reduction.effect, .observe(.visibleImmediate(after: nil)))

        reduction = reducer.reduce(
            reduction.state,
            event: .visibleObserved(
                PredicatePollingVisibleObservation(
                    sequence: 1,
                    fingerprint: .known("visible-a"),
                    matched: true
                ),
                timing: PredicatePollingTickTiming(remaining: 0.9, elapsed: 0.01)
            )
        )

        XCTAssertEqual(reduction.effect, .finish(.matched))
    }

    func testPredicatePollingReducerFallsBackToDiscoveryWhenVisibleUnavailable() {
        let reducer = PredicatePollingReducer(timeout: 1, pollWhenTimeoutZero: true)
        var reduction = reducer.start(
            scope: .discovery,
            initialObservedSequence: nil,
            initialVisibleFingerprint: .known("visible-a")
        )

        XCTAssertEqual(reduction.effect, .observe(.visibleImmediate(after: nil)))

        reduction = reducer.reduce(
            reduction.state,
            event: .visibleUnavailable(timing: PredicatePollingTickTiming(remaining: 1, elapsed: 0.01))
        )

        XCTAssertEqual(reduction.effect, .observe(.discovery(after: nil, timeout: 1)))
        XCTAssertEqual(reduction.state.nextProbe, .discovery)
    }

    func testPredicatePollingReducerProbesDiscoveryWhenVisibleFingerprintChangesWithoutMatch() {
        let reducer = PredicatePollingReducer(timeout: 1, pollWhenTimeoutZero: true)
        var reduction = reducer.start(
            scope: .discovery,
            initialObservedSequence: 10,
            initialVisibleFingerprint: .known("visible-a"),
            discoveryBootstrap: .afterInitialDiscoveryAttempt
        )

        XCTAssertEqual(reduction.effect, .observe(.visibleImmediate(after: 10)))

        reduction = reducer.reduce(
            reduction.state,
            event: .visibleObserved(
                PredicatePollingVisibleObservation(
                    sequence: 11,
                    fingerprint: .known("visible-b"),
                    matched: false
                ),
                timing: PredicatePollingTickTiming(remaining: 0.8, elapsed: 0.01)
            )
        )
        XCTAssertEqual(reduction.effect, .observe(.visibleSettled(after: 11, timeout: 0.1)))

        reduction = reducer.reduce(
            reduction.state,
            event: .visibleUnavailable(timing: PredicatePollingTickTiming(remaining: 0.7, elapsed: 0.02))
        )

        XCTAssertEqual(reduction.effect, .observe(.discovery(after: 11, timeout: 0.7)))
    }

    func testPredicatePollingReducerTimeoutZeroCanSkipPolling() {
        let reducer = PredicatePollingReducer(timeout: 0, pollWhenTimeoutZero: false)
        let reduction = reducer.start(scope: .discovery, initialObservedSequence: nil)

        XCTAssertEqual(reduction.effect, .finish(.notPolled))
    }

    func testPredicatePollingReducerFinishesNoMatchAtTimeout() {
        let reducer = PredicatePollingReducer(timeout: 1, pollWhenTimeoutZero: true)
        var reduction = reducer.start(scope: .visible, initialObservedSequence: nil)

        XCTAssertEqual(reduction.effect, .observe(.visibleImmediate(after: nil)))

        reduction = reducer.reduce(
            reduction.state,
            event: .visibleUnavailable(timing: PredicatePollingTickTiming(remaining: 0, elapsed: 1))
        )

        XCTAssertEqual(reduction.effect, .finish(.timedOut))
    }

    func testPredicatePollingEngineKeepsVisibleTicksBetweenDiscoveryProbes() async {
        let predicate = AccessibilityPredicate.state(.exists(ElementPredicate(label: "Never")))
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
            requiresChangeBaseline: false,
            evaluate: { observation, _ in
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
        let predicate = AccessibilityPredicate.state(.exists(ElementPredicate(label: "Ready")))
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
            requiresChangeBaseline: false,
            initialVisibleFingerprint: .known("previous-visible-fingerprint"),
            discoveryBootstrap: .afterInitialDiscoveryAttempt,
            evaluate: { observation, _ in
                PredicateEvaluation.evaluate(predicate, in: observation)
            },
            isMatched: \.met
        )

        XCTAssertTrue(result.last?.evaluation.met == true)
        XCTAssertEqual(observedScopes, [.visible])
    }

    func testPredicatePollingEngineDefersDiscoveryAfterInitialDiscoveryAttempt() async {
        let predicate = AccessibilityPredicate.state(.exists(ElementPredicate(label: "Ready")))
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
            requiresChangeBaseline: false,
            initialVisibleFingerprint: .known("visible-seed"),
            discoveryBootstrap: .afterInitialDiscoveryAttempt,
            evaluate: { observation, _ in
                PredicateEvaluation.evaluate(predicate, in: observation)
            },
            isMatched: \.met
        )

        XCTAssertNil(result.last)
        XCTAssertFalse(observedScopes.contains(.discovery))
        XCTAssertEqual(observedTimeouts.first.flatMap { $0 }, 0)
    }

    func testPredicateWaitStartsWithDiscoveryThenUsesVisibleTicks() async {
        let predicate = AccessibilityPredicate.state(.exists(ElementPredicate(label: "Ready")))
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

        XCTAssertTrue(receipt.actionResult.success)
        XCTAssertTrue(receipt.expectation.met)
        XCTAssertEqual(Array(observedScopes.prefix(2)), [.discovery, .visible])
    }

    func testPredicateWaitReturnsFromInitialDiscoveryMatch() async {
        let predicate = AccessibilityPredicate.state(.exists(ElementPredicate(label: "Ready")))
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

        XCTAssertTrue(receipt.actionResult.success)
        XCTAssertTrue(receipt.expectation.met)
        XCTAssertEqual(observedScopes, [.discovery])
    }

    func testClassifiedTraceKeepsSameScreenStructuralDiscoveryAsElementChange() throws {
        seedScreen(elements: [("Menu", .header, "menu_header")])
        let before = brains.postActionObservation.captureSemanticState()

        seedScreen(elements: [
            ("Menu", .header, "menu_header"),
            ("Chicken Tikka", .button, "button_chicken_tikka"),
        ])
        let after = brains.postActionObservation.captureSemanticState()

        let trace = brains.postActionObservation.makeClassifiedAccessibilityTrace(after: after, parent: before)

        XCTAssertNil(trace.captures.last?.transition.screenChangeReason)
        guard case .elementsChanged(let payload)? = trace.endpointDelta else {
            return XCTFail("Expected elementsChanged delta, got \(String(describing: trace.endpointDelta))")
        }
        XCTAssertEqual(payload.captureEdge?.before.hash, before.capture.hash)
        XCTAssertEqual(payload.captureEdge?.after.hash, trace.captures.last?.hash)
    }

    func testClassifiedTraceStartsSegmentForRealScreenChange() throws {
        seedScreen(elements: [("Menu", .header, "menu_header")])
        let before = brains.postActionObservation.captureSemanticState()

        seedScreen(elements: [("Checkout", .header, "checkout_header")])
        let after = brains.postActionObservation.captureSemanticState()

        let trace = brains.postActionObservation.makeClassifiedAccessibilityTrace(after: after, parent: before)

        XCTAssertEqual(trace.captures.last?.transition.screenChangeReason, "primaryHeaderChanged")
        guard case .screenChanged(let payload)? = trace.endpointDelta else {
            return XCTFail("Expected screenChanged delta, got \(String(describing: trace.endpointDelta))")
        }
        XCTAssertEqual(payload.captureEdge?.before.hash, before.capture.hash)
        XCTAssertEqual(payload.captureEdge?.after.hash, trace.captures.last?.hash)
    }

    func testClassifiedTraceDeltaIsDerivedFromCaptureEndpoints() throws {
        seedScreen(elements: [("Cart", .header, "cart_header"), ("Total", .staticText, "total_label")])
        let before = brains.postActionObservation.captureSemanticState()

        seedScreen(elements: [("Cart", .header, "cart_header"), ("Total $12.00", .staticText, "total_label")])
        let after = brains.postActionObservation.captureSemanticState()

        let trace = brains.postActionObservation.makeClassifiedAccessibilityTrace(after: after, parent: before)
        let endpointDelta = try XCTUnwrap(trace.endpointDelta)

        XCTAssertEqual(trace.meaningfulEndpointDelta, endpointDelta)
        XCTAssertEqual(trace.captures.first?.hash, before.capture.hash)
        XCTAssertEqual(trace.captures.last?.parentHash, before.capture.hash)
        XCTAssertEqual(trace.captures.last?.hash, after.capture.hash)
    }

    // MARK: - Semantic Capture

    func testCaptureSemanticStateKeepsKnownElementsWithCanonicalInterfaceHash() {
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
            Set(state.snapshot.map(\.heistId)),
            ["button_visible", "button_below_fold"]
        )
        XCTAssertEqual(
            Set(state.interface.projectedElements.compactMap { $0.label }),
            ["Visible", "Below fold"]
        )
        XCTAssertEqual(
            state.interfaceHash,
            AccessibilityTrace.Capture.hash(state.interface),
            "Semantic captures hash the explored targetable interface, including known off-viewport entries"
        )
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
            after: current.screenSnapshot
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
            after: current.screenSnapshot
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
        // Exploration seeds the local union from settled world and merges each
        // parse into it. The observation stream commits the completed union as
        // settled discovery truth. There is no pruning — the union is the
        // canonical "all elements seen this cycle".
        // With no scrollable containers in the host hierarchy, semantic discovery
        // reduces to refresh-and-commit, and the seeded entry merges into the
        // live parse rather than being pruned.
        seedScreen(elements: [("Seed", .button, "button_seed")])
        XCTAssertEqual(brains.stash.settledSemanticScreen.semantic.elements.count, 1)

        brains.startSemanticObservation()
        let observation = await brains.stash.observeSettledSemanticObservation(scope: .discovery, after: nil, timeout: 2)

        // Either the seed survives (no live parse landed and the union still
        // holds it) or it merges with new live entries — either way, the
        // settled screen reflects the committed union, not the pre-explore
        // value alone.
        XCTAssertNotNil(observation)
        XCTAssertGreaterThanOrEqual(brains.stash.settledSemanticScreen.semantic.elements.count, 1)
    }

    func testExploreScreenStopsEarlyWhenTargetAlreadyResolved() async throws {
        guard let screen = brains.stash.refreshLiveCapture(),
              let label = screen.visibleIds
                  .compactMap({ screen.findElement(heistId: $0)?.element.label })
                  .first(where: { !$0.isEmpty }) else {
            throw XCTSkip("No live labeled element available for target short-circuit test")
        }

        let exploration = await brains.navigation.exploreScreen(
            target: .predicate(ElementPredicate(label: .exact(label)))
        )

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
            baseline: Screen.makeForTests(elements: [(before, HeistId(rawValue: "total_staticText"))])
        )

        exploration.absorb(Screen.makeForTests(elements: [(after, HeistId(rawValue: "total_staticText"))]))

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
        var exploration = Navigation.SemanticExploration(baseline: .empty)
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
        let page = Screen(
            elements: [:],
            hierarchy: [
                .container(outer, children: [
                    .container(nested, children: [])
                ])
            ],
            firstResponderHeistId: nil,
        )
        var exploration = Navigation.SemanticExploration(baseline: .empty)

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
        let page = Screen(
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
        var exploration = Navigation.SemanticExploration(baseline: .empty)
        exploration.manifest.addPendingContainers([outerEntry])
        exploration.markExplored(outerEntry)

        exploration.absorb(page)

        XCTAssertTrue(exploration.manifest.exploredScrollPaths.contains(outerPath))
        XCTAssertFalse(exploration.manifest.pendingScrollPaths.contains(outerPath))
        XCTAssertTrue(exploration.manifest.pendingScrollPaths.contains(nestedPath))
    }

    func testSemanticExplorationFinishOwnsExplorationTimestamp() {
        var exploration = Navigation.SemanticExploration(baseline: .empty)

        let result = exploration.finish(startTime: CACurrentMediaTime() - 0.01)

        XCTAssertGreaterThan(result.manifest.explorationTime, 0)
        XCTAssertEqual(result.screen, .empty)
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

        let exploration = await brains.navigation.exploreScreen()
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

    private func makeScreen(elements: [(label: String, traits: UIAccessibilityTraits, heistId: HeistId)]) -> Screen {
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
            tripwireSignal: .empty
        )
        let state = brains.postActionObservation.captureSemanticState(from: settled)
        let trace = AccessibilityTrace(capture: state.capture)
        let event = SettledSemanticObservationEvent(
            sequence: sequence,
            scope: scope,
            observation: settled,
            previous: nil,
            trace: trace,
            delta: trace.endpointDelta
        )
        return HeistSemanticObservation(
            event: event,
            state: state,
            accessibilityTrace: trace,
            delta: event.delta,
            summary: "known: \(state.interface.projectedElements.count) elements"
        )
    }

    private func activationSubjectEvidence(
        target: ElementTarget,
        element: AccessibilityElement,
        settledObservationSequence: SettledObservationSequence?
    ) -> ActionSubjectEvidence {
        ActionSubjectEvidence(
            source: .resolvedSemanticTarget,
            target: target,
            element: TheStash.WireConversion.convert(element),
            settledObservationSequence: settledObservationSequence
        )
    }

    private func makeScrollableContainer(frame: CGRect, contentSize: CGSize) -> AccessibilityContainer {
        AccessibilityContainer(
            type: .scrollable(contentSize: AccessibilitySize(contentSize)),
            frame: AccessibilityRect(frame)
        )
    }

    private func semanticContainer(
        _ container: AccessibilityContainer,
        path: TreePath
    ) -> SemanticScreen.Container {
        SemanticScreen.Container(
            container: container,
            path: path,
            containerName: nil,
            contentFrame: container.frame.cgRect
        )
    }

    private func settledOutcome(
        finalScreen: Screen?,
        outcome: SettleOutcome = .settled(timeMs: 0)
    ) -> SettleSession.Outcome {
        let elements = finalScreen?.liveCapture.hierarchy.sortedElements ?? []
        let elementsByKey = Dictionary(uniqueKeysWithValues: elements.map { ($0.timelineKey, $0) })
        return SettleSession.Outcome(
            outcome: outcome,
            events: [],
            finalScreen: finalScreen,
            elementsByKey: elementsByKey
        )
    }

}

#endif
