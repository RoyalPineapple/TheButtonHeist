#if canImport(UIKit)
import XCTest
@testable import AccessibilitySnapshotParser
import ButtonHeistSupport
@testable import TheInsideJob
@testable import TheScore

@MainActor
final class SettleSessionTimeoutChangeBaselineTests: XCTestCase {
    private typealias Support = SettleSessionTestSupport

    func testSemanticQuietSettleTripwireChangeResetsBaseline() async {
        let stable = Support.makeParseResult([
            Support.makeElement(label: "Ready", traits: .staticText, frame: CGRect(x: 0, y: 0, width: 100, height: 30)),
        ])
        let clock = Support.ManualClock()
        let changedVC = ObjectIdentifier(UIViewController())
        let session = Support.makeQuietSession(
            script: [stable],
            clock: clock,
            quietWindowMs: 30,
            topVCSequence: [changedVC, changedVC, changedVC, changedVC]
        )

        let outcome = await session.run(
            start: clock.currentTime(),
            baselineTripwireSignal: Support.tripwireSignal(topmostVC: nil)
        )

        XCTAssertEqual(outcome.outcome, .settled(timeMs: 50))
        XCTAssertEqual(outcome.events, [
            .tripwireSignalChanged(
                from: Support.tripwireSignal(topmostVC: nil),
                to: Support.tripwireSignal(topmostVC: changedVC)
            ),
        ])
    }

    func testSemanticQuietSettleTimesOutWhenFingerprintNeverStabilizes() async {
        let clock = Support.ManualClock()
        let counter = Support.Counter()
        let session = SettleSession(
            parseProvider: {
                let index = counter.next()
                return Support.makeParseResult([
                    Support.makeElement(
                        label: "Tick \(index)",
                        traits: .staticText,
                        frame: CGRect(x: 0, y: 0, width: 100, height: 30)
                    ),
                ])
            },
            tripwireSignalProvider: { Support.tripwireSignal(topmostVC: nil) },
            observationYield: {
                clock.advance(milliseconds: 10)
            },
            clock: { clock.currentTime() },
            quietWindowMs: 30,
            timeoutMs: 50
        )

        let outcome = await session.run(
            start: clock.currentTime(),
            baselineTripwireSignal: Support.tripwireSignal(topmostVC: nil)
        )

        XCTAssertEqual(outcome.outcome, .timedOut(timeMs: 50))
        XCTAssertEqual(outcome.finalObservation?.tree.viewportCapture.hierarchy.sortedElements.first?.label, "Tick 5")
        XCTAssertNotNil(outcome.instabilityDescription)
    }

    func testFrameJitterInsideCoarseBucketSettlesAndKeepsFinalFrame() async {
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
        let session = Support.makeSession(
            script: [
                Support.makeParseResult([first]),
                Support.makeParseResult([jittered]),
                Support.makeParseResult([first]),
                Support.makeParseResult([jittered]),
            ],
            cyclesRequired: 3
        )

        let outcome = await session.run(
            start: CFAbsoluteTimeGetCurrent(),
            baselineTripwireSignal: Support.tripwireSignal(topmostVC: nil)
        )

        guard case .settled = outcome.outcome else {
            return XCTFail("Expected frame jitter inside the bucket to settle, got \(outcome.outcome)")
        }
        XCTAssertNil(outcome.instabilityDescription)
        XCTAssertEqual(outcome.finalObservation?.tree.viewportCapture.hierarchy.sortedElements.first?.shape.frame.origin.y, 428)
    }

    func testFrameJitterInsideCoarseBucketDoesNotProduceChangeDescription() {
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

        XCTAssertNil(SettleTimeline.changeDescription(from: [first], to: [jittered], bucket: 13))
    }

    func testChangeDescriptionNamesChangedFieldsAndIsBounded() {
        let before = [
            Support.makeElement(
                label: "Old",
                value: "offline",
                identifier: "old_id",
                traits: .button,
                frame: CGRect(x: 561, y: 423, width: 90, height: 72)
            ),
            Support.makeElement(label: "Second", traits: .staticText),
            Support.makeElement(label: "Third", traits: .staticText),
            Support.makeElement(label: "Fourth", traits: .staticText),
            Support.makeElement(label: "Fifth", traits: .staticText),
        ]
        let after = [
            Support.makeElement(
                label: "New",
                value: "online",
                identifier: "new_id",
                traits: .staticText,
                frame: CGRect(x: 561, y: 467, width: 90, height: 72)
            ),
            Support.makeElement(label: "Second changed", traits: .staticText),
            Support.makeElement(label: "Third changed", traits: .staticText),
            Support.makeElement(label: "Fourth changed", traits: .staticText),
            Support.makeElement(label: "Fifth changed", traits: .staticText),
            Support.makeElement(label: "Sixth", traits: .staticText),
        ]

        let diagnostic = SettleTimeline.changeDescription(from: before, to: after, bucket: 13)

        XCTAssertTrue(diagnostic?.contains("count 5->6") == true, diagnostic ?? "missing diagnostic")
        XCTAssertTrue(diagnostic?.contains("label \"Old\"->\"New\"") == true, diagnostic ?? "missing diagnostic")
        XCTAssertTrue(
            diagnostic?.contains("identifier \"old_id\"->\"new_id\"") == true,
            diagnostic ?? "missing diagnostic"
        )
        XCTAssertTrue(diagnostic?.contains("traits") == true, diagnostic ?? "missing diagnostic")
        XCTAssertTrue(diagnostic?.contains("value \"offline\"->\"online\"") == true, diagnostic ?? "missing diagnostic")
        XCTAssertTrue(diagnostic?.contains("frame bucket") == true, diagnostic ?? "missing diagnostic")
        XCTAssertTrue(diagnostic?.hasSuffix("; ...") == true, diagnostic ?? "missing diagnostic")
    }

    func testTimesOutWhenTreeNeverStabilizes() async {
        // Each parse returns a unique element so the fingerprint never
        // matches the previous — stableCycles never reaches 3 and the
        // loop exits via the wall-clock deadline.
        let counter = Support.Counter()
        let session = SettleSession(
            parseProvider: { [weak self] in
                guard let self else { return nil }
                let value = counter.next()
                return Support.makeParseResult([
                    Support.makeElement(label: "label-\(value)", traits: .staticText)
                ])
            },
            tripwireSignalProvider: { Support.tripwireSignal(topmostVC: nil) },
            // Real (small) sleeps so wall clock advances; a no-op sleeper
            // would let the loop reach a finite-script end before the
            // timeout fires.
            sleeper: { _ = await Task.cancellableSleep(nanoseconds: $0) },
            cyclesRequired: 3,
            cycleIntervalMs: 5,
            timeoutMs: 50
        )

        let outcome = await session.run(
            start: CFAbsoluteTimeGetCurrent(),
            baselineTripwireSignal: Support.tripwireSignal(topmostVC: nil)
        )

        if case .timedOut = outcome.outcome {
            // Expected.
        } else {
            XCTFail("Expected .timedOut, got \(outcome.outcome)")
        }
        XCTAssertFalse(outcome.outcome.didSettleCleanly)
        XCTAssertGreaterThan(outcome.elementsByKey.count, 1,
                             "Every distinct element observed mid-loop should accumulate into elementsByKey")
    }

    func testTimeoutReportsUnstableFrameBucketChanges() async {
        let counter = Support.Counter()
        let session = SettleSession(
            parseProvider: { [weak self] in
                guard let self else { return nil }
                let value = counter.next()
                let y: CGFloat = value.isMultiple(of: 2) ? 423 : 467
                return Support.makeParseResult([
                    Support.makeElement(
                        label: "$ 9 Cash",
                        traits: .button,
                        frame: CGRect(x: 561, y: y, width: 90, height: 72)
                    ),
                ])
            },
            tripwireSignalProvider: { Support.tripwireSignal(topmostVC: nil) },
            sleeper: { _ = await Task.cancellableSleep(nanoseconds: $0) },
            cyclesRequired: 3,
            cycleIntervalMs: 5,
            timeoutMs: 50
        )

        let outcome = await session.run(
            start: CFAbsoluteTimeGetCurrent(),
            baselineTripwireSignal: Support.tripwireSignal(topmostVC: nil)
        )

        guard case .timedOut = outcome.outcome else {
            return XCTFail("Expected .timedOut, got \(outcome.outcome)")
        }
        XCTAssertFalse(outcome.outcome.didSettleCleanly)
        guard let diagnostic = outcome.instabilityDescription else {
            return XCTFail("Expected instabilityDescription on timeout, got nil")
        }
        XCTAssertTrue(diagnostic.contains("unstable accessibility changes"), diagnostic)
        XCTAssertTrue(diagnostic.contains("$ 9 Cash"), diagnostic)
        XCTAssertTrue(diagnostic.contains("frame bucket"), diagnostic)
        XCTAssertTrue(diagnostic.contains("frame"), diagnostic)
    }

    func testTripwireTriggerResetsBaselineAndSettlesCleanly() async {
        let stable = Support.makeParseResult([Support.makeElement(label: "A", traits: .staticText)])
        let placeholder = ObjectIdentifier(NSObject())
        // Baseline is passed in explicitly as `nil`; every call to the
        // provider during the loop returns the post-transition VC, so
        // the very first post-sleep comparison detects the change.
        let topVCSeq: [ObjectIdentifier?] = [placeholder]
        let session = Support.makeSession(
            script: [stable, stable, stable],
            cyclesRequired: 3,
            cycleIntervalMs: 1,
            timeoutMs: 100,
            topVCSequence: topVCSeq
        )

        let outcome = await session.run(
            start: CFAbsoluteTimeGetCurrent(),
            baselineTripwireSignal: Support.tripwireSignal(topmostVC: nil)
        )

        if case .settled = outcome.outcome {
            // Expected.
        } else {
            XCTFail("Expected .settled after Tripwire signal, got \(outcome.outcome)")
        }
        XCTAssertTrue(outcome.events.containsTripwireSignalChange)
        XCTAssertEqual(outcome.elementsByKey.count, 1)
        XCTAssertTrue(outcome.outcome.didSettleCleanly,
                      ".settled after Tripwire signal should report didSettleCleanly == true")
    }

    func testTripwireTriggerWaitsForStablePostTransitionTree() async {
        let before = Support.makeElement(label: "Display", traits: .header)
        let after = Support.makeElement(label: "Controls Demo", traits: .header)
        let liveObject = NSObject()
        let livePostTransition = ObjectIdentifier(liveObject)
        let session = Support.makeSession(
            script: [
                Support.makeParseResult([before]),
                Support.makeParseResult([before]),
                Support.makeParseResult([after]),
                Support.makeParseResult([after]),
                Support.makeParseResult([after])
            ],
            cyclesRequired: 2,
            cycleIntervalMs: 1,
            timeoutMs: 100,
            topVCSequence: [livePostTransition, livePostTransition, livePostTransition, livePostTransition]
        )

        let outcome = await session.run(
            start: CFAbsoluteTimeGetCurrent(),
            baselineTripwireSignal: Support.tripwireSignal(topmostVC: nil)
        )
        _ = liveObject // keep alive

        if case .settled = outcome.outcome {
            // Expected.
        } else {
            XCTFail("Expected .settled after Tripwire signal, got \(outcome.outcome)")
        }
        XCTAssertTrue(outcome.events.containsTripwireSignalChange)
        let labels = Set(outcome.elementsByKey.values.compactMap(\.label))
        XCTAssertTrue(labels.contains("Display"))
        XCTAssertTrue(labels.contains("Controls Demo"))
    }

    func testLateTripwireTriggerResetsPreviouslyStableCycles() async {
        let before = Support.makeElement(label: "Before", traits: .header)
        let loading = Support.makeElement(label: "Loading", traits: .staticText)
        let after = Support.makeElement(label: "After", traits: .header)
        let baselineObject = NSObject()
        let liveObject = NSObject()
        let baseline = ObjectIdentifier(baselineObject)
        let livePostTransition = ObjectIdentifier(liveObject)
        let session = Support.makeSession(
            script: [
                Support.makeParseResult([before]),
                Support.makeParseResult([before]),
                Support.makeParseResult([loading]),
                Support.makeParseResult([after]),
                Support.makeParseResult([after]),
                Support.makeParseResult([after])
            ],
            cyclesRequired: 2,
            cycleIntervalMs: 1,
            timeoutMs: 100,
            topVCSequence: [baseline, livePostTransition, livePostTransition, livePostTransition, livePostTransition]
        )

        let outcome = await session.run(
            start: CFAbsoluteTimeGetCurrent(),
            baselineTripwireSignal: Support.tripwireSignal(topmostVC: baseline)
        )
        _ = baselineObject // keep alive
        _ = liveObject // keep alive

        if case .settled = outcome.outcome {
            // Expected.
        } else {
            XCTFail("Expected .settled after late Tripwire signal, got \(outcome.outcome)")
        }
        XCTAssertTrue(outcome.events.containsTripwireSignalChange)
        let labels = Set(outcome.elementsByKey.values.compactMap(\.label))
        XCTAssertTrue(labels.contains("Before"))
        XCTAssertTrue(labels.contains("Loading"))
        XCTAssertTrue(labels.contains("After"))
    }

    /// The baseline top-VC is passed in explicitly, so the loop never
    /// consumes a script entry just to "discover" what the pre-action VC
    /// was. With the same VC value passed as baseline AND returned by
    /// every provider call, no screen-change should ever trigger.
    func testExplicitBaselineMatchesProviderSequenceNoScreenChange() async {
        let stable = Support.makeParseResult([Support.makeElement(label: "A", traits: .staticText)])
        // Retain the underlying object so the ObjectIdentifier stays valid
        // for the entire loop — otherwise the temp NSObject can be
        // deallocated and a later allocation can collide on its slot.
        let baselineObject = NSObject()
        let baseline = ObjectIdentifier(baselineObject)
        // Every provider call answers with the same VC as the baseline —
        // proves the loop is comparing against the parameter, not its own
        // first sampled value.
        let session = Support.makeSession(
            script: [stable, stable, stable, stable],
            cyclesRequired: 3,
            cycleIntervalMs: 1,
            timeoutMs: 100,
            topVCSequence: [baseline, baseline, baseline, baseline]
        )

        let outcome = await session.run(
            start: CFAbsoluteTimeGetCurrent(),
            baselineTripwireSignal: Support.tripwireSignal(topmostVC: baseline)
        )
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
        let stable = Support.makeParseResult([Support.makeElement(label: "A", traits: .staticText)])
        let baselineObject = NSObject()
        let liveObject = NSObject()
        let baseline = ObjectIdentifier(baselineObject)
        let livePostTransition = ObjectIdentifier(liveObject)
        let session = Support.makeSession(
            script: [stable, stable, stable],
            cyclesRequired: 3,
            cycleIntervalMs: 1,
            timeoutMs: 100,
            topVCSequence: [livePostTransition]
        )

        let outcome = await session.run(
            start: CFAbsoluteTimeGetCurrent(),
            baselineTripwireSignal: Support.tripwireSignal(topmostVC: baseline)
        )
        _ = baselineObject // keep alive
        _ = liveObject // keep alive

        if case .settled = outcome.outcome {
            // Expected.
        } else {
            XCTFail("Differing baseline vs provider must surface a Tripwire signal event, got \(outcome.outcome)")
        }
        XCTAssertTrue(outcome.events.containsTripwireSignalChange)
    }
}
#endif // canImport(UIKit)
