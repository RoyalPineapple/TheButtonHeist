#if canImport(UIKit)
// Integration tests for performWaitFor — the settle-event polling loop that waits
// for an element to appear or disappear. Requires the BH Demo test host
// since wait_for polls the semantic accessibility tree via TheStash.
import XCTest
@testable import AccessibilitySnapshotParser
@testable import TheInsideJob
@testable import TheScore

@MainActor
final class WaitForIntegrationTests: XCTestCase {

    private var insideJob: TheInsideJob!
    private var window: UIWindow!
    private var hostView: UIView!

    override func setUp() async throws {
        let windowScene = try requireForegroundWindowScene()
        let viewController = UIViewController()
        viewController.view.backgroundColor = .white
        viewController.view.accessibilityViewIsModal = true

        let window = UIWindow(windowScene: windowScene)
        window.frame = UIScreen.main.bounds
        window.windowLevel = .alert + 60
        window.rootViewController = viewController
        window.isHidden = false

        self.window = window
        hostView = viewController.view
        insideJob = TheInsideJob(token: "wait-for-test-token")
        insideJob.tripwire.startPulse()
        insideJob.brains.startSemanticObservation()
    }

    override func tearDown() async throws {
        insideJob?.brains.stopSemanticObservation()
        insideJob?.tripwire.stopPulse()
        insideJob = nil
        window?.rootViewController?.view.accessibilityViewIsModal = false
        window?.isHidden = true
        window?.rootViewController = nil
        window = nil
        hostView = nil
    }

    // MARK: - Helpers

    private func requireForegroundWindowScene() throws -> UIWindowScene {
        guard let scene = UIApplication.shared.connectedScenes
            .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene
        else {
            throw XCTSkip("No foreground-active UIWindowScene available in test host")
        }
        return scene
    }

    private func collectResponse() -> (respond: @Sendable (Data) -> Void, result: () -> ActionResult?) {
        // Test-only inspection box. Mutated only from within the @Sendable
        // closure that captures it; not shared across threads in practice.
        final class Box: @unchecked Sendable { // swiftlint:disable:this agent_unchecked_sendable_no_comment
            var data: Data?
        }
        let box = Box()
        let respond: @Sendable (Data) -> Void = { data in
            box.data = data
        }
        return (respond, {
            guard let data = box.data else { return nil }
            let envelope: ResponseEnvelope
            do {
                envelope = try JSONDecoder().decode(ResponseEnvelope.self, from: data)
            } catch {
                XCTFail("Failed to decode ResponseEnvelope: \(error)")
                return nil
            }
            guard case .actionResult(let result) = envelope.message else { return nil }
            return result
        })
    }

    @discardableResult
    private func addLabel(_ text: String, identifier: String? = nil, y: CGFloat = 100) -> UILabel {
        let label = UILabel()
        label.text = text
        label.accessibilityLabel = text
        label.isAccessibilityElement = true
        label.frame = CGRect(x: 10, y: y, width: 200, height: 44)
        if let identifier {
            label.accessibilityIdentifier = identifier
        }
        hostView.addSubview(label)
        return label
    }

    @discardableResult
    private func addScrollViewWithOffscreenLabel(_ text: String) -> UIScrollView {
        let scrollView = UIScrollView(frame: CGRect(x: 10, y: 100, width: 220, height: 120))
        scrollView.contentSize = CGSize(width: 220, height: 640)
        scrollView.isAccessibilityElement = false

        let label = UILabel(frame: CGRect(x: 10, y: 480, width: 180, height: 44))
        label.text = text
        label.accessibilityLabel = text
        label.isAccessibilityElement = true
        scrollView.addSubview(label)

        hostView.addSubview(scrollView)
        return scrollView
    }

    private func waitFor(
        target: ElementPredicate,
        absent: Bool = false,
        timeout: Double? = nil
    ) async -> ActionResult? {
        let state: AccessibilityPredicate.State = absent ? .absent(target) : .present(target)
        let waitTarget = WaitTarget(predicate: .state(state), timeout: timeout)
        return await insideJob.brains.performWait(target: waitTarget)
    }

    private func changedWait(
        expectation: AccessibilityPredicate,
        timeout: Double? = nil
    ) async -> ActionResult {
        await insideJob.brains.executeChangedWait(
            timeout: timeout ?? 5.0,
            expectation: expectation
        )
    }

    @discardableResult
    private func waitForSettledVisibleObservation() async -> Bool {
        await insideJob.brains.interactionObservation.observeSemanticState(
            scope: .visible,
            after: nil,
            timeout: 1.0
        ) != nil
    }

    private func mutateVisibleHierarchy(_ body: () -> Void) {
        body()
        insideJob.brains.stash.invalidateSettledObservationFromTripwire()
    }

    // MARK: - Passive Observation

    func testPassiveVisibleObservationPublishesStableAXTreeWhileLayerAnimationRuns() async throws {
        let label = addLabel("PassiveObservation-StableAX")
        defer { label.removeFromSuperview() }

        let animatedLayer = CALayer()
        animatedLayer.frame = CGRect(x: 0, y: 0, width: 12, height: 12)
        hostView.layer.addSublayer(animatedLayer)
        defer {
            animatedLayer.removeAllAnimations()
            animatedLayer.removeFromSuperlayer()
        }

        let animation = CABasicAnimation(keyPath: "position.x")
        animation.fromValue = 0
        animation.toValue = 24
        animation.duration = 10.0
        animation.repeatCount = .infinity
        animatedLayer.add(animation, forKey: "semanticObservationRegressionMotion")

        let layerSettled = await insideJob.tripwire.waitForAllClear(timeout: 0.2)
        XCTAssertFalse(layerSettled, "Regression setup must keep the CALayer quiet gate blocked")

        insideJob.brains.stash.invalidateSettledObservationFromTripwire()
        let observation = await insideJob.brains.interactionObservation.observeSemanticState(
            scope: .visible,
            after: nil,
            timeout: 2.0
        )

        let event = try XCTUnwrap(observation?.event)
        XCTAssertTrue(
            event.observation.screen.orderedElements.contains { $0.element.label == "PassiveObservation-StableAX" },
            "Passive visible observation should publish a stable AX tree even while unrelated layer motion continues"
        )
        XCTAssertNil(insideJob.brains.stash.latestSemanticObservationFailureDiagnostic())
    }

    // MARK: - 1. Element already present — returns immediately

    func testWaitForAlreadyPresentReturnsImmediately() async throws {
        let label = addLabel("WaitFor-AlreadyPresent")
        defer { label.removeFromSuperview() }

        let response = await waitFor(
            target: ElementPredicate(label: "WaitFor-AlreadyPresent"),
            timeout: 5.0
        )
        let result = try XCTUnwrap(response)

        XCTAssertTrue(result.success)
        XCTAssertEqual(result.method, .wait)
        XCTAssertTrue(result.message?.hasPrefix("matched") == true)
        XCTAssertNil(result.errorKind)
    }

    func testWaitForAppearTimeoutNamesExpectedMatcherAndKnownCount() async throws {
        let label = addLabel("WaitFor-Known-Anchor")
        defer { label.removeFromSuperview() }

        let response = await waitFor(
            target: ElementPredicate(label: "WaitFor-Missing-Target"),
            timeout: 0.2
        )
        let result = try XCTUnwrap(response)
        let message = try XCTUnwrap(result.message)

        XCTAssertFalse(result.success)
        XCTAssertEqual(result.method, .wait)
        XCTAssertEqual(result.errorKind, .timeout)
        XCTAssertTrue(message.contains("waiting for element to appear"), "Unexpected message: \(message)")
        XCTAssertTrue(message.contains("expected: label=\"WaitFor-Missing-Target\""), "Unexpected message: \(message)")
        XCTAssertTrue(message.contains("known:"), "Unexpected message: \(message)")
        XCTAssertTrue(message.contains("Next: get_interface()"), "Unexpected message: \(message)")
    }

    // MARK: - 2. Element appears after a delay

    func testWaitForElementAppearsAfterDelay() async throws {
        // Delay the UI mutation by a couple of display frames so the first
        // semantic snapshot still observes absence and the poll path observes
        // the later arrival.
        let addTask = Task { @MainActor in
            await self.insideJob.tripwire.yieldRealFrames(2)
            _ = self.addLabel("WaitFor-Delayed")
        }

        let response = await self.waitFor(
            target: ElementPredicate(label: "WaitFor-Delayed"),
            timeout: 10.0
        )
        await addTask.value

        // Clean up
        for subview in window.subviews where subview.accessibilityLabel == "WaitFor-Delayed" {
            subview.removeFromSuperview()
        }

        let unwrapped = try XCTUnwrap(response)
        XCTAssertTrue(unwrapped.success)
        XCTAssertEqual(unwrapped.method, .wait)
        let message = try XCTUnwrap(unwrapped.message)
        XCTAssertTrue(message.contains("matched after"), "Unexpected message: \(message)")
        XCTAssertNil(unwrapped.errorKind)
    }

    // MARK: - 3. wait_for absent: true on a present element — should timeout

    func testWaitForAbsentOnPresentElementTimesOut() async throws {
        let label = addLabel("WaitFor-StillHere")
        defer { label.removeFromSuperview() }

        let response = await waitFor(
            target: ElementPredicate(label: "WaitFor-StillHere"),
            absent: true,
            timeout: 2.0
        )
        let result = try XCTUnwrap(response)

        XCTAssertFalse(result.success)
        XCTAssertEqual(result.method, .wait)
        XCTAssertEqual(result.errorKind, .timeout)
        XCTAssertTrue(result.message?.contains("element still present") == true)
    }

    // MARK: - 4. wait_for absent: true on an element that disappears

    func testWaitForAbsentElementDisappears() async throws {
        let label = addLabel("WaitFor-GoingAway")

        // Queue the removal on @MainActor; it runs once waitFor suspends on
        // its first tripwire await. The pulse then observes the absence and
        // resolves the wait deterministically.
        let removeTask = Task { @MainActor in
            label.removeFromSuperview()
        }

        let response = await self.waitFor(
            target: ElementPredicate(label: "WaitFor-GoingAway"),
            absent: true,
            timeout: 10.0
        )
        await removeTask.value

        let unwrapped = try XCTUnwrap(response)
        XCTAssertTrue(unwrapped.success)
        XCTAssertEqual(unwrapped.method, .wait)
        XCTAssertTrue(unwrapped.message?.contains("absent confirmed") == true)
        XCTAssertNil(unwrapped.errorKind)
    }

    // MARK: - 5. wait_for respects timeout value

    func testWaitForRespectsTimeout() async throws {
        let start = CFAbsoluteTimeGetCurrent()

        let response = await waitFor(
            target: ElementPredicate(label: "WaitFor-NonExistent-Element"),
            timeout: 2.0
        )
        let result = try XCTUnwrap(response)

        let elapsed = CFAbsoluteTimeGetCurrent() - start

        XCTAssertFalse(result.success)
        XCTAssertEqual(result.errorKind, .timeout)
        XCTAssertTrue(result.message?.contains("element not found") == true)
        // Should complete around 2s — allow generous margin for settle loop overhead
        XCTAssertGreaterThanOrEqual(elapsed, 1.5, "Should wait at least close to the timeout")
        XCTAssertLessThan(elapsed, 5.0, "Should not wait much longer than the timeout")
    }

    // MARK: - 6. wait_for with heistId vs matcher — both paths resolve

    func testWaitForWithMatcherByIdentifier() async throws {
        let label = addLabel("WaitFor-ById", identifier: "waitfor-test-id")
        defer { label.removeFromSuperview() }

        let response = await waitFor(
            target: ElementPredicate(identifier: "waitfor-test-id"),
            timeout: 5.0
        )
        let result = try XCTUnwrap(response)

        XCTAssertTrue(result.success)
        XCTAssertTrue(result.message?.hasPrefix("matched") == true)
    }

    func testWaitForAbsentTreatsOffscreenScrollableElementAsPresent() async throws {
        let scrollView = addScrollViewWithOffscreenLabel("WaitFor-Offscreen-StillHere")
        defer { scrollView.removeFromSuperview() }

        let response = await waitFor(
            target: ElementPredicate(label: "WaitFor-Offscreen-StillHere"),
            absent: true,
            timeout: 2.0
        )
        let result = try XCTUnwrap(response)

        XCTAssertFalse(result.success)
        XCTAssertEqual(result.method, .wait)
        XCTAssertEqual(result.errorKind, .timeout)
        XCTAssertTrue(result.message?.contains("element still present") == true)
    }

    // MARK: - Absent already absent returns immediately

    func testWaitForAbsentAlreadyAbsentReturnsImmediately() async throws {
        let response = await waitFor(
            target: ElementPredicate(label: "WaitFor-NeverExisted"),
            absent: true,
            timeout: 5.0
        )
        let result = try XCTUnwrap(response)

        XCTAssertTrue(result.success)
        XCTAssertEqual(result.method, .wait)
        XCTAssertTrue(result.message?.contains("absent confirmed after") == true)
        XCTAssertNil(result.errorKind)
    }

    // MARK: - Changed wait trace truth

    func testWaitForChangeElementAppearedAlreadyPresentStillRequiresObservedChange() async throws {
        let label = addLabel("WaitForChange-AlreadyPresent")
        defer { label.removeFromSuperview() }

        let result = await changedWait(
            expectation: .changed(.appeared(ElementPredicate(label: "WaitForChange-AlreadyPresent"))),
            timeout: 0.2
        )

        XCTAssertFalse(result.success)
        XCTAssertEqual(result.method, .wait)
        XCTAssertEqual(result.errorKind, .timeout)
        XCTAssertTrue(
            result.message?.contains("expected: changed(element_appeared(predicate(label=\"WaitForChange-AlreadyPresent\")))") == true
        )
    }

    func testWaitForChangeElementDisappearedAlreadyAbsentStillRequiresObservedChange() async throws {
        let result = await changedWait(
            expectation: .changed(.disappeared(ElementPredicate(label: "WaitForChange-NeverExisted"))),
            timeout: 0.2
        )

        XCTAssertFalse(result.success)
        XCTAssertEqual(result.method, .wait)
        XCTAssertEqual(result.errorKind, .timeout)
        XCTAssertTrue(
            result.message?.contains("expected: changed(element_disappeared(predicate(label=\"WaitForChange-NeverExisted\")))") == true
        )
    }

    func testWaitForChangeElementAppearedOnNextEventReturnsThroughChangePath() async throws {
        let baseline = addLabel("WaitForChange-Baseline")
        defer { baseline.removeFromSuperview() }
        let didObserveBaseline = await waitForSettledVisibleObservation()
        XCTAssertTrue(didObserveBaseline)

        var delayedLabel: UILabel?
        defer { delayedLabel?.removeFromSuperview() }
        let addTask = Task { @MainActor in
            await self.insideJob.tripwire.yieldRealFrames(2)
            let label = self.addLabel("WaitForChange-Delayed")
            self.insideJob.brains.stash.invalidateSettledObservationFromTripwire()
            return label
        }

        let result = await changedWait(
            expectation: .changed(.appeared(ElementPredicate(label: "WaitForChange-Delayed"))),
            timeout: 5.0
        )
        delayedLabel = await addTask.value

        XCTAssertTrue(result.success)
        XCTAssertEqual(result.method, .wait)
        XCTAssertTrue(result.message?.contains("predicate met after") == true, result.message ?? "missing wait message")
        guard case .elementsChanged = result.accessibilityTrace?.endpointDelta else {
            return XCTFail("Expected elementsChanged delta, got \(String(describing: result.accessibilityTrace?.endpointDelta))")
        }
    }

    func testWaitForChangeElementDisappearedOnNextEventReturnsThroughChangePath() async throws {
        let label = addLabel("WaitForChange-Removed")
        let didObserveBaseline = await waitForSettledVisibleObservation()
        XCTAssertTrue(didObserveBaseline)

        let removeTask = Task { @MainActor in
            await self.insideJob.tripwire.yieldRealFrames(2)
            label.removeFromSuperview()
            self.insideJob.brains.stash.invalidateSettledObservationFromTripwire()
        }

        let result = await changedWait(
            expectation: .changed(.disappeared(ElementPredicate(label: "WaitForChange-Removed"))),
            timeout: 5.0
        )
        await removeTask.value

        XCTAssertTrue(result.success, result.message ?? "missing wait message")
        XCTAssertEqual(result.method, .wait)
        XCTAssertTrue(result.message?.contains("predicate met after") == true, result.message ?? "missing wait message")
        guard case .elementsChanged = result.accessibilityTrace?.endpointDelta else {
            return XCTFail("Expected elementsChanged delta, got \(String(describing: result.accessibilityTrace?.endpointDelta))")
        }
    }

    func testWaitForChangeElementsChangedRequiresFutureSettledDelta() async throws {
        let changed = addLabel("WaitForChange-ElementsChanged")
        defer { changed.removeFromSuperview() }
        let didObserveBaseline = await waitForSettledVisibleObservation()
        XCTAssertTrue(didObserveBaseline)

        let result = await changedWait(
            expectation: .changed(.elements),
            timeout: 0.2
        )

        XCTAssertFalse(result.success)
        XCTAssertEqual(result.method, .wait)
        XCTAssertEqual(result.errorKind, .timeout)
        XCTAssertTrue(result.message?.contains("expected: changed(elements_changed)") == true)
    }

    func testWaitForChangeTimeoutZeroPerformsOneBoundedSettledCheck() async throws {
        let baseline = addLabel("WaitForChange-TimeoutZeroBaseline")
        defer { baseline.removeFromSuperview() }
        let didObserveBaseline = await waitForSettledVisibleObservation()
        XCTAssertTrue(didObserveBaseline)

        let start = CFAbsoluteTimeGetCurrent()
        let result = await changedWait(
            expectation: .changed(.appeared(ElementPredicate(label: "WaitForChange-TimeoutZeroMissing"))),
            timeout: 0
        )
        let elapsed = CFAbsoluteTimeGetCurrent() - start
        let message = try XCTUnwrap(result.message)

        XCTAssertFalse(result.success)
        XCTAssertEqual(result.method, .wait)
        XCTAssertEqual(result.errorKind, .timeout)
        XCTAssertLessThan(elapsed, 1.0)
        XCTAssertTrue(
            message.contains("expected: changed(element_appeared(predicate(label=\"WaitForChange-TimeoutZeroMissing\")))"),
            "Unexpected message: \(message)"
        )
        XCTAssertTrue(message.contains("baseline: sequence "), "Unexpected message: \(message)")
        XCTAssertTrue(message.contains("last settled: sequence "), "Unexpected message: \(message)")
        XCTAssertTrue(message.contains("last delta:"), "Unexpected message: \(message)")
        XCTAssertTrue(message.contains("no future settled observation arrived after baseline"), "Unexpected message: \(message)")
    }

    func testWaitForChangeVisibleUpdatePreservesKnownOffViewportMemory() async throws {
        let visible = addLabel(
            "WaitForChange-KnownMemory-Anchor",
            identifier: "wait_change_visible_anchor"
        )
        visible.accessibilityValue = "Old"
        defer { visible.removeFromSuperview() }

        guard insideJob.brains.stash.refreshLiveCapture() != nil else {
            throw XCTSkip("No live hierarchy available for changed-wait memory test")
        }

        let offViewportElement = AccessibilityElement.make(
            label: "WaitForChange-KnownMemory-OffViewport",
            traits: .button,
            respondsToUserInteraction: false
        )
        let offViewportHeistId = "wait_change_known_offviewport_button"
        let offViewportMemory = Screen.makeForTests(
            offViewport: [.init(offViewportElement, heistId: offViewportHeistId)]
        )
        insideJob.brains.stash.installScreenForTesting(offViewportMemory.merging(
            insideJob.brains.stash.settledSemanticScreen
        ))
        XCTAssertNotNil(insideJob.brains.stash.settledSemanticScreen.findElement(heistId: offViewportHeistId))

        let mutationTask = Task { @MainActor in
            await self.insideJob.tripwire.yieldRealFrames(2)
            self.mutateVisibleHierarchy {
                // Mutate a tracked update property (value) while keeping the element's
                // identity (identifier/label) stable so before/after pair on the same
                // diffPairingKey and the change registers as an elements update.
                visible.accessibilityValue = "New"
            }
        }

        let result = await changedWait(
            expectation: .changed(.elements),
            timeout: 5.0
        )
        await mutationTask.value

        XCTAssertTrue(result.success, result.message ?? "changed wait did not observe visible update")
        XCTAssertNotNil(
            insideJob.brains.stash.settledSemanticScreen.findElement(heistId: offViewportHeistId),
            "changed wait must refresh visible evidence without deleting explored off-viewport semantic memory"
        )
    }

    func testWaitForChangeElementDisappearedTimesOutWhenElementStillPresent() async throws {
        let label = addLabel("WaitForChange-StillPresent")
        defer { label.removeFromSuperview() }

        let result = await changedWait(
            expectation: .changed(.disappeared(ElementPredicate(label: "WaitForChange-StillPresent"))),
            timeout: 0.2
        )

        XCTAssertFalse(result.success)
        XCTAssertEqual(result.method, .wait)
        XCTAssertEqual(result.errorKind, .timeout)
        XCTAssertTrue(
            result.message?.contains("expected: changed(element_disappeared(predicate(label=\"WaitForChange-StillPresent\")))") == true
        )
        XCTAssertTrue(result.message?.contains("last observed:") == true)
    }

    func testWaitForChangeScreenChangedTimeoutSuggestsElementsChanged() async throws {
        let label = addLabel("WaitForChange-ScreenChangedTimeout")
        defer { label.removeFromSuperview() }

        let result = await changedWait(
            expectation: .changed(.screen()),
            timeout: 0.2
        )
        let message = try XCTUnwrap(result.message)

        XCTAssertFalse(result.success)
        XCTAssertEqual(result.method, .wait)
        XCTAssertEqual(result.errorKind, .timeout)
        XCTAssertTrue(message.contains("expected: changed(screen_changed)"), "Unexpected message: \(message)")
        XCTAssertTrue(message.contains("last observed:"), "Unexpected message: \(message)")
    }

    func testWaitForChangeElementsChangedTimeoutDoesNotSuggestElementsChanged() async throws {
        let label = addLabel("WaitForChange-ElementsChangedTimeout")
        defer { label.removeFromSuperview() }

        let result = await changedWait(
            expectation: .changed(.elements),
            timeout: 0.2
        )
        let message = try XCTUnwrap(result.message)

        XCTAssertFalse(result.success)
        XCTAssertEqual(result.method, .wait)
        XCTAssertEqual(result.errorKind, .timeout)
        XCTAssertTrue(message.contains("expected: changed(elements_changed)"), "Unexpected message: \(message)")
        XCTAssertFalse(message.contains("predicate: {\"type\": \"elements_changed\"}"), "Unexpected message: \(message)")
    }

    func testWaitForChangeElementUpdatedWithOldValueRequiresObservedUpdate() async throws {
        let label = addLabel("WaitForChange-UpdateOldValue")
        label.accessibilityValue = "Ready"
        defer { label.removeFromSuperview() }

        let result = await changedWait(
            expectation: .changed(.updated(ElementUpdatePredicate(
                element: nil,
                property: .value,
                from: "Loading",
                to: "Ready"
            ))),
            timeout: 0.2
        )

        XCTAssertFalse(result.success)
        XCTAssertEqual(result.method, .wait)
        XCTAssertEqual(result.errorKind, .timeout)
    }

}
#endif
