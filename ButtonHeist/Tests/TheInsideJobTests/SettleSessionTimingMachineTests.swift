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
        let eventCount = state.events.count
        let transition = machine.reduce(state, event: event)
        state = transition.state
        if state.events.count > eventCount {
            ledger.resetCurrentGeneration()
        }
        let result: SettleSession.Result? = switch transition.decision {
        case .continuePolling:
            nil
        case .terminal(let outcome):
            SettleSession.result(
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

    func testViewportTransitionSettleUsesTwoRunLoopTurnsWhenTheRepeatsAreStable() async {
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
            cyclesRequired: 2,
            cycleIntervalMs: 0,
            timeoutMs: SettleSession.viewportTransitionTimeoutMs
        )

        let outcome = await session.run(
            start: RuntimeElapsed.now,
            baselineTripwireSignal: tripwireSignal(topmostVC: nil)
        )

        XCTAssertTrue(outcome.outcome.didSettleCleanly)
        XCTAssertEqual(parseCount.next(), 3)
    }

    func testViewportTransitionSettleRejectsOneStaleRepeatAfterMovement() async {
        let loading = makeParseResult([
            makeElement(label: "Loading", traits: .staticText),
        ])
        let ready = makeParseResult([
            makeElement(label: "Ready", traits: .staticText),
        ])
        let script = ScriptBox(script: [loading, loading, ready, ready, ready])
        let parseCount = Counter()
        let session = SettleSession(
            parseProvider: {
                _ = parseCount.next()
                return script.next()
            },
            tripwireSignalProvider: { self.tripwireSignal(topmostVC: nil) },
            sleeper: { _ in },
            cyclesRequired: 2,
            cycleIntervalMs: 0,
            timeoutMs: SettleSession.viewportTransitionTimeoutMs
        )

        let outcome = await session.run(
            start: RuntimeElapsed.now,
            baselineTripwireSignal: tripwireSignal(topmostVC: nil)
        )

        XCTAssertTrue(outcome.outcome.didSettleCleanly)
        XCTAssertEqual(parseCount.next(), 5)
        XCTAssertEqual(
            outcome.finalObservation?.tree.viewportCapture.hierarchy.sortedElements.first?.label,
            "Ready"
        )
    }

    func testMachineSettlesFixedCadenceAfterRequiredConsecutiveCycles() {
        let stable = makeParseResult([
            makeElement(label: "Ready", traits: .staticText),
        ])
        let machine = SettleLoopMachine()
        var ledger = SettleObservationLedger()
        var state = SettleLoopMachine.State(
            policy: .consecutiveCycles(required: 2),
            tripwireBaseline: tripwireSignal(topmostVC: nil)
        )

        XCTAssertContinue(reduceObservation(stable, elapsedMs: 0, machine: machine, ledger: &ledger, state: &state))
        XCTAssertContinue(reduceObservation(stable, elapsedMs: 1, machine: machine, ledger: &ledger, state: &state))
        let step = reduceObservation(stable, elapsedMs: 2, machine: machine, ledger: &ledger, state: &state)

        guard case .terminal(.settled(let timeMs)) = step.decision else {
            return XCTFail("Expected settled terminal decision, got \(step.decision)")
        }
        XCTAssertEqual(timeMs, 2)
        XCTAssertEqual(step.result?.finalObservation?.tree.viewportCapture.hierarchy.sortedElements.first?.label, "Ready")
    }

    func testMachineSettlesQuietWindowAfterFingerprintRemainsStableForWindow() {
        let stable = makeParseResult([
            makeElement(label: "Ready", traits: .staticText),
        ])
        let machine = SettleLoopMachine()
        var ledger = SettleObservationLedger()
        var state = SettleLoopMachine.State(
            policy: .quietWindow(milliseconds: 30),
            tripwireBaseline: tripwireSignal(topmostVC: nil)
        )

        XCTAssertContinue(reduceObservation(stable, elapsedMs: 0, machine: machine, ledger: &ledger, state: &state))
        XCTAssertContinue(reduceObservation(stable, elapsedMs: 20, machine: machine, ledger: &ledger, state: &state))
        let step = reduceObservation(stable, elapsedMs: 30, machine: machine, ledger: &ledger, state: &state)

        guard case .terminal(.settled(let timeMs)) = step.decision else {
            return XCTFail("Expected settled terminal decision, got \(step.decision)")
        }
        XCTAssertEqual(timeMs, 30)
        XCTAssertEqual(step.result?.finalObservation?.tree.viewportCapture.hierarchy.sortedElements.first?.label, "Ready")
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
            tripwireBaseline: tripwireSignal(topmostVC: nil)
        )

        XCTAssertContinue(reduceObservation(loading, elapsedMs: 0, machine: machine, ledger: &ledger, state: &state))
        XCTAssertContinue(reduceObservation(loading, elapsedMs: 1, machine: machine, ledger: &ledger, state: &state))
        XCTAssertContinue(reduceObservation(ready, elapsedMs: 2, machine: machine, ledger: &ledger, state: &state))
        XCTAssertContinue(reduceObservation(ready, elapsedMs: 3, machine: machine, ledger: &ledger, state: &state))
        let step = reduceObservation(ready, elapsedMs: 4, machine: machine, ledger: &ledger, state: &state)

        guard case .terminal(.settled(let timeMs)) = step.decision else {
            return XCTFail("Expected settled terminal decision after post-change stability, got \(step.decision)")
        }
        XCTAssertEqual(timeMs, 4)
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
            policy: .consecutiveCycles(required: 1),
            tripwireBaseline: baseline
        )

        XCTAssertContinue(reduceObservation(stale, elapsedMs: 0, machine: machine, ledger: &ledger, state: &state))
        XCTAssertContinue(reduce(.tripwireSignal(changed), machine: machine, ledger: &ledger, state: &state))
        let result = SettleSession.result(
            outcome: .timedOut(timeMs: 10),
            state: state,
            observations: ledger
        )

        XCTAssertEqual(result.outcome, .timedOut(timeMs: 10))
        XCTAssertNil(result.finalObservation)
        XCTAssertEqual(result.events, [.tripwireSignalChanged(from: baseline, to: changed)])
        _ = changedObject
    }

    func testMachineTripwireResetRestartsBothPolicyCriteria() {
        let stable = makeParseResult([
            makeElement(label: "Stable", traits: .staticText),
        ])
        let baseline = tripwireSignal(topmostVC: nil)
        let changedObject = NSObject()
        let changed = tripwireSignal(topmostVC: ObjectIdentifier(changedObject))

        for policy in [
            SettlePolicy.consecutiveCycles(required: 1),
            .quietWindow(milliseconds: 1),
        ] {
            let machine = SettleLoopMachine()
            var ledger = SettleObservationLedger()
            var state = SettleLoopMachine.State(
                policy: policy,
                tripwireBaseline: baseline
            )

            XCTAssertContinue(reduceObservation(stable, elapsedMs: 0, machine: machine, ledger: &ledger, state: &state))
            XCTAssertContinue(reduce(.tripwireSignal(changed), machine: machine, ledger: &ledger, state: &state))
            XCTAssertContinue(reduceObservation(stable, elapsedMs: 1, machine: machine, ledger: &ledger, state: &state))
            let step = reduceObservation(stable, elapsedMs: 2, machine: machine, ledger: &ledger, state: &state)

            guard case .terminal(.settled(let timeMs)) = step.decision else {
                return XCTFail("Expected post-reset settle for \(policy), got \(step.decision)")
            }
            XCTAssertEqual(timeMs, 2)
            XCTAssertEqual(step.result?.events, [.tripwireSignalChanged(from: baseline, to: changed)])
        }
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
            policy: .consecutiveCycles(required: 1),
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
        XCTAssertTrue(state.events.isEmpty)
    }

    func testResultProjectsCancelledOutcomeFromCurrentSettleState() {
        let stable = makeParseResult([
            makeElement(label: "Ready", traits: .staticText),
        ])
        let machine = SettleLoopMachine()
        var ledger = SettleObservationLedger()
        var state = SettleLoopMachine.State(
            policy: .consecutiveCycles(required: 2),
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
            policy: .quietWindow(milliseconds: 30),
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
}
#endif // canImport(UIKit)
