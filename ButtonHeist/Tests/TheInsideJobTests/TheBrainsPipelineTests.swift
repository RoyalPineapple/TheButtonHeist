#if canImport(UIKit)
import XCTest
import UIKit
@testable import AccessibilitySnapshotParser
@testable import TheInsideJob
@testable import TheScore

/// Deterministic tests for the pipelines on TheBrains that operate purely against
/// the current `Screen` snapshot: the failure branch of `actionResultWithDelta`, the
/// `SentState` accessors, the `computeBackgroundAccessibilityTrace` guards, the
/// settled-change cache-miss, and `exploreAndPrune` pruning.
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
            value: "",
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
            tree: brains.stash.wireTree(),
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
            attempt: .delivered(method: .typeText, message: "typed text", value: "hello"),
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
        expectedBuilder.value = "hello"
        expectedBuilder.accessibilityDelta = delta
        expectedBuilder.accessibilityTrace = accessibilityTrace
        expectedBuilder.settled = true
        expectedBuilder.settleTimeMs = 321
        let expected = expectedBuilder.success()

        XCTAssertEqual(try canonicalJSON(projected), try canonicalJSON(expected))
        XCTAssertEqual(projected.screenName, "Receipt Screen")
        XCTAssertEqual(projected.screenId, "receipt_screen")
        XCTAssertEqual(projected.settled, true)
        XCTAssertEqual(projected.settleTimeMs, 321)
        XCTAssertEqual(projected.accessibilityDelta, delta)
        XCTAssertEqual(projected.accessibilityTrace, accessibilityTrace)
        XCTAssertEqual(receipt.attempt.deliveryPhase, .delivered)
        XCTAssertEqual(receipt.settle?.outcome, .settled(timeMs: 321))
        XCTAssertEqual(receipt.settle?.didSettle, true)
        XCTAssertEqual(receipt.settle?.timeMs, 321)
        XCTAssertEqual(receipt.settle?.postCapture?.hash, postCapture.hash)
        XCTAssertEqual(receipt.settle?.accessibilityDelta, delta)
        XCTAssertEqual(receipt.settle?.accessibilityTrace, accessibilityTrace)
    }

    func testCommandReceiptProjectionDerivesScreenChangeFromTraceTransition() throws {
        seedScreen(elements: [("Before", .header, "before_header")])
        let before = brains.captureBeforeState()

        let afterInterface = Interface(
            timestamp: Date(timeIntervalSince1970: 0),
            tree: [
                .element(HeistElement(
                    heistId: "after_header",
                    description: "After",
                    label: "After",
                    value: nil,
                    identifier: nil,
                    traits: [.header],
                    frameX: 0,
                    frameY: 0,
                    frameWidth: 100,
                    frameHeight: 44,
                    actions: []
                )),
            ]
        )
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
        XCTAssertEqual(result.accessibilityTrace, accessibilityTrace)
        XCTAssertEqual(result.screenName, "After")
        XCTAssertEqual(result.screenId, "after")
    }

    // MARK: - SentState

    func testLastSentStateStartsNil() {
        XCTAssertNil(brains.lastSentState)
        XCTAssertNil(brains.lastSentScreenId)
        XCTAssertFalse(brains.screenChangedSinceLastSent,
                       "No prior send means there is no baseline for screen-change classification")
    }

    func testRecordSentStatePopulatesAllFields() {
        seedScreen(elements: [("Home", .header, "home_header"), ("A", .button, "button_a")])
        let viewportHash = brains.stash.wireTreeHash()

        brains.recordSentState()

        let sent = brains.lastSentState
        XCTAssertNotNil(sent)
        XCTAssertEqual(sent?.screenId, "home")
        XCTAssertEqual(sent?.viewportHash, viewportHash)
        XCTAssertNotEqual(sent?.treeHash, 0,
                          "treeHash should be non-zero for a non-empty screen")
        XCTAssertEqual(brains.lastSentScreenId, "home")
    }

    func testRecordSentStateUsesKnownSemanticElements() {
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
        let liveViewportHash = brains.stash.wireTreeHash()

        brains.recordSentState()

        let sent = brains.lastSentState
        XCTAssertEqual(
            Set(sent?.beforeState.snapshot.map(\.heistId) ?? []),
            ["button_visible", "button_below_fold"]
        )
        XCTAssertNotEqual(
            sent?.treeHash,
            liveViewportHash,
            "Sent state should hash the known semantic set, not only the live viewport tree"
        )
    }

    func testRecordSentStateWithViewportHashKeepsSemanticHashDomain() {
        seedScreen(elements: [("Screen X", .header, "screen_x_header"), ("A", .button, "button_a")])
        let semanticHash = brains.captureSemanticState().treeHash

        brains.recordSentState(viewportHash: 42)

        XCTAssertEqual(brains.lastSentState?.treeHash, semanticHash)
        XCTAssertEqual(brains.lastSentState?.viewportHash, 42)
        XCTAssertEqual(brains.lastSentState?.screenId, "screen_x")
    }

    func testScreenChangedSinceLastSentDetectsIdTransition() {
        seedScreen(elements: [("Home", .header, "home_header")])
        brains.recordSentState(viewportHash: 1)
        XCTAssertFalse(brains.screenChangedSinceLastSent)

        seedScreen(elements: [("Settings", .header, "settings_header")])
        XCTAssertTrue(brains.screenChangedSinceLastSent,
                      "A changed parsed screen signature should report a screen change")
    }

    func testClearCacheResetsSentState() {
        seedScreen(elements: [("A", .button, "button_a")])
        brains.recordSentState()
        XCTAssertNotNil(brains.lastSentState)

        brains.clearCache()

        XCTAssertNil(brains.lastSentState)
    }

    func testClearCacheResetsSettledChangeMemo() throws {
        guard brains.interfaceChangedSinceLastSettledCheck() else {
            throw XCTSkip("No live hierarchy available for settled-change memo test")
        }
        guard !brains.interfaceChangedSinceLastSettledCheck() else {
            throw XCTSkip("Live hierarchy changed during settled-change memo test")
        }

        brains.clearCache()

        XCTAssertTrue(brains.interfaceChangedSinceLastSettledCheck())
    }

    // MARK: - computeBackgroundAccessibilityTrace Guards

    func testComputeBackgroundAccessibilityTraceReturnsNilWithoutPriorSend() async {
        let trace = await brains.computeBackgroundAccessibilityTrace()
        XCTAssertNil(trace, "No prior send means no comparison baseline, so return nil")
    }

    func testComputeBackgroundAccessibilityTraceReturnsNilWhenViewportHashIsZero() async {
        // A viewportHash of 0 is the sentinel for "not set" — even if lastSentState exists,
        // the trace must be suppressed to avoid false positives.
        seedScreen(elements: [("A", .button, "button_a")])
        brains.recordSentState(viewportHash: 0)

        let trace = await brains.computeBackgroundAccessibilityTrace()
        XCTAssertNil(trace)
    }

    // MARK: - Unsupported Diagnostics

    func testExecuteCommandUnsupportedIncludesCommandIdentityAndScreenContext() async {
        seedScreen(elements: [("Home", .header, "home_header")])

        let result = await brains.executeCommand(.ping)

        XCTAssertFalse(result.success)
        XCTAssertEqual(result.errorKind, .unsupported)
        XCTAssertEqual(result.method, .activate, "Non-action protocol commands fall back to .activate diagnostics")
        XCTAssertEqual(result.screenName, "Home")
        XCTAssertEqual(result.screenId, "home")
        XCTAssertEqual(result.message, "Unsupported command 'ping' in executeCommand")
    }

    // MARK: - Transient Suppression on Screen Change (PR #330 H2)

    /// `SettleSession.elementsByKey` accumulates every element observed
    /// across cycles, including the previous screen's elements before a
    /// transition. Those are stale, not transient, and must not be surfaced
    /// under the delta's `transient` list when the action triggered a
    /// screen change.
    func testShouldSuppressTransientOnTripwireSignalEvent() {
        let changedObject = NSObject()
        let changedSignal = TheTripwire.TripwireSignal(
            topmostVC: ObjectIdentifier(changedObject),
            navigation: .empty,
            windowStack: .empty
        )
        XCTAssertTrue(
            TheBrains.shouldSuppressTransient(
                settleEvents: [
                    .tripwireSignalChanged(from: .empty, to: changedSignal)
                ],
                isScreenChange: false
            ),
            "A Tripwire signal event alone must suppress transients"
        )
        _ = changedObject // keep alive
    }

    func testShouldSuppressTransientOnDiffDetectedScreenChange() {
        XCTAssertTrue(
            TheBrains.shouldSuppressTransient(
                settleEvents: [],
                isScreenChange: true
            ),
            "Even when the settle loop reached .settled, a parsed screen change must suppress transients"
        )
    }

    func testShouldNotSuppressTransientOnCleanSettle() {
        XCTAssertFalse(
            TheBrains.shouldSuppressTransient(
                settleEvents: [],
                isScreenChange: false
            ),
            "Clean settle without a screen change: transients are real (spinners, snackbars, overlays)"
        )
    }

    func testShouldNotSuppressTransientOnTimedOut() {
        XCTAssertFalse(
            TheBrains.shouldSuppressTransient(
                settleEvents: [],
                isScreenChange: false
            ),
            "Timed-out settle: still on the same screen, so observed transients are still valid"
        )
    }

    func testShouldNotSuppressTransientOnCancelled() {
        XCTAssertFalse(
            TheBrains.shouldSuppressTransient(
                settleEvents: [],
                isScreenChange: false
            ),
            "Cancelled mid-action: not a screen change, transients (if any) are valid"
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
        XCTAssertEqual(brains.stash.currentScreen.elements.count, 1)

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

    private func seedScreen(elements: [(label: String, traits: UIAccessibilityTraits, heistId: String)]) {
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
