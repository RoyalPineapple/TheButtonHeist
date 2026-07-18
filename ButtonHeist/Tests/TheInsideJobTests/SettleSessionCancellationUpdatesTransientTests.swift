#if canImport(UIKit)
import XCTest
@testable import AccessibilitySnapshotParser
import ButtonHeistSupport
@testable import TheInsideJob
@testable import TheScore

@MainActor
final class SettleSessionCancellationUpdatesTransientTests: XCTestCase {
    private typealias Support = SettleSessionTestSupport

    func testSemanticQuietSettleReturnsCancelledWhenObservationYieldSwallowsCancellation() async {
        let stable = Support.makeParseResult([
            Support.makeElement(label: "Ready", traits: .staticText, frame: CGRect(x: 0, y: 0, width: 100, height: 30)),
        ])
        let clock = Support.ManualClock()
        let yieldStarted = expectation(description: "observation yield started")
        let session = SettleSession(
            parseProvider: { stable },
            tripwireSignalProvider: { Support.tripwireSignal(topmostVC: nil) },
            observationYield: {
                yieldStarted.fulfill()
                _ = await Task.cancellableSleep(for: .seconds(10))
                clock.advance(milliseconds: 10)
            },
            clock: { clock.currentTime() },
            quietWindowMs: 30,
            timeoutMs: 100
        )
        let task = Task {
            await session.run(
                start: clock.currentTime(),
                baselineTripwireSignal: Support.tripwireSignal(topmostVC: nil)
            )
        }

        await fulfillment(of: [yieldStarted], timeout: 1)
        task.cancel()
        let outcome = await task.value

        XCTAssertEqual(outcome.outcome, .cancelled(timeMs: 10))
        XCTAssertEqual(outcome.finalObservation?.tree.viewportCapture.hierarchy.sortedElements.first?.label, "Ready")
    }

    func testCancellationPropagatesAsCancelledOutcome() async {
        let stable = Support.makeParseResult([Support.makeElement(label: "A")])
        let sleepStarted = expectation(description: "sleep started")
        let session = SettleSession(
            parseProvider: { stable },
            tripwireSignalProvider: { Support.tripwireSignal(topmostVC: nil) },
            sleeper: { _ in
                sleepStarted.fulfill()
                _ = await Task.cancellableSleep(for: .seconds(10))
            },
            cyclesRequired: 3,
            cycleIntervalMs: 1,
            timeoutMs: 200
        )
        let task = Task {
            await session.run(
                start: CFAbsoluteTimeGetCurrent(),
                baselineTripwireSignal: Support.tripwireSignal(topmostVC: nil)
            )
        }

        await fulfillment(of: [sleepStarted], timeout: 1)
        task.cancel()
        let outcome = await task.value

        if case .cancelled = outcome.outcome {
            // Expected.
        } else {
            XCTFail("Expected .cancelled, got \(outcome.outcome)")
        }
        XCTAssertFalse(outcome.outcome.didSettleCleanly,
                       ".cancelled must NOT count as settled cleanly")
    }

    func testUpdatesFrequentlySpinnerDoesNotBlockSettle() async {
        let staticElement = Support.makeElement(label: "Hello", traits: .staticText)
        let spinnerA = Support.makeElement(label: "loader", value: "A", traits: .updatesFrequently)
        let spinnerB = Support.makeElement(label: "loader", value: "B", traits: .updatesFrequently)
        let spinnerC = Support.makeElement(label: "loader", value: "C", traits: .updatesFrequently)

        // Spinner value cycles each parse but updatesFrequently masks
        // it, so the fingerprint stays stable and the loop settles.
        let session = Support.makeSession(
            script: [
                Support.makeParseResult([staticElement, spinnerA]),
                Support.makeParseResult([staticElement, spinnerB]),
                Support.makeParseResult([staticElement, spinnerC]),
                Support.makeParseResult([staticElement, spinnerA])
            ],
            cyclesRequired: 3
        )

        let outcome = await session.run(
            start: CFAbsoluteTimeGetCurrent(),
            baselineTripwireSignal: Support.tripwireSignal(topmostVC: nil)
        )

        if case .settled = outcome.outcome {
            // Expected.
        } else {
            XCTFail("Spinner with .updatesFrequently must not block settle. Got \(outcome.outcome)")
        }
        XCTAssertFalse(outcome.events.containsTripwireSignalChange)
    }

    func testUpdatesFrequentlyMaskingAlsoIgnoresFrameChanges() async {
        // Analog clock case: a hand element keeps the same label/identifier
        // but its frame translates every cycle. With masking, the fingerprint
        // stays stable.
        let staticElement = Support.makeElement(label: "Static", traits: .staticText)
        let hands = (0..<10).map { i in
            Support.makeElement(
                label: "hand",
                traits: .updatesFrequently,
                frame: CGRect(x: i * 10, y: i * 10, width: 5, height: 50)
            )
        }
        let session = Support.makeSession(
            script: hands.map { hand in Support.makeParseResult([staticElement, hand]) },
            cyclesRequired: 3
        )

        let outcome = await session.run(
            start: CFAbsoluteTimeGetCurrent(),
            baselineTripwireSignal: Support.tripwireSignal(topmostVC: nil)
        )

        if case .settled = outcome.outcome {
            // Expected.
        } else {
            XCTFail("Animated frame on .updatesFrequently element must not block settle. Got \(outcome.outcome)")
        }
    }

    func testTransientElementsExcludesBaselineAndFinal() {
        let baseline = Support.makeElement(label: "Baseline", traits: .staticText)
        let final = Support.makeElement(label: "Final", traits: .staticText)
        let transient = Support.makeElement(label: "Loading", traits: .staticText)

        let seenByKey: [TimelineKey: AccessibilityElement] = [
            baseline.timelineKey: baseline,
            final.timelineKey: final,
            transient.timelineKey: transient
        ]

        let result = SettleSession.transientElements(
            seenByKey: seenByKey,
            baseline: [baseline],
            final: [final]
        )

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.label, "Loading")
    }

    func testTransientSpinnerCapturedOnCleanSameScreenSettle() async {
        let content = Support.makeElement(label: "Content", traits: .staticText)
        let spinner = Support.makeElement(label: "Loading", traits: .staticText)
        let stable = Support.makeParseResult([content])
        let session = Support.makeSession(
            script: [
                stable,
                Support.makeParseResult([content, spinner]),
                stable,
                stable
            ],
            cyclesRequired: 2
        )

        let outcome = await session.run(
            start: CFAbsoluteTimeGetCurrent(),
            baselineTripwireSignal: Support.tripwireSignal(topmostVC: nil)
        )

        if case .settled = outcome.outcome {
            // Expected.
        } else {
            XCTFail("Expected clean same-screen settle, got \(outcome.outcome)")
        }
        XCTAssertFalse(outcome.events.containsTripwireSignalChange)
        let transients = SettleSession.transientElements(
            seenByKey: outcome.elementsByKey,
            baseline: [content],
            final: [content]
        )
        XCTAssertEqual(transients.map(\.label), ["Loading"])
    }

    func testTransientElementsOrderedByReadingOrder() {
        let lowerLeft = Support.makeElement(label: "B", frame: CGRect(x: 0, y: 100, width: 10, height: 10))
        let upperLeft = Support.makeElement(label: "A", frame: CGRect(x: 0, y: 0, width: 10, height: 10))
        let upperRight = Support.makeElement(label: "C", frame: CGRect(x: 50, y: 0, width: 10, height: 10))

        let seenByKey: [TimelineKey: AccessibilityElement] = [
            lowerLeft.timelineKey: lowerLeft,
            upperRight.timelineKey: upperRight,
            upperLeft.timelineKey: upperLeft
        ]

        let result = SettleSession.transientElements(
            seenByKey: seenByKey,
            baseline: [],
            final: []
        )

        XCTAssertEqual(result.map(\.label), ["A", "C", "B"],
                       "Reading order: top row left-to-right, then next row.")
    }

    func testTransientElementsReturnsEmptyWhenSeenIsEmpty() {
        let result = SettleSession.transientElements(
            seenByKey: [:],
            baseline: [Support.makeElement(label: "X")],
            final: []
        )
        XCTAssertTrue(result.isEmpty)
    }
}
#endif // canImport(UIKit)
