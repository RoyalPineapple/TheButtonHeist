#if canImport(UIKit)
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
            success: false,
            method: .activate,
            message: "target disappeared",
            before: before,
            settleOutcome: settledOutcome(finalScreen: afterScreen)
        )

        XCTAssertFalse(result.success)
        XCTAssertEqual(result.method, .activate)
        XCTAssertEqual(result.message, "target disappeared")
        XCTAssertEqual(result.errorKind, .actionFailed,
                       "Without explicit errorKind, failures default to actionFailed")
        XCTAssertEqual(result.accessibilityTrace?.captures.first?.hash, before.capture.hash)
        XCTAssertNotNil(result.accessibilityTrace?.captures.last)
        guard case .elementsChanged? = result.accessibilityTrace?.endpointDelta else {
            return XCTFail("Expected elementsChanged delta, got \(String(describing: result.accessibilityTrace?.endpointDelta))")
        }
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

    func testPostActionObservationFailureDoesNotInferNotFoundFromActionIdentity() async {
        let before = brains.postActionObservation.captureSemanticState()

        let result = await brains.interactionObservation.finishAfterAction(
            success: false,
            method: .activate,
            before: before,
            settleOutcome: settledOutcome(finalScreen: brains.stash.settledSemanticScreen)
        )

        XCTAssertEqual(result.errorKind, .actionFailed)
    }

    func testPostActionObservationFailureRespectsExplicitErrorKind() async {
        let before = brains.postActionObservation.captureSemanticState()

        let result = await brains.interactionObservation.finishAfterAction(
            success: false,
            method: .activate,
            errorKind: .timeout,
            before: before,
            settleOutcome: settledOutcome(finalScreen: brains.stash.settledSemanticScreen)
        )

        XCTAssertEqual(result.errorKind, .timeout,
                       "An explicit errorKind must override the method-based inference")
    }

    func testPostActionObservationFailureCarriesValueAndMessage() async {
        let before = brains.postActionObservation.captureSemanticState()

        let result = await brains.interactionObservation.finishAfterAction(
            success: false,
            method: .getPasteboard,
            message: "pasteboard empty",
            payload: .value(""),
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
        let screen = Screen.makeForTests(elements: [(element, "inert_option")])
        brains.stash.installScreenForTesting(screen)
        let before = brains.postActionObservation.captureSemanticState()

        let result = await brains.interactionObservation.finishAfterAction(
            success: true,
            method: .activate,
            subjectEvidence: activationSubjectEvidence(
                target: .predicate(ElementPredicate(identifier: "inert_option")),
                element: element,
                settledObservationSequence: before.settledObservationSequence
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

    func testSyntheticTapNoChangeCanRemainSuccessful() async {
        let beforeScreen = makeScreen(elements: [("Map", .button, "map_button")])
        brains.stash.installScreenForTesting(beforeScreen)
        let before = brains.postActionObservation.captureSemanticState()

        let result = await brains.interactionObservation.finishAfterAction(
            success: true,
            method: .syntheticTap,
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
        let screen = Screen.makeForTests(elements: [(element, "tap_activated_option")])
        brains.stash.installScreenForTesting(screen)
        let before = brains.postActionObservation.captureSemanticState()
        let activationTrace = ActivationTrace(
            axActivateReturned: false,
            retryAxActivateReturned: false,
            tapActivationDispatched: true,
            tapActivationPoint: ScreenPoint(x: 888, y: 372),
            tapActivationSucceeded: true
        )

        let result = await brains.interactionObservation.finishAfterAction(
            success: true,
            method: .activate,
            subjectEvidence: activationSubjectEvidence(
                target: .predicate(ElementPredicate(identifier: "tap_activated_option")),
                element: element,
                settledObservationSequence: before.settledObservationSequence
            ),
            activationTrace: activationTrace,
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
            success: true,
            method: .activate,
            before: before,
            settleOutcome: settledOutcome(finalScreen: afterScreen)
        )

        XCTAssertTrue(result.success, result.message ?? "action unexpectedly failed")
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
            success: true,
            method: .activate,
            subjectEvidence: evidence,
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
            success: true,
            method: .activate,
            before: before,
            settleOutcome: settledOutcome(finalScreen: afterScreen)
        )

        XCTAssertTrue(result.success, result.message ?? "action unexpectedly failed")
        guard case .screenChanged? = result.accessibilityTrace?.endpointDelta else {
            return XCTFail("Expected screenChanged delta, got \(String(describing: result.accessibilityTrace?.endpointDelta))")
        }
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
            ), "controls_demo")],
            offViewport: [
                Screen.OffViewportEntry(
                    discoveredOnly,
                    heistId: "buttonheist_demo",
                    contentSpaceOrigin: CGPoint(x: 20, y: 2_000),
                    scrollContainer: "root_scroll"
                ),
            ]
        )

        let resultTask = Task { @MainActor in
            await brains.interactionObservation.finishAfterAction(
                success: true,
                method: .activate,
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
            .compactMap(\.label)
        XCTAssertEqual(labels, ["Controls Demo"])
        XCTAssertFalse(labels.contains("ButtonHeist Demo"))
    }

    func testActionResultWithDeltaSettleTimeoutStillReturnsSuccessfulAction() async {
        let beforeScreen = makeScreen(elements: [("Save", .button, "save")])
        brains.stash.installScreenForTesting(beforeScreen)
        let before = brains.postActionObservation.captureSemanticState()
        let settledSequence = brains.stash.latestSettledSemanticObservationEvent?.sequence
        let afterScreen = makeScreen(elements: [("Saved", .button, "save")])

        let result = await brains.interactionObservation.finishAfterAction(
            success: true,
            method: .activate,
            before: before,
            settleOutcome: settledOutcome(finalScreen: afterScreen, outcome: .timedOut(timeMs: 250))
        )

        XCTAssertTrue(result.success, result.message ?? "action unexpectedly failed")
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
        XCTAssertEqual(result.accessibilityTrace?.captures.last?.interface.projectedElements.first?.label, "Saved")
    }

    func testActionResultWithDeltaCancelledSettleFailsActionResult() async {
        let beforeScreen = makeScreen(elements: [("Save", .button, "save")])
        brains.stash.installScreenForTesting(beforeScreen)
        let before = brains.postActionObservation.captureSemanticState()
        let settledSequence = brains.stash.latestSettledSemanticObservationEvent?.sequence

        let result = await brains.interactionObservation.finishAfterAction(
            success: true,
            method: .activate,
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
            success: true,
            method: .activate,
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
            (makeElement(label: "Home"), "home"),
        ])

        let receiptTask = Task { @MainActor in
            await isolatedBrains.interactionObservation.waitForPredicate(WaitStep(
                predicate: .state(.present(ElementPredicate(label: "Home"))),
                timeout: 1
            ))
        }

        await waitForSettledSemanticWaiter(on: isolatedBrains.stash)
        _ = isolatedBrains.stash.semanticObservationStream.commitSettledVisibleObservation(matchedScreen)

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
            predicate: .state(.present(ElementPredicate(label: "Home"))),
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
            (makeElement(label: "Before"), "before"),
        ])
        let matchedScreen = Screen.makeForTests(elements: [
            (makeElement(label: "Before"), "before"),
            (makeElement(label: "Loaded"), "loaded"),
        ])

        let receiptTask = Task { @MainActor in
            await isolatedBrains.interactionObservation.waitForPredicate(WaitStep(
                predicate: .present(ElementPredicate(label: "Loaded")),
                timeout: 1
            ))
        }

        await waitForSettledSemanticWaiter(on: isolatedBrains.stash)
        _ = isolatedBrains.stash.semanticObservationStream.commitSettledVisibleObservation(beforeScreen)
        await waitForSettledSemanticWaiter(on: isolatedBrains.stash)
        _ = isolatedBrains.stash.semanticObservationStream.commitSettledVisibleObservation(matchedScreen)

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
            (makeElement(label: "Known"), "known"),
        ])

        let receiptTask = Task { @MainActor in
            await isolatedBrains.interactionObservation.waitForPredicate(WaitStep(
                predicate: .present(ElementPredicate(label: "Missing")),
                timeout: 0.05
            ))
        }

        await waitForSettledSemanticWaiter(on: isolatedBrains.stash)
        _ = isolatedBrains.stash.semanticObservationStream.commitSettledVisibleObservation(observedScreen)

        let receipt = await receiptTask.value
        let trace = try XCTUnwrap(receipt.actionResult.accessibilityTrace)

        XCTAssertFalse(receipt.actionResult.success)
        XCTAssertEqual(receipt.actionResult.errorKind, .timeout)
        XCTAssertEqual(trace.captures.last?.interface.projectedElements.map(\.label), ["Known"])
        XCTAssertTrue(receipt.actionResult.message?.contains("known: 1 elements") == true)
        XCTAssertTrue(receipt.actionResult.message?.contains("last result:") == true)
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
            elements: [(visible, "button_visible")],
            offViewport: [.init(offViewport, heistId: "button_below_fold")]
        ))
        let state = brains.postActionObservation.captureSemanticState()

        XCTAssertEqual(
            Set(state.snapshot.map(\.heistId)),
            ["button_visible", "button_below_fold"]
        )
        XCTAssertEqual(
            Set(state.interface.projectedElements.compactMap(\.label)),
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
        brains.stash.installScreenForTesting(.makeForTests(elements: [(beforeElement, "chicken_tikka_button")]))
        let baseline = brains.postActionObservation.captureSemanticState()

        let afterElement = AccessibilityElement.make(
            label: "Chicken Tikka",
            traits: .button,
            shape: .frame(AccessibilityRect(CGRect(x: 0, y: -300, width: 200, height: 44))),
            activationPoint: CGPoint(x: 100, y: -278),
            respondsToUserInteraction: false
        )
        brains.stash.installScreenForTesting(.makeForTests(elements: [(afterElement, "chicken_tikka_button")]))
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
        brains.stash.installScreenForTesting(.makeForTests(elements: [(beforeElement, "total_staticText")]))
        let baseline = brains.postActionObservation.captureSemanticState()

        let afterElement = AccessibilityElement.make(
            label: "Total",
            value: "$8.00",
            traits: .staticText,
            respondsToUserInteraction: false
        )
        brains.stash.installScreenForTesting(.makeForTests(elements: [(afterElement, "total_staticText")]))
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
        XCTAssertTrue(exploration.manifest.pendingContainers.isEmpty)
        XCTAssertTrue(exploration.manifest.exploredContainers.isEmpty)
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
            baseline: .makeForTests(elements: [(before, "total_staticText")])
        )

        exploration.absorb(.makeForTests(elements: [(after, "total_staticText")]))

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
        var exploration = Navigation.SemanticExploration(baseline: .empty)
        exploration.manifest.addPendingContainers([outer])

        exploration.markExplored(outer)
        exploration.addDiscoveredContainers([outer, nested])

        XCTAssertTrue(exploration.manifest.exploredContainers.contains(outer))
        XCTAssertFalse(exploration.manifest.pendingContainers.contains(outer))
        XCTAssertTrue(exploration.manifest.pendingContainers.contains(nested))
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
        guard let container = brains.stash.latestObservedLiveHierarchy.scrollableContainers.first(where: {
            guard let view = brains.stash.scrollableContainerViews[$0] else { return true }
            return !(view is UIScrollView)
        }) else {
            throw XCTSkip("No non-UIScrollView scrollable container in host UI")
        }

        let exploration = await brains.navigation.exploreScreen()
        let manifest = exploration.manifest

        XCTAssertTrue(manifest.exploredContainers.contains(container))
    }

    // MARK: - Helpers

    private func seedScreen(elements: [(label: String, traits: UIAccessibilityTraits, heistId: HeistId)]) {
        brains.stash.installScreenForTesting(makeScreen(elements: elements))
    }

    private func waitForSettledSemanticWaiter(
        on stash: TheStash,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        for _ in 0..<50 where stash.semanticObservationStream.settledWaiterCount == 0 {
            await Task.yield()
        }
        XCTAssertEqual(stash.semanticObservationStream.settledWaiterCount, 1, file: file, line: line)
    }

    private func makeElement(label: String) -> AccessibilityElement {
        AccessibilityElement.make(label: label, respondsToUserInteraction: false)
    }

    private func makeScreen(elements: [(label: String, traits: UIAccessibilityTraits, heistId: HeistId)]) -> Screen {
        let pairs: [(AccessibilityElement, String)] = elements.map { entry in
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
        target: ElementTarget,
        element: AccessibilityElement,
        settledObservationSequence: UInt64?
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
