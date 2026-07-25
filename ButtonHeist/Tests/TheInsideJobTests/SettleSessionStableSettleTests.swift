#if canImport(UIKit)
import XCTest
@testable import AccessibilitySnapshotParser
import ButtonHeistSupport
@testable import TheInsideJob
@testable import TheScore

@MainActor
extension SettleSessionTests {

    func testStableSettleLandsOnTheFirstRepeat() async {
        let element = makeElement(label: "Hello", traits: .staticText, frame: CGRect(x: 0, y: 0, width: 100, height: 30))
        let stable = makeParseResult([element])
        let clock = ManualClock()
        let yieldCount = Counter()
        let session = makeClockedSession(
            script: [stable],
            clock: clock,
            yieldCount: yieldCount
        )

        let outcome = await session.run(
            start: clock.currentTime(),
            baselineTripwireSignal: tripwireSignal(topmostVC: nil)
        )

        XCTAssertEqual(outcome.outcome, .settled(timeMs: 10))
        XCTAssertEqual(yieldCount.next(), 1)
    }

    func testStableSettleRestartsTheRunWhenTheFingerprintChanges() async {
        let first = makeParseResult([
            makeElement(label: "Loading", traits: .staticText, frame: CGRect(x: 0, y: 0, width: 100, height: 30)),
        ])
        let second = makeParseResult([
            makeElement(label: "Ready", traits: .staticText, frame: CGRect(x: 0, y: 0, width: 100, height: 30)),
        ])
        let clock = ManualClock()
        let session = makeClockedSession(
            script: [first, second, second, second],
            clock: clock
        )

        let outcome = await session.run(
            start: clock.currentTime(),
            baselineTripwireSignal: tripwireSignal(topmostVC: nil)
        )

        XCTAssertEqual(outcome.outcome, .settled(timeMs: 20))
        XCTAssertEqual(outcome.finalObservation?.tree.viewportCapture.hierarchy.sortedElements.first?.label, "Ready")
    }

    func testStableSettleNotificationOnlySignalsDoNotStarveParser() async {
        let stable = makeParseResult([
            makeElement(label: "Ready", traits: .staticText, frame: CGRect(x: 0, y: 0, width: 100, height: 30)),
        ])
        let clock = ManualClock()
        let session = makeClockedSession(
            script: [stable],
            clock: clock,
            accessibilityNotificationSequence: [1, 2, 3, 4, 5]
        )

        let outcome = await session.run(
            start: clock.currentTime(),
            baselineTripwireSignal: tripwireSignal(topmostVC: nil, accessibilityNotificationSequence: 0)
        )

        XCTAssertEqual(outcome.outcome, .settled(timeMs: 10))
        XCTAssertEqual(outcome.finalObservation?.tree.viewportCapture.hierarchy.sortedElements.first?.label, "Ready")
    }

    func testClockedSettleIgnoresNilParsesUntilAStableScreenArrives() async {
        let stable = makeParseResult([
            makeElement(label: "Ready", traits: .staticText, frame: CGRect(x: 0, y: 0, width: 100, height: 30)),
        ])
        let clock = ManualClock()
        let session = makeClockedSession(
            script: [nil, nil, stable, stable, stable, stable],
            clock: clock,
            timeoutMs: 100
        )

        let outcome = await session.run(
            start: clock.currentTime(),
            baselineTripwireSignal: tripwireSignal(topmostVC: nil)
        )

        XCTAssertEqual(outcome.outcome, .settled(timeMs: 50))
        XCTAssertEqual(outcome.finalObservation?.tree.viewportCapture.hierarchy.sortedElements.first?.label, "Ready")
    }

    func testFixedCadenceSettleIgnoresNilParsesUntilAStableScreenArrives() async {
        let stable = makeParseResult([
            makeElement(label: "Ready", traits: .staticText, frame: CGRect(x: 0, y: 0, width: 100, height: 30)),
        ])
        let session = makeSession(
            script: [nil, nil, stable, stable, stable],
            timeoutMs: 100
        )

        let outcome = await session.run(
            start: RuntimeElapsed.now,
            baselineTripwireSignal: tripwireSignal(topmostVC: nil)
        )

        guard case .settled = outcome.outcome else {
            return XCTFail("Expected fixed-cadence settle after nil parses, got \(outcome.outcome)")
        }
        XCTAssertEqual(outcome.finalObservation?.tree.viewportCapture.hierarchy.sortedElements.first?.label, "Ready")
    }

    func testSettlesAfterCyclesRequiredStableCycles() async {
        let element = makeElement(label: "Hello", traits: .staticText, frame: CGRect(x: 0, y: 0, width: 100, height: 30))
        let stable = makeParseResult([element])
        let session = makeSession(
            script: [stable, stable, stable, stable]
        )

        let outcome = await session.run(
            start: RuntimeElapsed.now,
            baselineTripwireSignal: tripwireSignal(topmostVC: nil)
        )

        if case .settled = outcome.outcome {
            // Expected.
        } else {
            XCTFail("Expected .settled, got \(outcome.outcome)")
        }
        XCTAssertEqual(outcome.finalObservation?.tree.viewportCapture.hierarchy.sortedElements.first?.label, "Hello")
    }

    func testNoChangeParsesSettleAndReturnFinalStableScreen() async {
        let element = makeElement(label: "Unchanged", traits: .staticText)
        let stable = makeParseResult([element])
        let session = makeSession(
            script: [stable, stable, stable]
        )

        let outcome = await session.run(
            start: RuntimeElapsed.now,
            baselineTripwireSignal: tripwireSignal(topmostVC: nil)
        )

        if case .settled = outcome.outcome {
            // Expected: a no-change parse is valid stability evidence.
        } else {
            XCTFail("Expected .settled for no-change parses, got \(outcome.outcome)")
        }
        XCTAssertEqual(outcome.finalObservation?.tree.viewportCapture.hierarchy.sortedElements.map(\.label), ["Unchanged"])
    }

    func testFingerprintUsesSharedCoarseFrameComparisonForIPadJitter() {
        let first = makeElement(
            label: "$ 9 Cash",
            traits: .button,
            frame: CGRect(x: 561, y: 423, width: 90, height: 72)
        )
        let jittered = makeElement(
            label: "$ 9 Cash",
            traits: .button,
            frame: CGRect(x: 561, y: 428, width: 90, height: 72)
        )
        let moved = makeElement(
            label: "$ 9 Cash",
            traits: .button,
            frame: CGRect(x: 561, y: 467, width: 90, height: 72)
        )
        let valueChanged = makeElement(
            label: "$ 9 Cash",
            value: "selected",
            traits: .button,
            frame: CGRect(x: 561, y: 423, width: 90, height: 72)
        )
        let labelChanged = makeElement(
            label: "$ 10 Cash",
            traits: .button,
            frame: CGRect(x: 561, y: 423, width: 90, height: 72)
        )
        let identifierChanged = makeElement(
            label: "$ 9 Cash",
            identifier: "cash_9",
            traits: .button,
            frame: CGRect(x: 561, y: 423, width: 90, height: 72)
        )
        let traitsChanged = makeElement(
            label: "$ 9 Cash",
            traits: [.button, .selected],
            frame: CGRect(x: 561, y: 423, width: 90, height: 72)
        )
        let second = makeElement(
            label: "$ 10 Cash",
            traits: .button,
            frame: CGRect(x: 651, y: 423, width: 94, height: 72)
        )
        let hintChanged = AccessibilityElementFixture(
            label: "$ 9 Cash",
            hint: "Double tap to pay",
            traits: .button,
            shape: first.shape
        ).element()
        let actionsChanged = AccessibilityElementFixture(
            label: "$ 9 Cash",
            traits: .button,
            shape: first.shape,
            customActions: [.init(name: "Apply discount")]
        ).element()

        XCTAssertEqual(
            settleFingerprint([first]),
            settleFingerprint([jittered]),
            "iPad scroll-view content-offset jitter should not reset settle"
        )
        XCTAssertNotEqual(
            settleFingerprint([first]),
            settleFingerprint([moved]),
            "movement across coarse frame buckets should reset settle"
        )
        XCTAssertNotEqual(
            settleFingerprint([first]),
            settleFingerprint([valueChanged])
        )
        XCTAssertNotEqual(
            settleFingerprint([first]),
            settleFingerprint([labelChanged])
        )
        XCTAssertNotEqual(
            settleFingerprint([first]),
            settleFingerprint([identifierChanged])
        )
        XCTAssertNotEqual(
            settleFingerprint([first]),
            settleFingerprint([traitsChanged])
        )
        XCTAssertNotEqual(
            settleFingerprint([first]),
            settleFingerprint([hintChanged])
        )
        XCTAssertNotEqual(
            settleFingerprint([first]),
            settleFingerprint([actionsChanged])
        )
        XCTAssertNotEqual(
            settleFingerprint([first]),
            settleFingerprint([first, second]),
            "element count is semantic settle state"
        )
        XCTAssertNotEqual(
            settleFingerprint([first, second]),
            settleFingerprint([second, first]),
            "settle fingerprint intentionally preserves traversal order"
        )
    }

}
#endif // canImport(UIKit)
