#if canImport(UIKit)
import XCTest
@testable import AccessibilitySnapshotParser
@testable import TheInsideJob
@testable import TheScore

/// Deterministic tests for `SettleSession` — the multi-cycle AX-tree
/// settle loop. These do not stand up a UIKit hierarchy; they drive the
/// loop's closure-based `parseProvider` / `tripwireSignalProvider` / `sleeper`
/// seams with scripted sequences and assert the resulting `SettleOutcome`,
/// observed `SettleEvent`s, and accumulated `elementsByKey`.
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
            shape: .frame(AccessibilityRect(frame))
        )
    }

    private func makeParseResult(_ elements: [AccessibilityElement]) -> InterfaceObservation {
        return InterfaceObservation.makeForTests(
            elements.enumerated().map { index, element in
                InterfaceObservation.TestEntry(
                    element,
                    heistId: HeistId(rawValue: "settle_\(index)")
                )
            }
        )
    }

    private func recordedObservation(
        _ observation: InterfaceObservation,
        ledger: inout SettleObservationLedger
    ) -> SettleRecordedObservation {
        ledger.record(observation)
    }

    private func reduceObservation(
        _ observation: InterfaceObservation,
        elapsedMs: Int,
        machine: SettleLoopMachine,
        ledger: inout SettleObservationLedger,
        state: inout SettleLoopMachine.State
    ) -> MachineStep {
        let recordedObservation = recordedObservation(observation, ledger: &ledger)
        return send(
            .observation(recordedObservation.sample, elapsedMs: elapsedMs),
            machine: machine,
            ledger: &ledger,
            state: &state
        )
    }

    private func send(
        _ event: SettleLoopMachine.Event,
        machine: SettleLoopMachine,
        ledger: inout SettleObservationLedger,
        state: inout SettleLoopMachine.State
    ) -> MachineStep {
        let eventCount = state.events.count
        let transition = machine.advance(state, with: event)
        state = transition.state
        if state.events.count > eventCount {
            ledger.resetCurrentGeneration()
        }
        return MachineStep(
            effect: transition.effect,
            outcome: SettleSession.outcome(for: transition, observations: ledger)
        )
    }

    private struct MachineStep {
        let effect: SettleLoopMachine.Effect
        let outcome: SettleSession.Outcome?
    }

    /// Drives the loop with scripted parse results. The first script entry
    /// is consumed by the synchronous baseline-seed parse; subsequent
    /// entries feed the post-sleep parses. The last entry is repeated
    /// indefinitely if the loop runs longer than the script.
    ///
    /// `topVCSequence` feeds the Tripwire signal seam inside the loop.
    /// The baseline signal is passed explicitly to `run(...)` so the provider
    /// never has to answer for the pre-action snapshot.
    private func makeSession(
        script: [InterfaceObservation?],
        cyclesRequired: Int = 3,
        cycleIntervalMs: Int = 1,
        timeoutMs: Int = 200,
        topVCSequence: [ObjectIdentifier?]? = nil,
        accessibilityNotificationSequence: [UInt64]? = nil
    ) -> SettleSession {
        let scriptBox = ScriptBox(script: script)
        let topVCBox = ScriptBox(script: topVCSequence ?? [nil])
        let notificationBox = ScriptBox(script: accessibilityNotificationSequence ?? [0])
        return SettleSession(
            parseProvider: { scriptBox.next() },
            tripwireSignalProvider: {
                Self.tripwireSignal(
                    topmostVC: topVCBox.next(),
                    accessibilityNotificationSequence: notificationBox.next()
                )
            },
            sleeper: { _ in /* no real sleep; loop runs at wall-clock pace */ },
            cyclesRequired: cyclesRequired,
            cycleIntervalMs: cycleIntervalMs,
            timeoutMs: timeoutMs
        )
    }

    private static func tripwireSignal(
        topmostVC: ObjectIdentifier?,
        accessibilityNotificationSequence: UInt64 = 0
    ) -> TheTripwire.TripwireSignal {
        TheTripwire.TripwireSignal(
            topmostVC: topmostVC,
            navigation: .empty,
            windowStack: .empty,
            accessibilityNotificationSequence: accessibilityNotificationSequence
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

    @MainActor
    private final class ManualClock {
        private(set) var now: CFAbsoluteTime = 0

        func currentTime() -> CFAbsoluteTime {
            now
        }

        func advance(milliseconds: Int) {
            now += Double(milliseconds) / 1_000
        }
    }

    private func makeQuietSession(
        script: [InterfaceObservation?],
        clock: ManualClock,
        frameMs: Int = 10,
        quietWindowMs: Int = 30,
        timeoutMs: Int = 500,
        topVCSequence: [ObjectIdentifier?]? = nil,
        accessibilityNotificationSequence: [UInt64]? = nil,
        yieldCount: Counter? = nil
        ) -> SettleSession {
        let scriptBox = ScriptBox(script: script)
        let topVCBox = ScriptBox(script: topVCSequence ?? [nil])
        let notificationBox = ScriptBox(script: accessibilityNotificationSequence ?? [0])
        return SettleSession(
            parseProvider: { scriptBox.next() },
            tripwireSignalProvider: {
                Self.tripwireSignal(
                    topmostVC: topVCBox.next(),
                    accessibilityNotificationSequence: notificationBox.next()
                )
            },
            observationYield: {
                _ = yieldCount?.next()
                clock.advance(milliseconds: frameMs)
            },
            clock: { clock.currentTime() },
            quietWindowMs: quietWindowMs,
            timeoutMs: timeoutMs
        )
    }

    // MARK: - Timing

    func testSemanticObservationDeadlineOwnsRemainingAndElapsedTime() {
        let deadline = SemanticObservationDeadline(start: 10, timeoutSeconds: 0.25)

        XCTAssertTrue(deadline.hasTimeRemaining(at: 10.1))
        XCTAssertEqual(deadline.remainingSeconds(at: 10.1), 0.15, accuracy: 0.000_001)
        XCTAssertEqual(deadline.elapsedMilliseconds(at: 10.125), 125)
        XCTAssertFalse(deadline.hasTimeRemaining(at: 10.25))
        XCTAssertEqual(deadline.remainingSeconds(at: 10.5), 0)

        let millisecondDeadline = SemanticObservationDeadline(start: 20, timeoutMs: 250)
        XCTAssertEqual(millisecondDeadline.remainingSeconds(at: 20.1), 0.15, accuracy: 0.000_001)

        let expiredDeadline = SemanticObservationDeadline(start: 30, timeoutSeconds: -1)
        XCTAssertFalse(expiredDeadline.hasTimeRemaining(at: 30))
        XCTAssertEqual(expiredDeadline.remainingSeconds(at: 30), 0)
    }

    func testViewportTransitionSettleUsesOneRunLoopTurnWhenTheRepeatIsStable() async {
        let stable = makeParseResult([
            makeElement(label: "Stable", traits: .staticText),
        ])
        let parseCount = Counter()
        let session = SettleSession(
            parseProvider: {
                _ = parseCount.next()
                return stable
            },
            tripwireSignalProvider: { Self.tripwireSignal(topmostVC: nil) },
            sleeper: { _ in },
            cyclesRequired: 1,
            cycleIntervalMs: 0,
            timeoutMs: SettleSession.viewportTransitionTimeoutMs
        )

        let outcome = await session.run(
            start: CFAbsoluteTimeGetCurrent(),
            baselineTripwireSignal: Self.tripwireSignal(topmostVC: nil)
        )

        XCTAssertTrue(outcome.outcome.didSettleCleanly)
        XCTAssertEqual(parseCount.next(), 2)
    }

    func testViewportTransitionSettleUsesASecondRunLoopTurnAfterOneLayoutChange() async {
        let loading = makeParseResult([
            makeElement(label: "Loading", traits: .staticText),
        ])
        let ready = makeParseResult([
            makeElement(label: "Ready", traits: .staticText),
        ])
        let script = ScriptBox(script: [loading, ready, ready])
        let parseCount = Counter()
        let session = SettleSession(
            parseProvider: {
                _ = parseCount.next()
                return script.next()
            },
            tripwireSignalProvider: { Self.tripwireSignal(topmostVC: nil) },
            sleeper: { _ in },
            cyclesRequired: 1,
            cycleIntervalMs: 0,
            timeoutMs: SettleSession.viewportTransitionTimeoutMs
        )

        let outcome = await session.run(
            start: CFAbsoluteTimeGetCurrent(),
            baselineTripwireSignal: Self.tripwireSignal(topmostVC: nil)
        )

        XCTAssertTrue(outcome.outcome.didSettleCleanly)
        XCTAssertEqual(parseCount.next(), 3)
        XCTAssertEqual(
            outcome.finalObservation?.tree.viewportCapture.hierarchy.sortedElements.first?.label,
            "Ready"
        )
    }

    // MARK: - Machine

    func testMachineSettlesFixedCadenceAfterRequiredConsecutiveCycles() {
        let stable = makeParseResult([
            makeElement(label: "Ready", traits: .staticText),
        ])
        let machine = SettleLoopMachine()
        var ledger = SettleObservationLedger()
        var state = SettleLoopMachine.State(
            policy: .consecutiveCycles(required: 2),
            tripwireBaseline: Self.tripwireSignal(topmostVC: nil)
        )

        XCTAssertContinue(reduceObservation(stable, elapsedMs: 0, machine: machine, ledger: &ledger, state: &state))
        XCTAssertContinue(reduceObservation(stable, elapsedMs: 1, machine: machine, ledger: &ledger, state: &state))
        let step = reduceObservation(stable, elapsedMs: 2, machine: machine, ledger: &ledger, state: &state)

        guard case .terminal(.settled(let timeMs)) = step.effect else {
            return XCTFail("Expected settled terminal effect, got \(step.effect)")
        }
        XCTAssertEqual(timeMs, 2)
        XCTAssertEqual(step.outcome?.finalObservation?.tree.viewportCapture.hierarchy.sortedElements.first?.label, "Ready")
    }

    func testMachineSettlesQuietWindowAfterFingerprintRemainsStableForWindow() {
        let stable = makeParseResult([
            makeElement(label: "Ready", traits: .staticText),
        ])
        let machine = SettleLoopMachine()
        var ledger = SettleObservationLedger()
        var state = SettleLoopMachine.State(
            policy: .quietWindow(milliseconds: 30),
            tripwireBaseline: Self.tripwireSignal(topmostVC: nil)
        )

        XCTAssertContinue(reduceObservation(stable, elapsedMs: 0, machine: machine, ledger: &ledger, state: &state))
        XCTAssertContinue(reduceObservation(stable, elapsedMs: 20, machine: machine, ledger: &ledger, state: &state))
        let step = reduceObservation(stable, elapsedMs: 30, machine: machine, ledger: &ledger, state: &state)

        guard case .terminal(.settled(let timeMs)) = step.effect else {
            return XCTFail("Expected settled terminal effect, got \(step.effect)")
        }
        XCTAssertEqual(timeMs, 30)
        XCTAssertEqual(step.outcome?.finalObservation?.tree.viewportCapture.hierarchy.sortedElements.first?.label, "Ready")
    }

    func testMachineFingerprintChangeResetsStability() {
        let loading = makeParseResult([
            makeElement(label: "Loading", traits: .staticText),
        ])
        let ready = makeParseResult([
            makeElement(label: "Ready", traits: .staticText),
        ])
        let machine = SettleLoopMachine()
        var ledger = SettleObservationLedger()
        var state = SettleLoopMachine.State(
            policy: .consecutiveCycles(required: 2),
            tripwireBaseline: Self.tripwireSignal(topmostVC: nil)
        )

        XCTAssertContinue(reduceObservation(loading, elapsedMs: 0, machine: machine, ledger: &ledger, state: &state))
        XCTAssertContinue(reduceObservation(loading, elapsedMs: 1, machine: machine, ledger: &ledger, state: &state))
        XCTAssertContinue(reduceObservation(ready, elapsedMs: 2, machine: machine, ledger: &ledger, state: &state))
        XCTAssertContinue(reduceObservation(ready, elapsedMs: 3, machine: machine, ledger: &ledger, state: &state))
        let step = reduceObservation(ready, elapsedMs: 4, machine: machine, ledger: &ledger, state: &state)

        guard case .terminal(.settled(let timeMs)) = step.effect else {
            return XCTFail("Expected settled terminal effect after post-change stability, got \(step.effect)")
        }
        XCTAssertEqual(timeMs, 4)
        XCTAssertEqual(step.outcome?.finalObservation?.tree.viewportCapture.hierarchy.sortedElements.first?.label, "Ready")
    }

    func testMachineTripwireResetThenNilParseCannotReturnStaleFinalScreen() {
        let stale = makeParseResult([
            makeElement(label: "Stale", traits: .staticText),
        ])
        let baseline = Self.tripwireSignal(topmostVC: nil)
        let changedObject = NSObject()
        let changed = Self.tripwireSignal(topmostVC: ObjectIdentifier(changedObject))
        let machine = SettleLoopMachine()
        var ledger = SettleObservationLedger()
        var state = SettleLoopMachine.State(
            policy: .consecutiveCycles(required: 1),
            tripwireBaseline: baseline
        )

        XCTAssertContinue(reduceObservation(stale, elapsedMs: 0, machine: machine, ledger: &ledger, state: &state))
        XCTAssertContinue(send(.tripwireSignal(changed), machine: machine, ledger: &ledger, state: &state))
        let outcome = send(.timeout(elapsedMs: 10), machine: machine, ledger: &ledger, state: &state).outcome

        XCTAssertEqual(outcome?.outcome, .timedOut(timeMs: 10))
        XCTAssertNil(outcome?.finalObservation)
        XCTAssertEqual(outcome?.events, [.tripwireSignalChanged(from: baseline, to: changed)])
        _ = changedObject
    }

    func testMachineNotificationOnlyTripwireChangeDoesNotResetSettleBaseline() {
        let stable = makeParseResult([
            makeElement(label: "Stable", traits: .staticText),
        ])
        let baseline = Self.tripwireSignal(topmostVC: nil, accessibilityNotificationSequence: 1)
        let changed = Self.tripwireSignal(topmostVC: nil, accessibilityNotificationSequence: 2)
        let machine = SettleLoopMachine()
        var ledger = SettleObservationLedger()
        var state = SettleLoopMachine.State(
            policy: .consecutiveCycles(required: 1),
            tripwireBaseline: baseline
        )

        XCTAssertContinue(reduceObservation(stable, elapsedMs: 0, machine: machine, ledger: &ledger, state: &state))
        XCTAssertContinue(send(.tripwireSignal(changed), machine: machine, ledger: &ledger, state: &state))
        let step = reduceObservation(stable, elapsedMs: 1, machine: machine, ledger: &ledger, state: &state)

        guard case .terminal(.settled(let timeMs)) = step.effect else {
            return XCTFail("Expected notification-only signal to allow settle, got \(step.effect)")
        }
        XCTAssertEqual(timeMs, 1)
        XCTAssertEqual(step.outcome?.finalObservation?.tree.viewportCapture.hierarchy.sortedElements.first?.label, "Stable")
        XCTAssertTrue(state.events.isEmpty)
    }

    func testMachineCancellationTerminalEffectProjectsCancelledOutcome() {
        let stable = makeParseResult([
            makeElement(label: "Ready", traits: .staticText),
        ])
        let machine = SettleLoopMachine()
        var ledger = SettleObservationLedger()
        var state = SettleLoopMachine.State(
            policy: .consecutiveCycles(required: 2),
            tripwireBaseline: Self.tripwireSignal(topmostVC: nil)
        )
        XCTAssertContinue(reduceObservation(stable, elapsedMs: 0, machine: machine, ledger: &ledger, state: &state))

        let outcome = send(.yieldFailed(.cancellation, elapsedMs: 7), machine: machine, ledger: &ledger, state: &state).outcome

        XCTAssertEqual(outcome?.outcome, .cancelled(timeMs: 7))
        XCTAssertEqual(outcome?.finalObservation?.tree.viewportCapture.hierarchy.sortedElements.first?.label, "Ready")
    }

    func testMachineTimeoutTerminalEffectProjectsTimedOutOutcome() {
        let stable = makeParseResult([
            makeElement(label: "Ready", traits: .staticText),
        ])
        let machine = SettleLoopMachine()
        var ledger = SettleObservationLedger()
        var state = SettleLoopMachine.State(
            policy: .quietWindow(milliseconds: 30),
            tripwireBaseline: Self.tripwireSignal(topmostVC: nil)
        )
        XCTAssertContinue(reduceObservation(stable, elapsedMs: 0, machine: machine, ledger: &ledger, state: &state))

        let outcome = send(.timeout(elapsedMs: 99), machine: machine, ledger: &ledger, state: &state).outcome

        XCTAssertEqual(outcome?.outcome, .timedOut(timeMs: 99))
        XCTAssertEqual(outcome?.finalObservation?.tree.viewportCapture.hierarchy.sortedElements.first?.label, "Ready")
    }

    func testMachineNonCancellationYieldErrorProjectsTimedOutOutcome() {
        let stable = makeParseResult([
            makeElement(label: "Ready", traits: .staticText),
        ])
        let machine = SettleLoopMachine()
        var ledger = SettleObservationLedger()
        var state = SettleLoopMachine.State(
            policy: .quietWindow(milliseconds: 30),
            tripwireBaseline: Self.tripwireSignal(topmostVC: nil)
        )
        XCTAssertContinue(reduceObservation(stable, elapsedMs: 0, machine: machine, ledger: &ledger, state: &state))

        let step = send(.yieldFailed(.error, elapsedMs: 11), machine: machine, ledger: &ledger, state: &state)
        guard case .terminal(.yieldFailed(let timeMs)) = step.effect else {
            return XCTFail("Expected yieldFailed terminal effect, got \(step.effect)")
        }
        XCTAssertEqual(timeMs, 11)
        XCTAssertEqual(step.outcome?.outcome, .timedOut(timeMs: 11))
    }

    private func XCTAssertContinue(
        _ step: MachineStep,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case .continuePolling = step.effect else {
            return XCTFail("Expected continuePolling, got \(step.effect)", file: file, line: line)
        }
    }

    // MARK: - Stable Settle

    func testSemanticQuietSettleUsesQuietWindowInsteadOfFixedCycles() async {
        let element = makeElement(label: "Hello", traits: .staticText, frame: CGRect(x: 0, y: 0, width: 100, height: 30))
        let stable = makeParseResult([element])
        let clock = ManualClock()
        let yieldCount = Counter()
        let session = makeQuietSession(
            script: [stable],
            clock: clock,
            quietWindowMs: 30,
            yieldCount: yieldCount
        )

        let outcome = await session.run(
            start: clock.currentTime(),
            baselineTripwireSignal: Self.tripwireSignal(topmostVC: nil)
        )

        XCTAssertEqual(outcome.outcome, .settled(timeMs: 30))
        XCTAssertEqual(yieldCount.next(), 3)
    }

    func testSemanticQuietSettleResetsQuietWindowWhenFingerprintChanges() async {
        let first = makeParseResult([
            makeElement(label: "Loading", traits: .staticText, frame: CGRect(x: 0, y: 0, width: 100, height: 30)),
        ])
        let second = makeParseResult([
            makeElement(label: "Ready", traits: .staticText, frame: CGRect(x: 0, y: 0, width: 100, height: 30)),
        ])
        let clock = ManualClock()
        let session = makeQuietSession(
            script: [first, first, second, second, second, second],
            clock: clock,
            quietWindowMs: 30
        )

        let outcome = await session.run(
            start: clock.currentTime(),
            baselineTripwireSignal: Self.tripwireSignal(topmostVC: nil)
        )

        XCTAssertEqual(outcome.outcome, .settled(timeMs: 50))
        XCTAssertEqual(outcome.finalObservation?.tree.viewportCapture.hierarchy.sortedElements.first?.label, "Ready")
    }

    func testSemanticQuietSettleTripwireChangeResetsBaseline() async {
        let stable = makeParseResult([
            makeElement(label: "Ready", traits: .staticText, frame: CGRect(x: 0, y: 0, width: 100, height: 30)),
        ])
        let clock = ManualClock()
        let changedVC = ObjectIdentifier(UIViewController())
        let session = makeQuietSession(
            script: [stable],
            clock: clock,
            quietWindowMs: 30,
            topVCSequence: [changedVC, changedVC, changedVC, changedVC]
        )

        let outcome = await session.run(
            start: clock.currentTime(),
            baselineTripwireSignal: Self.tripwireSignal(topmostVC: nil)
        )

        XCTAssertEqual(outcome.outcome, .settled(timeMs: 50))
        XCTAssertEqual(outcome.events, [
            .tripwireSignalChanged(
                from: Self.tripwireSignal(topmostVC: nil),
                to: Self.tripwireSignal(topmostVC: changedVC)
            ),
        ])
    }

    func testSemanticQuietSettleNotificationOnlySignalsDoNotStarveParser() async {
        let stable = makeParseResult([
            makeElement(label: "Ready", traits: .staticText, frame: CGRect(x: 0, y: 0, width: 100, height: 30)),
        ])
        let clock = ManualClock()
        let session = makeQuietSession(
            script: [stable],
            clock: clock,
            quietWindowMs: 30,
            accessibilityNotificationSequence: [1, 2, 3, 4, 5]
        )

        let outcome = await session.run(
            start: clock.currentTime(),
            baselineTripwireSignal: Self.tripwireSignal(topmostVC: nil, accessibilityNotificationSequence: 0)
        )

        XCTAssertEqual(outcome.outcome, .settled(timeMs: 30))
        XCTAssertEqual(outcome.finalObservation?.tree.viewportCapture.hierarchy.sortedElements.first?.label, "Ready")
        XCTAssertTrue(outcome.events.isEmpty)
    }

    func testSemanticQuietSettleTimesOutWhenFingerprintNeverStabilizes() async {
        let clock = ManualClock()
        let counter = Counter()
        let session = SettleSession(
            parseProvider: {
                let index = counter.next()
                return self.makeParseResult([
                    self.makeElement(
                        label: "Tick \(index)",
                        traits: .staticText,
                        frame: CGRect(x: 0, y: 0, width: 100, height: 30)
                    ),
                ])
            },
            tripwireSignalProvider: { Self.tripwireSignal(topmostVC: nil) },
            observationYield: {
                clock.advance(milliseconds: 10)
            },
            clock: { clock.currentTime() },
            quietWindowMs: 30,
            timeoutMs: 50
        )

        let outcome = await session.run(
            start: clock.currentTime(),
            baselineTripwireSignal: Self.tripwireSignal(topmostVC: nil)
        )

        XCTAssertEqual(outcome.outcome, .timedOut(timeMs: 50))
        XCTAssertEqual(outcome.finalObservation?.tree.viewportCapture.hierarchy.sortedElements.first?.label, "Tick 5")
        XCTAssertNotNil(outcome.instabilityDescription)
    }

    func testSemanticQuietSettleReturnsCancelledWhenObservationYieldCancels() async {
        let stable = makeParseResult([
            makeElement(label: "Ready", traits: .staticText, frame: CGRect(x: 0, y: 0, width: 100, height: 30)),
        ])
        let clock = ManualClock()
        let session = SettleSession(
            parseProvider: { stable },
            tripwireSignalProvider: { Self.tripwireSignal(topmostVC: nil) },
            observationYield: {
                clock.advance(milliseconds: 10)
                throw CancellationError()
            },
            clock: { clock.currentTime() },
            quietWindowMs: 30,
            timeoutMs: 100
        )

        let outcome = await session.run(
            start: clock.currentTime(),
            baselineTripwireSignal: Self.tripwireSignal(topmostVC: nil)
        )

        XCTAssertEqual(outcome.outcome, .cancelled(timeMs: 10))
        XCTAssertEqual(outcome.finalObservation?.tree.viewportCapture.hierarchy.sortedElements.first?.label, "Ready")
    }

    func testSemanticQuietSettleIgnoresNilParsesUntilAStableScreenArrives() async {
        let stable = makeParseResult([
            makeElement(label: "Ready", traits: .staticText, frame: CGRect(x: 0, y: 0, width: 100, height: 30)),
        ])
        let clock = ManualClock()
        let session = makeQuietSession(
            script: [nil, nil, stable, stable, stable, stable],
            clock: clock,
            quietWindowMs: 30,
            timeoutMs: 100
        )

        let outcome = await session.run(
            start: clock.currentTime(),
            baselineTripwireSignal: Self.tripwireSignal(topmostVC: nil)
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
            cyclesRequired: 2,
            timeoutMs: 100
        )

        let outcome = await session.run(
            start: CFAbsoluteTimeGetCurrent(),
            baselineTripwireSignal: Self.tripwireSignal(topmostVC: nil)
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
            script: [stable, stable, stable, stable],
            cyclesRequired: 3
        )

        let outcome = await session.run(
            start: CFAbsoluteTimeGetCurrent(),
            baselineTripwireSignal: Self.tripwireSignal(topmostVC: nil)
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
        let element = makeElement(label: "Unchanged", traits: .staticText)
        let stable = makeParseResult([element])
        let session = makeSession(
            script: [stable, stable, stable],
            cyclesRequired: 2
        )

        let outcome = await session.run(
            start: CFAbsoluteTimeGetCurrent(),
            baselineTripwireSignal: Self.tripwireSignal(topmostVC: nil)
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

        XCTAssertEqual(
            SettleTimeline.fingerprint(of: [first], bucket: 13),
            SettleTimeline.fingerprint(of: [jittered], bucket: 13),
            "iPad scroll-view content-offset jitter should not reset settle"
        )
        XCTAssertNotEqual(
            SettleTimeline.fingerprint(of: [first], bucket: 13),
            SettleTimeline.fingerprint(of: [moved], bucket: 13),
            "movement across coarse frame buckets should reset settle"
        )
        XCTAssertNotEqual(
            SettleTimeline.fingerprint(of: [first], bucket: 13),
            SettleTimeline.fingerprint(of: [valueChanged], bucket: 13)
        )
        XCTAssertNotEqual(
            SettleTimeline.fingerprint(of: [first], bucket: 13),
            SettleTimeline.fingerprint(of: [labelChanged], bucket: 13)
        )
        XCTAssertNotEqual(
            SettleTimeline.fingerprint(of: [first], bucket: 13),
            SettleTimeline.fingerprint(of: [identifierChanged], bucket: 13)
        )
        XCTAssertNotEqual(
            SettleTimeline.fingerprint(of: [first], bucket: 13),
            SettleTimeline.fingerprint(of: [traitsChanged], bucket: 13)
        )
        XCTAssertNotEqual(
            SettleTimeline.fingerprint(of: [first], bucket: 13),
            SettleTimeline.fingerprint(of: [first, second], bucket: 13),
            "element count is semantic settle state"
        )
        XCTAssertNotEqual(
            SettleTimeline.fingerprint(of: [first, second], bucket: 13),
            SettleTimeline.fingerprint(of: [second, first], bucket: 13),
            "settle fingerprint intentionally preserves traversal order"
        )
    }

    func testTimelineKeysUseSharedCoarseFrameComparisonForIPadJitter() {
        let first = makeElement(
            label: "Cash",
            traits: .staticText,
            frame: CGRect(x: 244, y: 423, width: 42, height: 72)
        )
        let jittered = makeElement(
            label: "Cash",
            traits: .staticText,
            frame: CGRect(x: 244, y: 428, width: 42, height: 72)
        )

        XCTAssertEqual(first.timelineKey(bucket: 13), jittered.timelineKey(bucket: 13))
    }

    // MARK: - Timeout

    func testFrameJitterInsideCoarseBucketSettlesAndKeepsFinalFrame() async {
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
        let session = makeSession(
            script: [
                makeParseResult([first]),
                makeParseResult([jittered]),
                makeParseResult([first]),
                makeParseResult([jittered]),
            ],
            cyclesRequired: 3
        )

        let outcome = await session.run(
            start: CFAbsoluteTimeGetCurrent(),
            baselineTripwireSignal: Self.tripwireSignal(topmostVC: nil)
        )

        guard case .settled = outcome.outcome else {
            return XCTFail("Expected frame jitter inside the bucket to settle, got \(outcome.outcome)")
        }
        XCTAssertNil(outcome.instabilityDescription)
        XCTAssertEqual(outcome.finalObservation?.tree.viewportCapture.hierarchy.sortedElements.first?.shape.frame.origin.y, 428)
    }

    func testFrameJitterInsideCoarseBucketDoesNotProduceChangeDescription() {
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

        XCTAssertNil(SettleTimeline.changeDescription(from: [first], to: [jittered], bucket: 13))
    }

    func testChangeDescriptionNamesChangedFieldsAndIsBounded() {
        let before = [
            makeElement(
                label: "Old",
                value: "offline",
                identifier: "old_id",
                traits: .button,
                frame: CGRect(x: 561, y: 423, width: 90, height: 72)
            ),
            makeElement(label: "Second", traits: .staticText),
            makeElement(label: "Third", traits: .staticText),
            makeElement(label: "Fourth", traits: .staticText),
            makeElement(label: "Fifth", traits: .staticText),
        ]
        let after = [
            makeElement(
                label: "New",
                value: "online",
                identifier: "new_id",
                traits: .staticText,
                frame: CGRect(x: 561, y: 467, width: 90, height: 72)
            ),
            makeElement(label: "Second changed", traits: .staticText),
            makeElement(label: "Third changed", traits: .staticText),
            makeElement(label: "Fourth changed", traits: .staticText),
            makeElement(label: "Fifth changed", traits: .staticText),
            makeElement(label: "Sixth", traits: .staticText),
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
        let counter = Counter()
        let session = SettleSession(
            parseProvider: { [weak self] in
                guard let self else { return nil }
                let value = counter.next()
                return self.makeParseResult([
                    self.makeElement(label: "label-\(value)", traits: .staticText)
                ])
            },
            tripwireSignalProvider: { Self.tripwireSignal(topmostVC: nil) },
            // Real (small) sleeps so wall clock advances; a no-op sleeper
            // would let the loop reach a finite-script end before the
            // timeout fires.
            // swiftlint:disable:next agent_test_task_sleep
            sleeper: { try await Task.sleep(nanoseconds: $0) },
            cyclesRequired: 3,
            cycleIntervalMs: 5,
            timeoutMs: 50
        )

        let outcome = await session.run(
            start: CFAbsoluteTimeGetCurrent(),
            baselineTripwireSignal: Self.tripwireSignal(topmostVC: nil)
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
        let counter = Counter()
        let session = SettleSession(
            parseProvider: { [weak self] in
                guard let self else { return nil }
                let value = counter.next()
                let y: CGFloat = value.isMultiple(of: 2) ? 423 : 467
                return self.makeParseResult([
                    self.makeElement(
                        label: "$ 9 Cash",
                        traits: .button,
                        frame: CGRect(x: 561, y: y, width: 90, height: 72)
                    ),
                ])
            },
            tripwireSignalProvider: { Self.tripwireSignal(topmostVC: nil) },
            // swiftlint:disable:next agent_test_task_sleep
            sleeper: { try await Task.sleep(nanoseconds: $0) },
            cyclesRequired: 3,
            cycleIntervalMs: 5,
            timeoutMs: 50
        )

        let outcome = await session.run(
            start: CFAbsoluteTimeGetCurrent(),
            baselineTripwireSignal: Self.tripwireSignal(topmostVC: nil)
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

    // MARK: - InterfaceObservation Change

    func testTripwireTriggerResetsBaselineAndSettlesCleanly() async {
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

        let outcome = await session.run(
            start: CFAbsoluteTimeGetCurrent(),
            baselineTripwireSignal: Self.tripwireSignal(topmostVC: nil)
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
        let before = makeElement(label: "Display", traits: .header)
        let after = makeElement(label: "Controls Demo", traits: .header)
        let liveObject = NSObject()
        let livePostTransition = ObjectIdentifier(liveObject)
        let session = makeSession(
            script: [
                makeParseResult([before]),
                makeParseResult([before]),
                makeParseResult([after]),
                makeParseResult([after]),
                makeParseResult([after])
            ],
            cyclesRequired: 2,
            cycleIntervalMs: 1,
            timeoutMs: 100,
            topVCSequence: [livePostTransition, livePostTransition, livePostTransition, livePostTransition]
        )

        let outcome = await session.run(
            start: CFAbsoluteTimeGetCurrent(),
            baselineTripwireSignal: Self.tripwireSignal(topmostVC: nil)
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
        let before = makeElement(label: "Before", traits: .header)
        let loading = makeElement(label: "Loading", traits: .staticText)
        let after = makeElement(label: "After", traits: .header)
        let baselineObject = NSObject()
        let liveObject = NSObject()
        let baseline = ObjectIdentifier(baselineObject)
        let livePostTransition = ObjectIdentifier(liveObject)
        let session = makeSession(
            script: [
                makeParseResult([before]),
                makeParseResult([before]),
                makeParseResult([loading]),
                makeParseResult([after]),
                makeParseResult([after]),
                makeParseResult([after])
            ],
            cyclesRequired: 2,
            cycleIntervalMs: 1,
            timeoutMs: 100,
            topVCSequence: [baseline, livePostTransition, livePostTransition, livePostTransition, livePostTransition]
        )

        let outcome = await session.run(
            start: CFAbsoluteTimeGetCurrent(),
            baselineTripwireSignal: Self.tripwireSignal(topmostVC: baseline)
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

        let outcome = await session.run(
            start: CFAbsoluteTimeGetCurrent(),
            baselineTripwireSignal: Self.tripwireSignal(topmostVC: baseline)
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

        let outcome = await session.run(
            start: CFAbsoluteTimeGetCurrent(),
            baselineTripwireSignal: Self.tripwireSignal(topmostVC: baseline)
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

    // MARK: - Cancellation

    func testCancellationPropagatesAsCancelledOutcome() async {
        let stable = makeParseResult([makeElement(label: "A")])
        let session = SettleSession(
            parseProvider: { stable },
            tripwireSignalProvider: { Self.tripwireSignal(topmostVC: nil) },
            sleeper: { _ in throw CancellationError() },
            cyclesRequired: 3,
            cycleIntervalMs: 1,
            timeoutMs: 200
        )

        let outcome = await session.run(
            start: CFAbsoluteTimeGetCurrent(),
            baselineTripwireSignal: Self.tripwireSignal(topmostVC: nil)
        )

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
            tripwireSignalProvider: { Self.tripwireSignal(topmostVC: nil) },
            sleeper: { _ in throw DummyError() },
            cyclesRequired: 3,
            cycleIntervalMs: 1,
            timeoutMs: 200
        )

        let outcome = await session.run(
            start: CFAbsoluteTimeGetCurrent(),
            baselineTripwireSignal: Self.tripwireSignal(topmostVC: nil)
        )

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

        let outcome = await session.run(
            start: CFAbsoluteTimeGetCurrent(),
            baselineTripwireSignal: Self.tripwireSignal(topmostVC: nil)
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

        let outcome = await session.run(
            start: CFAbsoluteTimeGetCurrent(),
            baselineTripwireSignal: Self.tripwireSignal(topmostVC: nil)
        )

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

    func testTransientSpinnerCapturedOnCleanSameScreenSettle() async {
        let content = makeElement(label: "Content", traits: .staticText)
        let spinner = makeElement(label: "Loading", traits: .staticText)
        let stable = makeParseResult([content])
        let session = makeSession(
            script: [
                stable,
                makeParseResult([content, spinner]),
                stable,
                stable
            ],
            cyclesRequired: 2
        )

        let outcome = await session.run(
            start: CFAbsoluteTimeGetCurrent(),
            baselineTripwireSignal: Self.tripwireSignal(topmostVC: nil)
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
