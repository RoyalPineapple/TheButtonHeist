#if canImport(UIKit)
import XCTest
@testable import AccessibilitySnapshotParser
import ButtonHeistSupport
@testable import TheInsideJob
@testable import TheScore

@MainActor
extension SettleSessionTests {

    func testClockedSettleReturnsCancelledWhenObservationYieldSwallowsCancellation() async {
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

        // The yield reports `.cancelled` instead of throwing, and the run has to
        // honour that as cancellation while still handing back the reading it
        // already took.
        guard case .cancelled = outcome.outcome else {
            return XCTFail("Expected a swallowed cancellation to surface as .cancelled, got \(outcome.outcome)")
        }
        XCTAssertFalse(outcome.outcome.didSettleCleanly)
        XCTAssertEqual(outcome.finalObservation?.tree.viewportCapture.hierarchy.sortedElements.map(\.label), ["Ready"])
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
            ]
        )

        let outcome = await session.run(
            start: RuntimeElapsed.now,
            baselineTripwireSignal: tripwireSignal(topmostVC: nil)
        )

        guard case .settled = outcome.outcome else {
            return XCTFail("Spinner with .updatesFrequently must not block settle. Got \(outcome.outcome)")
        }
        // Settling is half the claim; the other half is *when*. Masking holds the
        // fingerprint still from the second parse, so the settle lands while the
        // spinner is mid-cycle rather than waiting for its value to come back
        // around to where it started.
        XCTAssertEqual(
            outcome.finalObservation?.tree.viewportCapture.hierarchy.sortedElements.map(\.value),
            [nil, "B"],
            "expected the settle on the second parse, with the spinner still churning"
        )
    }

    func testUpdatesFrequentlyMaskingKeepsSettlingWhenGeometryHolds() async {
        // Analog clock case: a hand rotates in place. Its value churns and its
        // bounding box jitters within one coarse bucket, so the fingerprint is
        // stable and the loop settles.
        let staticElement = makeElement(label: "Static", traits: .staticText)
        let hands = (0..<10).map { i in
            makeElement(
                label: "hand",
                value: "tick \(i)",
                traits: .updatesFrequently,
                frame: CGRect(x: 100, y: 100, width: 5, height: 50)
            )
        }
        let session = makeSession(
            script: hands.map { hand in makeParseResult([staticElement, hand]) }
        )

        let outcome = await session.run(
            start: RuntimeElapsed.now,
            baselineTripwireSignal: tripwireSignal(topmostVC: nil)
        )

        if case .settled = outcome.outcome {
            // Expected.
        } else {
            XCTFail("Churning value at a fixed frame must still settle. Got \(outcome.outcome)")
        }
    }

    func testUpdatesFrequentlyDoesNotMaskMovingGeometry() async {
        // The trait declares that the *value* churns, not the position. An
        // element that translates across the screen is unstable regardless of
        // the trait — actions dispatch at coordinates, so settling here would
        // tap where the element used to be.
        let staticElement = makeElement(label: "Static", traits: .staticText)
        // `ScriptBox` repeats its last entry once exhausted, and a repeated
        // frame is an unchanged diff. The script has to outlast the timeout or
        // the banner "parks" and settles for a reason this test is not about.
        let sliding = (0..<5_000).map { i in
            makeElement(
                label: "banner",
                traits: .updatesFrequently,
                frame: CGRect(x: i * 40, y: i * 40, width: 5, height: 50)
            )
        }
        let session = makeSession(
            script: sliding.map { banner in makeParseResult([staticElement, banner]) }
        )

        let outcome = await session.run(
            start: RuntimeElapsed.now,
            baselineTripwireSignal: tripwireSignal(topmostVC: nil)
        )

        if case .settled = outcome.outcome {
            XCTFail("Moving geometry must falsify stability even with .updatesFrequently")
        }
    }

    func testUpdatesFrequentlyMasksValueButNotFrameInFingerprint() {
        let fixed = CGRect(x: 10, y: 10, width: 20, height: 20)
        let moved = CGRect(x: 200, y: 200, width: 20, height: 20)

        let valueChanged = settleFingerprint(
            [makeElement(label: "l", value: "A", traits: .updatesFrequently, frame: fixed)]
        )
        let valueChangedAgain = settleFingerprint(
            [makeElement(label: "l", value: "B", traits: .updatesFrequently, frame: fixed)]
        )
        XCTAssertEqual(valueChanged, valueChangedAgain, "value must stay masked")

        let frameMoved = settleFingerprint(
            [makeElement(label: "l", value: "A", traits: .updatesFrequently, frame: moved)]
        )
        XCTAssertNotEqual(valueChanged, frameMoved, "geometry must never be masked")
    }

}
#endif // canImport(UIKit)
