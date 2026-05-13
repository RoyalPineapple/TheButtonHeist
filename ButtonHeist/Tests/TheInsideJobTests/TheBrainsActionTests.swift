#if canImport(UIKit)
import XCTest
@testable import AccessibilitySnapshotParser
@testable import TheInsideJob
@testable import TheScore

private final class ActionActivationOverrideView: UIView {
    private(set) var activationCount = 0

    override func accessibilityActivate() -> Bool {
        activationCount += 1
        return true
    }
}

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
        let result = brains.actions.clampDuration(nil)
        XCTAssertEqual(result, 0.5, accuracy: 0.001,
                       "nil duration should return default (0.5)")
    }

    func testClampDurationRespectsMinimum() {
        let result = brains.actions.clampDuration(0.001)
        XCTAssertEqual(result, 0.01, accuracy: 0.001,
                       "Duration below minimum should clamp to 0.01")
    }

    func testClampDurationRespectsMaximum() {
        let result = brains.actions.clampDuration(120.0)
        XCTAssertEqual(result, 60.0, accuracy: 0.001,
                       "Duration above maximum should clamp to 60.0")
    }

    func testClampDurationPassesThroughValidValue() {
        let result = brains.actions.clampDuration(1.5)
        XCTAssertEqual(result, 1.5, accuracy: 0.001,
                       "Valid duration should pass through unchanged")
    }

    // MARK: - resolveDuration

    func testResolveDurationExplicitDurationTakesPrecedence() {
        let points = [CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 0)]
        let result = brains.actions.resolveDuration(2.0, velocity: 50.0, points: points)
        XCTAssertEqual(result, 2.0, accuracy: 0.001,
                       "Explicit duration should take precedence over velocity")
    }

    func testResolveDurationFromVelocity() {
        let points = [
            CGPoint(x: 0, y: 0),
            CGPoint(x: 100, y: 0),
            CGPoint(x: 200, y: 0),
        ]
        let result = brains.actions.resolveDuration(nil, velocity: 100.0, points: points)
        XCTAssertEqual(result, 2.0, accuracy: 0.01,
                       "200pt path at 100pt/s = 2.0s")
    }

    func testResolveDurationFromVelocityDiagonal() {
        let points = [
            CGPoint(x: 0, y: 0),
            CGPoint(x: 300, y: 400),
        ]
        let result = brains.actions.resolveDuration(nil, velocity: 500.0, points: points)
        XCTAssertEqual(result, 1.0, accuracy: 0.01,
                       "500pt diagonal path at 500pt/s = 1.0s")
    }

    func testResolveDurationNilBothReturnsDefault() {
        let points = [CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 0)]
        let result = brains.actions.resolveDuration(nil, velocity: nil, points: points)
        XCTAssertEqual(result, 0.5, accuracy: 0.001,
                       "No duration and no velocity should return default")
    }

    func testResolveDurationZeroVelocityReturnsDefault() {
        let points = [CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 0)]
        let result = brains.actions.resolveDuration(nil, velocity: 0.0, points: points)
        XCTAssertEqual(result, 0.5, accuracy: 0.001,
                       "Zero velocity should fall through to default")
    }

    func testResolveDurationVelocityResultIsClamped() {
        let points = [CGPoint(x: 0, y: 0), CGPoint(x: 10000, y: 0)]
        let result = brains.actions.resolveDuration(nil, velocity: 1.0, points: points)
        XCTAssertEqual(result, 60.0, accuracy: 0.001,
                       "Very long path at low velocity should clamp to max")
    }

    func testResolveDurationVelocitySmallPathClamps() {
        let points = [CGPoint(x: 0, y: 0), CGPoint(x: 0.0001, y: 0)]
        let result = brains.actions.resolveDuration(nil, velocity: 1000.0, points: points)
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
        installScreen(elements: [(element, heistId)])

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

        let result = await brains.actions.executeIncrement(.heistId(heistId))

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

        let result = await brains.actions.executeDecrement(.heistId(heistId))

        XCTAssertFalse(result.success)
        XCTAssertEqual(result.method, .elementDeallocated)
        XCTAssertTrue(result.message?.contains("deallocated") ?? false)
    }

    func testExecuteIncrementFailsWhenElementIsNotAdjustable() async {
        let heistId = "live_button"
        let liveObject = UIButton(type: .system)
        registerScreenElement(
            heistId: heistId,
            element: makeElement(label: "Live", traits: .button),
            object: liveObject
        )

        let result = await brains.actions.executeIncrement(.heistId(heistId))

        XCTAssertFalse(result.success)
        XCTAssertEqual(result.method, .increment)
        XCTAssertEqual(result.message, "Element is not adjustable")
    }

    func testExecuteDecrementFailsWhenElementIsNotAdjustable() async {
        let heistId = "live_button"
        let liveObject = UIButton(type: .system)
        registerScreenElement(
            heistId: heistId,
            element: makeElement(label: "Live", traits: .button),
            object: liveObject
        )

        let result = await brains.actions.executeDecrement(.heistId(heistId))

        XCTAssertFalse(result.success)
        XCTAssertEqual(result.method, .decrement)
        XCTAssertEqual(result.message, "Element is not adjustable")
    }

    func testExecuteCustomActionFailsWhenElementObjectIsDeallocated() async {
        let heistId = "options_button"
        registerScreenElement(
            heistId: heistId,
            element: makeElement(label: "Options", traits: .button),
            object: nil
        )

        let result = await brains.actions.executeCustomAction(
            CustomActionTarget(elementTarget: .heistId(heistId), actionName: "Delete")
        )

        XCTAssertFalse(result.success)
        XCTAssertEqual(result.method, .elementDeallocated)
        XCTAssertTrue(result.message?.contains("deallocated") ?? false)
    }

    func testExecuteActivateSucceedsForNoTraitElementWithActivationOverride() async {
        let heistId = "plain_action"
        let liveObject = ActionActivationOverrideView()
        registerScreenElement(
            heistId: heistId,
            element: makeElement(label: "Plain action"),
            object: liveObject
        )

        let result = await brains.actions.executeActivate(.heistId(heistId))

        XCTAssertTrue(result.success)
        XCTAssertEqual(result.method, .activate)
        XCTAssertEqual(liveObject.activationCount, 1)
    }

    func testExecuteActivateFailsForNoTraitElementWithoutActivationSignal() async {
        let heistId = "plain_label"
        let liveObject = UIView()
        registerScreenElement(
            heistId: heistId,
            element: makeElement(label: "Plain label"),
            object: liveObject
        )

        let result = await brains.actions.executeActivate(.heistId(heistId))

        XCTAssertFalse(result.success)
        XCTAssertEqual(result.method, .activate)
        XCTAssertEqual(result.message, "Element does not support activate")
    }

    func testExecuteActivateBlocksDisabledElementWithActivationOverride() async {
        let heistId = "disabled_action"
        let liveObject = ActionActivationOverrideView()
        registerScreenElement(
            heistId: heistId,
            element: makeElement(label: "Disabled action", traits: .notEnabled),
            object: liveObject
        )

        let result = await brains.actions.executeActivate(.heistId(heistId))

        XCTAssertFalse(result.success)
        XCTAssertEqual(result.method, .activate)
        XCTAssertTrue(result.message?.contains("disabled") ?? false)
        XCTAssertEqual(liveObject.activationCount, 0)
    }

    func testExecuteIncrementSucceedsWhenElementObjectIsLive() async {
        let heistId = "live_slider"
        let liveObject = UISlider()
        registerScreenElement(
            heistId: heistId,
            element: makeElement(label: "Live", traits: .adjustable),
            object: liveObject
        )

        let result = await brains.actions.executeIncrement(.heistId(heistId))

        XCTAssertTrue(result.success)
        XCTAssertEqual(result.method, .increment)
    }

    // MARK: - clearCache

    func testClearCacheResetsStashAndExploreState() {
        let element = makeElement(label: "Item")
        installScreen(elements: [(element, "test_id")])
        brains.navigation.containerExploreStates[
            AccessibilityContainer(
                type: .scrollable(contentSize: CGSize(width: 375, height: 2000)),
                frame: .zero
            )
        ] = Navigation.ContainerExploreState(
            visibleSubtreeFingerprint: 1,
            discoveredHeistIds: ["x"]
        )

        brains.clearCache()

        XCTAssertTrue(brains.navigation.containerExploreStates.isEmpty)
        XCTAssertEqual(brains.stash.currentScreen, .empty)
    }

    // MARK: - Accessibility Tree Availability

    func testExecuteWaitForIdleFailsWhenAccessibilityTreeUnavailable() async {
        let result = await withNoTraversableWindows {
            await brains.executeWaitForIdle(timeout: 0.1)
        }

        XCTAssertFalse(result.success)
        XCTAssertEqual(result.method, .waitForIdle)
        XCTAssertEqual(result.errorKind, .actionFailed)
        // The exact `message` here is user-facing copy, not a control-flow
        // contract. Anchor on `errorKind` for behavioural assertions; this one
        // sanity-check on the literal stays so a wording regression is visible.
        XCTAssertEqual(result.message, "Could not access accessibility tree")
    }

    func testExecuteCommandExploreFailsWhenAccessibilityTreeUnavailable() async {
        let result = await withNoTraversableWindows {
            await brains.executeCommand(.explore)
        }

        XCTAssertFalse(result.success)
        XCTAssertEqual(result.method, .explore)
        XCTAssertEqual(result.errorKind, .actionFailed)
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
    }

    // MARK: - Helpers

    private func registerScreenElement(
        heistId: String,
        element: AccessibilityElement,
        object: NSObject?
    ) {
        installScreen(elements: [(element, heistId)], objects: [heistId: object])
    }

    private func installScreen(
        elements: [(AccessibilityElement, String)],
        objects: [String: NSObject?] = [:]
    ) {
        brains.stash.currentScreen = .makeForTests(
            elements: elements.map { ($0.0, $0.1) },
            objects: objects
        )
    }

    private func makeElement(
        label: String? = nil,
        traits: UIAccessibilityTraits = .none
    ) -> AccessibilityElement {
        .make(label: label, traits: traits, respondsToUserInteraction: false)
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
