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
        XCTAssertNil(result.historicalWaitDiagnostics)
    }

    func testTimeoutRetainsBoundedAccessiblePredicateMismatches() async throws {
        brains.vault.semanticObservationStream.commitVisibleObservationForTesting(
            makeScreen(elements: [("Ticket saved., Dismiss", .staticText, "toast")])
        )
        let predicate = AccessibilityPredicate.exists(.label("Ticket saved."))

        let result = await brains.interactionCoordinator.waitForPredicate(
            try resolvedWait(WaitStep(predicate: predicate, timeout: .milliseconds(1))),
            historicalWaitDiagnostics: .predicateMismatches
        )
        let evidence = try XCTUnwrap(result.historicalWaitDiagnostics)
        let mismatch = try XCTUnwrap(evidence.predicateMismatches.first)

        XCTAssertFalse(result.outcome.actionResult.outcome.isSuccess)
        XCTAssertEqual(evidence.predicateMismatches.count, 1)
        XCTAssertEqual(mismatch.exactPredicate, predicate)
        XCTAssertEqual(mismatch.candidate.label, "Ticket saved., Dismiss")
        XCTAssertEqual(mismatch.candidate.value, nil)
        XCTAssertEqual(mismatch.candidate.hint, nil)
        XCTAssertEqual(mismatch.candidate.traits, [.staticText])
        XCTAssertEqual(
            mismatch.provenance.firstObservationSequence,
            mismatch.provenance.lastObservationSequence
        )
        XCTAssertNotEqual(mismatch.candidate.label, "Ticket saved.")
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
            )),
            historicalWaitDiagnostics: .predicateMismatches
        )
        let evidence = try XCTUnwrap(result.historicalWaitDiagnostics)

        XCTAssertEqual(
            evidence.predicateMismatches.compactMap(\.candidate.label),
            (2 ..< 10).map { "Candidate \($0)" }
        )
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

#endif
