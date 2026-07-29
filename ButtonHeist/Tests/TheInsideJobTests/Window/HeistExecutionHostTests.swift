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
    func testFreshSnapshotBecomesReplayBaselineAfterAdmissionInvalidation() async throws {
        let observation = hostObservation(label: "Home")
        let source = HostVisibleObservationSource(observation)
        let brains = TheBrains(
            tripwire: TheTripwire(),
            failureEvidencePolicy: .hierarchy,
            visibleObservationSource: source.capture
        )
        let stream = brains.vault.semanticObservationStream
        _ = await stream.commitVisibleObservationForTesting(observation)
        await stream.stateOwner.invalidateCurrentAdmission()

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
        XCTAssertNotNil(evidence.baseline)
        XCTAssertEqual(predicate.evaluate(in: evidence).met, true)
    }

    func testEventPublishedDuringInitialCaptureIsReplayedExactlyOnce() async throws {
        let observation = hostObservation(label: "Home")
        let source = HostVisibleObservationSource(observation)
        let brains = TheBrains(
            tripwire: TheTripwire(),
            failureEvidencePolicy: .hierarchy,
            visibleObservationSource: source.capture
        )
        let stream = brains.vault.semanticObservationStream
        _ = await stream.commitVisibleObservationForTesting(observation)
        let gate = HostCaptureGate()
        installFirstReadingGate(gate, on: stream)
        defer { gate.release() }

        let execution = Task { @MainActor in
            try await HeistExecution.Host(brains: brains).execute(
                try notificationWaitPlan("Saved"),
                timeout: try .seconds(5)
            )
        }
        await gate.waitUntilEntered()
        _ = await stream.commitVisibleObservationForTesting(
            observation,
            notificationBatch: notificationBatch("Saved")
        )
        gate.release()

        let completion = try await execution.value
        let step = try XCTUnwrap(completion.steps.first)
        let evidence = try XCTUnwrap(step.waitObservation)

        XCTAssertEqual(step.status, .passed)
        XCTAssertEqual(step.reportExpectation?.met, true)
        XCTAssertEqual(evidence.notificationTexts, ["Saved"])
        XCTAssertEqual(
            evidence.events.count {
                guard case .notification = $0 else { return false }
                return true
            },
            1
        )
    }

    func testUnavailableCaptureCannotProduceCompletedWaitEvidence() async throws {
        let observation = hostObservation(label: "Home")
        let source = HostVisibleObservationSource(nil)
        let brains = TheBrains(
            tripwire: TheTripwire(),
            failureEvidencePolicy: .hierarchy,
            visibleObservationSource: source.capture
        )
        let stream = brains.vault.semanticObservationStream
        _ = await stream.commitVisibleObservationForTesting(observation)
        let gate = HostCaptureGate()
        installFirstReadingGate(gate, on: stream)
        defer { gate.release() }

        let execution = Task { @MainActor in
            try await HeistExecution.Host(brains: brains).execute(
                try notificationWaitPlan("Saved"),
                timeout: try .seconds(5)
            )
        }
        await gate.waitUntilEntered()
        _ = await stream.commitVisibleObservationForTesting(
            observation,
            notificationBatch: notificationBatch("Saved")
        )
        gate.release()

        let completion = try await execution.value
        let step = try XCTUnwrap(completion.steps.first)
        XCTAssertEqual(step.status, .failed)
        XCTAssertEqual(step.reportExpectation?.met, false)
        XCTAssertEqual(step.failure?.category, .runtimeUnavailable)
        XCTAssertEqual(step.failure?.observed, TheBrains.treeUnavailableMessage)
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
        defer { tripwire.stopPulse() }
        await tripwire.yieldFrames(2)
        let initial = try XCTUnwrap(brains.vault.refreshLiveCapture())
        _ = await brains.vault.semanticObservationStream
            .commitVisibleObservationForTesting(initial)
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

    private func notificationBatch(_ text: String) -> AccessibilityNotificationBatch {
        AccessibilityNotificationBatch(
            events: [
                PendingAccessibilityNotificationEvent(
                    sequence: 1,
                    kind: .announcement,
                    timestamp: Date(timeIntervalSince1970: 1),
                    notificationData: .string(text),
                    associatedElement: .none,
                    provenance: .scoped
                ),
            ],
            through: AccessibilityNotificationCursor(sequence: 1),
            scopedScreenChangedThrough: 0,
            gap: nil
        )
    }

    private func hostObservation(label: String) -> InterfaceObservation {
        .makeForTests(elements: [
            (AccessibilityElement.make(label: label), HeistId(rawValue: "host_element")),
        ])
    }

}

@MainActor
private final class HostVisibleObservationSource {
    var observation: InterfaceObservation?

    init(_ observation: InterfaceObservation?) {
        self.observation = observation
    }

    func capture(from _: TheVault) -> InterfaceObservation? {
        observation
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
