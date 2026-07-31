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

    func testSettledAdmittedBaselineCompletesPresentValueAndMissingWaits() async throws {
        let observation = InterfaceObservation.makeForTests(elements: [
            (
                AccessibilityElement.make(label: "Ready", value: "42"),
                HeistId(rawValue: "stable_ready")
            ),
        ])
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
        _ = await stream.commitVisibleObservationForTesting(observation)

        let completion = try await HeistExecution.Host(brains: brains).execute(
            try HeistPlan(body: [
                .wait(WaitStep(
                    predicate: .exists(.label("Ready")),
                    timeout: try .seconds(1)
                )),
                .wait(WaitStep(
                    predicate: .exists(.value("42")),
                    timeout: try .seconds(1)
                )),
                .wait(WaitStep(
                    predicate: .missing(.label("Back")),
                    timeout: try .seconds(1)
                )),
            ]),
            timeout: try .seconds(5)
        )

        XCTAssertEqual(completion.steps.map(\.status), [.passed, .passed, .passed])
        XCTAssertTrue(try completion.steps.allSatisfy { try $0.replayExpectation()?.met == true })
        XCTAssertTrue(try completion.steps.allSatisfy {
            try XCTUnwrap($0.waitObservation).events.allSatisfy { event in
                if case .noChange = event { return true }
                return false
            }
        })
    }

    func testColdStartChangedBaselineCannotCompleteWaitWithoutNoChangeWitness() async throws {
        let observation = hostObservation(label: "Ready")
        let source = HostVisibleObservationSource(sequence: [observation, observation])
        let tripwire = TheTripwire(pulseSource: .injected)
        let brains = TheBrains(
            tripwire: tripwire,
            failureEvidencePolicy: .hierarchy,
            visibleObservationSource: source.capture
        )
        let stream = brains.vault.semanticObservationStream
        let ticker = observationTicker(stream, tripwire: tripwire)
        await brains.startTestObservation()
        defer {
            ticker.cancel()
            brains.stopTestObservation()
        }

        let completion = try await HeistExecution.Host(brains: brains).execute(
            try HeistPlan(body: [
                .wait(WaitStep(
                    predicate: .exists(.label("Ready")),
                    timeout: try .seconds(1)
                )),
            ]),
            timeout: try .seconds(5)
        )
        let step = try XCTUnwrap(completion.steps.first)
        let evidence = try XCTUnwrap(step.waitObservation)

        XCTAssertEqual(step.status, .passed)
        XCTAssertEqual(try step.replayExpectation()?.met, true)
        XCTAssertFalse(evidence.events.contains(where: \.changesInterface))
        XCTAssertEqual(evidence.events, [.noChange])
    }

    func testWaivedActionProofStillRequiresANoChangeWitness() throws {
        let step = ActionStep(
            command: .dismiss,
            expectationPolicy: .waived(try ActionExpectationWaiver(validating: "fixture"))
        )
        let leaf = HeistExecution.ActiveLeaf.action(.init(
            id: .init(rawValue: 1),
            step: step,
            command: try HeistActionCommand.dismiss.resolve(in: .empty),
            predicate: nil,
            path: "$.body[0]",
            phase: .dispatching(Expectation([.noChange]))
        ))
        let changed = Observation.Event.elementsChanged(.init(
            interface: Interface(
                timestamp: Date(timeIntervalSince1970: 1),
                tree: []
            ),
            context: .empty
        ))
        let changedOnlyEvidence = Observation.Evidence(
            baseline: nil,
            events: [changed],
            current: changed.snapshot,
            coverage: .complete
        )

        XCTAssertFalse(leaf.expectationIsProven(by: changedOnlyEvidence))
        XCTAssertTrue(leaf.needsStabilityCapture(after: changedOnlyEvidence))
        let stableEvidence = Observation.Evidence(
            baseline: nil,
            events: [changed, .noChange],
            current: changed.snapshot,
            coverage: .complete
        )
        XCTAssertTrue(leaf.expectationIsProven(by: stableEvidence))
        XCTAssertFalse(leaf.needsStabilityCapture(after: stableEvidence))
    }

    func testUnmetWaitProofDoesNotRequestAStabilityCapture() throws {
        let step = WaitStep(
            predicate: .exists(.label("Ready")),
            timeout: try .seconds(1),
            elseBody: [.warn(WarnStep(message: "fallback"))]
        )
        let plan = try HeistPlan(body: [.wait(step)])
        let leaf = HeistExecution.ActiveLeaf.wait(.init(
            id: .init(rawValue: 1),
            predicate: try .init(authored: step.predicate, bindings: .empty),
            purpose: .authored(
                step: step,
                context: .init(path: "$.body[0]", environment: .empty, scope: .init(plan: plan))
            ),
            phase: .beginningObservation
        ))
        let evidence = Observation.Evidence(
            baseline: nil,
            events: [.elementsChanged(.init(
                interface: Interface(
                    timestamp: Date(timeIntervalSince1970: 1),
                    tree: []
                ),
                context: .empty
            ))],
            current: nil,
            coverage: .complete
        )

        XCTAssertFalse(leaf.expectationIsProven(by: evidence))
        XCTAssertFalse(leaf.needsStabilityCapture(after: evidence))
    }

    func testExecutionBoundaryDoesNotReplayStableEventAfterInterveningChange() async throws {
        let ready = hostObservation(label: "Ready")
        let changed = hostObservation(label: "Changed")
        let source = HostVisibleObservationSource(changed)
        let brains = TheBrains(
            tripwire: TheTripwire(pulseSource: .injected),
            failureEvidencePolicy: .hierarchy,
            visibleObservationSource: source.capture
        )
        await brains.startTestObservation()
        defer { brains.stopTestObservation() }
        let stream = brains.vault.semanticObservationStream
        _ = await stream.commitVisibleObservationForTesting(ready)
        _ = await stream.commitVisibleObservationForTesting(ready)
        _ = await stream.commitVisibleObservationForTesting(changed)

        var replayedEvents: [Observation.Event] = []
        let admission = try XCTUnwrap(stream.admitExecutionBoundary {
            replayedEvents.append($0)
        })
        defer {
            admission.subscription.cancel()
            admission.demand.cancel()
            stream.releaseHistory(from: admission.retainedHistoryIndex)
        }

        XCTAssertEqual(admission.retainedHistoryIndex, brains.vault.state.history.endIndex)
        XCTAssertTrue(replayedEvents.isEmpty)
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
        let ticker = observationTicker(stream, tripwire: tripwire)
        defer {
            ticker.cancel()
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

    func testWholeHeistTimeoutCapturesFailureScreenshotOutsideExecutionSteps() async throws {
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

        XCTAssertEqual(completion.steps.count, 1)
        XCTAssertEqual(failedStep.status, .failed)
        XCTAssertEqual(failedStep.failure?.category, .timeout)
        XCTAssertNotNil(completion.failureCapture?.payload)
        XCTAssertEqual(completion.steps.first(where: { $0.status == .failed })?.path, failedStep.path)
    }

    func testFailureScreenshotBoundaryStopsAfterOneUnavailableObservationCycle() async {
        let source = HostVisibleObservationSource(nil)
        let brains = TheBrains(
            tripwire: TheTripwire(),
            failureEvidencePolicy: .screenshot,
            visibleObservationSource: source.capture
        )
        await brains.startTestObservation()
        defer {
            brains.stopTestObservation()
        }

        let capture = Task { @MainActor in
            await brains.captureScreenPayload(
                observationBoundary: .observationCycle
            )
        }
        try? await waitForObservationWaiter(in: brains.vault.semanticObservationStream)
        XCTAssertEqual(
            brains.vault.semanticObservationStream.observationWaiterCount,
            1
        )
        brains.tripwire.stopPulse()
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

    func testLifecycleMatrixCancellationDuringEffectReleasesEveryTokenOnce() async throws {
        let tripwire = TheTripwire(pulseSource: .injected)
        let source = HostVisibleObservationSource(hostObservation(label: "Home"))
        let brains = TheBrains(
            tripwire: tripwire,
            failureEvidencePolicy: .screenshot,
            visibleObservationSource: source.capture
        )
        await brains.startTestObservation()
        defer { brains.stopTestObservation() }

        let execution = Task { @MainActor in
            try await HeistExecution.Host(brains: brains).execute(
                try HeistPlan(body: [
                    .fail(FailStep(message: try .init(validating: "expected failure"))),
                ]),
                timeout: try .seconds(5)
            )
        }
        try await waitForObservationWaiter(in: brains.vault.semanticObservationStream)
        execution.cancel()
        tripwire.onTick()

        do {
            _ = try await execution.value
            XCTFail("Expected execution interrupted during failure-capture effect to cancel")
        } catch is CancellationError {
            // Expected: the observation-cycle effect completes before cancellation is observed.
        }

    }

    func testLifecycleMatrixCancellationWhileWaitingForAnEvent() async throws {
        let tripwire = TheTripwire(pulseSource: .injected)
        let source = HostVisibleObservationSource(hostObservation(label: "Home"))
        let brains = TheBrains(
            tripwire: tripwire,
            failureEvidencePolicy: .hierarchy,
            visibleObservationSource: source.capture
        )
        let stream = brains.vault.semanticObservationStream
        let ticker = observationTicker(stream, tripwire: tripwire)
        await brains.startTestObservation()
        defer {
            ticker.cancel()
            brains.stopTestObservation()
        }

        let execution = Task { @MainActor in
            try await HeistExecution.Host(brains: brains).execute(
                try self.notificationWaitPlan("never", timeout: 30),
                timeout: try .seconds(60)
            )
        }
        try await waitForCapture(in: source)
        for _ in 0..<8 { await Task.yield() }
        execution.cancel()

        do {
            _ = try await execution.value
            XCTFail("Expected execution waiting for an event to be cancelled")
        } catch is CancellationError {
            // Expected: cancellation crosses the active observation wait.
        }
    }

    func testCancellationRestoresPhysicalViewportAndAdmitsOneTerminalObservationCycle() async throws {
        let root = UIViewController()
        root.view.backgroundColor = .white
        root.view.accessibilityViewIsModal = true
        let scrollView = TrackingScrollView(
            frame: CGRect(x: 0, y: 40, width: 320, height: 240)
        )
        scrollView.contentSize = CGSize(width: 320, height: 960)
        let row = UILabel(frame: CGRect(x: 20, y: 20, width: 200, height: 44))
        row.text = "Visible Row"
        row.accessibilityLabel = "Visible Row"
        row.isAccessibilityElement = true
        scrollView.addSubview(row)
        root.view.addSubview(scrollView)
        present(root, above: true)

        let tripwire = TheTripwire(pulseSource: .injected)
        let brains = TheBrains(tripwire: tripwire, failureEvidencePolicy: .hierarchy)
        let stream = brains.vault.semanticObservationStream
        let forwardScroll = HostCaptureGate()
        scrollView.onForwardScroll = forwardScroll.arrive
        let ticker = observationTicker(stream, tripwire: tripwire)
        await brains.startTestObservation()
        defer {
            ticker.cancel()
            brains.stopTestObservation()
        }

        let initialContentOffset = scrollView.contentOffset

        let execution = Task { @MainActor in
            try await HeistExecution.Host(brains: brains).execute(
                try HeistPlan(body: [
                    .wait(WaitStep(
                        predicate: .exists(.label("Never Appears")),
                        timeout: 30
                    )),
                ]),
                timeout: try .seconds(60)
            )
        }
        await forwardScroll.waitUntilEntered()
        XCTAssertGreaterThan(scrollView.forwardScrollCount, 0)
        XCTAssertGreaterThan(scrollView.contentOffset.y, 0)
        execution.cancel()

        do {
            _ = try await execution.value
            XCTFail("Expected cancelled execution")
        } catch is CancellationError {
            // Expected after terminal restoration finishes.
        }

        XCTAssertEqual(scrollView.contentOffset, initialContentOffset)
    }

    func testLifecycleMatrixLeafTimeoutReleasesEveryTokenOnce() async throws {
        let (brains, ticker) = await lifecycleTimeoutFixture()
        defer {
            ticker.cancel()
            brains.stopTestObservation()
        }

        let completion = try await HeistExecution.Host(brains: brains).execute(
            try notificationWaitPlan("never", timeout: 1),
            timeout: try .seconds(5)
        )

        XCTAssertEqual(completion.steps.first?.failure?.category, .timeout)
    }

    func testLifecycleMatrixWholeHeistTimeoutReleasesEveryTokenOnce() async throws {
        let (brains, ticker) = await lifecycleTimeoutFixture()
        defer {
            ticker.cancel()
            brains.stopTestObservation()
        }

        let completion = try await HeistExecution.Host(brains: brains).execute(
            try notificationWaitPlan("never", timeout: 5),
            timeout: try .seconds(1)
        )

        XCTAssertEqual(completion.steps.first?.failure?.category, .timeout)
    }

    func testTimelyExplorationObservationIsReducedBeforeTheNextDeadlineDecision() async throws {
        let tripwire = TheTripwire(pulseSource: .injected)
        let source = HostVisibleObservationSource(sequence: [
            hostObservation(label: "Home"),
            hostObservation(label: "Ready"),
        ])
        let brains = TheBrains(
            tripwire: tripwire,
            failureEvidencePolicy: .hierarchy,
            visibleObservationSource: source.capture
        )
        let stream = brains.vault.semanticObservationStream
        let ticker = observationTicker(stream, tripwire: tripwire)
        await brains.startTestObservation()
        defer {
            ticker.cancel()
            brains.stopTestObservation()
        }

        let completion = try await HeistExecution.Host(brains: brains).execute(
            try HeistPlan(body: [
                .wait(WaitStep(
                    predicate: .exists(.label("Ready")),
                    timeout: 1
                )),
            ]),
            timeout: try .seconds(5)
        )

        XCTAssertEqual(completion.steps.first?.status, .passed)
    }

    private func lifecycleTimeoutFixture() async -> (TheBrains, Task<Void, Never>) {
        let tripwire = TheTripwire(pulseSource: .injected)
        let source = HostVisibleObservationSource(hostObservation(label: "Home"))
        let brains = TheBrains(
            tripwire: tripwire,
            failureEvidencePolicy: .hierarchy,
            visibleObservationSource: source.capture
        )
        let ticker = observationTicker(brains.vault.semanticObservationStream, tripwire: tripwire)
        await brains.startTestObservation()
        return (brains, ticker)
    }

    private func waitForObservationWaiter(in stream: Observation.Stream) async throws {
        for _ in 0..<100 {
            if stream.observationWaiterCount == 1 { return }
            await Task.yield()
        }
        throw HostLifecycleTestFailure.observationWaiterDidNotRegister
    }

    private func waitForCapture(in source: HostVisibleObservationSource) async throws {
        for _ in 0..<100 {
            if source.captureCount > 0 { return }
            await Task.yield()
        }
        throw HostLifecycleTestFailure.observationDidNotBegin
    }

    private func observationTicker(
        _ stream: Observation.Stream,
        tripwire: TheTripwire
    ) -> Task<Void, Never> {
        Task { @MainActor in
            while !Task.isCancelled {
                if stream.observationWaiterCount > 0 {
                    tripwire.onTick()
                }
                await Task.yield()
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

    func arrive() {
        guard !entered else { return }
        entered = true
        enteredWaiters.forEach { $0.resume() }
        enteredWaiters.removeAll()
    }

    func suspend() async {
        arrive()
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

private enum HostLifecycleTestFailure: Error {
    case observationDidNotBegin
    case observationWaiterDidNotRegister
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

@MainActor
private final class TrackingScrollView: UIScrollView {
    private(set) var forwardScrollCount = 0
    var onForwardScroll: (@MainActor () -> Void)?

    override func setContentOffset(_ contentOffset: CGPoint, animated: Bool) {
        if contentOffset.y > self.contentOffset.y {
            forwardScrollCount += 1
            onForwardScroll?()
        }
        super.setContentOffset(contentOffset, animated: animated)
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
