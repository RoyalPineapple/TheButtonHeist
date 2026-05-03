#if canImport(UIKit)
import XCTest
@testable import AccessibilitySnapshotParser
@testable import TheInsideJob
@testable import TheScore

@MainActor
final class TheBrainsActionTests: XCTestCase {

    private var brains: TheBrains!

    override func setUp() async throws {
        try await super.setUp()
        brains = TheBrains(tripwire: TheTripwire())
    }

    override func tearDown() async throws {
        brains = nil
        try await super.tearDown()
    }

    // MARK: - clampDuration

    func testClampDurationNilReturnsDefault() {
        let result = brains.clampDuration(nil)
        XCTAssertEqual(result, 0.5, accuracy: 0.001,
                       "nil duration should return default (0.5)")
    }

    func testClampDurationRespectsMinimum() {
        let result = brains.clampDuration(0.001)
        XCTAssertEqual(result, 0.01, accuracy: 0.001,
                       "Duration below minimum should clamp to 0.01")
    }

    func testClampDurationRespectsMaximum() {
        let result = brains.clampDuration(120.0)
        XCTAssertEqual(result, 60.0, accuracy: 0.001,
                       "Duration above maximum should clamp to 60.0")
    }

    func testClampDurationPassesThroughValidValue() {
        let result = brains.clampDuration(1.5)
        XCTAssertEqual(result, 1.5, accuracy: 0.001,
                       "Valid duration should pass through unchanged")
    }

    func testClampDurationAtExactMinimum() {
        let result = brains.clampDuration(0.01)
        XCTAssertEqual(result, 0.01, accuracy: 0.001,
                       "Exact minimum should pass through")
    }

    func testClampDurationAtExactMaximum() {
        let result = brains.clampDuration(60.0)
        XCTAssertEqual(result, 60.0, accuracy: 0.001,
                       "Exact maximum should pass through")
    }

    func testClampDurationNegativeValueClampsToMin() {
        let result = brains.clampDuration(-5.0)
        XCTAssertEqual(result, 0.01, accuracy: 0.001,
                       "Negative duration should clamp to minimum")
    }

    func testClampDurationZeroClampsToMin() {
        let result = brains.clampDuration(0.0)
        XCTAssertEqual(result, 0.01, accuracy: 0.001,
                       "Zero duration should clamp to minimum")
    }

    // MARK: - resolveDuration

    func testResolveDurationExplicitDurationTakesPrecedence() {
        let points = [CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 0)]
        let result = brains.resolveDuration(2.0, velocity: 50.0, points: points)
        XCTAssertEqual(result, 2.0, accuracy: 0.001,
                       "Explicit duration should take precedence over velocity")
    }

    func testResolveDurationFromVelocity() {
        let points = [
            CGPoint(x: 0, y: 0),
            CGPoint(x: 100, y: 0),
            CGPoint(x: 200, y: 0),
        ]
        let result = brains.resolveDuration(nil, velocity: 100.0, points: points)
        XCTAssertEqual(result, 2.0, accuracy: 0.01,
                       "200pt path at 100pt/s = 2.0s")
    }

    func testResolveDurationFromVelocityDiagonal() {
        let points = [
            CGPoint(x: 0, y: 0),
            CGPoint(x: 300, y: 400),
        ]
        let result = brains.resolveDuration(nil, velocity: 500.0, points: points)
        XCTAssertEqual(result, 1.0, accuracy: 0.01,
                       "500pt diagonal path at 500pt/s = 1.0s")
    }

    func testResolveDurationNilBothReturnsDefault() {
        let points = [CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 0)]
        let result = brains.resolveDuration(nil, velocity: nil, points: points)
        XCTAssertEqual(result, 0.5, accuracy: 0.001,
                       "No duration and no velocity should return default")
    }

    func testResolveDurationZeroVelocityReturnsDefault() {
        let points = [CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 0)]
        let result = brains.resolveDuration(nil, velocity: 0.0, points: points)
        XCTAssertEqual(result, 0.5, accuracy: 0.001,
                       "Zero velocity should fall through to default")
    }

    func testResolveDurationVelocityResultIsClamped() {
        let points = [CGPoint(x: 0, y: 0), CGPoint(x: 10000, y: 0)]
        let result = brains.resolveDuration(nil, velocity: 1.0, points: points)
        XCTAssertEqual(result, 60.0, accuracy: 0.001,
                       "Very long path at low velocity should clamp to max")
    }

    func testResolveDurationVelocitySmallPathClamps() {
        let points = [CGPoint(x: 0, y: 0), CGPoint(x: 0.0001, y: 0)]
        let result = brains.resolveDuration(nil, velocity: 1000.0, points: points)
        XCTAssertEqual(result, 0.01, accuracy: 0.001,
                       "Tiny path at high velocity should clamp to minimum")
    }

    // MARK: - BeforeState Capture

    func testCaptureBeforeStateReturnsEmptySnapshotWhenRegistryEmpty() {
        let before = brains.captureBeforeState()
        XCTAssertTrue(before.snapshot.isEmpty,
                      "Snapshot should be empty when no elements in registry")
        XCTAssertTrue(before.elements.isEmpty,
                      "Elements should be empty when no hierarchy set")
    }

    func testCaptureBeforeStateIncludesRegisteredElements() {
        let element = makeElement(label: "Title", traits: .header)
        let heistId = "header_title"
        brains.stash.registry.insertForTesting(TheStash.ScreenElement(
            heistId: heistId,
            contentSpaceOrigin: nil,
            element: element,
            object: nil,
            scrollView: nil
        ))
        brains.stash.currentHierarchy = [.element(element, traversalIndex: 0)]

        let before = brains.captureBeforeState()
        XCTAssertEqual(before.snapshot.count, 1)
        XCTAssertEqual(before.snapshot.first?.heistId, heistId)
        XCTAssertEqual(before.elements.count, 1)
    }

    // MARK: - Deallocated Element Fail-Closed

    func testExecuteIncrementFailsWhenElementObjectIsDeallocated() async {
        let heistId = "volume_slider"
        registerScreenElement(
            heistId: heistId,
            element: makeElement(label: "Volume", traits: .adjustable),
            object: nil
        )

        let result = await brains.executeIncrement(.heistId(heistId))

        XCTAssertFalse(result.success)
        XCTAssertEqual(result.method, .elementDeallocated)
        XCTAssertTrue(result.message?.contains("deallocated") ?? false)
    }

    func testExecuteDecrementFailsWhenElementObjectIsDeallocated() async {
        let heistId = "brightness_slider"
        registerScreenElement(
            heistId: heistId,
            element: makeElement(label: "Brightness", traits: .adjustable),
            object: nil
        )

        let result = await brains.executeDecrement(.heistId(heistId))

        XCTAssertFalse(result.success)
        XCTAssertEqual(result.method, .elementDeallocated)
        XCTAssertTrue(result.message?.contains("deallocated") ?? false)
    }

    func testExecuteCustomActionFailsWhenElementObjectIsDeallocated() async {
        let heistId = "options_button"
        registerScreenElement(
            heistId: heistId,
            element: makeElement(label: "Options", traits: .button),
            object: nil
        )

        let result = await brains.executeCustomAction(
            CustomActionTarget(elementTarget: .heistId(heistId), actionName: "Delete")
        )

        XCTAssertFalse(result.success)
        XCTAssertEqual(result.method, .elementDeallocated)
        XCTAssertTrue(result.message?.contains("deallocated") ?? false)
    }

    func testExecuteIncrementSucceedsWhenElementObjectIsLive() async {
        let heistId = "live_slider"
        let liveObject = UISlider()
        registerScreenElement(
            heistId: heistId,
            element: makeElement(label: "Live", traits: .adjustable),
            object: liveObject
        )

        let result = await brains.executeIncrement(.heistId(heistId))

        XCTAssertTrue(result.success)
        XCTAssertEqual(result.method, .increment)
    }

    // MARK: - clearCache

    func testClearCacheResetsStashAndExploreState() {
        let element = makeElement(label: "Item")
        brains.stash.registry.insertForTesting(TheStash.ScreenElement(
            heistId: "test_id",
            contentSpaceOrigin: nil,
            element: element,
            object: nil,
            scrollView: nil
        ))
        brains.beginExploreCycle()
        brains.containerExploreStates[
            AccessibilityContainer(
                type: .scrollable(contentSize: CGSize(width: 375, height: 2000)),
                frame: .zero
            )
        ] = TheBrains.ContainerExploreState(
            visibleSubtreeFingerprint: 1,
            discoveredHeistIds: ["x"]
        )

        brains.clearCache()

        XCTAssertEqual(brains.explorePhase, .idle)
        XCTAssertTrue(brains.containerExploreStates.isEmpty)
    }

    // MARK: - ExplorePhase state machine

    func testExplorePhaseStartsIdle() {
        XCTAssertEqual(brains.explorePhase, .idle)
    }

    func testRecordDuringExploreIsNoOpWhenIdle() {
        brains.recordDuringExplore(["abc"])
        XCTAssertEqual(brains.explorePhase, .idle,
                       "recordDuringExplore must not transition out of .idle")
    }

    func testBeginExploreCycleSeedsWithViewport() {
        brains.stash.registry.viewportIds = ["viewport_a", "viewport_b"]
        brains.beginExploreCycle()
        guard case .active(let seen) = brains.explorePhase else {
            XCTFail("Expected .active phase after beginExploreCycle")
            return
        }
        XCTAssertEqual(seen, ["viewport_a", "viewport_b"])
    }

    func testRecordDuringExploreAccumulatesWhenActive() {
        brains.stash.registry.viewportIds = ["seed"]
        brains.beginExploreCycle()
        brains.recordDuringExplore(["discovered_a", "discovered_b"])
        guard case .active(let seen) = brains.explorePhase else {
            XCTFail("Expected .active phase")
            return
        }
        XCTAssertEqual(seen, ["seed", "discovered_a", "discovered_b"])
    }

    func testEndExploreCycleReturnsAccumulatedAndTransitionsToIdle() {
        brains.stash.registry.viewportIds = ["seed"]
        brains.beginExploreCycle()
        brains.recordDuringExplore(["extra"])
        let result = brains.endExploreCycle()
        XCTAssertEqual(result, ["seed", "extra"])
        XCTAssertEqual(brains.explorePhase, .idle)
    }

    func testEndExploreCycleReturnsNilWhenIdle() {
        XCTAssertNil(brains.endExploreCycle())
    }

    // MARK: - refresh integrates with ExplorePhase

    func testRefreshDoesNotAccumulateWhenIdle() {
        XCTAssertEqual(brains.explorePhase, .idle)
        brains.refresh()
        XCTAssertEqual(brains.explorePhase, .idle,
                       "refresh() must not transition the phase")
    }

    // MARK: - Accessibility Tree Availability

    func testExecuteWaitForIdleFailsWhenAccessibilityTreeUnavailable() async {
        let result = await withNoTraversableWindows {
            await brains.executeWaitForIdle(timeout: 0.1)
        }

        XCTAssertFalse(result.success)
        XCTAssertEqual(result.method, .waitForIdle)
        XCTAssertEqual(result.errorKind, .actionFailed)
        XCTAssertEqual(result.message, "Could not access accessibility tree")
    }

    func testExecuteCommandExploreFailsWhenAccessibilityTreeUnavailable() async {
        let result = await withNoTraversableWindows {
            await brains.executeCommand(.explore)
        }

        XCTAssertFalse(result.success)
        XCTAssertEqual(result.method, .explore)
        XCTAssertEqual(result.errorKind, .actionFailed)
        XCTAssertEqual(result.message, "Could not access accessibility tree")
    }

    func testExecuteCommandWaitForFailsWhenAccessibilityTreeUnavailable() async {
        let target = WaitForTarget(
            elementTarget: .matcher(ElementMatcher(label: "never"))
        )
        let result = await withNoTraversableWindows {
            await brains.executeCommand(.waitFor(target))
        }

        XCTAssertFalse(result.success)
        XCTAssertEqual(result.method, .waitFor)
        XCTAssertEqual(result.errorKind, .actionFailed)
        XCTAssertEqual(result.message, "Could not access accessibility tree")
    }

    // MARK: - Helpers

    private func registerScreenElement(
        heistId: String,
        element: AccessibilityElement,
        object: NSObject?
    ) {
        brains.stash.registry.insertForTesting(TheStash.ScreenElement(
            heistId: heistId,
            contentSpaceOrigin: nil,
            element: element,
            object: object,
            scrollView: nil
        ))
        brains.stash.registry.viewportIds.insert(heistId)
    }

    private func makeElement(
        label: String? = nil,
        traits: UIAccessibilityTraits = .none
    ) -> AccessibilityElement {
        AccessibilityElement(
            description: label ?? "",
            label: label,
            value: nil,
            traits: traits,
            identifier: nil,
            hint: nil,
            userInputLabels: nil,
            shape: .frame(.zero),
            activationPoint: .zero,
            usesDefaultActivationPoint: true,
            customActions: [],
            customContent: [],
            customRotors: [],
            accessibilityLanguage: nil,
            respondsToUserInteraction: false
        )
    }

    private func withNoTraversableWindows<T>(
        _ operation: () async -> T
    ) async -> T {
        let windows = brains.tripwire.getTraversableWindows().map(\.window)
        let originalHiddenStates = windows.map(\.isHidden)
        for window in windows {
            window.isHidden = true
        }
        defer {
            for (window, originalIsHidden) in zip(windows, originalHiddenStates) {
                window.isHidden = originalIsHidden
            }
        }
        return await operation()
    }
}

#endif
