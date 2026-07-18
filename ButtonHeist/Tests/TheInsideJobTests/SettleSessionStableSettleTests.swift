#if canImport(UIKit)
import XCTest
@testable import AccessibilitySnapshotParser
import ButtonHeistSupport
@testable import TheInsideJob
@testable import TheScore

@MainActor
final class SettleSessionStableSettleTests: XCTestCase {
    private typealias Support = SettleSessionTestSupport

    func testSemanticQuietSettleUsesQuietWindowInsteadOfFixedCycles() async {
        let element = Support.makeElement(label: "Hello", traits: .staticText, frame: CGRect(x: 0, y: 0, width: 100, height: 30))
        let stable = Support.makeParseResult([element])
        let clock = Support.ManualClock()
        let yieldCount = Support.Counter()
        let session = Support.makeQuietSession(
            script: [stable],
            clock: clock,
            quietWindowMs: 30,
            yieldCount: yieldCount
        )

        let outcome = await session.run(
            start: clock.currentTime(),
            baselineTripwireSignal: Support.tripwireSignal(topmostVC: nil)
        )

        XCTAssertEqual(outcome.outcome, .settled(timeMs: 30))
        XCTAssertEqual(yieldCount.next(), 3)
    }

    func testSemanticQuietSettleResetsQuietWindowWhenFingerprintChanges() async {
        let first = Support.makeParseResult([
            Support.makeElement(label: "Loading", traits: .staticText, frame: CGRect(x: 0, y: 0, width: 100, height: 30)),
        ])
        let second = Support.makeParseResult([
            Support.makeElement(label: "Ready", traits: .staticText, frame: CGRect(x: 0, y: 0, width: 100, height: 30)),
        ])
        let clock = Support.ManualClock()
        let session = Support.makeQuietSession(
            script: [first, first, second, second, second, second],
            clock: clock,
            quietWindowMs: 30
        )

        let outcome = await session.run(
            start: clock.currentTime(),
            baselineTripwireSignal: Support.tripwireSignal(topmostVC: nil)
        )

        XCTAssertEqual(outcome.outcome, .settled(timeMs: 50))
        XCTAssertEqual(outcome.finalObservation?.tree.viewportCapture.hierarchy.sortedElements.first?.label, "Ready")
    }

    func testSemanticQuietSettleNotificationOnlySignalsDoNotStarveParser() async {
        let stable = Support.makeParseResult([
            Support.makeElement(label: "Ready", traits: .staticText, frame: CGRect(x: 0, y: 0, width: 100, height: 30)),
        ])
        let clock = Support.ManualClock()
        let session = Support.makeQuietSession(
            script: [stable],
            clock: clock,
            quietWindowMs: 30,
            accessibilityNotificationSequence: [1, 2, 3, 4, 5]
        )

        let outcome = await session.run(
            start: clock.currentTime(),
            baselineTripwireSignal: Support.tripwireSignal(topmostVC: nil, accessibilityNotificationSequence: 0)
        )

        XCTAssertEqual(outcome.outcome, .settled(timeMs: 30))
        XCTAssertEqual(outcome.finalObservation?.tree.viewportCapture.hierarchy.sortedElements.first?.label, "Ready")
        XCTAssertTrue(outcome.events.isEmpty)
    }

    func testSemanticQuietSettleIgnoresNilParsesUntilAStableScreenArrives() async {
        let stable = Support.makeParseResult([
            Support.makeElement(label: "Ready", traits: .staticText, frame: CGRect(x: 0, y: 0, width: 100, height: 30)),
        ])
        let clock = Support.ManualClock()
        let session = Support.makeQuietSession(
            script: [nil, nil, stable, stable, stable, stable],
            clock: clock,
            quietWindowMs: 30,
            timeoutMs: 100
        )

        let outcome = await session.run(
            start: clock.currentTime(),
            baselineTripwireSignal: Support.tripwireSignal(topmostVC: nil)
        )

        XCTAssertEqual(outcome.outcome, .settled(timeMs: 50))
        XCTAssertEqual(outcome.finalObservation?.tree.viewportCapture.hierarchy.sortedElements.first?.label, "Ready")
    }

    func testFixedCadenceSettleIgnoresNilParsesUntilAStableScreenArrives() async {
        let stable = Support.makeParseResult([
            Support.makeElement(label: "Ready", traits: .staticText, frame: CGRect(x: 0, y: 0, width: 100, height: 30)),
        ])
        let session = Support.makeSession(
            script: [nil, nil, stable, stable, stable],
            cyclesRequired: 2,
            timeoutMs: 100
        )

        let outcome = await session.run(
            start: CFAbsoluteTimeGetCurrent(),
            baselineTripwireSignal: Support.tripwireSignal(topmostVC: nil)
        )

        guard case .settled = outcome.outcome else {
            return XCTFail("Expected fixed-cadence settle after nil parses, got \(outcome.outcome)")
        }
        XCTAssertEqual(outcome.finalObservation?.tree.viewportCapture.hierarchy.sortedElements.first?.label, "Ready")
    }

    func testSettlesAfterCyclesRequiredStableCycles() async {
        let element = Support.makeElement(label: "Hello", traits: .staticText, frame: CGRect(x: 0, y: 0, width: 100, height: 30))
        let stable = Support.makeParseResult([element])
        let session = Support.makeSession(
            script: [stable, stable, stable, stable],
            cyclesRequired: 3
        )

        let outcome = await session.run(
            start: CFAbsoluteTimeGetCurrent(),
            baselineTripwireSignal: Support.tripwireSignal(topmostVC: nil)
        )

        if case .settled = outcome.outcome {
            // Expected.
        } else {
            XCTFail("Expected .settled, got \(outcome.outcome)")
        }
        XCTAssertEqual(outcome.elementsByKey.count, 1)
        XCTAssertEqual(outcome.finalObservation?.tree.viewportCapture.hierarchy.sortedElements.first?.label, "Hello")
    }

    func testNoChangeParsesSettleAndReturnFinalStableScreen() async {
        let element = Support.makeElement(label: "Unchanged", traits: .staticText)
        let stable = Support.makeParseResult([element])
        let session = Support.makeSession(
            script: [stable, stable, stable],
            cyclesRequired: 2
        )

        let outcome = await session.run(
            start: CFAbsoluteTimeGetCurrent(),
            baselineTripwireSignal: Support.tripwireSignal(topmostVC: nil)
        )

        if case .settled = outcome.outcome {
            // Expected: a no-change parse is valid stability proof.
        } else {
            XCTFail("Expected .settled for no-change parses, got \(outcome.outcome)")
        }
        XCTAssertFalse(outcome.events.containsTripwireSignalChange)
        XCTAssertEqual(outcome.finalObservation?.tree.viewportCapture.hierarchy.sortedElements.map(\.label), ["Unchanged"])
    }

    func testFingerprintUsesSharedCoarseFrameComparisonForIPadJitter() {
        let first = Support.makeElement(
            label: "$ 9 Cash",
            traits: .button,
            frame: CGRect(x: 561, y: 423, width: 90, height: 72)
        )
        let jittered = Support.makeElement(
            label: "$ 9 Cash",
            traits: .button,
            frame: CGRect(x: 561, y: 428, width: 90, height: 72)
        )
        let moved = Support.makeElement(
            label: "$ 9 Cash",
            traits: .button,
            frame: CGRect(x: 561, y: 467, width: 90, height: 72)
        )
        let valueChanged = Support.makeElement(
            label: "$ 9 Cash",
            value: "selected",
            traits: .button,
            frame: CGRect(x: 561, y: 423, width: 90, height: 72)
        )
        let labelChanged = Support.makeElement(
            label: "$ 10 Cash",
            traits: .button,
            frame: CGRect(x: 561, y: 423, width: 90, height: 72)
        )
        let identifierChanged = Support.makeElement(
            label: "$ 9 Cash",
            identifier: "cash_9",
            traits: .button,
            frame: CGRect(x: 561, y: 423, width: 90, height: 72)
        )
        let traitsChanged = Support.makeElement(
            label: "$ 9 Cash",
            traits: [.button, .selected],
            frame: CGRect(x: 561, y: 423, width: 90, height: 72)
        )
        let second = Support.makeElement(
            label: "$ 10 Cash",
            traits: .button,
            frame: CGRect(x: 651, y: 423, width: 94, height: 72)
        )
        let hintChanged = AccessibilityElementBuilder(
            label: "$ 9 Cash",
            hint: "Double tap to pay",
            traits: .button,
            shape: first.shape
        ).build()
        let actionsChanged = AccessibilityElementBuilder(
            label: "$ 9 Cash",
            traits: .button,
            shape: first.shape,
            customActions: [.init(name: "Apply discount")]
        ).build()

        XCTAssertEqual(
            Support.settleFingerprint([first]),
            Support.settleFingerprint([jittered]),
            "iPad scroll-view content-offset jitter should not reset settle"
        )
        XCTAssertNotEqual(
            Support.settleFingerprint([first]),
            Support.settleFingerprint([moved]),
            "movement across coarse frame buckets should reset settle"
        )
        XCTAssertNotEqual(
            Support.settleFingerprint([first]),
            Support.settleFingerprint([valueChanged])
        )
        XCTAssertNotEqual(
            Support.settleFingerprint([first]),
            Support.settleFingerprint([labelChanged])
        )
        XCTAssertNotEqual(
            Support.settleFingerprint([first]),
            Support.settleFingerprint([identifierChanged])
        )
        XCTAssertNotEqual(
            Support.settleFingerprint([first]),
            Support.settleFingerprint([traitsChanged])
        )
        XCTAssertNotEqual(
            Support.settleFingerprint([first]),
            Support.settleFingerprint([hintChanged])
        )
        XCTAssertNotEqual(
            Support.settleFingerprint([first]),
            Support.settleFingerprint([actionsChanged])
        )
        XCTAssertNotEqual(
            Support.settleFingerprint([first]),
            Support.settleFingerprint([first, second]),
            "element count is semantic settle state"
        )
        XCTAssertNotEqual(
            Support.settleFingerprint([first, second]),
            Support.settleFingerprint([second, first]),
            "settle fingerprint intentionally preserves traversal order"
        )
    }

    func testTimelineKeysUseSharedCoarseFrameComparisonForIPadJitter() {
        let first = Support.makeElement(
            label: "Cash",
            traits: .staticText,
            frame: CGRect(x: 244, y: 423, width: 42, height: 72)
        )
        let jittered = Support.makeElement(
            label: "Cash",
            traits: .staticText,
            frame: CGRect(x: 244, y: 428, width: 42, height: 72)
        )

        XCTAssertEqual(first.timelineKey(bucket: 13), jittered.timelineKey(bucket: 13))
    }
}
#endif // canImport(UIKit)
