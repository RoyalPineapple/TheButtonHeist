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
        await brains.vault.semanticObservationStream.commitVisibleObservationForTesting(
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
        await brains.vault.installObservationForTesting(
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
        await brains.vault.semanticObservationStream.commitVisibleObservationForTesting(
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
        await brains.vault.semanticObservationStream.commitVisibleObservationForTesting(
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

    func testTimeoutDiagnosticsIncludeIdentifierActionsAndRotors() async throws {
        let candidate = AccessibilityElement.make(
            label: "Checkout",
            identifier: "checkout_identifier",
            customActions: [.init(name: "Archive")],
            customRotors: [.init(name: "Errors")],
            respondsToUserInteraction: false
        )
        await brains.vault.semanticObservationStream.commitVisibleObservationForTesting(
            .makeForTests([.init(candidate, heistId: HeistId(rawValue: "checkout"))])
        )

        let result = await brains.interactionCoordinator.waitForPredicate(
            try resolvedWait(WaitStep(
                predicate: .exists(.label("Missing")),
                timeout: .milliseconds(1)
            ))
        )
        let message = try XCTUnwrap(result.outcome.actionResult.message)

        XCTAssertTrue(message.contains(#"identifier="checkout_identifier""#), message)
        XCTAssertTrue(message.contains("actions=[activate, Archive]"), message)
        XCTAssertTrue(message.contains(#"rotors=["Errors"]"#), message)
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
        await brains.vault.semanticObservationStream.commitVisibleObservationForTesting(
            makeScreen(elements: [("First candidate", .staticText, "first")])
        )
        let first = await brains.interactionCoordinator.waitForPredicate(
            try resolvedWait(WaitStep(
                predicate: .exists(.label("Missing")),
                timeout: .milliseconds(1)
            ))
        )

        await brains.vault.semanticObservationStream.commitVisibleObservationForTesting(
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
        isolatedBrains.tripwire.startPulse()
        defer {
            isolatedBrains.stopSemanticObservation()
            isolatedBrains.tripwire.stopPulse()
        }
        isolatedBrains.interactionCoordinator.observePredicateWaitScheduledEffects(spy.observe)
        isolatedBrains.vault.semanticObservationStream.settleVisibleObservation = { vault, _, _, baseline, _ in
            spy.settle(vault: vault, baseline: baseline)
        }
        let wait = WaitStep(
            predicate: .exists(.label("Ticket saved.")),
            timeout: try .milliseconds(350)
        )
        let runtime = TheBrains.HeistExecutionRuntime(
            execute: { command, expectation in
                let execution = spy.execute(command)
                guard let expectation else { return execution }
                let request = TheBrains.HeistRuntimeWaitRequest.actionEndpoint(
                    expectation,
                    trace: execution.result.settled == true
                        ? execution.result.accessibilityTrace
                        : nil,
                    context: execution.actionExpectationContext
                )
                let result = await isolatedBrains.interactionCoordinator.waitForPredicate(
                    request.step,
                    initialTrace: request.initialTrace,
                    baselineSequence: request.afterSequence,
                    changeBaseline: request.changeBaseline,
                    actionExpectationContext: request.actionExpectationContext,
                    startedAt: request.startedAt
                )
                spy.record(result)
                let evidence: HeistActionEvidence
                switch result.outcome {
                case .matched(let expectationResult, let checkedExpectation):
                    evidence = .expectation(
                        dispatchResult: execution.result,
                        expectationResult: expectationResult,
                        expectation: checkedExpectation.result
                    )
                case .unmatched(let expectationResult, let checkedExpectation):
                    evidence = .expectation(
                        dispatchResult: execution.result,
                        expectationResult: expectationResult,
                        expectation: checkedExpectation.result
                    )
                }
                return RuntimeActionExecution(evidence: evidence)
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
        let latestSnapshot = await isolatedBrains.vault.semanticObservationStream.latestCommittedSnapshot()
        return HistoricalWaitAutomaticRun(
            result: result,
            work: spy.snapshot(
                commitCount: latestSnapshot?.sequence.rawValue ?? 0
            )
        )
    }

    func testTimeoutDiagnosticEvictsOldestSemanticCandidatesDeterministically() async throws {
        let elements = (0 ..< 10).map { index in
            ("Candidate \(index)", UIAccessibilityTraits.staticText, HeistId(rawValue: "candidate_\(index)"))
        }
        await brains.vault.semanticObservationStream.commitVisibleObservationForTesting(
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
        _ = await brains.vault.semanticObservationStream.commitVisibleObservationForTesting(
            volumeScreen(value: "2")
        )
        let after = await brains.vault.semanticObservationStream.commitVisibleObservationForTesting(
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
        let beforeEvent = await stream.commitVisibleObservationForTesting(volumeScreen(value: "2"))
        let afterEvent = await stream.commitVisibleObservationForTesting(volumeScreen(value: "3"))
        let before = try XCTUnwrap(beforeEvent.moment)
        let after = try XCTUnwrap(afterEvent.moment)
        let staleBrains = TheBrains(tripwire: TheTripwire())
        defer { staleBrains.stopSemanticObservation() }
        let staleEvent = await staleBrains.vault.semanticObservationStream.commitVisibleObservationForTesting(
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
        let beforeEvent = await stream.commitVisibleObservationForTesting(
            makeScreen(elements: [("ButtonHeist Demo", .header, "root")])
        )
        let actionEndpointEvent = await stream.commitVisibleObservationForTesting(
            makeScreen(elements: [("Order Summary", .header, "summary")]),
            notificationBatch: notificationBatch(kind: .screenChanged)
        )
        let destinationEvent = await stream.commitVisibleObservationForTesting(
            makeScreen(elements: [
                ("Order Summary", .header, "summary"),
                ("Menu", .button, "menu"),
            ])
        )
        let before = try XCTUnwrap(beforeEvent.moment)
        let actionEndpoint = try XCTUnwrap(actionEndpointEvent.moment)
        let destination = try XCTUnwrap(destinationEvent.moment)
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

    func testCanonicalLogEventsKeepScreenAndElementFactsDistinct() async throws {
        let elementStream = brains.vault.semanticObservationStream
        let elementBeforeEvent = await elementStream.commitVisibleObservationForTesting(volumeScreen(value: "2"))
        let elementAfterEvent = await elementStream.commitVisibleObservationForTesting(volumeScreen(value: "3"))
        let elementBefore = try XCTUnwrap(elementBeforeEvent.moment)
        let elementEvidence = PredicateObservationEvidence(
            observation: brains.actionEvidenceProjector.projectSettledEvidence(from: elementAfterEvent),
            baseline: elementBefore,
            eventsSinceBaseline: await elementStream.storeOwner.readLog {
                $0.events(since: elementBefore)
            }
        )

        let screenBrains = TheBrains(tripwire: TheTripwire())
        defer { screenBrains.stopSemanticObservation() }
        let screenStream = screenBrains.vault.semanticObservationStream
        let screenBeforeEvent = await screenStream.commitVisibleObservationForTesting(
            makeScreen(elements: [("Home", .header, "home")])
        )
        let screenAfterEvent = await screenStream.commitVisibleObservationForTesting(
            makeScreen(elements: [("Details", .header, "details")]),
            notificationBatch: notificationBatch(kind: .screenChanged)
        )
        let screenBefore = try XCTUnwrap(screenBeforeEvent.moment)
        let screenEvidence = PredicateObservationEvidence(
            observation: screenBrains.actionEvidenceProjector.projectSettledEvidence(from: screenAfterEvent),
            baseline: screenBefore,
            eventsSinceBaseline: await screenStream.storeOwner.readLog {
                $0.events(since: screenBefore)
            }
        )

        XCTAssertEqual(elementEvidence.changeTrace?.changeFacts.map(\.kind), [.elementsChanged])
        XCTAssertEqual(
            screenEvidence.changeTrace?.changeFacts.map(\.kind),
            [.elementsChanged, .screenChanged, .elementsChanged]
        )
        XCTAssertNil(screenAfterEvent.trace.captures.last?.transition.fallbackReason)
    }

    func testLogEventsRetainFastRoundTripTransition() async throws {
        let baselineEvent = await brains.vault.semanticObservationStream.commitVisibleObservationForTesting(
            volumeScreen(value: "50%")
        )
        _ = await brains.vault.semanticObservationStream.commitVisibleObservationForTesting(
            volumeScreen(value: "60%")
        )
        let finalEvent = await brains.vault.semanticObservationStream.commitVisibleObservationForTesting(
            volumeScreen(value: "50%")
        )
        let baseline = try XCTUnwrap(baselineEvent.moment)
        let evidence = PredicateObservationEvidence(
            observation: brains.actionEvidenceProjector.projectSettledEvidence(from: finalEvent),
            baseline: baseline,
            eventsSinceBaseline: await brains.vault.semanticObservationStream.storeOwner.readLog {
                $0.events(since: baseline)
            }
        )
        let trace = try XCTUnwrap(evidence.changeTrace)

        XCTAssertEqual(trace.captures.count, 3)
        XCTAssertEqual(trace.changeFacts.count, 2)
        XCTAssertTrue(trace.changeFacts.allSatisfy {
            if case .elementsChanged = $0 { return true }
            return false
        })
    }

    func testLogEventsProduceTraceFromExactlyRecordedCaptures() async throws {
        let baselineEvent = await brains.vault.semanticObservationStream.commitDiscoveryObservationForTesting(
            volumeScreen(value: "50%")
        )
        let actionEndpointEvent = await brains.vault.semanticObservationStream.commitDiscoveryObservationForTesting(
            volumeScreen(value: "60%")
        )
        let intermediateEvent = await brains.vault.semanticObservationStream.commitDiscoveryObservationForTesting(
            volumeScreen(value: "70%")
        )
        let finalEvent = await brains.vault.semanticObservationStream.commitDiscoveryObservationForTesting(
            volumeScreen(value: "80%")
        )
        let baseline = try XCTUnwrap(baselineEvent.moment)
        let actionEndpoint = try XCTUnwrap(actionEndpointEvent.moment)
        let intermediate = try XCTUnwrap(intermediateEvent.moment)
        let final = try XCTUnwrap(finalEvent.moment)
        let evidence = PredicateObservationEvidence(
            observation: brains.actionEvidenceProjector.projectSettledEvidence(from: finalEvent),
            baseline: baseline,
            eventsSinceBaseline: await brains.vault.semanticObservationStream.storeOwner.readLog {
                $0.events(since: baseline)
            }
        )
        let trace = try XCTUnwrap(evidence.changeTrace)

        XCTAssertEqual(
            trace.captures.map(\.hash),
            [baseline.capture.hash, actionEndpoint.capture.hash, intermediate.capture.hash, final.capture.hash]
        )
        XCTAssertEqual(trace.changeFacts.count, 3)
    }

    func testCompleteLogEventsProduceUnchangedWaitEvidence() async throws {
        let baselineEvent = await brains.vault.semanticObservationStream.commitVisibleObservationForTesting(
            volumeScreen(value: "50%")
        )
        let currentEvent = await brains.vault.semanticObservationStream.commitVisibleObservationForTesting(
            volumeScreen(value: "50%")
        )
        let baseline = try XCTUnwrap(baselineEvent.moment)
        let history = await brains.vault.semanticObservationStream.storeOwner.readLog {
            $0.events(since: baseline)
        }
        XCTAssertEqual(history, .events([.snapshot(currentEvent)]))

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

    func testExpiredLogEventsTimeOutUnchangedWait() async throws {
        let baselineEvent = await brains.vault.semanticObservationStream.commitVisibleObservationForTesting(
            volumeScreen(value: "50%")
        )
        let baseline = try XCTUnwrap(baselineEvent.moment)
        for _ in 0...Observation.Store.defaultRetentionLimit {
            _ = await brains.vault.semanticObservationStream.commitVisibleObservationForTesting(
                volumeScreen(value: "50%")
            )
        }
        let expiredHistory = await brains.vault.semanticObservationStream.storeOwner.readLog {
            $0.events(since: baseline)
        }
        guard case .expired = expiredHistory else {
            return XCTFail("Expected the evicted baseline moment to report expired history")
        }

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

    func testExpiredLogEventsCannotSatisfyElementChange() async throws {
        let baselineEvent = await brains.vault.semanticObservationStream.commitVisibleObservationForTesting(
            volumeScreen(value: "50%")
        )
        let baseline = try XCTUnwrap(baselineEvent.moment)
        for _ in 0...Observation.Store.defaultRetentionLimit {
            _ = await brains.vault.semanticObservationStream.commitVisibleObservationForTesting(
                volumeScreen(value: "50%")
            )
        }
        let currentEvent = await brains.vault.semanticObservationStream.commitVisibleObservationForTesting(
            volumeScreen(value: "60%")
        )
        let events = await brains.vault.semanticObservationStream.storeOwner.readLog {
            $0.events(since: baseline)
        }
        guard case .expired = events else {
            return XCTFail("Expected the evicted baseline moment to report expired history")
        }

        let observation = brains.actionEvidenceProjector.projectSettledEvidence(from: currentEvent)
        let expression = AccessibilityPredicate.changed(.elements())
        let predicateResult = PredicateObservationEvidence(
            observation: observation,
            baseline: baseline,
            eventsSinceBaseline: events
        ).evaluate(try resolvedPredicate(expression), expression: expression)
        XCTAssertFalse(predicateResult.met)
        XCTAssertEqual(predicateResult.actual, "observation history incomplete")
    }

    func testAfterObservationWithUnavailableMomentNeverUsesPredicateWait() async throws {
        var scheduledLegacyEffects: [PredicateWait.ScheduledEffect] = []
        brains.interactionCoordinator.observePredicateWaitScheduledEffects {
            scheduledLegacyEffects.append($0)
        }
        let step = try resolvedWait(WaitStep(
            predicate: .changed(.elements()),
            timeout: .milliseconds(1)
        ))
        let unrelatedBrains = TheBrains(tripwire: TheTripwire())
        let unavailableMoment = await unrelatedBrains.vault.semanticObservationStream
            .commitVisibleObservationForTesting(.makeForTests())
            .moment

        let result = await TheBrains.HeistExecutionRuntime.live(brains).wait(
            .afterObservation(
                step,
                baselineTrace: nil,
                moment: unavailableMoment
            )
        )

        XCTAssertTrue(scheduledLegacyEffects.isEmpty)
        XCTAssertEqual(
            result.outcome.actionResult.outcome.failureKind,
            .accessibilityTreeUnavailable
        )
        XCTAssertFalse(result.outcome.expectation.met)
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
