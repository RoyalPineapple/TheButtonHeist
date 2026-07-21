#if canImport(UIKit)
import Foundation
import XCTest
import ThePlans
import UIKit
@testable import AccessibilitySnapshotParser
@testable import TheInsideJob
@testable import TheScore

@MainActor
extension TheBrainsPipelineTests {

    // MARK: - Wait Evidence Path

    func testWaitSuccessResultUsesSettledVisibleObservation() async throws {
        brains.vault.semanticObservationStream.commitVisibleObservationForTesting(
            makeScreen(elements: [("Home", .header, "home")])
        )
        let result = await brains.interactionCoordinator.waitForPredicate(
            try resolvedWait(WaitStep(predicate: .exists(.label("Home")), timeout: .milliseconds(1)))
        )
        let trace = try XCTUnwrap(result.outcome.actionResult.accessibilityTrace)

        XCTAssertTrue(result.outcome.actionResult.outcome.isSuccess)
        XCTAssertEqual(trace.captures.last?.interface.projectedElements.map(\.label), ["Home"])
        XCTAssertTrue(result.outcome.expectation.met)
    }

    func testWaitTimeoutResultUsesLastSettledVisibleObservation() async throws {
        brains.vault.installObservationForTesting(
            makeScreen(elements: [("Known", .staticText, "known")])
        )
        let result = await brains.interactionCoordinator.waitForPredicate(
            try resolvedWait(WaitStep(predicate: .exists(.label("Missing")), timeout: .milliseconds(1)))
        )
        let trace = try XCTUnwrap(result.outcome.actionResult.accessibilityTrace)

        XCTAssertFalse(result.outcome.actionResult.outcome.isSuccess)
        XCTAssertEqual(result.outcome.actionResult.outcome.failureKind, .timeout)
        XCTAssertEqual(trace.captures.last?.interface.projectedElements.map(\.label), ["Known"])
        XCTAssertTrue(result.outcome.actionResult.message?.contains("interface: 1 elements") == true)
        XCTAssertTrue(result.outcome.actionResult.message?.contains("last result:") == true)
    }

    func testTimeoutReportIncludesObservedCombinedLabelMismatch() async throws {
        brains.vault.semanticObservationStream.commitVisibleObservationForTesting(
            makeScreen(elements: [("Ticket saved., Dismiss", .staticText, "toast")])
        )
        let wait = WaitStep(
            predicate: .exists(.label("Ticket saved.")),
            timeout: try .milliseconds(1)
        )
        let result = await brains.interactionCoordinator.waitForPredicate(try resolvedWait(wait))
        guard case .unmatched(let actionResult, let expectation) = result.outcome else {
            return XCTFail("Expected the exact predicate to time out")
        }
        let evidence = HeistWaitEvidence.failed(
            .init(executed: actionResult, expectation: expectation.result),
            finalSummary: expectation.actual
        )
        let step = HeistExecutionStepResult.wait(
            path: "$.body[0]",
            durationMs: 1,
            predicate: wait.predicate,
            timeout: wait.timeout,
            completion: .failed(
                evidence: .observed(.init(admitted: evidence)),
                failure: brains.standaloneWaitFailureDetail(wait: wait, result: result)
            )
        )
        let report = HeistReport.project(result: try HeistResult(steps: [step], durationMs: 1))
        let failure = try XCTUnwrap(report.failure?.message)

        XCTAssertTrue(failure.contains(#"observed accessibility candidate label="Ticket saved., Dismiss""#), failure)
        XCTAssertTrue(failure.contains(#"did not match exists(target(predicate(label="Ticket saved.")))"#), failure)
        XCTAssertEqual(report.failure?.actionKind, .timeout)
        XCTAssertFalse(report.summary.expectations?.allMet == true)
    }

    func testTimeoutDiagnosticsExcludeImperceptibleUIKitDescendants() async throws {
        let combined = UIView(frame: CGRect(x: 0, y: 0, width: 240, height: 44))
        combined.isAccessibilityElement = true
        combined.accessibilityLabel = "Ticket saved., Dismiss"
        combined.accessibilityTraits = .staticText
        let inner = UILabel(frame: combined.bounds)
        inner.text = "Ticket saved."
        inner.isAccessibilityElement = true
        combined.addSubview(inner)

        let semanticElement = try XCTUnwrap(brains.vault.captureObject(combined))
        XCTAssertEqual(semanticElement.label, "Ticket saved., Dismiss")
        brains.vault.semanticObservationStream.commitVisibleObservationForTesting(
            .makeForTests([.init(semanticElement, heistId: HeistId(rawValue: "toast"))])
        )

        let result = await brains.interactionCoordinator.waitForPredicate(
            try resolvedWait(WaitStep(
                predicate: .exists(.label("Ticket saved.")),
                timeout: .milliseconds(1)
            ))
        )
        let message = try XCTUnwrap(result.outcome.actionResult.message)

        XCTAssertTrue(
            message.contains(#"observed accessibility candidate label="Ticket saved., Dismiss""#),
            message
        )
        XCTAssertFalse(
            message.contains(#"observed accessibility candidate label="Ticket saved." did not match"#),
            message
        )
    }

    func testAutomaticTimeoutDiagnosticsScheduleNoExtraWork() async throws {
        let withCandidate = try await automaticTimeoutRun(
            screen: makeScreen(elements: [("Ticket saved., Dismiss", .staticText, "toast")])
        )
        let withoutCandidate = try await automaticTimeoutRun(screen: .empty)

        let candidateMessage = try XCTUnwrap(withCandidate.result.outcome.actionResult.message)
        let emptyMessage = try XCTUnwrap(withoutCandidate.result.outcome.actionResult.message)

        XCTAssertTrue(candidateMessage.contains("observed accessibility candidate"), candidateMessage)
        XCTAssertFalse(emptyMessage.contains("observed accessibility candidate"), emptyMessage)
        XCTAssertFalse(withCandidate.result.outcome.actionResult.outcome.isSuccess)
        XCTAssertFalse(withoutCandidate.result.outcome.actionResult.outcome.isSuccess)
        XCTAssertEqual(withCandidate.result.outcome.actionResult.outcome.failureKind, .timeout)
        XCTAssertEqual(withoutCandidate.result.outcome.actionResult.outcome.failureKind, .timeout)
        XCTAssertEqual(withCandidate.work, withoutCandidate.work)
        XCTAssertGreaterThan(withCandidate.work.captureCount, 0)
        XCTAssertGreaterThan(withCandidate.work.commitCount, 0)
        XCTAssertGreaterThan(withCandidate.work.settlementCount, 0)
        XCTAssertGreaterThan(withCandidate.work.actionCount, 0)
        XCTAssertGreaterThan(withCandidate.work.discoveryCount, 0)
        XCTAssertGreaterThan(withCandidate.work.observationWaitCount, 0)
        XCTAssertGreaterThan(withCandidate.work.scheduledSettlementCount, 0)
        XCTAssertNil(withCandidate.result.outcome.actionResult.warning)
        XCTAssertNil(withoutCandidate.result.outcome.actionResult.warning)
    }

    func testTimeoutDiagnosticsRemainScopedToEachStandaloneWait() async throws {
        brains.vault.semanticObservationStream.commitVisibleObservationForTesting(
            makeScreen(elements: [("First candidate", .staticText, "first")])
        )
        let first = await brains.interactionCoordinator.waitForPredicate(
            try resolvedWait(WaitStep(
                predicate: .exists(.label("Missing")),
                timeout: .milliseconds(1)
            ))
        )

        brains.vault.semanticObservationStream.commitVisibleObservationForTesting(
            makeScreen(elements: [("Second candidate", .staticText, "second")])
        )
        let second = await brains.interactionCoordinator.waitForPredicate(
            try resolvedWait(WaitStep(
                predicate: .exists(.label("Missing")),
                timeout: .milliseconds(1)
            ))
        )

        let firstMessage = try XCTUnwrap(first.outcome.actionResult.message)
        let secondMessage = try XCTUnwrap(second.outcome.actionResult.message)

        XCTAssertTrue(firstMessage.contains("First candidate"), firstMessage)
        XCTAssertFalse(firstMessage.contains("Second candidate"), firstMessage)
        XCTAssertTrue(secondMessage.contains("Second candidate"), secondMessage)
        XCTAssertFalse(secondMessage.contains("First candidate"), secondMessage)
    }

    private func automaticTimeoutRun(
        screen: InterfaceObservation
    ) async throws -> HistoricalWaitAutomaticRun {
        let spy = HistoricalWaitUIWorkSpy(observation: screen)
        let isolatedBrains = TheBrains(
            tripwire: TheTripwire(),
            visibleObservationSource: spy.capture
        )
        defer { isolatedBrains.stopSemanticObservation() }
        isolatedBrains.interactionCoordinator.observePredicateWaitScheduledEffects(spy.observe)
        isolatedBrains.vault.semanticObservationStream.settleVisibleObservation = { vault, _, _, baseline, _ in
            spy.settle(vault: vault, baseline: baseline)
        }
        let wait = WaitStep(
            predicate: .exists(.label("Ticket saved.")),
            timeout: try .milliseconds(350)
        )
        let runtime = TheBrains.HeistExecutionRuntime(
            execute: { command, _ in
                spy.execute(command)
            },
            wait: { request in
                let result = await isolatedBrains.interactionCoordinator.waitForPredicate(
                    request.step,
                    initialTrace: request.initialTrace,
                    baselineSequence: request.afterSequence,
                    changeBaseline: request.changeBaseline,
                    actionExpectationContext: request.actionExpectationContext,
                    startedAt: request.startedAt
                )
                spy.record(result)
                return result
            },
            selectPredicateCase: { cases, timeout in
                await isolatedBrains.interactionCoordinator.waitForPredicateCases(
                    cases,
                    timeout: timeout
                )
            },
            settledEvidence: { scope, sequence, timeout in
                await isolatedBrains.interactionCoordinator.settledEvidence(
                    scope: scope,
                    after: sequence,
                    timeout: timeout
                )
            }
        )
        let plan = try HeistPlan(body: [
            .action(ActionStep(
                command: .setPasteboard(SetPasteboardTarget(text: "diagnostic work probe")),
                expectationPolicy: .expect(try ActionExpectation(wait))
            )),
        ])

        _ = await isolatedBrains.executeHeistPlanForTest(plan, runtime: runtime)
        let result = try XCTUnwrap(spy.waitResult)
        return HistoricalWaitAutomaticRun(
            result: result,
            work: spy.snapshot(
                commitCount: isolatedBrains.vault.semanticObservationStream
                    .latestCommittedObservation?.sequence.rawValue ?? 0
            )
        )
    }

    func testTimeoutDiagnosticEvictsOldestSemanticCandidatesDeterministically() async throws {
        let elements = (0 ..< 10).map { index in
            ("Candidate \(index)", UIAccessibilityTraits.staticText, HeistId(rawValue: "candidate_\(index)"))
        }
        brains.vault.semanticObservationStream.commitVisibleObservationForTesting(
            makeScreen(elements: elements)
        )

        let result = await brains.interactionCoordinator.waitForPredicate(
            try resolvedWait(WaitStep(
                predicate: .exists(.label("Missing")),
                timeout: .milliseconds(1)
            ))
        )
        let message = try XCTUnwrap(result.outcome.actionResult.message)

        for index in 0 ..< 2 {
            XCTAssertFalse(
                message.contains("observed accessibility candidate label=\"Candidate \(index)\" traits="),
                message
            )
        }
        for index in 2 ..< 10 {
            XCTAssertTrue(
                message.contains("observed accessibility candidate label=\"Candidate \(index)\" traits="),
                message
            )
        }
    }

    func testAppearedWaitRequiresObservedTransitionWhenFinalStateIsAlreadyPresent() async throws {
        let ready = makeScreen(elements: [("Ready", .staticText, "ready")])
        let result = try await temporalWaitResult(
            predicate: .changed(.elements([.appeared(.label("Ready"))])),
            baseline: ready,
            final: ready
        )

        XCTAssertFalse(result.outcome.actionResult.outcome.isSuccess)
        XCTAssertEqual(result.outcome.actionResult.outcome.failureKind, .timeout)
        XCTAssertFalse(result.outcome.expectation.met)
        XCTAssertTrue(elementChanges(in: result).isEmpty)
    }

    func testAppearedWaitSucceedsFromCanonicalTransition() async throws {
        let result = try await temporalWaitResult(
            predicate: .changed(.elements([.appeared(.label("Ready"))])),
            baseline: .empty,
            final: makeScreen(elements: [("Ready", .staticText, "ready")])
        )
        let changes = try XCTUnwrap(elementChanges(in: result).first)

        XCTAssertTrue(result.outcome.actionResult.outcome.isSuccess)
        XCTAssertTrue(result.outcome.expectation.met)
        XCTAssertEqual(changes.appeared.count, 1)
        XCTAssertTrue(changes.disappeared.isEmpty)
        XCTAssertTrue(changes.updated.isEmpty)
    }

    func testDisappearedWaitRequiresObservedTransitionWhenFinalStateIsAlreadyAbsent() async throws {
        let result = try await temporalWaitResult(
            predicate: .changed(.elements([.disappeared(.label("Loading"))])),
            baseline: .empty,
            final: .empty
        )

        XCTAssertFalse(result.outcome.actionResult.outcome.isSuccess)
        XCTAssertEqual(result.outcome.actionResult.outcome.failureKind, .timeout)
        XCTAssertFalse(result.outcome.expectation.met)
        XCTAssertTrue(elementChanges(in: result).isEmpty)
    }

    func testDisappearedWaitSucceedsFromCanonicalTransition() async throws {
        let result = try await temporalWaitResult(
            predicate: .changed(.elements([.disappeared(.label("Loading"))])),
            baseline: makeScreen(elements: [("Loading", .staticText, "loading")]),
            final: .empty
        )
        let changes = try XCTUnwrap(elementChanges(in: result).first)

        XCTAssertTrue(result.outcome.actionResult.outcome.isSuccess)
        XCTAssertTrue(result.outcome.expectation.met)
        XCTAssertTrue(changes.appeared.isEmpty)
        XCTAssertEqual(changes.disappeared.count, 1)
        XCTAssertTrue(changes.updated.isEmpty)
    }

    func testUpdatedWaitRequiresObservedTransitionWhenFinalStateAlreadyMatches() async throws {
        let quantity = volumeScreen(value: "3")
        let result = try await temporalWaitResult(
            predicate: .changed(.elements([.updated(
                .label("Volume"),
                .value(before: "2", after: "3")
            )])),
            baseline: quantity,
            final: quantity
        )

        XCTAssertFalse(result.outcome.actionResult.outcome.isSuccess)
        XCTAssertEqual(result.outcome.actionResult.outcome.failureKind, .timeout)
        XCTAssertFalse(result.outcome.expectation.met)
        XCTAssertTrue(elementChanges(in: result).isEmpty)
    }

    func testUpdatedWaitSucceedsFromCanonicalTransition() async throws {
        let result = try await temporalWaitResult(
            predicate: .changed(.elements([.updated(
                .label("Volume"),
                .value(before: "2", after: "3")
            )])),
            baseline: volumeScreen(value: "2"),
            final: volumeScreen(value: "3")
        )
        let changes = try XCTUnwrap(elementChanges(in: result).first)

        XCTAssertTrue(result.outcome.actionResult.outcome.isSuccess)
        XCTAssertTrue(result.outcome.expectation.met)
        XCTAssertTrue(changes.appeared.isEmpty)
        XCTAssertTrue(changes.disappeared.isEmpty)
        XCTAssertEqual(changes.updated.count, 1)
    }

    func testCanonicalInitialTraceCanProveCompletedChangeWithoutAnotherObservation() async throws {
        _ = brains.vault.semanticObservationStream.commitVisibleObservationForTesting(
            volumeScreen(value: "2")
        )
        let after = brains.vault.semanticObservationStream.commitVisibleObservationForTesting(
            volumeScreen(value: "3")
        )
        let result = await brains.interactionCoordinator.waitForPredicate(
            try resolvedWait(WaitStep(predicate: .changed(.elements()), timeout: .milliseconds(1))),
            initialTrace: after.trace
        )

        XCTAssertTrue(result.outcome.actionResult.outcome.isSuccess)
        XCTAssertTrue(result.outcome.expectation.met)
    }

    func testSuppliedCanonicalBaselineOverridesStaleInitialTrace() async throws {
        let stream = brains.vault.semanticObservationStream
        let beforeEvent = stream.commitVisibleObservationForTesting(volumeScreen(value: "2"))
        let afterEvent = stream.commitVisibleObservationForTesting(volumeScreen(value: "3"))
        let before = try XCTUnwrap(beforeEvent.settledCapture)
        let after = try XCTUnwrap(afterEvent.settledCapture)
        let staleBrains = TheBrains(tripwire: TheTripwire())
        defer { staleBrains.stopSemanticObservation() }
        let staleEvent = staleBrains.vault.semanticObservationStream.commitVisibleObservationForTesting(
            volumeScreen(value: "1")
        )
        let staleHash = try XCTUnwrap(staleEvent.trace.captures.last?.hash)
        let result = await brains.interactionCoordinator.waitForPredicate(
            try resolvedWait(WaitStep(predicate: .changed(.elements()), timeout: .milliseconds(1))),
            initialTrace: staleEvent.trace,
            changeBaseline: .supplied(before)
        )

        XCTAssertTrue(result.outcome.actionResult.outcome.isSuccess)
        XCTAssertTrue(result.outcome.expectation.met)
        XCTAssertEqual(
            result.outcome.actionResult.accessibilityTrace?.captures.map(\.hash),
            [before.capture.hash, after.capture.hash]
        )
        XCTAssertFalse(result.outcome.actionResult.accessibilityTrace?.captures.contains { $0.hash == staleHash } == true)
    }

    func testPredicateWaitBuildsScreenChangeHistoryOnlyFromCanonicalObservationLog() async throws {
        let stream = brains.vault.semanticObservationStream
        let beforeEvent = stream.commitVisibleObservationForTesting(
            makeScreen(elements: [("ButtonHeist Demo", .header, "root")])
        )
        let actionEndpointEvent = stream.commitVisibleObservationForTesting(
            makeScreen(elements: [("Order Summary", .header, "summary")]),
            notificationBatch: notificationBatch(kind: .screenChanged)
        )
        let destinationEvent = stream.commitVisibleObservationForTesting(
            makeScreen(elements: [
                ("Order Summary", .header, "summary"),
                ("Menu", .button, "menu"),
            ])
        )
        let before = try XCTUnwrap(beforeEvent.settledCapture)
        let actionEndpoint = try XCTUnwrap(actionEndpointEvent.settledCapture)
        let destination = try XCTUnwrap(destinationEvent.settledCapture)
        let result = await brains.interactionCoordinator.waitForPredicate(
            try resolvedWait(WaitStep(
                predicate: .changed(.screen([.exists(.label("Menu"))])),
                timeout: .milliseconds(1)
            )),
            changeBaseline: .supplied(before)
        )

        XCTAssertTrue(result.outcome.actionResult.outcome.isSuccess)
        XCTAssertTrue(result.outcome.expectation.met)
        XCTAssertEqual(result.outcome.actionResult.traceEvidence?.completeness, .complete)
        let resultTrace = try XCTUnwrap(result.outcome.actionResult.accessibilityTrace)
        XCTAssertEqual(
            resultTrace.captures.map(\.hash),
            [before.capture.hash, actionEndpoint.capture.hash, destination.capture.hash]
        )
        XCTAssertEqual(resultTrace.captures.last?.interface.projectedElements.last?.label, "Menu")
        XCTAssertTrue(resultTrace.changeFacts.contains {
            if case .screenChanged = $0 { true } else { false }
        })
    }

    func testCanonicalObservationWindowsKeepScreenAndElementFactsDistinct() throws {
        let elementStream = brains.vault.semanticObservationStream
        let elementBeforeEvent = elementStream.commitVisibleObservationForTesting(volumeScreen(value: "2"))
        let elementAfterEvent = elementStream.commitVisibleObservationForTesting(volumeScreen(value: "3"))
        let elementBefore = try XCTUnwrap(elementBeforeEvent.settledCapture)
        let elementWindow = try XCTUnwrap(elementStream.observationWindow(
            from: elementBefore,
            through: elementAfterEvent
        ))

        let screenBrains = TheBrains(tripwire: TheTripwire())
        defer { screenBrains.stopSemanticObservation() }
        let screenStream = screenBrains.vault.semanticObservationStream
        let screenBeforeEvent = screenStream.commitVisibleObservationForTesting(
            makeScreen(elements: [("Home", .header, "home")])
        )
        let screenAfterEvent = screenStream.commitVisibleObservationForTesting(
            makeScreen(elements: [("Details", .header, "details")]),
            notificationBatch: notificationBatch(kind: .screenChanged)
        )
        let screenBefore = try XCTUnwrap(screenBeforeEvent.settledCapture)
        let screenWindow = try XCTUnwrap(screenStream.observationWindow(
            from: screenBefore,
            through: screenAfterEvent
        ))

        XCTAssertEqual(elementWindow.trace.changeFacts.map(\.kind), [.elementsChanged])
        XCTAssertEqual(
            screenWindow.trace.changeFacts.map(\.kind),
            [.elementsChanged, .screenChanged, .elementsChanged]
        )
        XCTAssertNil(screenAfterEvent.trace.captures.last?.transition.fallbackReason)
    }

    func testObservationWindowRetainsFastRoundTripTransition() throws {
        let baselineEvent = brains.vault.semanticObservationStream.commitVisibleObservationForTesting(
            volumeScreen(value: "50%")
        )
        _ = brains.vault.semanticObservationStream.commitVisibleObservationForTesting(
            volumeScreen(value: "60%")
        )
        let finalEvent = brains.vault.semanticObservationStream.commitVisibleObservationForTesting(
            volumeScreen(value: "50%")
        )
        let baseline = try XCTUnwrap(baselineEvent.settledCapture)
        let window = try XCTUnwrap(brains.vault.semanticObservationStream.observationWindow(
            from: baseline,
            through: finalEvent
        ))

        XCTAssertEqual(window.completeness, .complete)
        XCTAssertEqual(window.trace.captures.count, 3)
        XCTAssertEqual(window.trace.changeFacts.count, 2)
        XCTAssertTrue(window.trace.changeFacts.allSatisfy {
            if case .elementsChanged = $0 { return true }
            return false
        })
    }

    func testObservationWindowTraceContainsExactlyRetainedLogCaptures() throws {
        let baselineEvent = brains.vault.semanticObservationStream.commitDiscoveryObservationForTesting(
            volumeScreen(value: "50%")
        )
        let actionEndpointEvent = brains.vault.semanticObservationStream.commitDiscoveryObservationForTesting(
            volumeScreen(value: "60%")
        )
        let intermediateEvent = brains.vault.semanticObservationStream.commitDiscoveryObservationForTesting(
            volumeScreen(value: "70%")
        )
        let finalEvent = brains.vault.semanticObservationStream.commitDiscoveryObservationForTesting(
            volumeScreen(value: "80%")
        )
        let baseline = try XCTUnwrap(baselineEvent.settledCapture)
        let actionEndpoint = try XCTUnwrap(actionEndpointEvent.settledCapture)
        let intermediate = try XCTUnwrap(intermediateEvent.settledCapture)
        let final = try XCTUnwrap(finalEvent.settledCapture)
        let window = try XCTUnwrap(brains.vault.semanticObservationStream.observationWindow(
            from: baseline,
            through: finalEvent
        ))

        XCTAssertEqual(
            window.trace.captures.map(\.hash),
            [baseline.capture.hash, actionEndpoint.capture.hash, intermediate.capture.hash, final.capture.hash]
        )
        XCTAssertEqual(window.trace.changeFacts.count, 3)
    }

    func testCompleteObservationWindowProducesUnchangedWaitEvidence() async throws {
        let baselineEvent = brains.vault.semanticObservationStream.commitVisibleObservationForTesting(
            volumeScreen(value: "50%")
        )
        let currentEvent = brains.vault.semanticObservationStream.commitVisibleObservationForTesting(
            volumeScreen(value: "50%")
        )
        let baseline = try XCTUnwrap(baselineEvent.settledCapture)
        let window = try XCTUnwrap(brains.vault.semanticObservationStream.observationWindow(
            from: baseline,
            through: currentEvent
        ))

        XCTAssertEqual(window.completeness, .complete)
        XCTAssertTrue(window.trace.changeFacts.isEmpty)

        let expression = AccessibilityPredicate.noChange
        let predicate = try resolvedPredicate(expression)
        let result = await brains.interactionCoordinator.waitForPredicate(
            try resolvedWait(WaitStep(predicate: expression, timeout: .milliseconds(1))),
            changeBaseline: .supplied(baseline)
        )

        XCTAssertTrue(result.outcome.actionResult.outcome.isSuccess)
        XCTAssertTrue(result.outcome.expectation.met)
        XCTAssertEqual(result.outcome.actionResult.traceEvidence?.completeness, .complete)
        XCTAssertTrue(predicate.validate(against: result.outcome.actionResult).met)
    }

    func testIncompleteObservationWindowTimesOutUnchangedWait() async throws {
        let baselineEvent = brains.vault.semanticObservationStream.commitVisibleObservationForTesting(
            volumeScreen(value: "50%")
        )
        let baseline = try XCTUnwrap(baselineEvent.settledCapture)
        var currentEvent = baselineEvent
        for _ in 0...SemanticObservationStore.defaultRetentionLimit {
            currentEvent = brains.vault.semanticObservationStream.commitVisibleObservationForTesting(
                volumeScreen(value: "50%")
            )
        }
        let window = try XCTUnwrap(brains.vault.semanticObservationStream.observationWindow(
            from: baseline,
            through: currentEvent
        ))

        guard case .incomplete = window.completeness else {
            return XCTFail("Expected evicted baseline history to make the window incomplete")
        }
        XCTAssertTrue(window.trace.changeFacts.isEmpty)

        let expression = AccessibilityPredicate.noChange
        let predicate = try resolvedPredicate(expression)
        let result = await brains.interactionCoordinator.waitForPredicate(
            try resolvedWait(WaitStep(predicate: expression, timeout: .milliseconds(1))),
            changeBaseline: .supplied(baseline)
        )
        let laterValidation = predicate.validate(
            against: result.outcome.actionResult
        )

        XCTAssertFalse(result.outcome.actionResult.outcome.isSuccess)
        XCTAssertEqual(result.outcome.actionResult.outcome.failureKind, .timeout)
        XCTAssertFalse(result.outcome.expectation.met)
        XCTAssertEqual(result.outcome.expectation.actual, "observation history incomplete")
        XCTAssertEqual(result.outcome.actionResult.traceEvidence?.completeness, .incomplete)
        XCTAssertFalse(laterValidation.met)
        XCTAssertEqual(laterValidation.actual, "observation history incomplete")
    }

    func testIncompleteObservationWindowUsesOnlyRetainedElementEdges() throws {
        let baselineEvent = brains.vault.semanticObservationStream.commitVisibleObservationForTesting(
            volumeScreen(value: "50%")
        )
        let baseline = try XCTUnwrap(baselineEvent.settledCapture)
        for _ in 0...SemanticObservationStore.defaultRetentionLimit {
            _ = brains.vault.semanticObservationStream.commitVisibleObservationForTesting(
                volumeScreen(value: "50%")
            )
        }
        let currentEvent = brains.vault.semanticObservationStream.commitVisibleObservationForTesting(
            volumeScreen(value: "60%")
        )
        let window = try XCTUnwrap(brains.vault.semanticObservationStream.observationWindow(
            from: baseline,
            through: currentEvent
        ))

        guard case .incomplete = window.completeness else {
            return XCTFail("Expected evicted baseline history to make the window incomplete")
        }
        XCTAssertNotEqual(window.captures.first?.cursor, baseline.cursor)
        XCTAssertEqual(window.trace.changeFacts.count, 1)

        let observation = brains.actionEvidenceProjector.projectSettledEvidence(from: currentEvent)
        let expression = AccessibilityPredicate.changed(.elements())
        let predicateResult = PredicateObservationEvidence(
            observation: observation,
            baseline: baseline,
            window: window
        ).evaluate(try resolvedPredicate(expression), expression: expression)
        XCTAssertTrue(predicateResult.met)
    }

}

@MainActor
private final class HistoricalWaitUIWorkSpy {
    private let observation: InterfaceObservation
    private var captureCount = 0
    private var settlementCount = 0
    private(set) var waitResult: HeistWaitResult?
    private var actionCount = 0
    private var discoveryCount = 0
    private var observationWaitCount = 0
    private var scheduledSettlementCount = 0

    init(observation: InterfaceObservation) {
        self.observation = observation
    }

    func snapshot(commitCount: UInt64) -> HistoricalWaitUIWork {
        HistoricalWaitUIWork(
            captureCount: captureCount,
            commitCount: commitCount,
            settlementCount: settlementCount,
            actionCount: actionCount,
            discoveryCount: discoveryCount,
            observationWaitCount: observationWaitCount,
            scheduledSettlementCount: scheduledSettlementCount
        )
    }

    func observe(_ effect: PredicateWait.ScheduledEffect) {
        switch effect {
        case .discovery:
            discoveryCount += 1
        case .observationWait:
            observationWaitCount += 1
        case .settlement:
            scheduledSettlementCount += 1
        }
    }

    func execute(_ command: ResolvedHeistActionCommand) -> RuntimeActionExecution {
        actionCount += 1
        return RuntimeActionExecution(
            result: .success(payload: command.resultPayload),
            actionExpectationContext: nil
        )
    }

    func record(_ result: HeistWaitResult) {
        waitResult = result
    }

    func capture(_ vault: TheVault) -> InterfaceObservation? {
        captureCount += 1
        return observation
    }

    func settle(
        vault: TheVault,
        baseline: TheTripwire.TripwireSignal
    ) -> SettleSession.Result {
        settlementCount += 1
        guard let captured = capture(vault) else {
            preconditionFailure("historical wait work fixture must capture an observation")
        }
        vault.latestObservation = captured
        return SettleSession.Result(
            outcome: .settled(timeMs: 0),
            events: [],
            finalObservation: SettleSessionFinalObservation(observation: captured),
            elementsByKey: [:],
            tripwireSignal: baseline
        )
    }
}

private struct HistoricalWaitUIWork: Equatable {
    let captureCount: Int
    let commitCount: UInt64
    let settlementCount: Int
    let actionCount: Int
    let discoveryCount: Int
    let observationWaitCount: Int
    let scheduledSettlementCount: Int
}

private struct HistoricalWaitAutomaticRun {
    let result: HeistWaitResult
    let work: HistoricalWaitUIWork
}

#endif
