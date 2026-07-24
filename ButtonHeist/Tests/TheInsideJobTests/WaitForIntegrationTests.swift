#if canImport(UIKit)
// Integration tests for performWaitFor — the settle-event polling loop that waits
// for an element to appear or disappear. Requires the BH Demo test host
// since wait_for polls the semantic accessibility tree via TheVault.
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
    private var visibleObservationOverride: InterfaceObservation?
    private var runtimeResources: TheInsideJob.InsideJobRuntimeResources!

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
        insideJob = try TheInsideJob(
            token: "wait-for-test-token",
            visibleObservationSource: { [weak self] vault in
                self?.visibleObservationOverride ?? TheVault.captureVisibleObservation(from: vault)
            }
        )
        let runtimeResources = TheInsideJob.InsideJobRuntimeResources(
            transport: ServerTransport(token: "wait-for-test-token"),
            actualPort: 0,
            bonjourServiceName: nil,
            idleTimerBaseline: UIApplication.shared.isIdleTimerDisabled
        )
        self.runtimeResources = runtimeResources
        await insideJob.activateRuntime(runtimeResources)
        XCTAssertTrue(insideJob.tripwire.uikitIdleTracker.isInstalled)
    }

    override func tearDown() async throws {
        if let insideJob, let runtimeResources {
            insideJob.releaseRuntimeOwnedResources(
                policy: .stop,
                idleTimerBaseline: runtimeResources.idleTimerBaseline
            )
            XCTAssertFalse(insideJob.tripwire.uikitIdleTracker.isInstalled)
        }
        insideJob = nil
        runtimeResources = nil
        window?.rootViewController?.view.accessibilityViewIsModal = false
        window?.isHidden = true
        window?.rootViewController = nil
        window = nil
        hostView = nil
        visibleObservationOverride = nil
    }

    // MARK: - Helpers

    private func collectResponse() -> (respond: SocketResponseHandler, result: () -> ActionResult?) {
        // Test-only inspection box. Mutated only from within the @Sendable
        // closure that captures it; not shared across threads in practice.
        final class Box: @unchecked Sendable {
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

    private func addButton(_ title: String, y: CGFloat = 100) -> UIButton {
        let button = UIButton(type: .system)
        button.setTitle(title, for: .normal)
        button.accessibilityLabel = title
        button.frame = CGRect(x: 10, y: y, width: 200, height: 44)
        button.addAction(UIAction { _ in }, for: .primaryActionTriggered)
        hostView.addSubview(button)
        return button
    }

    private func waitFor(
        target: AccessibilityTarget,
        absent: Bool = false,
        timeout: WaitTimeout? = nil
    ) async throws -> ActionResult? {
        let predicate: AccessibilityPredicate = absent
            ? .missing(target)
            : .exists(target)
        let waitTarget = WaitTarget(predicate: predicate, timeout: timeout)
        let step = WaitStep(
            predicate: waitTarget.predicate,
            timeout: waitTarget.resolvedTimeout
        )
        return await insideJob.brains.performWait(step: step)
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

    private func waitForSettlementDemand(after baseline: Int) async {
        for _ in 0..<1_000 {
            if insideJob.brains.vault.semanticObservationStream.activeObservationDemandCount > baseline {
                return
            }
            await Task.yield()
        }
        XCTFail("Changed wait did not arm Settlement observation demand")
    }

    @discardableResult
    private func waitForSettledVisibleObservation() async -> Bool {
        await insideJob.brains.interactionCoordinator.settledEvent(
            scope: .visible,
            after: nil,
            timeout: 1.0
        ) != nil
    }

    private func mutateVisibleHierarchy(_ body: () -> Void) async {
        body()
        await insideJob.brains.vault.invalidateSettledObservationFromTripwire()
    }

    private func assertSuccessfulWaitSettlement(
        _ result: ActionResult,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        XCTAssertTrue(insideJob.tripwire.uikitIdleTracker.isInstalled, file: file, line: line)
        let settlement = try XCTUnwrap(result.evidence.settlement, file: file, line: line)
        XCTAssertTrue(settlement.settled, file: file, line: line)
        XCTAssertTrue(settlement.readinessEstablished, file: file, line: line)
        XCTAssertTrue(settlement.observationHandoffCompleted, file: file, line: line)
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

        XCTAssertNotNil(
            animatedLayer.animation(forKey: "semanticObservationRegressionMotion"),
            "Regression setup must keep an unrelated CALayer animation active"
        )

        await insideJob.brains.vault.invalidateSettledObservationFromTripwire()
        let settledEvent = await insideJob.brains.interactionCoordinator.settledEvent(
            scope: .visible,
            after: nil,
            timeout: 2.0
        )

        let event = try XCTUnwrap(settledEvent)
        XCTAssertTrue(
            event.snapshot.observation.tree.orderedElements.contains { $0.element.label == "PassiveObservation-StableAX" },
            "Passive visible observation should publish a stable AX tree even while unrelated layer motion continues"
        )
        let diagnostic = await insideJob.brains.vault.semanticObservationStream.latestSettleFailureDiagnostic()
        XCTAssertNil(diagnostic)
    }

    // MARK: - 1. Element already present — returns immediately

    func testWaitForAlreadyPresentReturnsImmediately() async throws {
        let label = addLabel("WaitFor-AlreadyPresent")
        defer { label.removeFromSuperview() }

        let response = try await waitFor(
            target: .label("WaitFor-AlreadyPresent"),
            timeout: 5.0
        )
        let result = try XCTUnwrap(response)

        XCTAssertTrue(result.outcome.isSuccess)
        XCTAssertEqual(result.method, .wait)
        XCTAssertTrue(result.message?.hasPrefix("matched") == true)
        XCTAssertNil(result.outcome.failureKind)
        try assertSuccessfulWaitSettlement(result)
    }

    func testActionUsesSettledObservationWhileAnimationRemainsActive() async throws {
        let button = addButton("Action-RepeatingAnimation")
        defer { button.removeFromSuperview() }

        let baseline = await insideJob.brains.interactionCoordinator.settledEvent(
            scope: .visible,
            after: nil,
            timeout: 1
        )
        XCTAssertNotNil(baseline, "The action fixture must be observable before animation begins")

        UIView.animate(
            withDuration: 0.01,
            delay: 0,
            options: [.autoreverse, .repeat],
            animations: {
                button.alpha = 0.5
            }
        )
        defer { button.layer.removeAllAnimations() }

        let command = try HeistActionCommand.activate(
            .label("Action-RepeatingAnimation")
        ).resolve(in: .empty)
        let authoredExpectation = WaitStep(
            predicate: .exists(.label("Action-RepeatingAnimation")),
            timeout: try .seconds(1)
        )
        let resolvedExpectation = try authoredExpectation.resolve(in: .empty)
        let expectation = Settlement.ActionExpectation(
            authored: authoredExpectation.predicate,
            resolved: resolvedExpectation.predicate,
            timeout: resolvedExpectation.timeout
        )
        let execution = await insideJob.brains.executeRuntimeActionForHeist(
            command,
            expectation: expectation
        )
        let result = execution.result

        XCTAssertTrue(result.outcome.isSuccess, result.message ?? "action failed")
        XCTAssertEqual(result.evidence.settlement?.path, .accessibilityQuietWindow)
        try assertSuccessfulWaitSettlement(result)
        let animationIsIdle = await insideJob.tripwire.uikitIdleTracker.waitUntilIdle(timeout: .zero)
        XCTAssertFalse(animationIsIdle)
    }

    func testWaitForAppearTimeoutNamesExpectedMatcherAndInterfaceCount() async throws {
        let label = addLabel("WaitFor-Known-Anchor")
        defer { label.removeFromSuperview() }

        let response = try await waitFor(
            target: .label("WaitFor-Missing-Target"),
            timeout: 1.0
        )
        let result = try XCTUnwrap(response)
        let message = try XCTUnwrap(result.message)

        XCTAssertFalse(result.outcome.isSuccess)
        XCTAssertEqual(result.method, .wait)
        XCTAssertEqual(result.outcome.failureKind, .timeout)
        XCTAssertTrue(message.contains("waiting for element to appear"), "Unexpected message: \(message)")
        XCTAssertTrue(message.contains("expected: label=\"WaitFor-Missing-Target\""), "Unexpected message: \(message)")
        XCTAssertTrue(message.contains("interface:"), "Unexpected message: \(message)")
        XCTAssertTrue(message.contains("Next: get_interface()"), "Unexpected message: \(message)")
    }

    func testTimeoutDiagnosticsExcludeImperceptibleUIKitDescendants() async throws {
        let combined = UIView(frame: CGRect(x: 10, y: 100, width: 240, height: 44))
        combined.isAccessibilityElement = true
        combined.accessibilityLabel = "Ticket saved., Dismiss"
        combined.accessibilityTraits = .staticText
        let inner = UILabel(frame: combined.bounds)
        inner.text = "Ticket saved."
        inner.isAccessibilityElement = true
        combined.addSubview(inner)
        hostView.addSubview(combined)
        defer { combined.removeFromSuperview() }

        let response = try await waitFor(
            target: .label("Ticket saved."),
            timeout: 0.2
        )
        let message = try XCTUnwrap(response?.message)

        XCTAssertTrue(
            message.contains(#"observed accessibility candidate label="Ticket saved., Dismiss""#),
            message
        )
        XCTAssertFalse(
            message.contains(#"observed accessibility candidate label="Ticket saved." did not match"#),
            message
        )
    }

    func testSequentialWaitTimeoutDiagnosticsRemainScopedToEachWindow() async throws {
        let firstObservation = InterfaceObservation.makeForTests(elements: [(
            AccessibilityElement.make(
                label: "First candidate",
                traits: .staticText,
                respondsToUserInteraction: false
            ),
            "first_candidate"
        )])
        visibleObservationOverride = firstObservation
        await insideJob.brains.vault.installObservationForTesting(firstObservation)

        let firstResult = try await waitFor(
            target: .label("Missing candidate"),
            timeout: 0.2
        )
        let first = try XCTUnwrap(firstResult)

        let secondObservation = InterfaceObservation.makeForTests(elements: [(
            AccessibilityElement.make(
                label: "Second candidate",
                traits: .staticText,
                respondsToUserInteraction: false
            ),
            "second_candidate"
        )])
        visibleObservationOverride = secondObservation
        await insideJob.brains.vault.installObservationForTesting(secondObservation)

        let secondResult = try await waitFor(
            target: .label("Missing candidate"),
            timeout: 0.2
        )
        let second = try XCTUnwrap(secondResult)
        let firstMessage = try XCTUnwrap(first.message)
        let secondMessage = try XCTUnwrap(second.message)

        XCTAssertTrue(firstMessage.contains("First candidate"), firstMessage)
        XCTAssertFalse(firstMessage.contains("Second candidate"), firstMessage)
        XCTAssertTrue(secondMessage.contains("Second candidate"), secondMessage)
        XCTAssertFalse(secondMessage.contains("First candidate"), secondMessage)
    }

    // MARK: - 2. Element appears after a delay

    func testWaitForElementAppearsAfterDelay() async throws {
        // Delay the UI mutation by a couple of display frames so the first
        // semantic snapshot still observes absence and the poll path observes
        // the later arrival.
        let addTask = Task { @MainActor in
            for _ in 0..<2 {
                guard await self.insideJob.tripwire.waitForNextHeartbeat(
                    timeout: .seconds(1),
                    demand: .immediate
                ) == .observed else { return }
            }
            _ = self.addLabel("WaitFor-Delayed")
        }

        let response = try await self.waitFor(
            target: .label("WaitFor-Delayed"),
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
        XCTAssertNil(unwrapped.outcome.failureKind)
        try assertSuccessfulWaitSettlement(unwrapped)
    }

    // MARK: - 3. wait_for absent: true on a present element — should timeout

    func testWaitForAbsentOnPresentElementTimesOut() async throws {
        let label = addLabel("WaitFor-StillHere")
        defer { label.removeFromSuperview() }

        let response = try await waitFor(
            target: .label("WaitFor-StillHere"),
            absent: true,
            timeout: 2.0
        )
        let result = try XCTUnwrap(response)

        XCTAssertFalse(result.outcome.isSuccess)
        XCTAssertEqual(result.method, .wait)
        XCTAssertEqual(result.outcome.failureKind, .timeout)
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

        let response = try await self.waitFor(
            target: .label("WaitFor-GoingAway"),
            absent: true,
            timeout: 10.0
        )
        await removeTask.value

        let unwrapped = try XCTUnwrap(response)
        XCTAssertTrue(unwrapped.outcome.isSuccess)
        XCTAssertEqual(unwrapped.method, .wait)
        XCTAssertTrue(unwrapped.message?.contains("absent confirmed") == true)
        XCTAssertNil(unwrapped.outcome.failureKind)
        try assertSuccessfulWaitSettlement(unwrapped)
    }

    // MARK: - 5. wait_for respects timeout value

    func testWaitForRespectsTimeout() async throws {
        let start = CFAbsoluteTimeGetCurrent()

        let response = try await waitFor(
            target: .label("WaitFor-NonExistent-Element"),
            timeout: 2.0
        )
        let result = try XCTUnwrap(response)

        let elapsed = CFAbsoluteTimeGetCurrent() - start

        XCTAssertFalse(result.outcome.isSuccess)
        XCTAssertEqual(result.outcome.failureKind, .timeout)
        XCTAssertTrue(result.message?.contains("element not found") == true)
        // Should complete around 2s — allow generous margin for settle loop overhead
        XCTAssertGreaterThanOrEqual(elapsed, 1.5, "Should wait at least close to the timeout")
        XCTAssertLessThan(elapsed, 5.0, "Should not wait much longer than the timeout")
    }

    // MARK: - 6. wait_for with heistId vs matcher — both paths resolve

    func testWaitForWithMatcherByIdentifier() async throws {
        let label = addLabel("WaitFor-ById", identifier: "waitfor-test-id")
        defer { label.removeFromSuperview() }

        let response = try await waitFor(
            target: .identifier("waitfor-test-id"),
            timeout: 5.0
        )
        let result = try XCTUnwrap(response)

        XCTAssertTrue(result.outcome.isSuccess)
        XCTAssertTrue(result.message?.hasPrefix("matched") == true)
        try assertSuccessfulWaitSettlement(result)
    }

    func testWaitForAbsentTreatsKnownOffViewportElementAsPresent() async throws {
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
        visibleObservationOverride = screen
        await insideJob.brains.vault.installObservationForTesting(screen)
        XCTAssertTrue(insideJob.brains.semanticObservationIsActive)
        XCTAssertNotNil(insideJob.brains.vault.interfaceTree.findElement(heistId: offViewportHeistId))

        let response = try await waitFor(
            target: .label("WaitFor-Offscreen-StillHere"),
            absent: true,
            timeout: 2.0
        )
        let result = try XCTUnwrap(response)

        XCTAssertFalse(result.outcome.isSuccess)
        XCTAssertEqual(result.method, .wait)
        XCTAssertEqual(result.outcome.failureKind, .timeout)
        XCTAssertTrue(result.message?.contains("timed out") == true, result.message ?? "missing wait message")
    }

    // MARK: - Absent already absent returns immediately

    func testWaitForAbsentAlreadyAbsentReturnsImmediately() async throws {
        let response = try await waitFor(
            target: .label("WaitFor-NeverExisted"),
            absent: true,
            timeout: 5.0
        )
        let result = try XCTUnwrap(response)

        XCTAssertTrue(result.outcome.isSuccess)
        XCTAssertEqual(result.method, .wait)
        XCTAssertTrue(result.message?.contains("absent confirmed after") == true)
        XCTAssertNil(result.outcome.failureKind)
        try assertSuccessfulWaitSettlement(result)
    }

    // MARK: - Changed wait trace truth

    func testWaitForStatePresentAlreadyPresentSucceedsFromCurrentState() async throws {
        let label = addLabel("WaitForChange-AlreadyPresent")
        defer { label.removeFromSuperview() }

        let result = await changedWait(
            expectation: .exists(.label("WaitForChange-AlreadyPresent")),
            timeout: 1.0
        )

        XCTAssertTrue(result.outcome.isSuccess)
        XCTAssertEqual(result.method, .wait)
        XCTAssertNil(result.outcome.failureKind)
        XCTAssertTrue(
            result.message?.contains("matched") == true
        )
        try assertSuccessfulWaitSettlement(result)
    }

    func testWaitForStateAbsentAlreadyAbsentSucceedsFromCurrentState() async throws {
        let result = await changedWait(
            expectation: .missing(.label("WaitForChange-NeverExisted")),
            timeout: 1.0
        )

        XCTAssertTrue(result.outcome.isSuccess)
        XCTAssertEqual(result.method, .wait)
        XCTAssertNil(result.outcome.failureKind)
        XCTAssertTrue(
            result.message?.contains("absent confirmed") == true
        )
        try assertSuccessfulWaitSettlement(result)
    }

    func testWaitForStatePresentOnNextEventReturnsThroughWaitPath() async throws {
        let baseline = addLabel("WaitForChange-Baseline")
        defer { baseline.removeFromSuperview() }
        let didObserveBaseline = await waitForSettledVisibleObservation()
        XCTAssertTrue(didObserveBaseline)

        var delayedLabel: UILabel?
        defer { delayedLabel?.removeFromSuperview() }
        let baselineDemand = insideJob.brains.vault.semanticObservationStream
            .activeObservationDemandCount
        let mutationTask = Task { @MainActor in
            await self.waitForSettlementDemand(after: baselineDemand)
            delayedLabel = self.addLabel("WaitForChange-Delayed")
            await self.insideJob.brains.vault.invalidateSettledObservationFromTripwire()
        }
        let result = await changedWait(
            expectation: .exists(.label("WaitForChange-Delayed")),
            timeout: 5.0
        )
        await mutationTask.value

        XCTAssertTrue(result.outcome.isSuccess)
        XCTAssertEqual(result.method, .wait)
        XCTAssertTrue(result.message?.contains("matched after") == true, result.message ?? "missing wait message")
        try assertSuccessfulWaitSettlement(result)
    }

    func testWaitForStateAbsentOnNextEventReturnsThroughWaitPath() async throws {
        let label = addLabel("WaitForChange-Removed")
        let didObserveBaseline = await waitForSettledVisibleObservation()
        XCTAssertTrue(didObserveBaseline)
        XCTAssertTrue(
            insideJob.brains.vault.interfaceTree.orderedElements.contains {
                $0.element.label == "WaitForChange-Removed"
            },
            "Baseline must contain the element before waiting for absence"
        )

        let baselineDemand = insideJob.brains.vault.semanticObservationStream
            .activeObservationDemandCount
        let mutationTask = Task { @MainActor in
            await self.waitForSettlementDemand(after: baselineDemand)
            await self.mutateVisibleHierarchy {
                label.removeFromSuperview()
            }
        }
        let result = await changedWait(
            expectation: .missing(.label("WaitForChange-Removed")),
            timeout: 5.0
        )
        await mutationTask.value

        XCTAssertTrue(result.outcome.isSuccess, result.message ?? "missing wait message")
        XCTAssertEqual(result.method, .wait)
        XCTAssertTrue(
            result.message?.contains("absent confirmed after") == true,
            result.message ?? "missing wait message"
        )
        try assertSuccessfulWaitSettlement(result)
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
        XCTAssertEqual(result.outcome.failureKind, .timeout)
        XCTAssertTrue(result.message?.contains("expected: changed(elements(*))") == true)
        let settlement = try XCTUnwrap(result.evidence.settlement)
        XCTAssertTrue(settlement.settled)
        XCTAssertTrue(settlement.readinessEstablished)
        XCTAssertTrue(settlement.observationHandoffCompleted)
    }

    func testChangedWaitCancellationReturnsCanonicalFailureAndReleasesLease() async throws {
        let anchor = addLabel("WaitForChange-CancellationAnchor")
        defer { anchor.removeFromSuperview() }
        let baselineDemand = insideJob.brains.vault.semanticObservationStream
            .activeObservationDemandCount
        let waitTask = Task { @MainActor in
            await self.changedWait(
                expectation: .exists(.label("WaitForChange-NeverAppears")),
                timeout: 5.0
            )
        }
        await waitForSettlementDemand(after: baselineDemand)

        waitTask.cancel()
        let result = await waitTask.value

        XCTAssertFalse(result.outcome.isSuccess)
        XCTAssertEqual(result.method, .wait)
        XCTAssertEqual(result.outcome.failureKind, .actionFailed)
        XCTAssertTrue(result.message?.contains("settlement cancelled") == true)
        XCTAssertFalse(try XCTUnwrap(result.evidence.settlement).settled)

        let recovered = await changedWait(
            expectation: .exists(.label("WaitForChange-CancellationAnchor")),
            timeout: 1.0
        )
        XCTAssertTrue(recovered.outcome.isSuccess, recovered.message ?? "changed wait lease was not released")
        try assertSuccessfulWaitSettlement(recovered)
    }

    func testWaitForStateAbsentTimesOutWhenElementStillPresent() async throws {
        let label = addLabel("WaitForChange-StillPresent")
        defer { label.removeFromSuperview() }

        let result = await changedWait(
            expectation: .missing(.label("WaitForChange-StillPresent")),
            timeout: 1.0
        )

        XCTAssertFalse(result.outcome.isSuccess)
        XCTAssertEqual(result.method, .wait)
        XCTAssertEqual(result.outcome.failureKind, .timeout)
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
        XCTAssertEqual(result.outcome.failureKind, .timeout)
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
        XCTAssertEqual(result.outcome.failureKind, .timeout)
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
        XCTAssertEqual(result.outcome.failureKind, .timeout)
    }

}
#endif
