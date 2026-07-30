#if canImport(UIKit)
#if DEBUG
import Foundation
import UIKit
import XCTest

@testable import AccessibilitySnapshotParser
@_spi(ButtonHeistInternals) @testable import ThePlans
@testable import TheInsideJob
@_spi(ButtonHeistInternals) @testable import TheScore

@MainActor
final class HeistExecutionHostTests: ButtonHeistTestCase {
    func testHostOwnsRuntimeBoundaryForItsLifetime() throws {
        var brains: TheBrains? = TheBrains(
            tripwire: TheTripwire(),
            failureEvidencePolicy: .hierarchy
        )
        weak var retainedBrains: TheBrains?
        retainedBrains = brains
        let host = HeistExecution.Host(brains: try XCTUnwrap(brains))

        brains = nil

        XCTAssertNotNil(retainedBrains)
        withExtendedLifetime(host) {}
    }

    func testDirectActionUsesCanonicalPlanAndInjectedStandardPolicyReachesActiveLeafDeadline() async throws {
        let policy = ActionExpectationTimeoutPolicy(standard: 3, screenTransition: 12)
        let source = HostVisibleObservationSource(hostObservation(label: "Home"))
        let brains = TheBrains(
            tripwire: TheTripwire(),
            failureEvidencePolicy: .hierarchy,
            visibleObservationSource: source.capture
        )
        await brains.startTestObservation()
        defer { brains.stopTestObservation() }
        var dispatchedDeadline: SemanticObservationDeadline?
        brains.navigation.elementInflation.exploration.discoverTarget = { _, deadline in
            dispatchedDeadline = deadline
            return nil
        }

        let action = HeistActionCommand.activate(.label("Missing"))
        let direct = try await HeistExecution.Host(brains: brains).execute(
            action,
            timeout: try .seconds(5)
        )
        dispatchedDeadline = nil
        let planned = try await HeistExecution.Host(brains: brains).execute(
            HeistPlan(body: [
                .action(ActionStep(command: action)),
            ]),
            timeout: try .seconds(5),
            actionExpectationTimeoutPolicy: policy
        )

        let deadline = try XCTUnwrap(dispatchedDeadline)
        XCTAssertEqual(
            deadline.timeoutSeconds,
            policy.standard.seconds
        )
        let directStep = try XCTUnwrap(direct.steps.first)
        let plannedStep = try XCTUnwrap(planned.steps.first)

        XCTAssertEqual(directStep.path, plannedStep.path)
        XCTAssertEqual(directStep.status, plannedStep.status)
        XCTAssertEqual(directStep.actionCommand, plannedStep.actionCommand)
        XCTAssertEqual(directStep.failure, plannedStep.failure)
        let directEvidence = try XCTUnwrap(
            directStep.reportActionResult?.observationEvidence
        )
        let plannedEvidence = try XCTUnwrap(
            plannedStep.reportActionResult?.observationEvidence
        )
        XCTAssertEqual(directEvidence.coverage, plannedEvidence.coverage)
        let directBaseline = try XCTUnwrap(directEvidence.baseline)
        let plannedBaseline = try XCTUnwrap(plannedEvidence.baseline)
        let directCurrent = try XCTUnwrap(directEvidence.current)
        let plannedCurrent = try XCTUnwrap(plannedEvidence.current)
        XCTAssertTrue(
            directBaseline.hasSameObservedState(
                as: plannedBaseline,
                geometryTolerance: CoarseFrameComparison.currentGeometryTolerance
            )
        )
        XCTAssertTrue(
            directCurrent.hasSameObservedState(
                as: plannedCurrent,
                geometryTolerance: CoarseFrameComparison.currentGeometryTolerance
            )
        )
    }

    func testCausalAdmissionWaitsForVaultCoverageAcrossFailedCycles() async {
        let observation = hostObservation(label: "Home")
        let source = HostVisibleObservationSource(sequence: [nil, nil, observation])
        let tripwire = TheTripwire()
        let brains = TheBrains(
            tripwire: tripwire,
            failureEvidencePolicy: .hierarchy,
            visibleObservationSource: source.capture
        )
        let bus = brains.vault.accessibilityNotifications
        let window = bus.beginActionWindow()
        bus.record(
            sequence: 1,
            rawCode: 1008,
            timestamp: Date(timeIntervalSince1970: 1),
            notificationData: .string("Saved"),
            associatedElement: .none
        )
        await brains.startTestObservation()
        defer { brains.stopTestObservation() }

        let current = await window.admitCausallyCovered { coverage in
            await brains.vault.semanticObservationStream
                .visibleObservation(covering: coverage)
        }

        XCTAssertNotNil(current)
        XCTAssertEqual(source.captureCount, 3)
        XCTAssertTrue(
            bus.checkpoint(after: .origin, selection: .all).events.isEmpty
        )
    }

    func testTerminalCausalAdmissionAdvancesPastAnEarlierFrozenClaim() async throws {
        let observation = hostObservation(label: "Home")
        let source = HostVisibleObservationSource(sequence: [observation, observation])
        let brains = TheBrains(
            tripwire: TheTripwire(),
            failureEvidencePolicy: .hierarchy,
            visibleObservationSource: source.capture
        )
        let bus = brains.vault.accessibilityNotifications
        let scope = bus.beginHeistScope()
        bus.record(
            sequence: 1,
            rawCode: 1008,
            timestamp: Date(timeIntervalSince1970: 1),
            notificationData: .string("Earlier"),
            associatedElement: .none
        )
        _ = bus.freezeObservationCycleClaim()
        bus.record(
            sequence: 2,
            rawCode: 1008,
            timestamp: Date(timeIntervalSince1970: 2),
            notificationData: .string("Terminal"),
            associatedElement: .none
        )
        await brains.startTestObservation()
        defer { brains.stopTestObservation() }

        let current = await scope.admitCausallyCovered { coverage in
            await brains.vault.semanticObservationStream
                .visibleObservationThroughCausalCycles(covering: coverage)
        }

        XCTAssertNotNil(current)
        XCTAssertEqual(source.captureCount, 2)
        XCTAssertTrue(
            bus.checkpoint(after: .origin, selection: .all).events.isEmpty
        )
    }

    func testSuccessfulStepUsesAlreadyCoveredVaultObservationWithoutAnotherCapture() async {
        let observation = hostObservation(label: "Home")
        let source = HostVisibleObservationSource(nil)
        let brains = TheBrains(
            tripwire: TheTripwire(),
            failureEvidencePolicy: .hierarchy,
            visibleObservationSource: source.capture
        )
        let bus = brains.vault.accessibilityNotifications
        let window = bus.beginActionWindow()
        bus.record(
            sequence: 1,
            rawCode: 1008,
            timestamp: Date(timeIntervalSince1970: 1),
            notificationData: .string("Saved"),
            associatedElement: .none
        )
        let claim = bus.freezeObservationCycleClaim()
        _ = await brains.vault.semanticObservationStream
            .commitVisibleObservationForTesting(
                observation,
                notificationBatch: claim.batch
            )
        XCTAssertTrue(claim.acknowledgeObservationCycle())

        let current = await window.admitCausallyCovered { coverage in
            brains.vault.semanticObservationStream
                .currentObservation(covering: coverage)
        }

        XCTAssertNotNil(current)
        XCTAssertEqual(source.captureCount, 0)
        XCTAssertTrue(
            bus.checkpoint(after: .origin, selection: .all).events.isEmpty
        )
    }

    func testFreshSnapshotBecomesReplayBaselineAfterAdmissionInvalidation() async throws {
        let observation = hostObservation(label: "Home")
        let source = HostVisibleObservationSource(observation)
        let brains = TheBrains(
            tripwire: TheTripwire(),
            failureEvidencePolicy: .hierarchy,
            visibleObservationSource: source.capture
        )
        await brains.startTestObservation()
        defer { brains.stopTestObservation() }
        let stream = brains.vault.semanticObservationStream
        _ = await stream.commitVisibleObservationForTesting(observation)
        stream.invalidateCurrentAdmission()

        let completion = try await HeistExecution.Host(brains: brains).execute(
            try HeistPlan(body: [
                .wait(WaitStep(
                    predicate: .missing(.label("Never Existed")),
                    timeout: try .seconds(1)
                )),
            ]),
            timeout: try .seconds(5)
        )
        let step = try XCTUnwrap(completion.steps.first)
        let evidence = try XCTUnwrap(step.waitObservation)
        let predicate = try AccessibilityPredicate
            .missing(.label("Never Existed"))
            .resolve(in: .empty)

        XCTAssertEqual(step.status, .passed)
        let baseline = try XCTUnwrap(evidence.baseline)
        let current = try XCTUnwrap(evidence.current)
        XCTAssertTrue(
            baseline.hasSameObservedState(
                as: current,
                geometryTolerance: CoarseFrameComparison.currentGeometryTolerance
            )
        )
        XCTAssertEqual(
            evidence.events.count { event in
                if case .noChange = event { return true }
                return false
            },
            1
        )
        XCTAssertEqual(try step.replayExpectation()?.met, true)
        let evaluation = try predicate.evaluate(in: evidence)
        XCTAssertEqual(evaluation.met, true)
    }

    func testColdStartExcludesInitialCapturePublicationsAndDeliversPostWindowEventOnce() async throws {
        let actionView = ActionActivationOverrideView()
        let observation = InterfaceObservation.makeForTests([
            .init(
                label: "Trigger",
                traits: .button,
                object: actionView
            ),
        ])
        let source = HostVisibleObservationSource(observation)
        let tripwire = TheTripwire(pulseSource: .injected)
        let brains = TheBrains(
            tripwire: tripwire,
            failureEvidencePolicy: .hierarchy,
            visibleObservationSource: source.capture,
            notificationIngress: .injected
        )
        await brains.startTestObservation()
        defer { brains.stopTestObservation() }
        let stream = brains.vault.semanticObservationStream
        stream.observationWaiterDidRegister = {
            tripwire.onTick()
        }
        defer {
            stream.observationWaiterDidRegister = {}
        }
        actionView.onActivation = {
            brains.vault.accessibilityNotifications.recordForTesting(
                code: 1008,
                notificationData: CapturedAccessibilityNotificationPayload(
                    "After window" as NSString
                ),
                associatedElement: .none
            )
        }

        let completion = try await HeistExecution.Host(brains: brains).execute(
            try coldStartNotificationPlan(),
            timeout: try .seconds(5)
        )
        let step = try XCTUnwrap(completion.steps.first)
        let evidence = try XCTUnwrap(
            step.actionEvidence?.expectationEvidence?.observation
        )

        XCTAssertEqual(step.status, .passed)
        XCTAssertEqual(try step.replayExpectation()?.met, true)
        XCTAssertNotNil(evidence.baseline)
        XCTAssertFalse(evidence.events.contains(where: \.changesInterface))
        XCTAssertEqual(evidence.notificationTexts, ["After window"])
        XCTAssertEqual(
            evidence.events.count {
                guard case .notification = $0 else { return false }
                return true
            },
            1
        )
    }

    private func coldStartNotificationPlan() throws -> HeistPlan {
        try HeistPlan(body: [
            .action(ActionStep(
                command: .activate(.label("Trigger")),
                expectationPolicy: .expect(ActionExpectation(
                    predicate: .notification("After window"),
                    timeout: 1
                ))
            )),
        ])
    }

    func testFailedOriginRestorationCannotProduceCompletedWaitEvidence() async throws {
        let root = UIViewController()
        root.view.backgroundColor = .white
        root.view.accessibilityViewIsModal = true

        let anchor = UILabel(frame: CGRect(x: 20, y: 20, width: 200, height: 44))
        anchor.text = "Stable Screen"
        anchor.accessibilityLabel = "Stable Screen"
        anchor.isAccessibilityElement = true
        root.view.addSubview(anchor)

        let scrollView = DetachingScrollView(
            frame: CGRect(x: 0, y: 80, width: 320, height: 240)
        )
        scrollView.contentSize = CGSize(width: 320, height: 960)
        let row = UILabel(frame: CGRect(x: 20, y: 20, width: 200, height: 44))
        row.text = "Visible Row"
        row.accessibilityLabel = "Visible Row"
        row.isAccessibilityElement = true
        scrollView.addSubview(row)
        root.view.addSubview(scrollView)
        present(root, above: true)

        let tripwire = TheTripwire()
        let brains = TheBrains(
            tripwire: tripwire,
            failureEvidencePolicy: .hierarchy
        )
        tripwire.startPulse()
        await brains.startSemanticObservation()
        defer {
            brains.stopSemanticObservation()
            tripwire.stopPulse()
        }
        let initial = await brains.vault.semanticObservationStream.refreshedVisibleObservation(
            boundary: .cancellation
        )
        guard case .committed = initial else {
            return XCTFail("Expected the initial visible observation to be published")
        }
        scrollView.detachOnForwardScroll = true

        let plan = try HeistPlan(body: [
            .wait(WaitStep(
                predicate: .exists(.label("Never Appears")),
                timeout: try .seconds(5)
            )),
        ])
        let completion = try await HeistExecution.Host(brains: brains).execute(
            plan,
            timeout: try .seconds(10)
        )
        let step = try XCTUnwrap(completion.steps.first)
        XCTAssertTrue(scrollView.didDetach)
        XCTAssertEqual(step.status, .failed)
        XCTAssertEqual(step.failure?.category, .action)
        XCTAssertEqual(
            step.failure?.observed,
            "Could not restore the accessibility viewport after observation"
        )
    }

    func testWholeHeistTimeoutStillCapturesAndAdmitsFailureScreenshot() async throws {
        let source = HostVisibleObservationSource(hostObservation(label: "Home"))
        let brains = TheBrains(
            tripwire: TheTripwire(),
            failureEvidencePolicy: .screenshot,
            visibleObservationSource: source.capture
        )
        await brains.startTestObservation()
        defer { brains.stopTestObservation() }

        let execution = Task { @MainActor in
            try await HeistExecution.Host(brains: brains).execute(
                try notificationWaitPlan("Never Arrives", timeout: 5),
                timeout: try .seconds(1)
            )
        }

        let completion = try await execution.value
        let failedStep = try XCTUnwrap(completion.steps.first)
        let screenshotStep = try XCTUnwrap(completion.steps.last)

        XCTAssertEqual(failedStep.status, .failed)
        XCTAssertEqual(failedStep.failure?.category, .timeout)
        XCTAssertEqual(screenshotStep.actionCommand, .takeScreenshot)
        XCTAssertEqual(screenshotStep.reportActionResult?.method, .takeScreenshot)
        XCTAssertEqual(completion.abortedAtPath, failedStep.path)
        XCTAssertNotEqual(screenshotStep.path, completion.abortedAtPath)
    }

    func testFailureScreenshotBoundaryStopsAfterOneUnavailableObservationCycle() async {
        let source = HostVisibleObservationSource(nil)
        let brains = TheBrains(
            tripwire: TheTripwire(),
            failureEvidencePolicy: .screenshot,
            visibleObservationSource: source.capture
        )
        let gate = HostCaptureGate()
        brains.vault.semanticObservationStream.beforeVisibleReading = {
            await gate.suspend()
        }
        await brains.startTestObservation()
        defer {
            gate.release()
            brains.stopTestObservation()
        }

        let capture = Task { @MainActor in
            await brains.captureScreenPayload(
                observationBoundary: .observationCycle
            )
        }
        await gate.waitUntilEntered()
        XCTAssertEqual(
            brains.vault.semanticObservationStream.observationWaiterCount,
            1
        )
        brains.tripwire.stopPulse()
        gate.release()

        guard case .failure(let failure) = await capture.value else {
            return XCTFail("Expected unavailable observation to fail screenshot capture")
        }
        XCTAssertEqual(failure, .accessibilityTreeUnavailable)
        XCTAssertEqual(source.captureCount, 1)
        XCTAssertEqual(
            brains.vault.semanticObservationStream.observationWaiterCount,
            0
        )
    }

    func testDeadlineReturnsIncompleteEvidenceWhenFinalCaptureIsUnavailable() async throws {
        let observation = hostObservation(label: "Home")
        let source = HostVisibleObservationSource(nil)
        let brains = TheBrains(
            tripwire: TheTripwire(),
            failureEvidencePolicy: .hierarchy,
            visibleObservationSource: source.capture
        )
        await brains.startTestObservation()
        defer { brains.stopTestObservation() }
        _ = await brains.vault.semanticObservationStream
            .commitVisibleObservationForTesting(observation)

        let completion = try await HeistExecution.Host(brains: brains).execute(
            try notificationWaitPlan("Never Arrives"),
            timeout: try .seconds(5)
        )
        let failedStep = try XCTUnwrap(completion.steps.first)

        XCTAssertEqual(failedStep.status, .failed)
        XCTAssertEqual(failedStep.failure?.category, .timeout)
        XCTAssertEqual(
            failedStep.waitObservation?.coverage,
            .incomplete(.captureUnavailable)
        )
    }

    func testWaitElseRequiresCompleteReplayableFallbackEvidence() async throws {
        let observation = hostObservation(label: "Home")
        let source = HostVisibleObservationSource(nil)
        let brains = TheBrains(
            tripwire: TheTripwire(),
            failureEvidencePolicy: .hierarchy,
            visibleObservationSource: source.capture
        )
        await brains.startTestObservation()
        defer { brains.stopTestObservation() }
        _ = await brains.vault.semanticObservationStream
            .commitVisibleObservationForTesting(observation)

        let completion = try await HeistExecution.Host(brains: brains).execute(
            try HeistPlan(body: [
                .wait(WaitStep(
                    predicate: .notification("Never Arrives"),
                    timeout: 1,
                    elseBody: [.warn(WarnStep(message: "fallback"))]
                )),
            ]),
            timeout: try .seconds(5)
        )
        let wait = try XCTUnwrap(completion.steps.first)

        XCTAssertEqual(wait.status, .failed)
        XCTAssertTrue(wait.children.isEmpty)
        XCTAssertEqual(
            wait.waitObservation?.coverage,
            .incomplete(.captureUnavailable)
        )
    }

    private func installFirstReadingGate(
        _ gate: HostCaptureGate,
        on stream: Observation.Stream
    ) {
        var readingCount = 0
        stream.beforeVisibleReading = {
            readingCount += 1
            if readingCount == 1 {
                await gate.suspend()
            }
        }
    }

    private func notificationWaitPlan(
        _ text: String,
        timeout: WaitTimeout = 1
    ) throws -> HeistPlan {
        try HeistPlan(body: [
            .wait(WaitStep(
                predicate: .notification(text),
                timeout: timeout
            )),
        ])
    }

    private func hostObservation(label: String) -> InterfaceObservation {
        .makeForTests(elements: [
            (AccessibilityElement.make(label: label), HeistId(rawValue: "host_element")),
        ])
    }

}

@MainActor
private final class HostVisibleObservationSource {
    private var observations: [InterfaceObservation?]
    private(set) var captureCount = 0

    init(_ observation: InterfaceObservation?) {
        observations = [observation]
    }

    init(sequence: [InterfaceObservation?]) {
        precondition(!sequence.isEmpty)
        observations = sequence
    }

    func capture(from _: TheVault) -> InterfaceObservation? {
        captureCount += 1
        if observations.count == 1 {
            return observations[0]
        }
        return observations.removeFirst()
    }
}

@MainActor
private final class HostCaptureGate {
    private var entered = false
    private var released = false
    private var enteredWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseWaiter: CheckedContinuation<Void, Never>?

    func suspend() async {
        entered = true
        enteredWaiters.forEach { $0.resume() }
        enteredWaiters.removeAll()
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                if released || Task.isCancelled {
                    continuation.resume()
                } else {
                    releaseWaiter = continuation
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.release()
            }
        }
    }

    func waitUntilEntered() async {
        guard !entered else { return }
        await withCheckedContinuation { enteredWaiters.append($0) }
    }

    func release() {
        released = true
        releaseWaiter?.resume()
        releaseWaiter = nil
    }
}

@MainActor
private final class DetachingScrollView: UIScrollView {
    var detachOnForwardScroll = false
    private(set) var didDetach = false

    override func setContentOffset(_ contentOffset: CGPoint, animated: Bool) {
        super.setContentOffset(contentOffset, animated: animated)
        guard detachOnForwardScroll, contentOffset.y > 0, !didDetach else { return }
        didDetach = true
        removeFromSuperview()
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
