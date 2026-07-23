#if canImport(UIKit)
import XCTest
@testable import AccessibilitySnapshotParser
import ButtonHeistSupport
@testable import TheInsideJob
@testable import TheScore

@MainActor
extension SettleSessionTests {

    func testSemanticQuietSettleReturnsCancelledWhenObservationYieldSwallowsCancellation() async {
        let stable = makeParseResult([
            makeElement(label: "Ready", traits: .staticText, frame: CGRect(x: 0, y: 0, width: 100, height: 30)),
        ])
        let clock = ManualClock()
        let yieldStarted = expectation(description: "observation yield started")
        let session = SettleSession(
            parseProvider: { stable },
            tripwireSignalProvider: { self.tripwireSignal(topmostVC: nil) },
            observationYield: { _ in
                yieldStarted.fulfill()
                let completed = await Task.cancellableSleep(for: .seconds(10))
                clock.advance(milliseconds: 10)
                return completed ? .observed : .cancelled
            },
            clock: { clock.currentTime() },
            quietWindowMs: 30,
            timeoutMs: 100
        )
        let task = Task {
            await session.run(
                start: clock.currentTime(),
                baselineTripwireSignal: tripwireSignal(topmostVC: nil)
            )
        }

        await fulfillment(of: [yieldStarted], timeout: 1)
        task.cancel()
        let outcome = await task.value

        XCTAssertEqual(outcome.outcome, .cancelled(timeMs: 10))
        XCTAssertEqual(outcome.finalObservation?.tree.viewportCapture.hierarchy.sortedElements.first?.label, "Ready")
    }

    func testCancellationPropagatesAsCancelledOutcome() async {
        let stable = makeParseResult([makeElement(label: "A")])
        let sleepStarted = expectation(description: "sleep started")
        let session = SettleSession(
            parseProvider: { stable },
            tripwireSignalProvider: { self.tripwireSignal(topmostVC: nil) },
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
                start: RuntimeElapsed.now,
                baselineTripwireSignal: tripwireSignal(topmostVC: nil)
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
        let staticElement = makeElement(label: "Hello", traits: .staticText)
        let spinnerA = makeElement(label: "loader", value: "A", traits: .updatesFrequently)
        let spinnerB = makeElement(label: "loader", value: "B", traits: .updatesFrequently)
        let spinnerC = makeElement(label: "loader", value: "C", traits: .updatesFrequently)

        // Spinner value cycles each parse but updatesFrequently masks
        // it, so the fingerprint stays stable and the loop settles.
        let session = makeSession(
            script: [
                makeParseResult([staticElement, spinnerA]),
                makeParseResult([staticElement, spinnerB]),
                makeParseResult([staticElement, spinnerC]),
                makeParseResult([staticElement, spinnerA])
            ],
            cyclesRequired: 3
        )

        let outcome = await session.run(
            start: RuntimeElapsed.now,
            baselineTripwireSignal: tripwireSignal(topmostVC: nil)
        )

        if case .settled = outcome.outcome {
            // Expected.
        } else {
            XCTFail("Spinner with .updatesFrequently must not block settle. Got \(outcome.outcome)")
        }
    }

    func testUpdatesFrequentlyMaskingAlsoIgnoresFrameChanges() async {
        // Analog clock case: a hand element keeps the same label/identifier
        // but its frame translates every cycle. With masking, the fingerprint
        // stays stable.
        let staticElement = makeElement(label: "Static", traits: .staticText)
        let hands = (0..<10).map { i in
            makeElement(
                label: "hand",
                traits: .updatesFrequently,
                frame: CGRect(x: i * 10, y: i * 10, width: 5, height: 50)
            )
        }
        let session = makeSession(
            script: hands.map { hand in makeParseResult([staticElement, hand]) },
            cyclesRequired: 3
        )

        let outcome = await session.run(
            start: RuntimeElapsed.now,
            baselineTripwireSignal: tripwireSignal(topmostVC: nil)
        )

        if case .settled = outcome.outcome {
            // Expected.
        } else {
            XCTFail("Animated frame on .updatesFrequently element must not block settle. Got \(outcome.outcome)")
        }
    }

}
#endif // canImport(UIKit)
