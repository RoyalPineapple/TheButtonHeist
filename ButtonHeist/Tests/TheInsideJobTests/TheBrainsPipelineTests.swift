#if canImport(UIKit)
import XCTest
import UIKit
@testable import AccessibilitySnapshotParser
@testable import TheInsideJob
@testable import TheScore

/// Deterministic tests for the pipelines on TheBrains that operate purely against
/// the current `Screen` snapshot: the failure branch of `actionResultWithDelta`, the
/// `computeBackgroundAccessibilityTrace` guards, background trace guards, and
/// `exploreAndPrune` pruning.
///
/// Success-path `actionResultWithDelta` and `exploreScreen` container iteration
/// require a live window and are covered by integration/benchmark runs.
@MainActor
final class TheBrainsPipelineTests: XCTestCase {

    private var brains: TheBrains!

    override func setUp() async throws {
        try await super.setUp()
        brains = TheBrains(tripwire: TheTripwire())
    }

    override func tearDown() async throws {
        brains = nil
        try await super.tearDown()
    }

    // MARK: - actionResultWithDelta Failure Path

    func testActionResultWithDeltaFailureReturnsBeforeSnapshot() async {
        seedScreen(elements: [("Sign In", .button, "button_sign_in")])
        let before = brains.captureBeforeState()

        let result = await brains.actionResultWithDelta(
            success: false,
            method: .activate,
            message: "target disappeared",
            before: before
        )

        XCTAssertFalse(result.success)
        XCTAssertEqual(result.method, .activate)
        XCTAssertEqual(result.message, "target disappeared")
        XCTAssertEqual(result.errorKind, .actionFailed,
                       "Without explicit errorKind and with method != elementNotFound, default is .actionFailed")
    }

    func testActionResultWithDeltaFailureInfersNotFoundFromMethod() async {
        let before = brains.captureBeforeState()

        let result = await brains.actionResultWithDelta(
            success: false,
            method: .elementNotFound,
            before: before
        )

        XCTAssertEqual(result.errorKind, .elementNotFound,
                       "method == .elementNotFound should infer errorKind == .elementNotFound")
    }

    func testActionResultWithDeltaFailureInfersNotFoundFromDeallocated() async {
        let before = brains.captureBeforeState()

        let result = await brains.actionResultWithDelta(
            success: false,
            method: .elementDeallocated,
            before: before
        )

        XCTAssertEqual(result.errorKind, .elementNotFound,
                       "method == .elementDeallocated should infer errorKind == .elementNotFound")
    }

    func testActionResultWithDeltaFailureRespectsExplicitErrorKind() async {
        let before = brains.captureBeforeState()

        let result = await brains.actionResultWithDelta(
            success: false,
            method: .activate,
            errorKind: .timeout,
            before: before
        )

        XCTAssertEqual(result.errorKind, .timeout,
                       "An explicit errorKind must override the method-based inference")
    }

    func testActionResultWithDeltaFailureCarriesValueAndMessage() async {
        let before = brains.captureBeforeState()

        let result = await brains.actionResultWithDelta(
            success: false,
            method: .getPasteboard,
            message: "pasteboard empty",
            payload: .value(""),
            before: before
        )

        XCTAssertEqual(result.message, "pasteboard empty")
        guard case .value(let value) = result.payload else {
            XCTFail("Expected .value payload, got \(String(describing: result.payload))")
            return
        }
        XCTAssertEqual(value, "")
    }

    // MARK: - CommandReceipt Projection

    func testCommandReceiptProjectionMatchesExistingActionResultBuilder() throws {
        seedScreen(elements: [("Before", .header, "before_header")])
        let before = brains.captureBeforeState()

        let header = AccessibilityElement.make(
            label: "Receipt Screen",
            traits: .header,
            respondsToUserInteraction: false
        )
        let button = AccessibilityElement.make(
            label: "Done",
            traits: .button,
            respondsToUserInteraction: false
        )
        brains.stash.currentScreen = .makeForTests(elements: [
            (header, "receipt_header"),
            (button, "button_done"),
        ])
        let postCapture = brains.makeTraceCapture(
            interface: brains.stash.interface(),
            sequence: 2,
            parentHash: before.capture.hash
        )
        let accessibilityTrace = brains.makeAccessibilityTrace(
            afterCapture: postCapture,
            parentCapture: before.capture
        )
        let traceBefore = try XCTUnwrap(accessibilityTrace.captures.dropLast().last)
        let traceAfter = try XCTUnwrap(accessibilityTrace.captures.last)
        let delta = AccessibilityTrace.Delta.between(traceBefore, traceAfter)

        let receipt = CommandReceipt(
            before: before,
            attempt: .delivered(method: .typeText, message: "typed text", payload: .value("hello")),
            settle: SettleReceipt(
                outcome: .settled(timeMs: 321),
                events: [],
                elementsByKey: [:],
                didSettle: true,
                accessibilityTrace: accessibilityTrace
            )
        )

        let projected = receipt.actionResult()

        var expectedBuilder = ActionResultBuilder(method: .typeText, capture: traceAfter)
        expectedBuilder.message = "typed text"
        expectedBuilder.accessibilityTrace = accessibilityTrace
        expectedBuilder.settled = true
        expectedBuilder.settleTimeMs = 321
        let expected = expectedBuilder.success(payload: .value("hello"))

        XCTAssertEqual(try canonicalJSON(projected), try canonicalJSON(expected))
        XCTAssertEqual(projected.screenName, "Receipt Screen")
        XCTAssertEqual(projected.screenId, "receipt_screen")
        XCTAssertEqual(projected.settled, true)
        XCTAssertEqual(projected.settleTimeMs, 321)
        XCTAssertEqual(projected.accessibilityDelta, delta)
        XCTAssertEqual(projected.accessibilityDelta, projected.accessibilityTrace?.endpointDeltaProjection)
        XCTAssertEqual(projected.accessibilityTrace, accessibilityTrace)
        XCTAssertEqual(receipt.attempt.deliveryPhase, .delivered)
        XCTAssertEqual(receipt.settle?.outcome, .settled(timeMs: 321))
        XCTAssertEqual(receipt.settle?.didSettle, true)
        XCTAssertEqual(receipt.settle?.outcome.timeMs, 321)
        XCTAssertEqual(receipt.settle?.accessibilityTrace.captures.last?.hash, postCapture.hash)
        XCTAssertEqual(receipt.settle?.accessibilityTrace, accessibilityTrace)
    }

    func testCommandReceiptDeliveredWithoutSettleCapturePreservesPayload() {
        seedScreen(elements: [("Before", .header, "before_header")])
        let before = brains.captureBeforeState()
        let receipt = CommandReceipt(
            before: before,
            attempt: .delivered(method: .getPasteboard, message: "settle failed", payload: .value("hello")),
            settle: nil
        )

        let result = receipt.actionResult()

        XCTAssertFalse(result.success)
        XCTAssertEqual(result.message, "settle failed")
        XCTAssertEqual(result.errorKind, .actionFailed)
        guard case .value(let value) = result.payload else {
            XCTFail("Expected .value payload, got \(String(describing: result.payload))")
            return
        }
        XCTAssertEqual(value, "hello")
    }

    func testCommandReceiptDeliveredWithoutTraceDeltaFails() {
        seedScreen(elements: [("Before", .header, "before_header")])
        let before = brains.captureBeforeState()
        let receipt = CommandReceipt(
            before: before,
            attempt: .delivered(method: .getPasteboard, message: "settle incomplete", payload: .value("hello")),
            settle: SettleReceipt(
                outcome: .settled(timeMs: 1),
                events: [],
                elementsByKey: [:],
                didSettle: true,
                accessibilityTrace: AccessibilityTrace(capture: before.capture)
            )
        )

        let result = receipt.actionResult()

        XCTAssertFalse(result.success)
        XCTAssertEqual(result.message, "settle incomplete")
        XCTAssertEqual(result.errorKind, .actionFailed)
        XCTAssertNil(result.accessibilityDelta)
        XCTAssertNil(result.accessibilityTrace)
    }

    func testCommandReceiptProjectionDerivesScreenChangeFromTraceTransition() throws {
        seedScreen(elements: [("Before", .header, "before_header")])
        let before = brains.captureBeforeState()

        let afterInterface = makeInterface(label: "After", traits: .header, heistId: "after_header")
        let afterCapture = AccessibilityTrace.Capture(
            sequence: 2,
            interface: afterInterface,
            parentHash: before.capture.hash,
            context: AccessibilityTrace.Context(screenId: "after"),
            transition: AccessibilityTrace.Transition(screenChangeReason: "primaryHeaderChanged")
        )
        let accessibilityTrace = AccessibilityTrace(captures: [before.capture, afterCapture])
        let receipt = CommandReceipt(
            before: before,
            attempt: .delivered(method: .activate),
            settle: SettleReceipt(
                outcome: .settled(timeMs: 10),
                events: [],
                elementsByKey: [:],
                didSettle: true,
                accessibilityTrace: accessibilityTrace
            )
        )

        let result = receipt.actionResult()

        guard case .screenChanged(let payload)? = result.accessibilityDelta else {
            return XCTFail(
                "Expected trace transition to project screenChanged, got \(String(describing: result.accessibilityDelta))"
            )
        }
        XCTAssertEqual(payload.captureEdge?.before.hash, before.capture.hash)
        XCTAssertEqual(payload.captureEdge?.after.hash, afterCapture.hash)
        XCTAssertEqual(payload.newInterface, afterInterface)
        XCTAssertEqual(result.accessibilityDelta, result.accessibilityTrace?.endpointDeltaProjection)
        XCTAssertEqual(result.accessibilityTrace, accessibilityTrace)
        XCTAssertEqual(result.screenName, "After")
        XCTAssertEqual(result.screenId, "after")
    }

    func testCommandReceiptSettleOutcomeDoesNotClassifyDelta() throws {
        seedScreen(elements: [("Stable", .header, "stable_header")])
        let before = brains.captureBeforeState()
        let postCapture = AccessibilityTrace.Capture(
            sequence: 2,
            interface: before.capture.interface,
            parentHash: before.capture.hash,
            context: before.capture.context
        )
        let accessibilityTrace = AccessibilityTrace(captures: [before.capture, postCapture])
        let receipt = CommandReceipt(
            before: before,
            attempt: .delivered(method: .activate, message: "delivered"),
            settle: SettleReceipt(
                outcome: .timedOut(timeMs: 5_000),
                events: [],
                elementsByKey: [:],
                didSettle: false,
                accessibilityTrace: accessibilityTrace
            )
        )

        let result = receipt.actionResult()

        XCTAssertTrue(result.success)
        XCTAssertEqual(result.message, "delivered")
        XCTAssertEqual(result.settled, false)
        XCTAssertEqual(result.settleTimeMs, 5_000)
        guard case .noChange(let payload)? = result.accessibilityDelta else {
            return XCTFail(
                "Expected trace endpoints to project noChange, got \(String(describing: result.accessibilityDelta))"
            )
        }
        XCTAssertEqual(payload.captureEdge?.before.hash, before.capture.hash)
        XCTAssertEqual(payload.captureEdge?.after.hash, postCapture.hash)
        XCTAssertEqual(result.accessibilityDelta, accessibilityTrace.endpointDeltaProjection)
        XCTAssertEqual(result.accessibilityTrace, accessibilityTrace)
    }

    func testClassifiedTraceKeepsSameScreenStructuralDiscoveryAsElementChange() throws {
        seedScreen(elements: [("Menu", .header, "menu_header")])
        let before = brains.captureBeforeState()

        seedScreen(elements: [
            ("Menu", .header, "menu_header"),
            ("Chicken Tikka", .button, "button_chicken_tikka"),
        ])
        let after = brains.captureSemanticState()

        let trace = brains.makeClassifiedAccessibilityTrace(after: after, parent: before)

        XCTAssertNil(trace.captures.last?.transition.screenChangeReason)
        guard case .elementsChanged(let payload)? = trace.endpointDeltaProjection else {
            return XCTFail("Expected elementsChanged delta, got \(String(describing: trace.endpointDeltaProjection))")
        }
        XCTAssertEqual(payload.captureEdge?.before.hash, before.capture.hash)
        XCTAssertEqual(payload.captureEdge?.after.hash, trace.captures.last?.hash)
    }

    func testClassifiedTraceStartsSegmentForRealScreenChange() throws {
        seedScreen(elements: [("Menu", .header, "menu_header")])
        let before = brains.captureBeforeState()

        seedScreen(elements: [("Checkout", .header, "checkout_header")])
        let after = brains.captureSemanticState()

        let trace = brains.makeClassifiedAccessibilityTrace(after: after, parent: before)

        XCTAssertEqual(trace.captures.last?.transition.screenChangeReason, "primaryHeaderChanged")
        guard case .screenChanged(let payload)? = trace.endpointDeltaProjection else {
            return XCTFail("Expected screenChanged delta, got \(String(describing: trace.endpointDeltaProjection))")
        }
        XCTAssertEqual(payload.captureEdge?.before.hash, before.capture.hash)
        XCTAssertEqual(payload.captureEdge?.after.hash, trace.captures.last?.hash)
    }

    func testClassifiedTraceDeltaIsDerivedFromCaptureEndpoints() throws {
        seedScreen(elements: [("Cart", .header, "cart_header"), ("Total", .staticText, "total_label")])
        let before = brains.captureBeforeState()

        seedScreen(elements: [("Cart", .header, "cart_header"), ("Total $12.00", .staticText, "total_label")])
        let after = brains.captureSemanticState()

        let trace = brains.makeClassifiedAccessibilityTrace(after: after, parent: before)
        let endpointDelta = try XCTUnwrap(trace.endpointDeltaProjection)

        XCTAssertEqual(trace.backgroundDeltaProjection, endpointDelta)
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
        brains.stash.currentScreen = .makeForTests(
            elements: [(visible, "button_visible")],
            offViewport: [.init(offViewport, heistId: "button_below_fold")]
        )
        let interfaceHash = AccessibilityTrace.Capture.hash(brains.stash.interface())

        let state = brains.captureSemanticState()

        XCTAssertEqual(
            Set(state.snapshot.map(\.heistId)),
            ["button_visible", "button_below_fold"]
        )
        XCTAssertEqual(
            state.interfaceHash,
            interfaceHash,
            "Interface captures hash the canonical parser tree; known-only entries stay in the targeting snapshot"
        )
    }

    // MARK: - computeBackgroundAccessibilityTrace Guards

    func testComputeBackgroundAccessibilityTraceReturnsNilWithoutPriorSend() async {
        let trace = await brains.computeBackgroundAccessibilityTrace()
        XCTAssertNil(trace, "No prior send means no comparison baseline, so return nil")
    }

    func testComputeBackgroundAccessibilityTraceReturnsNilWhenSemanticStateIsUnchanged() async {
        guard brains.refresh() != nil else {
            XCTFail("Expected a live interface baseline")
            return
        }
        brains.recordSentState()

        let trace = await brains.computeBackgroundAccessibilityTrace()
        XCTAssertNil(trace)
    }

    func testShouldRecordAccessibilityTraceIgnoresViewportOnlyMovement() {
        let beforeElement = AccessibilityElement.make(
            label: "Chicken Tikka",
            traits: .button,
            shape: .frame(AccessibilityRect(CGRect(x: 0, y: 0, width: 200, height: 44))),
            activationPoint: CGPoint(x: 100, y: 22),
            respondsToUserInteraction: false
        )
        brains.stash.currentScreen = .makeForTests(elements: [(beforeElement, "chicken_tikka_button")])
        let baseline = brains.captureSemanticState()

        let afterElement = AccessibilityElement.make(
            label: "Chicken Tikka",
            traits: .button,
            shape: .frame(AccessibilityRect(CGRect(x: 0, y: -300, width: 200, height: 44))),
            activationPoint: CGPoint(x: 100, y: -278),
            respondsToUserInteraction: false
        )
        brains.stash.currentScreen = .makeForTests(elements: [(afterElement, "chicken_tikka_button")])
        let current = brains.captureSemanticState()
        let classification = ScreenClassifier.classify(
            before: baseline.screenSnapshot,
            after: current.screenSnapshot
        )

        XCTAssertFalse(
            TheBrains.shouldRecordAccessibilityTrace(
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
        brains.stash.currentScreen = .makeForTests(elements: [(beforeElement, "total_staticText")])
        let baseline = brains.captureSemanticState()

        let afterElement = AccessibilityElement.make(
            label: "Total",
            value: "$8.00",
            traits: .staticText,
            respondsToUserInteraction: false
        )
        brains.stash.currentScreen = .makeForTests(elements: [(afterElement, "total_staticText")])
        let current = brains.captureSemanticState()
        let classification = ScreenClassifier.classify(
            before: baseline.screenSnapshot,
            after: current.screenSnapshot
        )

        XCTAssertTrue(
            TheBrains.shouldRecordAccessibilityTrace(
                baseline: baseline,
                current: current,
                classification: classification
            ),
            "Same-screen value changes are semantic patches"
        )
    }

    // MARK: - exploreAndPrune

    func testExploreAndPruneCommitsUnion() async {
        // Post-0.2.25: exploration seeds the local union from currentScreen,
        // merges each parse into it, then commits the union back. There is no
        // pruning — the union is the canonical "all elements seen this cycle".
        // With no scrollable containers in the host hierarchy, exploreAndPrune
        // reduces to refresh-and-commit, and the seeded entry merges into the
        // live parse rather than being pruned.
        seedScreen(elements: [("Seed", .button, "button_seed")])
        XCTAssertEqual(brains.stash.currentScreen.semantic.elements.count, 1)

        _ = await brains.navigation.exploreAndPrune()

        // Either the seed survives (no live parse landed and the union still
        // holds it) or it merges with new live entries — either way, the
        // currentScreen reflects the committed union, not the pre-explore
        // value alone.
        XCTAssertNotNil(brains.stash.currentScreen,
                        "exploreAndPrune always commits a screen value")
    }

    func testExploreScreenExploresSwipeableContainer() async throws {
        guard brains.refresh() != nil else {
            throw XCTSkip("No live hierarchy available for swipeable explore test")
        }
        guard let container = brains.stash.currentHierarchy.scrollableContainers.first(where: {
            guard let view = brains.stash.scrollableContainerViews[$0] else { return true }
            return !(view is UIScrollView)
        }) else {
            throw XCTSkip("No non-UIScrollView scrollable container in host UI")
        }

        var union = brains.stash.currentScreen
        let manifest = await brains.navigation.exploreScreen(union: &union)

        XCTAssertTrue(manifest.exploredContainers.contains(container))
    }

    // MARK: - Helpers

    private func makeInterface(label: String, traits: UIAccessibilityTraits, heistId: HeistId) -> Interface {
        let element = AccessibilityElement.make(
            label: label,
            traits: traits,
            respondsToUserInteraction: false
        )
        return Interface(
            timestamp: Date(timeIntervalSince1970: 0),
            tree: [.element(element, traversalIndex: 0)],
            annotations: InterfaceAnnotations(elements: [
                InterfaceElementAnnotation(
                    path: TreePath([0]),
                    heistId: heistId,
                    actions: []
                ),
            ])
        )
    }

    private func seedScreen(elements: [(label: String, traits: UIAccessibilityTraits, heistId: HeistId)]) {
        let pairs: [(AccessibilityElement, String)] = elements.map { entry in
            let element = AccessibilityElement.make(
                label: entry.label,
                traits: entry.traits,
                respondsToUserInteraction: false
            )
            return (element, entry.heistId)
        }
        brains.stash.currentScreen = .makeForTests(elements: pairs)
    }

    private func canonicalJSON<T: Encodable>(_ value: T) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(value)
        guard let json = String(data: data, encoding: .utf8) else {
            throw NSError(domain: "TheBrainsPipelineTests", code: 1)
        }
        return json
    }

}

#endif
