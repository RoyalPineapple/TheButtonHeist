#if canImport(UIKit)
import XCTest
@testable import AccessibilitySnapshotParser
@testable import TheInsideJob
@testable import TheScore

/// Deterministic tests for `SettleSession` — the multi-cycle AX-tree
/// settle loop. These do not stand up a UIKit hierarchy; they drive the
/// loop's closure-based `parseProvider` / `topVCProvider` / `sleeper`
/// seams with scripted sequences and assert the resulting `SettleOutcome`
/// and accumulated `elementsByKey`.
@MainActor
final class SettleSessionTests: XCTestCase {

    // MARK: - Helpers

    private func makeElement(
        label: String? = nil,
        value: String? = nil,
        identifier: String? = nil,
        traits: UIAccessibilityTraits = .none,
        frame: CGRect = .zero
    ) -> AccessibilityElement {
        .make(
            label: label,
            value: value,
            identifier: identifier,
            traits: traits,
            shape: .frame(frame)
        )
    }

    private func makeParseResult(_ elements: [AccessibilityElement]) -> Screen {
        let hierarchy: [AccessibilityHierarchy] = elements.enumerated().map { index, element in
            .element(element, traversalIndex: index)
        }
        return Screen(
            elements: [:],
            hierarchy: hierarchy,
            firstResponderHeistId: nil,
            scrollableContainerViews: [:]
        )
    }

    /// Drives the loop with scripted parse results. The first script entry
    /// is consumed by the synchronous baseline-seed parse; subsequent
    /// entries feed the post-sleep parses. The last entry is repeated
    /// indefinitely if the loop runs longer than the script.
    ///
    /// `topVCSequence` feeds the legacy top-VC Tripwire seam inside the loop —
    /// the baseline top-VC is passed explicitly to `run(...)` so the
    /// provider never has to answer for the pre-action snapshot.
    private func makeSession(
        script: [Screen?],
        cyclesRequired: Int = 3,
        cycleIntervalMs: Int = 1,
        timeoutMs: Int = 200,
        topVCSequence: [ObjectIdentifier?]? = nil
    ) -> SettleSession {
        let scriptBox = ScriptBox(script: script)
        let topVCBox = ScriptBox(script: topVCSequence ?? [nil])
        return SettleSession(
            parseProvider: { scriptBox.next() },
            topVCProvider: { topVCBox.next() },
            sleeper: { _ in /* no real sleep; loop runs at wall-clock pace */ },
            cyclesRequired: cyclesRequired,
            cycleIntervalMs: cycleIntervalMs,
            timeoutMs: timeoutMs
        )
    }

    /// Mutable scripted-value provider that's safe to call from the
    /// `@MainActor` closures the loop dispatches.
    @MainActor
    private final class ScriptBox<T> {
        private var script: [T]
        private var index: Int = 0
        init(script: [T]) { self.script = script }
        func next() -> T {
            let value = script[min(index, script.count - 1)]
            if index < script.count { index += 1 }
            return value
        }
    }

    /// Unbounded monotonic counter for tests that need a never-stabilizing
    /// stream of distinct values.
    @MainActor
    private final class Counter {
        private var value: Int = 0
        func next() -> Int {
            defer { value += 1 }
            return value
        }
    }

    // MARK: - Stable Settle

    func testSettlesAfterCyclesRequiredStableCycles() async {
        let element = makeElement(label: "Hello", traits: .staticText, frame: CGRect(x: 0, y: 0, width: 100, height: 30))
        let stable = makeParseResult([element])
        let session = makeSession(
            script: [stable, stable, stable, stable],
            cyclesRequired: 3
        )

        let outcome = await session.run(start: CFAbsoluteTimeGetCurrent(), baselineTopVC: nil)

        if case .settled = outcome.outcome {
            // Expected.
        } else {
            XCTFail("Expected .settled, got \(outcome.outcome)")
        }
        XCTAssertEqual(outcome.elementsByKey.count, 1)
    }

    // MARK: - Timeout

    func testTimesOutWhenTreeNeverStabilizes() async {
        // Each parse returns a unique element so the fingerprint never
        // matches the previous — stableCycles never reaches 3 and the
        // loop exits via the wall-clock deadline.
        let counter = Counter()
        let session = SettleSession(
            parseProvider: { [weak self] in
                guard let self else { return nil }
                let value = counter.next()
                return self.makeParseResult([
                    self.makeElement(label: "label-\(value)", traits: .staticText)
                ])
            },
            topVCProvider: { nil },
            // Real (small) sleeps so wall clock advances; a no-op sleeper
            // would let the loop reach a finite-script end before the
            // timeout fires.
            // swiftlint:disable:next agent_test_task_sleep
            sleeper: { try await Task.sleep(nanoseconds: $0) },
            cyclesRequired: 3,
            cycleIntervalMs: 5,
            timeoutMs: 50
        )

        let outcome = await session.run(start: CFAbsoluteTimeGetCurrent(), baselineTopVC: nil)

        if case .timedOut = outcome.outcome {
            // Expected.
        } else {
            XCTFail("Expected .timedOut, got \(outcome.outcome)")
        }
        XCTAssertGreaterThan(outcome.elementsByKey.count, 1,
                             "Every distinct element observed mid-loop should accumulate into elementsByKey")
    }

    // MARK: - Screen Change

    func testTripwireTriggerAbortsLoopAndSettlesCleanly() async {
        let stable = makeParseResult([makeElement(label: "A", traits: .staticText)])
        let placeholder = ObjectIdentifier(NSObject())
        // Baseline is passed in explicitly as `nil`; every call to the
        // provider during the loop returns the post-transition VC, so
        // the very first post-sleep comparison detects the change.
        let topVCSeq: [ObjectIdentifier?] = [placeholder]
        let session = makeSession(
            script: [stable, stable, stable],
            cyclesRequired: 3,
            cycleIntervalMs: 1,
            timeoutMs: 100,
            topVCSequence: topVCSeq
        )

        let outcome = await session.run(start: CFAbsoluteTimeGetCurrent(), baselineTopVC: nil)

        if case .tripwireTriggered = outcome.outcome {
            // Expected.
        } else {
            XCTFail("Expected .tripwireTriggered, got \(outcome.outcome)")
        }
        XCTAssertTrue(outcome.outcome.didSettleCleanly,
                      ".tripwireTriggered should report didSettleCleanly == true")
    }

    // MARK: - Explicit Baseline (PR #330 H1)

    /// The baseline top-VC is passed in explicitly, so the loop never
    /// consumes a script entry just to "discover" what the pre-action VC
    /// was. With the same VC value passed as baseline AND returned by
    /// every provider call, no screen-change should ever trigger.
    func testExplicitBaselineMatchesProviderSequenceNoScreenChange() async {
        let stable = makeParseResult([makeElement(label: "A", traits: .staticText)])
        // Retain the underlying object so the ObjectIdentifier stays valid
        // for the entire loop — otherwise the temp NSObject can be
        // deallocated and a later allocation can collide on its slot.
        let baselineObject = NSObject()
        let baseline = ObjectIdentifier(baselineObject)
        // Every provider call answers with the same VC as the baseline —
        // proves the loop is comparing against the parameter, not its own
        // first sampled value.
        let session = makeSession(
            script: [stable, stable, stable, stable],
            cyclesRequired: 3,
            cycleIntervalMs: 1,
            timeoutMs: 100,
            topVCSequence: [baseline, baseline, baseline, baseline]
        )

        let outcome = await session.run(start: CFAbsoluteTimeGetCurrent(), baselineTopVC: baseline)
        _ = baselineObject // keep alive

        if case .settled = outcome.outcome {
            // Expected — same VC throughout means no screen change.
        } else {
            XCTFail("Same baseline + provider VC should settle, got \(outcome.outcome)")
        }
    }

    /// Inverse of the above: baseline differs from the provider's value
    /// from the first cycle, so the very first post-sleep comparison
    /// triggers a screen change. No script-position offset needed.
    func testExplicitBaselineDifferingFromProviderTriggersTripwire() async {
        let stable = makeParseResult([makeElement(label: "A", traits: .staticText)])
        let baselineObject = NSObject()
        let liveObject = NSObject()
        let baseline = ObjectIdentifier(baselineObject)
        let livePostTransition = ObjectIdentifier(liveObject)
        let session = makeSession(
            script: [stable, stable, stable],
            cyclesRequired: 3,
            cycleIntervalMs: 1,
            timeoutMs: 100,
            topVCSequence: [livePostTransition]
        )

        let outcome = await session.run(start: CFAbsoluteTimeGetCurrent(), baselineTopVC: baseline)
        _ = baselineObject // keep alive
        _ = liveObject // keep alive

        if case .tripwireTriggered = outcome.outcome {
            // Expected.
        } else {
            XCTFail("Differing baseline vs provider must surface .tripwireTriggered, got \(outcome.outcome)")
        }
    }

    // MARK: - Cancellation

    func testCancellationPropagatesAsCancelledOutcome() async {
        let stable = makeParseResult([makeElement(label: "A")])
        let session = SettleSession(
            parseProvider: { stable },
            topVCProvider: { nil },
            sleeper: { _ in throw CancellationError() },
            cyclesRequired: 3,
            cycleIntervalMs: 1,
            timeoutMs: 200
        )

        let outcome = await session.run(start: CFAbsoluteTimeGetCurrent(), baselineTopVC: nil)

        if case .cancelled = outcome.outcome {
            // Expected.
        } else {
            XCTFail("Expected .cancelled, got \(outcome.outcome)")
        }
        XCTAssertFalse(outcome.outcome.didSettleCleanly,
                       ".cancelled must NOT count as settled cleanly")
    }

    func testNonCancellationSleeperErrorMapsToTimedOut() async {
        struct DummyError: Error {}
        let stable = makeParseResult([makeElement(label: "A")])
        let session = SettleSession(
            parseProvider: { stable },
            topVCProvider: { nil },
            sleeper: { _ in throw DummyError() },
            cyclesRequired: 3,
            cycleIntervalMs: 1,
            timeoutMs: 200
        )

        let outcome = await session.run(start: CFAbsoluteTimeGetCurrent(), baselineTopVC: nil)

        if case .timedOut = outcome.outcome {
            // Expected.
        } else {
            XCTFail("Expected .timedOut for non-cancellation throw, got \(outcome.outcome)")
        }
    }

    // MARK: - updatesFrequently Masking

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

        let outcome = await session.run(start: CFAbsoluteTimeGetCurrent(), baselineTopVC: nil)

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
            self.makeElement(
                label: "hand",
                traits: .updatesFrequently,
                frame: CGRect(x: i * 10, y: i * 10, width: 5, height: 50)
            )
        }
        let session = makeSession(
            script: hands.map { hand in self.makeParseResult([staticElement, hand]) },
            cyclesRequired: 3
        )

        let outcome = await session.run(start: CFAbsoluteTimeGetCurrent(), baselineTopVC: nil)

        if case .settled = outcome.outcome {
            // Expected.
        } else {
            XCTFail("Animated frame on .updatesFrequently element must not block settle. Got \(outcome.outcome)")
        }
    }

    // MARK: - Transient Element Subtraction

    func testTransientElementsExcludesBaselineAndFinal() {
        let baseline = makeElement(label: "Baseline", traits: .staticText)
        let final = makeElement(label: "Final", traits: .staticText)
        let transient = makeElement(label: "Loading", traits: .staticText)

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

    func testTransientElementsOrderedByReadingOrder() {
        let lowerLeft = makeElement(label: "B", frame: CGRect(x: 0, y: 100, width: 10, height: 10))
        let upperLeft = makeElement(label: "A", frame: CGRect(x: 0, y: 0, width: 10, height: 10))
        let upperRight = makeElement(label: "C", frame: CGRect(x: 50, y: 0, width: 10, height: 10))

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
            baseline: [makeElement(label: "X")],
            final: []
        )
        XCTAssertTrue(result.isEmpty)
    }
}
#endif // canImport(UIKit)
