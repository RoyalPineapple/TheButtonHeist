#if canImport(UIKit)
#if DEBUG
import Foundation
import XCTest

import ButtonHeistTestSupport

@testable import AccessibilitySnapshotParser
@testable import TheInsideJob
@testable import TheScore

@MainActor
final class SemanticObservationPublicationTests: SemanticObservationStreamTestCase {
    func testObservationStreamRetainsEveryFastTransitionAfterCursor() async throws {
        let baseline = vault.semanticObservationStream.commitVisibleObservationForTesting(
            observation(label: "Baseline", heistId: "baseline")
        )
        let cursor = try XCTUnwrap(baseline.cursor)

        let first = observation(label: "First", heistId: "first")
        let second = observation(label: "Second", heistId: "second")
        let firstEvent = vault.semanticObservationStream.commitVisibleObservationForTesting(first)
        let secondEvent = vault.semanticObservationStream.commitVisibleObservationForTesting(second)

        let publishedFirst = await vault.semanticObservationStream.waitForObservation(
            after: cursor,
            scope: .visible,
            deadline: nil
        )
        let publishedSecond = await vault.semanticObservationStream.waitForObservation(
            after: try XCTUnwrap(firstEvent.cursor),
            scope: .visible,
            deadline: nil
        )
        guard case .observation(let firstEntry) = publishedFirst,
              case .observation(let secondEntry) = publishedSecond else {
            return XCTFail("Expected retained visible observations")
        }
        XCTAssertEqual(firstEntry.cursor, firstEvent.cursor)
        XCTAssertEqual(secondEntry.cursor, secondEvent.cursor)
    }

    func testLifecycleResetClearsCommittedTruth() {
        _ = vault.semanticObservationStream.commitVisibleObservationForTesting(
            observation(label: "Before Reset", heistId: "before_reset")
        )

        vault.resetInterfaceForLifecycle()

        XCTAssertEqual(vault.interfaceTree, .empty)
        XCTAssertEqual(vault.latestObservation.tree, InterfaceObservation.empty.tree)
    }

    func testConcurrentVisibleConsumersShareOneRefresh() async throws {
        let stream = vault.semanticObservationStream
        let signal = tripwireSignal(sequence: 1)
        var releaseSettle: CheckedContinuation<Void, Never>?
        let settleCount = installSettler(signal: { signal }, beforeSettle: {
            await withCheckedContinuation { releaseSettle = $0 }
        })
        defer { releaseSettle?.resume() }

        var firstEvidence: SemanticObservationStore.AdmittedObservation?
        var secondEvidence: SemanticObservationStore.AdmittedObservation?
        let firstTask = Task { @MainActor in
            firstEvidence = await stream.admittedVisibleObservation(timeout: 1)
        }
        await waitForSettleCount(1, current: settleCount)
        let secondTask = Task { @MainActor in
            secondEvidence = await stream.admittedVisibleObservation(timeout: 1)
        }
        await Task.yield()

        releaseSettle?.resume()
        releaseSettle = nil
        await firstTask.value
        await secondTask.value
        let first = try XCTUnwrap(firstEvidence)
        let second = try XCTUnwrap(secondEvidence)
        XCTAssertEqual(settleCount(), 1)
        XCTAssertEqual(first.event.sequence, second.event.sequence)
    }

    func testAdmittedStateIsReusedUntilTripInvalidationOrScreenReplacement() async throws {
        let stream = vault.semanticObservationStream
        let initialSignal = tripwireSignal(sequence: 1)
        let settleCount = installSettler(signal: { initialSignal })

        let initial = try await admittedVisibleObservation()
        let reused = try await admittedVisibleObservation()
        let changedSignal = tripwireSignal(sequence: 2)
        stream.readTripwireSignal = { changedSignal }
        let afterTrip = try await admittedVisibleObservation()
        stream.invalidateLatestSettledObservation()
        let afterInvalidation = try await admittedVisibleObservation()
        stream.requireScreenReplacement()
        let afterReplacement = try await admittedVisibleObservation()

        XCTAssertEqual(settleCount(), 4)
        XCTAssertEqual(reused.event.sequence, initial.event.sequence)
        XCTAssertNotEqual(afterTrip.event.sequence, reused.event.sequence)
        XCTAssertNotEqual(afterInvalidation.event.sequence, afterTrip.event.sequence)
        XCTAssertNotEqual(afterInvalidation.event.sequence, afterReplacement.event.sequence)
    }

    func testSameCaptureInDifferentScopeGetsItsOwnPublication() {
        let screen = observation(label: "Shared", heistId: "shared")

        _ = vault.semanticObservationStream.commitVisibleObservationForTesting(screen)
        _ = vault.semanticObservationStream.commitDiscoveryObservationForTesting(screen)

        XCTAssertEqual(vault.semanticObservationStream.retainedObservationEntries(scope: .visible).count, 2)
        XCTAssertEqual(vault.semanticObservationStream.retainedObservationEntries(scope: .discovery).count, 1)
    }

    func testFirstCommittedScopeAppendsInitialEntry() throws {
        let event = vault.semanticObservationStream.commitVisibleObservationForTesting(
            observation(label: "Initial", heistId: "initial")
        )

        let entries = vault.semanticObservationStream.retainedObservationEntries(scope: .visible)
        let entry = try XCTUnwrap(entries.first)

        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entry.cursor, event.cursor)
        guard case .initial = entry.transition else {
            return XCTFail("Expected the first visible entry to establish lineage")
        }
    }

    func testSecondCommitAppendsSameGenerationEntry() throws {
        let screen = observation(label: "Stable", heistId: "stable")
        let firstEvent = vault.semanticObservationStream.commitVisibleObservationForTesting(screen)
        let secondEvent = vault.semanticObservationStream.commitVisibleObservationForTesting(screen)

        let entries = vault.semanticObservationStream.retainedObservationEntries(scope: .visible)

        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(firstEvent.generation, secondEvent.generation)
        guard case .sameGeneration(let transition) = entries[1].transition else {
            return XCTFail("Expected a same-generation transition")
        }
        XCTAssertEqual(transition.previousCursor, entries[0].cursor)
    }

    func testVisiblePublicationRetainsKnownGraphInStateAndTraceEvidence() throws {
        let visibleBefore = AccessibilityElement.make(
            label: "Anchor",
            value: "Before",
            identifier: "anchor",
            traits: .staticText
        )
        let visibleAfter = AccessibilityElement.make(
            label: "Anchor",
            value: "After",
            identifier: "anchor",
            traits: .staticText
        )
        let offViewport = AccessibilityElement.make(label: "Known Offscreen", traits: .button)
        let offViewportId: HeistId = "known_offscreen_button"
        let baseline = InterfaceObservation.makeForTests(
            elements: [(visibleBefore, "anchor")],
            offViewport: [.init(offViewport, heistId: offViewportId)]
        )
        let current = InterfaceObservation.makeForTests(elements: [(visibleAfter, "anchor")])

        let baselineEvent = vault.semanticObservationStream.commitVisibleObservationForTesting(baseline)
        let currentEvent = vault.semanticObservationStream.commitVisibleObservationForTesting(current)

        XCTAssertEqual(currentEvent.generation, baselineEvent.generation)
        XCTAssertNotNil(vault.interfaceTree.findElement(heistId: offViewportId))
        XCTAssertTrue(
            currentEvent.trace.captures.last?.interface.projectedElements.contains {
                $0.label == "Known Offscreen"
            } == true
        )
        XCTAssertEqual(
            currentEvent.settledObservation.observation.tree.orderedElements.compactMap(\.element.label),
            currentEvent.trace.captures.last?.interface.projectedElements.compactMap(\.label)
        )
    }

    func testScreenReplacementRetainsBoundaryAndBothCaptures() throws {
        let firstEvent = vault.semanticObservationStream.commitVisibleObservationForTesting(
            observation(label: "Before", heistId: "before")
        )
        let secondEvent = vault.semanticObservationStream.commitVisibleObservationForTesting(
            observation(label: "After", heistId: "after"),
            notificationBatch: screenChangedBatch()
        )

        let entries = vault.semanticObservationStream.retainedObservationEntries(scope: .visible)

        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(secondEvent.generation, firstEvent.generation.advanced())
        XCTAssertEqual(
            AccessibilityTrace(captures: entries.map(\.settledCapture.capture)).changeFacts.map(\.kind),
            [.elementsChanged, .screenChanged, .elementsChanged]
        )
        guard case .screenBoundary(let transition) = entries[1].transition else {
            return XCTFail("Expected a retained screen boundary")
        }
        XCTAssertEqual(transition.previousCursor, entries[0].cursor)
        XCTAssertEqual(entries.map(\.cursor), [firstEvent.cursor, secondEvent.cursor].compactMap { $0 })
    }

    func testInferredReplacementResetsGraphAndRetainsClassifierEvidence() {
        let firstEvent = vault.semanticObservationStream.commitVisibleObservationForTesting(
            observation(label: "Before", heistId: "before")
        )
        let secondEvent = vault.semanticObservationStream.commitVisibleObservationForTesting(
            observation(label: "After", heistId: "after")
        )

        XCTAssertEqual(secondEvent.generation, firstEvent.generation.advanced())
        XCTAssertEqual(
            secondEvent.continuity,
            .replacement(.inferred(.primaryHeaderChanged))
        )
        XCTAssertEqual(vault.interfaceTree.elementIDs, ["after"])
    }
}
#endif // DEBUG
#endif // canImport(UIKit)
