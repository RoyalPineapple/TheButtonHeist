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

    func testWaitSuccessReceiptUsesSettledVisibleObservation() async throws {
        brains.vault.semanticObservationStream.commitVisibleObservationForTesting(
            makeScreen(elements: [("Home", .header, "home")])
        )
        let receipt = await brains.interactionObservation.waitForPredicate(
            try resolvedWait(WaitStep(predicate: .exists(.label("Home")), timeout: .milliseconds(1)))
        )
        let trace = try XCTUnwrap(receipt.result.actionResult.accessibilityTrace)

        XCTAssertTrue(receipt.result.actionResult.outcome.isSuccess)
        XCTAssertEqual(trace.captures.last?.interface.projectedElements.map(\.label), ["Home"])
        XCTAssertTrue(receipt.result.expectation.met)
    }

    func testWaitTimeoutReceiptUsesLastSettledVisibleObservation() async throws {
        brains.vault.installObservationForTesting(
            makeScreen(elements: [("Known", .staticText, "known")])
        )
        let receipt = await brains.interactionObservation.waitForPredicate(
            try resolvedWait(WaitStep(predicate: .exists(.label("Missing")), timeout: .milliseconds(1)))
        )
        let trace = try XCTUnwrap(receipt.result.actionResult.accessibilityTrace)

        XCTAssertFalse(receipt.result.actionResult.outcome.isSuccess)
        XCTAssertEqual(receipt.result.actionResult.outcome.errorKind, .timeout)
        XCTAssertEqual(trace.captures.last?.interface.projectedElements.map(\.label), ["Known"])
        XCTAssertTrue(receipt.result.actionResult.message?.contains("interface: 1 elements") == true)
        XCTAssertTrue(receipt.result.actionResult.message?.contains("last result:") == true)
    }

    func testAppearedWaitRequiresObservedTransitionWhenFinalStateIsAlreadyPresent() async throws {
        let ready = makeScreen(elements: [("Ready", .staticText, "ready")])
        let receipt = try await temporalWaitReceipt(
            predicate: .changed(.elements([.appeared(.label("Ready"))])),
            baseline: ready,
            final: ready
        )

        XCTAssertFalse(receipt.result.actionResult.outcome.isSuccess)
        XCTAssertEqual(receipt.result.actionResult.outcome.errorKind, .timeout)
        XCTAssertFalse(receipt.result.expectation.met)
        XCTAssertTrue(elementChanges(in: receipt).isEmpty)
    }

    func testAppearedWaitSucceedsFromCanonicalTransition() async throws {
        let receipt = try await temporalWaitReceipt(
            predicate: .changed(.elements([.appeared(.label("Ready"))])),
            baseline: .empty,
            final: makeScreen(elements: [("Ready", .staticText, "ready")])
        )
        let changes = try XCTUnwrap(elementChanges(in: receipt).first)

        XCTAssertTrue(receipt.result.actionResult.outcome.isSuccess)
        XCTAssertTrue(receipt.result.expectation.met)
        XCTAssertEqual(changes.appeared.count, 1)
        XCTAssertTrue(changes.disappeared.isEmpty)
        XCTAssertTrue(changes.updated.isEmpty)
    }

    func testDisappearedWaitRequiresObservedTransitionWhenFinalStateIsAlreadyAbsent() async throws {
        let receipt = try await temporalWaitReceipt(
            predicate: .changed(.elements([.disappeared(.label("Loading"))])),
            baseline: .empty,
            final: .empty
        )

        XCTAssertFalse(receipt.result.actionResult.outcome.isSuccess)
        XCTAssertEqual(receipt.result.actionResult.outcome.errorKind, .timeout)
        XCTAssertFalse(receipt.result.expectation.met)
        XCTAssertTrue(elementChanges(in: receipt).isEmpty)
    }

    func testDisappearedWaitSucceedsFromCanonicalTransition() async throws {
        let receipt = try await temporalWaitReceipt(
            predicate: .changed(.elements([.disappeared(.label("Loading"))])),
            baseline: makeScreen(elements: [("Loading", .staticText, "loading")]),
            final: .empty
        )
        let changes = try XCTUnwrap(elementChanges(in: receipt).first)

        XCTAssertTrue(receipt.result.actionResult.outcome.isSuccess)
        XCTAssertTrue(receipt.result.expectation.met)
        XCTAssertTrue(changes.appeared.isEmpty)
        XCTAssertEqual(changes.disappeared.count, 1)
        XCTAssertTrue(changes.updated.isEmpty)
    }

    func testUpdatedWaitRequiresObservedTransitionWhenFinalStateAlreadyMatches() async throws {
        let quantity = volumeScreen(value: "3")
        let receipt = try await temporalWaitReceipt(
            predicate: .changed(.elements([.updated(
                .label("Volume"),
                .value(before: "2", after: "3")
            )])),
            baseline: quantity,
            final: quantity
        )

        XCTAssertFalse(receipt.result.actionResult.outcome.isSuccess)
        XCTAssertEqual(receipt.result.actionResult.outcome.errorKind, .timeout)
        XCTAssertFalse(receipt.result.expectation.met)
        XCTAssertTrue(elementChanges(in: receipt).isEmpty)
    }

    func testUpdatedWaitSucceedsFromCanonicalTransition() async throws {
        let receipt = try await temporalWaitReceipt(
            predicate: .changed(.elements([.updated(
                .label("Volume"),
                .value(before: "2", after: "3")
            )])),
            baseline: volumeScreen(value: "2"),
            final: volumeScreen(value: "3")
        )
        let changes = try XCTUnwrap(elementChanges(in: receipt).first)

        XCTAssertTrue(receipt.result.actionResult.outcome.isSuccess)
        XCTAssertTrue(receipt.result.expectation.met)
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
        let receipt = await brains.interactionObservation.waitForPredicate(
            try resolvedWait(WaitStep(predicate: .changed(.elements()), timeout: .milliseconds(1))),
            initialTrace: after.trace
        )

        XCTAssertTrue(receipt.result.actionResult.outcome.isSuccess)
        XCTAssertTrue(receipt.result.expectation.met)
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
        let receipt = await brains.interactionObservation.waitForPredicate(
            try resolvedWait(WaitStep(predicate: .changed(.elements()), timeout: .milliseconds(1))),
            initialTrace: staleEvent.trace,
            changeBaseline: .supplied(before)
        )

        XCTAssertTrue(receipt.result.actionResult.outcome.isSuccess)
        XCTAssertTrue(receipt.result.expectation.met)
        XCTAssertEqual(
            receipt.result.actionResult.accessibilityTrace?.captures.map(\.hash),
            [before.capture.hash, after.capture.hash]
        )
        XCTAssertFalse(receipt.result.actionResult.accessibilityTrace?.captures.contains { $0.hash == staleHash } == true)
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
        let receipt = await brains.interactionObservation.waitForPredicate(
            try resolvedWait(WaitStep(
                predicate: .changed(.screen([.exists(.label("Menu"))])),
                timeout: .milliseconds(1)
            )),
            changeBaseline: .supplied(before)
        )

        XCTAssertTrue(receipt.result.actionResult.outcome.isSuccess)
        XCTAssertTrue(receipt.result.expectation.met)
        XCTAssertEqual(receipt.result.actionResult.traceEvidence?.completeness, .complete)
        let receiptTrace = try XCTUnwrap(receipt.result.actionResult.accessibilityTrace)
        XCTAssertEqual(
            receiptTrace.captures.map(\.hash),
            [before.capture.hash, actionEndpoint.capture.hash, destination.capture.hash]
        )
        XCTAssertEqual(receiptTrace.captures.last?.interface.projectedElements.last?.label, "Menu")
        XCTAssertTrue(receiptTrace.changeFacts.contains {
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

    func testCompleteObservationWindowProducesUnchangedWaitProof() async throws {
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
        let receipt = await brains.interactionObservation.waitForPredicate(
            try resolvedWait(WaitStep(predicate: expression, timeout: .milliseconds(1))),
            changeBaseline: .supplied(baseline)
        )

        XCTAssertTrue(receipt.result.actionResult.outcome.isSuccess)
        XCTAssertTrue(receipt.result.expectation.met)
        XCTAssertEqual(receipt.result.actionResult.traceEvidence?.completeness, .complete)
        XCTAssertEqual(receipt.result.actionResult.traceEvidence?.completeness, .complete)
        XCTAssertTrue(predicate.validate(against: receipt.result.actionResult).met)
    }

    func testIncompleteObservationWindowTimesOutUnchangedWait() async throws {
        let baselineEvent = brains.vault.semanticObservationStream.commitVisibleObservationForTesting(
            volumeScreen(value: "50%")
        )
        let baseline = try XCTUnwrap(baselineEvent.settledCapture)
        var currentEvent = baselineEvent
        for _ in 0...SemanticObservationLog.defaultRetentionLimit {
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
        let receipt = await brains.interactionObservation.waitForPredicate(
            try resolvedWait(WaitStep(predicate: expression, timeout: .milliseconds(1))),
            changeBaseline: .supplied(baseline)
        )
        let laterValidation = predicate.validate(
            against: receipt.result.actionResult
        )

        XCTAssertFalse(receipt.result.actionResult.outcome.isSuccess)
        XCTAssertEqual(receipt.result.actionResult.outcome.errorKind, .timeout)
        XCTAssertFalse(receipt.result.expectation.met)
        XCTAssertEqual(receipt.result.expectation.actual, "observation history incomplete")
        XCTAssertEqual(receipt.result.actionResult.traceEvidence?.completeness, .incomplete)
        XCTAssertEqual(receipt.result.actionResult.traceEvidence?.completeness, .incomplete)
        XCTAssertFalse(laterValidation.met)
        XCTAssertEqual(laterValidation.actual, "observation history incomplete")
    }

    func testIncompleteObservationWindowUsesOnlyRetainedElementEdges() throws {
        let baselineEvent = brains.vault.semanticObservationStream.commitVisibleObservationForTesting(
            volumeScreen(value: "50%")
        )
        let baseline = try XCTUnwrap(baselineEvent.settledCapture)
        for _ in 0...SemanticObservationLog.defaultRetentionLimit {
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

        let observation = brains.postActionObservation.semanticObservation(from: currentEvent)
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
