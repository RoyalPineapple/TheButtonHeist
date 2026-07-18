#if canImport(UIKit)
import XCTest
@testable import AccessibilitySnapshotParser
import ButtonHeistSupport
@testable import TheInsideJob
@testable import TheScore

@MainActor
final class SettleSessionTimingMachineTests: XCTestCase {
    private typealias Support = SettleSessionTestSupport

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
        let transition = machine.reduce(state, event: event)
        state = transition.state
        if state.events.count > eventCount {
            ledger.resetCurrentGeneration()
        }
        let result: SettleSession.Result? = switch transition.effect {
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
            effect: transition.effect,
            result: result
        )
    }

    private struct MachineStep {
        let effect: SettleLoopMachine.Effect
        let result: SettleSession.Result?
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

    func testSemanticObservationDeadlineOwnsRemainingAndElapsedTime() {
        let deadline = SemanticObservationDeadline(start: 10, timeoutSeconds: 0.25)

        XCTAssertTrue(deadline.hasTimeRemaining(at: 10.1))
        XCTAssertEqual(deadline.remainingSeconds(at: 10.1), 0.15, accuracy: 0.000_001)
        XCTAssertEqual(deadline.elapsedMilliseconds(at: 10.125), 125)
        XCTAssertFalse(deadline.hasTimeRemaining(at: 10.25))
        XCTAssertEqual(deadline.remainingSeconds(at: 10.5), 0)

        let terminalWakeDeadline = deadline.reserving(0.05, at: 10.1)
        XCTAssertEqual(terminalWakeDeadline.start, 10.1)
        XCTAssertEqual(terminalWakeDeadline.remainingSeconds(at: 10.1), 0.1, accuracy: 0.000_001)
        XCTAssertFalse(terminalWakeDeadline.hasTimeRemaining(at: 10.2))

        let millisecondDeadline = SemanticObservationDeadline(start: 20, timeoutMs: 250)
        XCTAssertEqual(millisecondDeadline.remainingSeconds(at: 20.1), 0.15, accuracy: 0.000_001)

        let expiredDeadline = SemanticObservationDeadline(start: 30, timeoutSeconds: -1)
        XCTAssertFalse(expiredDeadline.hasTimeRemaining(at: 30))
        XCTAssertEqual(expiredDeadline.remainingSeconds(at: 30), 0)
    }

    func testViewportTransitionSettleUsesOneRunLoopTurnWhenTheRepeatIsStable() async {
        let stable = Support.makeParseResult([
            Support.makeElement(label: "Stable", traits: .staticText),
        ])
        let parseCount = Support.Counter()
        let session = SettleSession(
            parseProvider: {
                _ = parseCount.next()
                return stable
            },
            tripwireSignalProvider: { Support.tripwireSignal(topmostVC: nil) },
            sleeper: { _ in },
            cyclesRequired: 1,
            cycleIntervalMs: 0,
            timeoutMs: SettleSession.viewportTransitionTimeoutMs
        )

        let outcome = await session.run(
            start: CFAbsoluteTimeGetCurrent(),
            baselineTripwireSignal: Support.tripwireSignal(topmostVC: nil)
        )

        XCTAssertTrue(outcome.outcome.didSettleCleanly)
        XCTAssertEqual(parseCount.next(), 2)
    }

    func testViewportTransitionSettleUsesASecondRunLoopTurnAfterOneLayoutChange() async {
        let loading = Support.makeParseResult([
            Support.makeElement(label: "Loading", traits: .staticText),
        ])
        let ready = Support.makeParseResult([
            Support.makeElement(label: "Ready", traits: .staticText),
        ])
        let script = Support.ScriptBox(script: [loading, ready, ready])
        let parseCount = Support.Counter()
        let session = SettleSession(
            parseProvider: {
                _ = parseCount.next()
                return script.next()
            },
            tripwireSignalProvider: { Support.tripwireSignal(topmostVC: nil) },
            sleeper: { _ in },
            cyclesRequired: 1,
            cycleIntervalMs: 0,
            timeoutMs: SettleSession.viewportTransitionTimeoutMs
        )

        let outcome = await session.run(
            start: CFAbsoluteTimeGetCurrent(),
            baselineTripwireSignal: Support.tripwireSignal(topmostVC: nil)
        )

        XCTAssertTrue(outcome.outcome.didSettleCleanly)
        XCTAssertEqual(parseCount.next(), 3)
        XCTAssertEqual(
            outcome.finalObservation?.tree.viewportCapture.hierarchy.sortedElements.first?.label,
            "Ready"
        )
    }

    func testMachineSettlesFixedCadenceAfterRequiredConsecutiveCycles() {
        let stable = Support.makeParseResult([
            Support.makeElement(label: "Ready", traits: .staticText),
        ])
        let machine = SettleLoopMachine()
        var ledger = SettleObservationLedger()
        var state = SettleLoopMachine.State(
            policy: .consecutiveCycles(required: 2),
            tripwireBaseline: Support.tripwireSignal(topmostVC: nil)
        )

        XCTAssertContinue(reduceObservation(stable, elapsedMs: 0, machine: machine, ledger: &ledger, state: &state))
        XCTAssertContinue(reduceObservation(stable, elapsedMs: 1, machine: machine, ledger: &ledger, state: &state))
        let step = reduceObservation(stable, elapsedMs: 2, machine: machine, ledger: &ledger, state: &state)

        guard case .terminal(.settled(let timeMs)) = step.effect else {
            return XCTFail("Expected settled terminal effect, got \(step.effect)")
        }
        XCTAssertEqual(timeMs, 2)
        XCTAssertEqual(step.result?.finalObservation?.tree.viewportCapture.hierarchy.sortedElements.first?.label, "Ready")
    }

    func testMachineSettlesQuietWindowAfterFingerprintRemainsStableForWindow() {
        let stable = Support.makeParseResult([
            Support.makeElement(label: "Ready", traits: .staticText),
        ])
        let machine = SettleLoopMachine()
        var ledger = SettleObservationLedger()
        var state = SettleLoopMachine.State(
            policy: .quietWindow(milliseconds: 30),
            tripwireBaseline: Support.tripwireSignal(topmostVC: nil)
        )

        XCTAssertContinue(reduceObservation(stable, elapsedMs: 0, machine: machine, ledger: &ledger, state: &state))
        XCTAssertContinue(reduceObservation(stable, elapsedMs: 20, machine: machine, ledger: &ledger, state: &state))
        let step = reduceObservation(stable, elapsedMs: 30, machine: machine, ledger: &ledger, state: &state)

        guard case .terminal(.settled(let timeMs)) = step.effect else {
            return XCTFail("Expected settled terminal effect, got \(step.effect)")
        }
        XCTAssertEqual(timeMs, 30)
        XCTAssertEqual(step.result?.finalObservation?.tree.viewportCapture.hierarchy.sortedElements.first?.label, "Ready")
    }

    func testMachineFingerprintChangeResetsStability() {
        let loading = Support.makeParseResult([
            Support.makeElement(label: "Loading", traits: .staticText),
        ])
        let ready = Support.makeParseResult([
            Support.makeElement(label: "Ready", traits: .staticText),
        ])
        let machine = SettleLoopMachine()
        var ledger = SettleObservationLedger()
        var state = SettleLoopMachine.State(
            policy: .consecutiveCycles(required: 2),
            tripwireBaseline: Support.tripwireSignal(topmostVC: nil)
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
        XCTAssertEqual(step.result?.finalObservation?.tree.viewportCapture.hierarchy.sortedElements.first?.label, "Ready")
    }

    func testMachineTripwireResetThenNilParseCannotReturnStaleFinalScreen() {
        let stale = Support.makeParseResult([
            Support.makeElement(label: "Stale", traits: .staticText),
        ])
        let baseline = Support.tripwireSignal(topmostVC: nil)
        let changedObject = NSObject()
        let changed = Support.tripwireSignal(topmostVC: ObjectIdentifier(changedObject))
        let machine = SettleLoopMachine()
        var ledger = SettleObservationLedger()
        var state = SettleLoopMachine.State(
            policy: .consecutiveCycles(required: 1),
            tripwireBaseline: baseline
        )

        XCTAssertContinue(reduceObservation(stale, elapsedMs: 0, machine: machine, ledger: &ledger, state: &state))
        XCTAssertContinue(send(.tripwireSignal(changed), machine: machine, ledger: &ledger, state: &state))
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

    func testMachineTripwireResetRestartsBothPolicyProofs() {
        let stable = Support.makeParseResult([
            Support.makeElement(label: "Stable", traits: .staticText),
        ])
        let baseline = Support.tripwireSignal(topmostVC: nil)
        let changedObject = NSObject()
        let changed = Support.tripwireSignal(topmostVC: ObjectIdentifier(changedObject))

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
            XCTAssertContinue(send(.tripwireSignal(changed), machine: machine, ledger: &ledger, state: &state))
            XCTAssertContinue(reduceObservation(stable, elapsedMs: 1, machine: machine, ledger: &ledger, state: &state))
            let step = reduceObservation(stable, elapsedMs: 2, machine: machine, ledger: &ledger, state: &state)

            guard case .terminal(.settled(let timeMs)) = step.effect else {
                return XCTFail("Expected post-reset settle for \(policy), got \(step.effect)")
            }
            XCTAssertEqual(timeMs, 2)
            XCTAssertEqual(step.result?.events, [.tripwireSignalChanged(from: baseline, to: changed)])
        }
        _ = changedObject
    }

    func testMachineNotificationOnlyTripwireChangeDoesNotResetSettleBaseline() {
        let stable = Support.makeParseResult([
            Support.makeElement(label: "Stable", traits: .staticText),
        ])
        let baseline = Support.tripwireSignal(topmostVC: nil, accessibilityNotificationSequence: 1)
        let changed = Support.tripwireSignal(topmostVC: nil, accessibilityNotificationSequence: 2)
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
        XCTAssertEqual(step.result?.finalObservation?.tree.viewportCapture.hierarchy.sortedElements.first?.label, "Stable")
        XCTAssertTrue(state.events.isEmpty)
    }

    func testResultProjectsCancelledOutcomeFromCurrentSettleState() {
        let stable = Support.makeParseResult([
            Support.makeElement(label: "Ready", traits: .staticText),
        ])
        let machine = SettleLoopMachine()
        var ledger = SettleObservationLedger()
        var state = SettleLoopMachine.State(
            policy: .consecutiveCycles(required: 2),
            tripwireBaseline: Support.tripwireSignal(topmostVC: nil)
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
        let stable = Support.makeParseResult([
            Support.makeElement(label: "Ready", traits: .staticText),
        ])
        let machine = SettleLoopMachine()
        var ledger = SettleObservationLedger()
        var state = SettleLoopMachine.State(
            policy: .quietWindow(milliseconds: 30),
            tripwireBaseline: Support.tripwireSignal(topmostVC: nil)
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
