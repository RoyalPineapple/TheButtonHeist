#if canImport(UIKit)
import XCTest
@testable import AccessibilitySnapshotParser
import ButtonHeistSupport
@testable import TheInsideJob
@testable import TheScore

@MainActor
extension SettleSessionTests {

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
        return reduce(
            .observation(recordedObservation.sample, elapsedMs: elapsedMs),
            machine: machine,
            ledger: &ledger,
            state: &state
        )
    }

    private func reduce(
        _ event: SettleLoopMachine.Event,
        machine: SettleLoopMachine,
        ledger: inout SettleObservationLedger,
        state: inout SettleLoopMachine.State
    ) -> MachineStep {
        let transition = machine.reduce(state, event: event)
        state = transition.state
        let result: SettleSession.Result?
        switch transition.decision {
        case .continuePolling:
            result = nil
        case .baselineReset:
            ledger.resetCurrentGeneration()
            result = nil
        case .terminal(let outcome):
            result = SettleSession.result(
                outcome: outcome,
                state: transition.state,
                observations: ledger
            )
        }
        return MachineStep(
            decision: transition.decision,
            result: result
        )
    }

    private struct MachineStep {
        let decision: SettleLoopMachine.Decision
        let result: SettleSession.Result?
    }

    private func XCTAssertContinue(
        _ step: MachineStep,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case .continuePolling = step.decision else {
            return XCTFail("Expected continuePolling, got \(step.decision)", file: file, line: line)
        }
    }

    private func XCTAssertBaselineReset(
        _ step: MachineStep,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case .baselineReset = step.decision else {
            return XCTFail("Expected baselineReset, got \(step.decision)", file: file, line: line)
        }
    }

    func testSemanticObservationDeadlineOwnsRemainingAndElapsedTime() {
        let start = RuntimeElapsed.now
        let deadline = SemanticObservationDeadline(start: start, timeoutSeconds: 0.25)

        XCTAssertTrue(deadline.hasTimeRemaining(at: start.advanced(by: .milliseconds(100))))
        XCTAssertEqual(
            deadline.remainingSeconds(at: start.advanced(by: .milliseconds(100))),
            0.15,
            accuracy: 0.000_001
        )
        XCTAssertEqual(deadline.elapsedMilliseconds(at: start.advanced(by: .milliseconds(125))), 125)
        XCTAssertFalse(deadline.hasTimeRemaining(at: start.advanced(by: .milliseconds(250))))
        XCTAssertEqual(deadline.remainingSeconds(at: start.advanced(by: .milliseconds(500))), 0)

        let reservationStart = start.advanced(by: .milliseconds(100))
        let terminalWakeDeadline = deadline.reserving(0.05, at: reservationStart)
        XCTAssertEqual(terminalWakeDeadline.start, reservationStart)
        XCTAssertEqual(terminalWakeDeadline.remainingSeconds(at: reservationStart), 0.1, accuracy: 0.000_001)
        XCTAssertFalse(terminalWakeDeadline.hasTimeRemaining(at: reservationStart.advanced(by: .milliseconds(100))))

        let millisecondDeadline = SemanticObservationDeadline(start: start, timeoutMs: 250)
        XCTAssertEqual(
            millisecondDeadline.remainingSeconds(at: start.advanced(by: .milliseconds(100))),
            0.15,
            accuracy: 0.000_001
        )

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
            tripwireSignalProvider: { self.tripwireSignal(topmostVC: nil) },
            sleeper: { _ in },
            cycleIntervalMs: 0,
            timeoutMs: SettleSession.viewportTransitionTimeoutMs
        )

        let outcome = await session.run(
            start: RuntimeElapsed.now,
            baselineTripwireSignal: tripwireSignal(topmostVC: nil)
        )

        XCTAssertTrue(outcome.outcome.didSettleCleanly)
        XCTAssertEqual(parseCount.next(), 2)
    }

    func testViewportTransitionSettleRejectsOneStaleRepeatAfterMovement() async {
        let loading = makeParseResult([
            makeElement(label: "Loading", traits: .staticText),
        ])
        let ready = makeParseResult([
            makeElement(label: "Ready", traits: .staticText),
        ])
        // The tree must move before it repeats: a repeat of `loading` would
        // settle the run before the movement was ever observed.
        let script = ScriptBox(script: [loading, ready, ready])
        let parseCount = Counter()
        let session = SettleSession(
            parseProvider: {
                _ = parseCount.next()
                return script.next()
            },
            tripwireSignalProvider: { self.tripwireSignal(topmostVC: nil) },
            sleeper: { _ in },
            cycleIntervalMs: 0,
            timeoutMs: SettleSession.viewportTransitionTimeoutMs
        )

        let outcome = await session.run(
            start: RuntimeElapsed.now,
            baselineTripwireSignal: tripwireSignal(topmostVC: nil)
        )

        XCTAssertTrue(outcome.outcome.didSettleCleanly)
        XCTAssertEqual(parseCount.next(), 3)
        XCTAssertEqual(
            outcome.finalObservation?.tree.viewportCapture.hierarchy.sortedElements.first?.label,
            "Ready"
        )
    }

    func testMachineSettlesOnTheFirstRepeatRegardlessOfCadence() {
        let stable = makeParseResult([
            makeElement(label: "Ready", traits: .staticText),
        ])
        let machine = SettleLoopMachine()
        var ledger = SettleObservationLedger()
        var state = SettleLoopMachine.State(
            tripwireBaseline: tripwireSignal(topmostVC: nil)
        )

        XCTAssertContinue(reduceObservation(stable, elapsedMs: 0, machine: machine, ledger: &ledger, state: &state))
        let step = reduceObservation(stable, elapsedMs: 1, machine: machine, ledger: &ledger, state: &state)

        guard case .terminal(.settled(let timeMs)) = step.decision else {
            return XCTFail("Expected settled terminal decision, got \(step.decision)")
        }
        XCTAssertEqual(timeMs, 1)
        XCTAssertEqual(step.result?.finalObservation?.tree.viewportCapture.hierarchy.sortedElements.first?.label, "Ready")
    }

    func testMachineSettlesOnOneNoChange() {
        let stable = makeParseResult([
            makeElement(label: "Ready", traits: .staticText),
        ])
        let machine = SettleLoopMachine()
        var ledger = SettleObservationLedger()
        var state = SettleLoopMachine.State(
            tripwireBaseline: tripwireSignal(topmostVC: nil)
        )

        // The first reading seeds the comparison; the next one that comes back
        // equal is the whole settle rule. A third look adds nothing.
        XCTAssertContinue(reduceObservation(stable, elapsedMs: 0, machine: machine, ledger: &ledger, state: &state))
        let step = reduceObservation(stable, elapsedMs: 10, machine: machine, ledger: &ledger, state: &state)

        guard case .terminal(.settled(let timeMs)) = step.decision else {
            return XCTFail("Expected settled terminal decision, got \(step.decision)")
        }
        XCTAssertEqual(timeMs, 10)
        XCTAssertEqual(step.result?.finalObservation?.tree.viewportCapture.hierarchy.sortedElements.first?.label, "Ready")
    }

    func testMachineCarriesTheObservationDeltaOnTheSettledResult() {
        let loading = makeParseResult([
            makeElement(label: "Loading", traits: .staticText),
        ])
        let ready = makeParseResult([
            makeElement(label: "Ready", traits: .staticText),
        ])
        let machine = SettleLoopMachine()
        var ledger = SettleObservationLedger()
        var state = SettleLoopMachine.State(
            tripwireBaseline: tripwireSignal(topmostVC: nil)
        )

        XCTAssertContinue(reduceObservation(loading, elapsedMs: 0, machine: machine, ledger: &ledger, state: &state))
        let changed = reduceObservation(ready, elapsedMs: 20, machine: machine, ledger: &ledger, state: &state)
        XCTAssertContinue(changed)
        let step = reduceObservation(ready, elapsedMs: 21, machine: machine, ledger: &ledger, state: &state)

        guard case .terminal(.settled(let timeMs)) = step.decision else {
            return XCTFail("Expected one unchanged diff to settle, got \(step.decision)")
        }
        XCTAssertEqual(timeMs, 21)
        let delta = try? XCTUnwrap(step.result?.delta)
        XCTAssertEqual(delta?.isUnchanged, true, "a clean settle must report an unchanged diff")
        XCTAssertNil(delta?.changeDescription)
        XCTAssertEqual(
            step.result?.finalObservation?.tree.viewportCapture.hierarchy.sortedElements.first?.label,
            "Ready"
        )
    }

    func testMachineDeltaNamesTheFieldThatFalsifiedStability() {
        let loading = makeParseResult([
            makeElement(label: "Loading", traits: .staticText),
        ])
        let ready = makeParseResult([
            makeElement(label: "Ready", traits: .staticText),
        ])
        let machine = SettleLoopMachine()
        var ledger = SettleObservationLedger()
        var state = SettleLoopMachine.State(
            tripwireBaseline: tripwireSignal(topmostVC: nil)
        )

        XCTAssertContinue(reduceObservation(loading, elapsedMs: 0, machine: machine, ledger: &ledger, state: &state))
        XCTAssertContinue(reduceObservation(ready, elapsedMs: 10, machine: machine, ledger: &ledger, state: &state))

        let result = SettleSession.result(
            outcome: .timedOut(timeMs: 10),
            state: state,
            observations: ledger
        )

        XCTAssertFalse(result.delta.isUnchanged)
        XCTAssertEqual(result.delta.elementChanges.count, 1)
        XCTAssertEqual(result.delta.elementChanges.first?.index, 0)
        XCTAssertTrue(
            result.delta.changeDescription?.contains("label \"Loading\"->\"Ready\"") == true,
            result.delta.changeDescription ?? "missing change description"
        )
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
            tripwireBaseline: tripwireSignal(topmostVC: nil)
        )

        // A change mid-run resets the comparison, so the repeat that settles is
        // the one after the change, not the one before it.
        XCTAssertContinue(reduceObservation(loading, elapsedMs: 0, machine: machine, ledger: &ledger, state: &state))
        XCTAssertContinue(reduceObservation(ready, elapsedMs: 1, machine: machine, ledger: &ledger, state: &state))
        let step = reduceObservation(ready, elapsedMs: 2, machine: machine, ledger: &ledger, state: &state)

        guard case .terminal(.settled(let timeMs)) = step.decision else {
            return XCTFail("Expected settled terminal decision after post-change stability, got \(step.decision)")
        }
        XCTAssertEqual(timeMs, 2)
        XCTAssertEqual(step.result?.finalObservation?.tree.viewportCapture.hierarchy.sortedElements.first?.label, "Ready")
    }

    func testMachineTripwireResetThenNilParseCannotReturnStaleFinalScreen() {
        let stale = makeParseResult([
            makeElement(label: "Stale", traits: .staticText),
        ])
        let baseline = tripwireSignal(topmostVC: nil)
        let changedObject = NSObject()
        let changed = tripwireSignal(topmostVC: ObjectIdentifier(changedObject))
        let machine = SettleLoopMachine()
        var ledger = SettleObservationLedger()
        var state = SettleLoopMachine.State(
            tripwireBaseline: baseline
        )

        XCTAssertContinue(reduceObservation(stale, elapsedMs: 0, machine: machine, ledger: &ledger, state: &state))
        XCTAssertBaselineReset(reduce(.tripwireSignal(changed), machine: machine, ledger: &ledger, state: &state))
        let result = SettleSession.result(
            outcome: .timedOut(timeMs: 10),
            state: state,
            observations: ledger
        )

        XCTAssertEqual(result.outcome, .timedOut(timeMs: 10))
        XCTAssertNil(result.finalObservation)
        _ = changedObject
    }

    /// A tripwire reset throws away the reading it had, so the run cannot settle
    /// on the very next observation however identical it looks — there is
    /// nothing to compare it against yet. It re-seeds, and the no-change comes
    /// one observation later.
    func testMachineTripwireResetDiscardsTheReadingItHad() {
        let stable = makeParseResult([
            makeElement(label: "Stable", traits: .staticText),
        ])
        let baseline = tripwireSignal(topmostVC: nil)
        let changedObject = NSObject()
        let changed = tripwireSignal(topmostVC: ObjectIdentifier(changedObject))

        let machine = SettleLoopMachine()
        var ledger = SettleObservationLedger()
        var state = SettleLoopMachine.State(tripwireBaseline: baseline)

        XCTAssertContinue(reduceObservation(stable, elapsedMs: 0, machine: machine, ledger: &ledger, state: &state))
        XCTAssertBaselineReset(reduce(.tripwireSignal(changed), machine: machine, ledger: &ledger, state: &state))

        // The re-seed has nothing to compare against, so it cannot settle here.
        XCTAssertContinue(
            reduceObservation(stable, elapsedMs: 1, machine: machine, ledger: &ledger, state: &state)
        )

        let step = reduceObservation(stable, elapsedMs: 2, machine: machine, ledger: &ledger, state: &state)
        guard case .terminal(.settled(let timeMs)) = step.decision else {
            return XCTFail("Expected a settle once the reading repeated, got \(step.decision)")
        }
        XCTAssertEqual(timeMs, 2)
        _ = changedObject
    }

    func testMachineNotificationOnlyTripwireChangeDoesNotResetSettleBaseline() {
        let stable = makeParseResult([
            makeElement(label: "Stable", traits: .staticText),
        ])
        let baseline = tripwireSignal(topmostVC: nil, accessibilityNotificationSequence: 1)
        let changed = tripwireSignal(topmostVC: nil, accessibilityNotificationSequence: 2)
        let machine = SettleLoopMachine()
        var ledger = SettleObservationLedger()
        var state = SettleLoopMachine.State(
            tripwireBaseline: baseline
        )

        XCTAssertContinue(reduceObservation(stable, elapsedMs: 0, machine: machine, ledger: &ledger, state: &state))
        XCTAssertContinue(reduce(.tripwireSignal(changed), machine: machine, ledger: &ledger, state: &state))
        let step = reduceObservation(stable, elapsedMs: 1, machine: machine, ledger: &ledger, state: &state)

        guard case .terminal(.settled(let timeMs)) = step.decision else {
            return XCTFail("Expected notification-only signal to allow settle, got \(step.decision)")
        }
        XCTAssertEqual(timeMs, 1)
        XCTAssertEqual(step.result?.finalObservation?.tree.viewportCapture.hierarchy.sortedElements.first?.label, "Stable")
    }

    func testResultProjectsCancelledOutcomeFromCurrentSettleState() {
        let stable = makeParseResult([
            makeElement(label: "Ready", traits: .staticText),
        ])
        let machine = SettleLoopMachine()
        var ledger = SettleObservationLedger()
        var state = SettleLoopMachine.State(
            tripwireBaseline: tripwireSignal(topmostVC: nil)
        )
        XCTAssertContinue(reduceObservation(stable, elapsedMs: 0, machine: machine, ledger: &ledger, state: &state))

        let result = SettleSession.result(
            outcome: .cancelled(timeMs: 7),
            state: state,
            observations: ledger
        )

        XCTAssertEqual(result.outcome, .cancelled(timeMs: 7))
        XCTAssertEqual(result.finalObservation?.tree.viewportCapture.hierarchy.sortedElements.first?.label, "Ready")
    }

    func testResultProjectsTimedOutOutcomeFromCurrentSettleState() {
        let stable = makeParseResult([
            makeElement(label: "Ready", traits: .staticText),
        ])
        let machine = SettleLoopMachine()
        var ledger = SettleObservationLedger()
        var state = SettleLoopMachine.State(
            tripwireBaseline: tripwireSignal(topmostVC: nil)
        )
        XCTAssertContinue(reduceObservation(stable, elapsedMs: 0, machine: machine, ledger: &ledger, state: &state))

        let result = SettleSession.result(
            outcome: .timedOut(timeMs: 99),
            state: state,
            observations: ledger
        )

        XCTAssertEqual(result.outcome, .timedOut(timeMs: 99))
        XCTAssertEqual(result.finalObservation?.tree.viewportCapture.hierarchy.sortedElements.first?.label, "Ready")
    }

    /// A stopped pulse and a slow app are different failures. The loop must not
    /// blame the app for a clock that never ticked.
    func testStoppedClockReportsUnavailableRatherThanTimedOut() async {
        let stable = makeParseResult([
            makeElement(label: "Ready", traits: .staticText),
        ])
        let clock = ManualClock()
        let session = makeClockedSession(
            script: [stable],
            clock: clock,
            timeoutMs: 500,
            tick: { .unavailable }
        )

        let outcome = await session.run(
            start: clock.currentTime(),
            baselineTripwireSignal: tripwireSignal(topmostVC: nil)
        )

        XCTAssertEqual(outcome.outcome, .clockUnavailable(timeMs: 10))
        XCTAssertFalse(outcome.outcome.didSettleCleanly)
    }

    func testSlowAppStillReportsTimedOutWhenTheClockKeepsTicking() async {
        let counter = Counter()
        let clock = ManualClock()
        let session = SettleSession(
            parseProvider: {
                self.makeParseResult([
                    self.makeElement(label: "Tick \(counter.next())", traits: .staticText),
                ])
            },
            tripwireSignalProvider: { self.tripwireSignal(topmostVC: nil) },
            observationYield: { _ in
                clock.advance(milliseconds: 10)
                return .observed
            },
            clock: { clock.currentTime() },
            timeoutMs: 50
        )

        let outcome = await session.run(
            start: clock.currentTime(),
            baselineTripwireSignal: tripwireSignal(topmostVC: nil)
        )

        XCTAssertEqual(outcome.outcome, .timedOut(timeMs: 50))
    }
}
#endif // canImport(UIKit)
