#if canImport(UIKit)
// Integration tests for performWaitFor — the settle-event polling loop that waits
// for an element to appear or disappear. Requires the BH Demo test host
// since wait_for polls the semantic accessibility tree via TheStash.
import ButtonHeistSupport
import XCTest
import ThePlans
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

    private func collectResponse() -> (respond: SocketResponseHandler, result: () -> ActionResult?) {
        // Test-only inspection box. Mutated only from within the @Sendable
        // closure that captures it; not shared across threads in practice.
        final class Box: @unchecked Sendable { // swiftlint:disable:this agent_unchecked_sendable_no_comment
            var data: Data?
        }
        let box = Box()
        let respond: SocketResponseHandler = { data in
            box.data = data
            return .delivered
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

    private func waitFor(
        target: ElementPredicate,
        absent: Bool = false,
        timeout: Double? = nil
    ) async -> ActionResult? {
        let accessibilityTarget = literalTarget(target)
        let predicate: AccessibilityPredicate<RootContext> = absent
            ? .missing(accessibilityTarget)
            : .exists(accessibilityTarget)
        let waitTarget = WaitTarget(predicate: predicate, timeout: timeout)
        return await insideJob.brains.performWait(target: waitTarget)
    }

    private func changedWait(
        expectation: AccessibilityPredicate<RootContext>,
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

    private func waitForSemanticObservationWaiter(
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        let stream = insideJob.brains.stash.semanticObservationStream
        let deadline = CFAbsoluteTimeGetCurrent() + 1
        while stream.settledWaiterCount == 0,
              stream.cycleWaiterCount == 0,
              CFAbsoluteTimeGetCurrent() < deadline {
            await Task.yield()
            guard await Task.cancellableSleep(for: .milliseconds(5)) else { break }
        }
        XCTAssertEqual(
            stream.settledWaiterCount + stream.cycleWaiterCount,
            1,
            "Wait must own exactly one next-event waiter",
            file: file,
            line: line
        )
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

        let scan = insideJob.tripwire.scanLayers()
        XCTAssertTrue(scan.hasRelevantAnimations, "Regression setup must keep an unrelated CALayer animation active")

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

        XCTAssertTrue(result.outcome.isSuccess)
        XCTAssertEqual(result.method, .wait)
        XCTAssertTrue(result.message?.hasPrefix("matched") == true)
        XCTAssertNil(result.outcome.errorKind)
    }

    func testWaitForAppearTimeoutNamesExpectedMatcherAndInterfaceCount() async throws {
        let label = addLabel("WaitFor-Known-Anchor")
        defer { label.removeFromSuperview() }

        let response = await waitFor(
            target: ElementPredicate(label: "WaitFor-Missing-Target"),
            timeout: 0.2
        )
        let result = try XCTUnwrap(response)
        let message = try XCTUnwrap(result.message)

        XCTAssertFalse(result.outcome.isSuccess)
        XCTAssertEqual(result.method, .wait)
        XCTAssertEqual(result.outcome.errorKind, .timeout)
        XCTAssertTrue(message.contains("waiting for element to appear"), "Unexpected message: \(message)")
        XCTAssertTrue(message.contains("expected: label=\"WaitFor-Missing-Target\""), "Unexpected message: \(message)")
        XCTAssertTrue(message.contains("interface:"), "Unexpected message: \(message)")
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
        XCTAssertTrue(unwrapped.outcome.isSuccess)
        XCTAssertEqual(unwrapped.method, .wait)
        let message = try XCTUnwrap(unwrapped.message)
        XCTAssertTrue(message.contains("matched after"), "Unexpected message: \(message)")
        XCTAssertNil(unwrapped.outcome.errorKind)
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

        XCTAssertFalse(result.outcome.isSuccess)
        XCTAssertEqual(result.method, .wait)
        XCTAssertEqual(result.outcome.errorKind, .timeout)
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
        XCTAssertTrue(unwrapped.outcome.isSuccess)
        XCTAssertEqual(unwrapped.method, .wait)
        XCTAssertTrue(unwrapped.message?.contains("absent confirmed") == true)
        XCTAssertNil(unwrapped.outcome.errorKind)
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

        XCTAssertFalse(result.outcome.isSuccess)
        XCTAssertEqual(result.outcome.errorKind, .timeout)
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

        XCTAssertTrue(result.outcome.isSuccess)
        XCTAssertTrue(result.message?.hasPrefix("matched") == true)
    }

    func testWaitForAbsentTreatsKnownOffViewportElementAsPresent() async throws {
        insideJob.brains.stash.stopPassiveSemanticObservation()

        let visibleElement = AccessibilityElement.make(
            label: "WaitFor-Offscreen-Anchor",
            traits: .staticText,
            respondsToUserInteraction: false
        )
        let offViewportElement = AccessibilityElement.make(
            label: "WaitFor-Offscreen-StillHere",
            traits: .staticText,
            respondsToUserInteraction: false
        )
        let offViewportHeistId: HeistId = "wait_for_offscreen_still_here_staticText"
        let screen = InterfaceObservation.makeForTests(
            elements: [(visibleElement, "wait_for_offscreen_anchor_staticText")],
            offViewport: [.init(offViewportElement, heistId: offViewportHeistId)]
        )
        insideJob.brains.stash.installScreenForTesting(screen)
        XCTAssertNotNil(insideJob.brains.stash.interfaceTree.findElement(heistId: offViewportHeistId))

        let response = await waitFor(
            target: ElementPredicate(label: "WaitFor-Offscreen-StillHere"),
            absent: true,
            timeout: 2.0
        )
        let result = try XCTUnwrap(response)

        XCTAssertFalse(result.outcome.isSuccess)
        XCTAssertEqual(result.method, .wait)
        XCTAssertEqual(result.outcome.errorKind, .timeout)
        XCTAssertTrue(result.message?.contains("timed out") == true, result.message ?? "missing wait message")
    }

    // MARK: - Absent already absent returns immediately

    func testWaitForAbsentAlreadyAbsentReturnsImmediately() async throws {
        let response = await waitFor(
            target: ElementPredicate(label: "WaitFor-NeverExisted"),
            absent: true,
            timeout: 5.0
        )
        let result = try XCTUnwrap(response)

        XCTAssertTrue(result.outcome.isSuccess)
        XCTAssertEqual(result.method, .wait)
        XCTAssertTrue(result.message?.contains("absent confirmed after") == true)
        XCTAssertNil(result.outcome.errorKind)
    }

    // MARK: - Changed wait trace truth

    func testWaitForStatePresentAlreadyPresentSucceedsFromCurrentState() async throws {
        let label = addLabel("WaitForChange-AlreadyPresent")
        defer { label.removeFromSuperview() }

        let result = await changedWait(
            expectation: .exists(literalTarget(ElementPredicate(label: "WaitForChange-AlreadyPresent"))),
            timeout: 0.2
        )

        XCTAssertTrue(result.outcome.isSuccess)
        XCTAssertEqual(result.method, .wait)
        XCTAssertNil(result.outcome.errorKind)
        XCTAssertTrue(
            result.message?.contains("matched") == true
        )
    }

    func testWaitForStateAbsentAlreadyAbsentSucceedsFromCurrentState() async throws {
        let result = await changedWait(
            expectation: .missing(literalTarget(ElementPredicate(label: "WaitForChange-NeverExisted"))),
            timeout: 0.2
        )

        XCTAssertTrue(result.outcome.isSuccess)
        XCTAssertEqual(result.method, .wait)
        XCTAssertNil(result.outcome.errorKind)
        XCTAssertTrue(
            result.message?.contains("absent confirmed") == true
        )
    }

    func testWaitForStatePresentOnNextEventReturnsThroughWaitPath() async throws {
        let baseline = addLabel("WaitForChange-Baseline")
        defer { baseline.removeFromSuperview() }
        let didObserveBaseline = await waitForSettledVisibleObservation()
        XCTAssertTrue(didObserveBaseline)

        var delayedLabel: UILabel?
        defer { delayedLabel?.removeFromSuperview() }
        let waitTask = Task { @MainActor in
            await self.changedWait(
                expectation: .exists(literalTarget(ElementPredicate(label: "WaitForChange-Delayed"))),
                timeout: 5.0
            )
        }
        // Commit the wait-owned baseline before publishing the satisfying event.
        await waitForSemanticObservationWaiter()
        let didObserveWaitBaseline = await waitForSettledVisibleObservation()
        XCTAssertTrue(didObserveWaitBaseline)
        delayedLabel = addLabel("WaitForChange-Delayed")
        insideJob.brains.stash.invalidateSettledObservationFromTripwire()
        let result = await waitTask.value

        XCTAssertTrue(result.outcome.isSuccess)
        XCTAssertEqual(result.method, .wait)
        XCTAssertTrue(result.message?.contains("matched after") == true, result.message ?? "missing wait message")
        XCTAssertTrue(result.accessibilityTrace?.changeFacts.contains {
            if case .elementsChanged = $0 { true } else { false }
        } == true)
    }

    func testWaitForStateAbsentOnNextEventReturnsThroughWaitPath() async throws {
        let label = addLabel("WaitForChange-Removed")
        let didObserveBaseline = await waitForSettledVisibleObservation()
        XCTAssertTrue(didObserveBaseline)
        XCTAssertTrue(
            insideJob.brains.stash.interfaceTree.orderedElements.contains {
                $0.element.label == "WaitForChange-Removed"
            },
            "Baseline must contain the element before waiting for absence"
        )

        let waitTask = Task { @MainActor in
            await self.changedWait(
                expectation: .missing(literalTarget(ElementPredicate(label: "WaitForChange-Removed"))),
                timeout: 5.0
            )
        }
        // Mutate only after the wait is suspended beyond the committed baseline.
        await waitForSemanticObservationWaiter()
        let didObserveWaitBaseline = await waitForSettledVisibleObservation()
        XCTAssertTrue(didObserveWaitBaseline)
        mutateVisibleHierarchy {
            label.removeFromSuperview()
        }

        let result = await waitTask.value

        XCTAssertTrue(result.outcome.isSuccess, result.message ?? "missing wait message")
        XCTAssertEqual(result.method, .wait)
        XCTAssertTrue(result.message?.contains("absent confirmed after") == true, result.message ?? "missing wait message")
        let facts = try XCTUnwrap(result.accessibilityTrace?.changeFacts)
        XCTAssertTrue(facts.contains { if case .elementsChanged = $0 { true } else { false } })
    }

    func testWaitForChangeElementsChangedRequiresFutureSettledDelta() async throws {
        let changed = addLabel("WaitForChange-ElementsChanged")
        defer { changed.removeFromSuperview() }
        let didObserveBaseline = await waitForSettledVisibleObservation()
        XCTAssertTrue(didObserveBaseline)

        let result = await changedWait(
            expectation: .changed(.elements()),
            timeout: 0.2
        )

        XCTAssertFalse(result.outcome.isSuccess)
        XCTAssertEqual(result.method, .wait)
        XCTAssertEqual(result.outcome.errorKind, .timeout)
        XCTAssertTrue(result.message?.contains("expected: changed(elements(*))") == true)
    }

    func testWaitForChangeTimeoutZeroPerformsOneBoundedSettledCheck() async throws {
        let baseline = addLabel("WaitForChange-TimeoutZeroBaseline")
        defer { baseline.removeFromSuperview() }
        let didObserveBaseline = await waitForSettledVisibleObservation()
        XCTAssertTrue(didObserveBaseline)

        let start = CFAbsoluteTimeGetCurrent()
        let result = await changedWait(
            expectation: .exists(literalTarget(ElementPredicate(label: "WaitForChange-TimeoutZeroMissing"))),
            timeout: 0
        )
        let elapsed = CFAbsoluteTimeGetCurrent() - start
        let message = try XCTUnwrap(result.message)

        XCTAssertFalse(result.outcome.isSuccess)
        XCTAssertEqual(result.method, .wait)
        XCTAssertEqual(result.outcome.errorKind, .timeout)
        XCTAssertLessThan(elapsed, 1.0)
        XCTAssertTrue(
            message.contains("expected: label=\"WaitForChange-TimeoutZeroMissing\""),
            "Unexpected message: \(message)"
        )
        XCTAssertTrue(message.contains("last result:"), "Unexpected message: \(message)")
    }

    func testWaitForChangeVisibleUpdatePreservesKnownOffViewportMemory() async throws {
        insideJob.brains.stash.stopPassiveSemanticObservation()

        let visibleBefore = AccessibilityElement.make(
            label: "WaitForChange-KnownMemory-Anchor",
            value: "Old",
            identifier: "wait_change_visible_anchor",
            traits: .staticText,
            respondsToUserInteraction: false
        )
        let visibleAfter = AccessibilityElement.make(
            label: "WaitForChange-KnownMemory-Anchor",
            value: "New",
            identifier: "wait_change_visible_anchor",
            traits: .staticText,
            respondsToUserInteraction: false
        )
        let visibleHeistId: HeistId = "wait_change_visible_anchor"

        let offViewportElement = AccessibilityElement.make(
            label: "WaitForChange-KnownMemory-OffViewport",
            traits: .button,
            respondsToUserInteraction: false
        )
        let offViewportHeistId: HeistId = "wait_change_known_offviewport_button"
        XCTAssertEqual(TheStash.IdAssignment.assign([visibleBefore]), [visibleHeistId])
        XCTAssertEqual(TheStash.IdAssignment.assign([visibleAfter]), [visibleHeistId])
        XCTAssertNil(
            offViewportElement.identifier,
            "The pure-value off-viewport fixture deliberately keeps its synthetic known identity"
        )
        let baseline = InterfaceObservation.makeForTests(
            elements: [(visibleBefore, visibleHeistId)],
            offViewport: [.init(offViewportElement, heistId: offViewportHeistId)]
        )
        insideJob.brains.stash.installScreenForTesting(baseline)
        XCTAssertNotNil(insideJob.brains.stash.interfaceTree.findElement(heistId: offViewportHeistId))

        let waitTask = Task { @MainActor in
            await self.changedWait(
                expectation: .changed(.elements()),
                timeout: 5.0
            )
        }
        await waitForSemanticObservationWaiter()

        let updatedVisible = InterfaceObservation.makeForTests(elements: [(visibleAfter, visibleHeistId)])
        insideJob.brains.stash.installScreenForTesting(updatedVisible)

        let result = await waitTask.value

        XCTAssertTrue(result.outcome.isSuccess, result.message ?? "changed wait did not observe visible update")
        XCTAssertNotNil(
            insideJob.brains.stash.interfaceTree.findElement(heistId: offViewportHeistId),
            "changed wait must refresh visible evidence without deleting explored off-viewport semantic memory"
        )
    }

    func testWaitForStateAbsentTimesOutWhenElementStillPresent() async throws {
        let label = addLabel("WaitForChange-StillPresent")
        defer { label.removeFromSuperview() }

        let result = await changedWait(
            expectation: .missing(literalTarget(ElementPredicate(label: "WaitForChange-StillPresent"))),
            timeout: 0.2
        )

        XCTAssertFalse(result.outcome.isSuccess)
        XCTAssertEqual(result.method, .wait)
        XCTAssertEqual(result.outcome.errorKind, .timeout)
        XCTAssertTrue(
            result.message?.contains("expected: label=\"WaitForChange-StillPresent\"") == true
        )
        XCTAssertTrue(result.message?.contains("element still present") == true)
    }

    func testWaitForChangeScreenChangedTimeoutSuggestsElementsChanged() async throws {
        let label = addLabel("WaitForChange-ScreenChangedTimeout")
        defer { label.removeFromSuperview() }

        let result = await changedWait(
            expectation: .changed(.screen()),
            timeout: 0.2
        )
        let message = try XCTUnwrap(result.message)

        XCTAssertFalse(result.outcome.isSuccess)
        XCTAssertEqual(result.method, .wait)
        XCTAssertEqual(result.outcome.errorKind, .timeout)
        XCTAssertTrue(message.contains("expected: changed(screen(*))"), "Unexpected message: \(message)")
        XCTAssertTrue(message.contains("last observed:"), "Unexpected message: \(message)")
    }

    func testWaitForChangeElementsChangedTimeoutDoesNotSuggestElementsChanged() async throws {
        let label = addLabel("WaitForChange-ElementsChangedTimeout")
        defer { label.removeFromSuperview() }

        let result = await changedWait(
            expectation: .changed(.elements()),
            timeout: 0.2
        )
        let message = try XCTUnwrap(result.message)

        XCTAssertFalse(result.outcome.isSuccess)
        XCTAssertEqual(result.method, .wait)
        XCTAssertEqual(result.outcome.errorKind, .timeout)
        XCTAssertTrue(message.contains("expected: changed(elements(*))"), "Unexpected message: \(message)")
    }

    func testWaitForChangeElementUpdatedWithOldValueRequiresObservedUpdate() async throws {
        let label = addLabel("WaitForChange-UpdateOldValue")
        label.accessibilityValue = "Ready"
        defer { label.removeFromSuperview() }

        let result = await changedWait(
            expectation: .changed(.elements([.updated(
                .label("WaitForChange-UpdateOldValue"),
                .value(before: "Loading", after: "Ready")
            )])),
            timeout: 0.2
        )

        XCTAssertFalse(result.outcome.isSuccess)
        XCTAssertEqual(result.method, .wait)
        XCTAssertEqual(result.outcome.errorKind, .timeout)
    }

}
#endif
