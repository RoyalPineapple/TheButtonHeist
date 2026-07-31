#if canImport(UIKit)
#if DEBUG
import ButtonHeistTestSupport
import Foundation
import XCTest

@testable import AccessibilitySnapshotParser
@_spi(ButtonHeistInternals) @testable import ThePlans
@testable import TheInsideJob
@_spi(ButtonHeistInternals) @testable import TheScore

final class HeistExecutionMachineTests: XCTestCase {
    func testMachineVocabularyIsPerformWaitOrComplete() throws {
        let plan = try HeistPlan(body: [
            .wait(WaitStep(
                predicate: .notification("Saved"),
                timeout: try .seconds(1)
            )),
        ])
        var machine = try HeistExecution.Machine(plan: plan)

        guard case .perform(let request) = machine.start(),
              case .beginObservation = request else {
            return XCTFail("A wait must begin one observation")
        }

        guard case .wait = machine.advance(.observationBegan(
            HeistExecution.RequestID(rawValue: 1),
            baseline: nil
        )) else {
            return XCTFail("An observed wait must suspend for events")
        }
    }

    func testDeadlineDuringObservationStartCannotCompleteWait() throws {
        let plan = try HeistPlan(body: [
            .wait(WaitStep(
                predicate: .missing(.label("Target")),
                timeout: try .seconds(1)
            )),
        ])
        var machine = try HeistExecution.Machine(plan: plan)
        let request = try XCTUnwrap(machine.start().singleBeginObservationRequest)
        let evidence = Observation.History(retentionLimit: 1).evidence(
            in: 0..<0,
            baseline: nil,
            current: nil
        )

        guard case .wait(let leaf) = machine.running.activeLeaf,
              case .beginningObservation = leaf.phase,
              case .complete(let completion) = machine.advance(.observationFinished(
                  source: .deadline,
                  observationID: request.id,
                  evidence: evidence,
                  outcome: .timedOut,
                  timing: HeistResultFixture.expectationTiming
              )) else {
            return XCTFail("An uninitialized expectation must remain unmet at its deadline")
        }
        XCTAssertEqual(completion.steps.first?.status, .failed)
    }

    func testStaleRequestCompletionDoesNotAdvanceMachine() throws {
        let plan = try HeistPlan(body: [
            .conditional(try ConditionalStep(cases: [
                PredicateCase(
                    predicate: .exists(.label("Home")),
                    body: [.warn(WarnStep(message: "selected"))]
                ),
            ])),
        ])
        var machine = try HeistExecution.Machine(plan: plan)
        let state = machine.start()
        let request = try XCTUnwrap(state.singleSnapshotRequest)

        guard case .wait = machine.advance(.currentSnapshot(
            HeistExecution.RequestID(rawValue: request.id.rawValue + 1),
            makeTestObservationSnapshot(labels: ["Home"])
        )) else {
            return XCTFail("A stale snapshot must leave the machine pending")
        }

        guard case .complete(let completion) = machine.advance(.currentSnapshot(
            request.id,
            makeTestObservationSnapshot(labels: ["Home"])
        )) else {
            return XCTFail("The admitted snapshot must complete the conditional")
        }
        XCTAssertEqual(completion.steps.first?.status, .passed)
    }

    func testCompleteStateIgnoresLateInput() throws {
        let plan = try HeistPlan(body: [
            .warn(WarnStep(message: "done")),
        ])
        var machine = try HeistExecution.Machine(plan: plan)
        guard case .complete(let completion) = machine.start() else {
            return XCTFail("A warning-only plan must complete synchronously")
        }
        XCTAssertEqual(completion.steps.map(\.path), ["$.body[0]"])
        XCTAssertEqual(completion.steps.map(\.kind), [.warn])
        XCTAssertEqual(completion.steps.map(\.reportMessage), ["done"])
        XCTAssertNil(completion.abortedAtPath)

        guard case .complete(let lateCompletion) = machine.advance(.event(.noChange)) else {
            return XCTFail("Late input must not reopen a completed machine")
        }
        XCTAssertEqual(lateCompletion.steps, completion.steps)
        XCTAssertEqual(lateCompletion.abortedAtPath, completion.abortedAtPath)
    }

    func testElementWaitRestartsDiscoveryAfterScreenReplacementAndSubstantiveEvents() throws {
        let plan = try HeistPlan(body: [
            .wait(WaitStep(
                predicate: .exists(.label("Target")),
                timeout: try .seconds(1)
            )),
        ])
        var machine = try HeistExecution.Machine(plan: plan)

        guard case .perform(let beginRequest) = machine.start(),
              case .beginObservation(let id, _) = beginRequest else {
            return XCTFail("The wait must begin one observation")
        }
        guard case .perform(let firstExploration) = machine.advance(
            .observationBegan(id, baseline: makeTestObservationSnapshot(labels: []))
        ),
              case .explore(id, _) = firstExploration else {
            return XCTFail("An unresolved element wait must explore")
        }

        guard case .perform(let restartedExploration) = machine.advance(
            .viewportExited(id, .superseded)
        ),
              case .explore(id, _) = restartedExploration else {
            return XCTFail("A screen replacement must restart the unfinished discovery")
        }
        guard case .wait = machine.advance(.viewportExited(id, .restored)) else {
            return XCTFail("A completed unmatched discovery must wait for new evidence")
        }

        guard case .perform(let eventExploration) = machine.advance(
            .event(.elementsChanged(makeTestObservationSnapshot(labels: ["Other"])))
        ),
              case .explore(id, _) = eventExploration else {
            return XCTFail("A substantive unmatched event must request one new discovery")
        }
        guard case .wait = machine.advance(.viewportExited(id, .restored)) else {
            return XCTFail("The second completed discovery must return to waiting")
        }
        guard case .wait = machine.advance(.event(.noChange)) else {
            return XCTFail("Stillness must not start another discovery")
        }
    }

    func testCurrentVisibleTruthSatisfiesWaitBeforeDiscovery() throws {
        let plan = try HeistPlan(body: [
            .wait(WaitStep(
                predicate: .exists(.label("Target")),
                timeout: try .seconds(1)
            )),
        ])
        var machine = try HeistExecution.Machine(plan: plan)
        guard case .perform(let beginRequest) = machine.start(),
              case .beginObservation(let id, _) = beginRequest else {
            return XCTFail("The wait must begin one observation")
        }
        guard case .wait = machine.advance(.observationBegan(
            id,
            baseline: makeTestObservationSnapshot(labels: ["Target"])
        )) else {
            return XCTFail("Current visible truth must satisfy existence without discovery")
        }
        guard case .perform(let request) = machine.advance(.event(.noChange)),
              case .finishObservation = request else {
            return XCTFail("Settled current truth must finish the wait")
        }
    }

    func testDispatchesEveryDurableActionCommandThroughTypedRequests() throws {
        let target = AccessibilityTarget.identifier("target")
        let point = GesturePointSelection.coordinate(ScreenPoint(x: 10, y: 20))
        let commands: [HeistActionCommand] = [
            .activate(target),
            .increment(target),
            .decrement(target),
            .customAction(name: "Archive", target: target),
            .rotor(selection: .named("Errors"), target: target, direction: .next),
            .typeText(text: "hello", target: target),
            .oneFingerTap(TapTarget(selection: point)),
            .longPress(LongPressTarget(selection: point)),
            .swipe(SwipeTarget(selection: .pointDirection(
                start: ScreenPoint(x: 20, y: 20),
                direction: .left
            ))),
            .drag(DragTarget(
                start: .coordinate(ScreenPoint(x: 20, y: 20)),
                end: ScreenPoint(x: 80, y: 80)
            )),
            .editAction(EditActionTarget(action: .paste)),
            .setPasteboard(SetPasteboardTarget(text: "clipboard")),
            .takeScreenshot,
            .dismissKeyboard,
        ]
        let plan = try HeistPlan(body: commands.map { .action(ActionStep(command: $0)) })
        var driver = try HeistMachineTestDriver(
            plan: plan,
            script: MachineRunScript(
                events: Array(repeating: [.noChange, .noChange], count: commands.count)
                    .flatMap { $0 }
            )
        )

        let completion = try driver.run()

        let expectedCommands = try commands.map { try $0.resolve(in: .empty) }
        XCTAssertEqual(driver.requests.compactMap(\.dispatchedCommand), expectedCommands)
        XCTAssertEqual(completion.steps.count, commands.count)
        XCTAssertTrue(completion.steps.allSatisfy { $0.status == .passed })
    }

    func testDirectScrollUsesTheActionPipelineWithoutDurablePlanAdmission() throws {
        var machine = HeistExecution.Machine(action: .scroll(.init()))
        guard case .perform(.beginObservation(let observationID, _)) = machine.start(),
              case .perform(.dispatch(let dispatchID, _)) = machine.advance(
                .observationBegan(observationID, baseline: nil)
              ),
              dispatchID == observationID,
              case .perform(.finishObservation(let finishID, let finishedObservationID, _)) = machine.advance(
                .dispatchCompleted(
                    dispatchID,
                    .failure(
                        .empty(for: .scroll),
                        message: "scroll dispatch failed",
                        failureKind: .actionFailed
                    )
                )
              ),
              finishedObservationID == observationID,
              case .complete(let completion) = machine.advance(.observationFinished(
                source: .request(finishID),
                observationID: observationID,
                evidence: .init(
                    baseline: nil,
                    events: [],
                    current: nil,
                    coverage: .incomplete(.captureUnavailable)
                ),
                outcome: .completed,
                timing: HeistResultFixture.expectationTiming
              ))
        else {
            return XCTFail("A direct scroll must complete through the action reducer")
        }
        XCTAssertEqual(completion.steps.count, 1)
        XCTAssertEqual(completion.steps.first?.status, .failed)
    }

    func testFailedActivateKeepsActivationTraceInActionEvidence() throws {
        let activationTrace = ActivationTrace(.activationPointFallback(
            axActivateReturned: false,
            tapActivationPoint: ScreenPoint(x: 195, y: 139),
            tapActivationSucceeded: true
        ), implementsAccessibilityActivation: false)
        let target = AccessibilityTarget.label("Search all items")
        let command = HeistActionCommand.activate(target)
        let plan = try HeistPlan(body: [.action(ActionStep(command: command))])
        var driver = try HeistMachineTestDriver(
            plan: plan,
            script: MachineRunScript(
                events: [.noChange],
                dispatchResults: [
                    .failure(
                        .activate,
                        message: "text entry failed: observed focus=none "
                            + "keyboardVisible=false activeTextInput=false",
                        activationTrace: activationTrace
                    ),
                ]
            )
        )

        let completion = try driver.run()
        let step = try XCTUnwrap(completion.steps.first)

        XCTAssertEqual(step.status, .failed)
        XCTAssertEqual(step.actionEvidence?.result?.activationTrace, activationTrace)
    }
}

struct MachineRunScript {
    var snapshots: [Observation.Snapshot?] = []
    var events: [Observation.Event] = []
    var dispatchResults: [TheSafecracker.ActionDispatchResult] = []
    var leafOutcomes: [HeistExecution.LeafOutcome] = []
}

struct SnapshotRequest {
    let id: HeistExecution.RequestID
    let scope: SemanticObservationScope
}

private struct MachineObservationStart {
    let baseline: Observation.Snapshot?
    let historyIndex: Int
}

struct HeistMachineTestDriver {
    private(set) var machine: HeistExecution.Machine
    private(set) var history = Observation.History(retentionLimit: 256)
    private(set) var requests: [HeistExecution.MainActorRequest] = []
    private var script: MachineRunScript
    private var currentSnapshot: Observation.Snapshot?
    private var observationStarts: [HeistExecution.RequestID: MachineObservationStart] = [:]

    init(
        plan: HeistPlan,
        argument: HeistArgument = .none,
        actionExpectationTimeoutPolicy: ActionExpectationTimeoutPolicy = .default,
        script: MachineRunScript = MachineRunScript()
    ) throws {
        machine = try HeistExecution.Machine(
            plan: plan,
            argument: argument,
            actionExpectationTimeoutPolicy: actionExpectationTimeoutPolicy
        )
        self.script = script
        currentSnapshot = nil
    }

    mutating func run(maximumTransitions: Int = 256) throws -> HeistExecution.Completion {
        var state = machine.start()
        for _ in 0..<maximumTransitions {
            switch state {
            case .complete(let completion):
                return completion
            case .perform(let request):
                requests.append(request)
                state = fulfill(request)
            case .wait:
                if !script.events.isEmpty {
                    let event = script.events.removeFirst()
                    record(event)
                    state = machine.advance(.event(event))
                    continue
                }
                guard let leaf = machine.running.activeLeaf,
                      let start = observationStarts[leaf.id] else {
                    throw MachineDriverFailure.stalled
                }
                let outcome = nextLeafOutcome(default: .timedOut)
                state = machine.advance(.observationFinished(
                    source: .deadline,
                    observationID: leaf.id,
                    evidence: evidence(since: start),
                    outcome: outcome,
                    timing: HeistResultFixture.expectationTiming
                ))
            }
        }
        throw MachineDriverFailure.transitionLimitExceeded
    }

    private mutating func fulfill(
        _ request: HeistExecution.MainActorRequest
    ) -> HeistExecution.Decision {
        switch request {
        case .currentSnapshot(let id, _):
            let snapshot = nextSnapshot()
            return machine.advance(.currentSnapshot(id, snapshot))

        case .beginObservation(let id, _):
            let start = MachineObservationStart(
                baseline: nextSnapshot(),
                historyIndex: history.endIndex
            )
            observationStarts[id] = start
            return machine.advance(.observationBegan(id, baseline: start.baseline))

        case .dispatch(let id, let command):
            let result = script.dispatchResults.isEmpty
                ? .success(payload: .empty(for: command.type))
                : script.dispatchResults.removeFirst()
            return machine.advance(.dispatchCompleted(id, result))

        case .explore(let id, _):
            return machine.advance(.viewportExited(id, .retained))

        case .finishObservation(
            let requestID,
            let observationID,
            _
        ):
            guard let start = observationStarts[observationID] else {
                return machine.decision
            }
            return machine.advance(.observationFinished(
                source: .request(requestID),
                observationID: observationID,
                evidence: evidence(since: start),
                outcome: nextLeafOutcome(default: .completed),
                timing: HeistResultFixture.expectationTiming
            ))

        case .captureFailureScreenshot(let id, _, _):
            return machine.advance(.failureScreenshotCaptured(
                id,
                .unavailable(kind: .actionFailed, message: "capture unavailable")
            ))
        }
    }

    private mutating func nextSnapshot() -> Observation.Snapshot? {
        if !script.snapshots.isEmpty {
            currentSnapshot = script.snapshots.removeFirst()
        }
        return currentSnapshot
    }

    private mutating func record(_ event: Observation.Event) {
        _ = history.record([event], protectedBy: nil)
        if case .elementsChanged(let snapshot) = event {
            currentSnapshot = snapshot
        }
    }

    private func evidence(
        since start: MachineObservationStart
    ) -> Observation.Evidence {
        history.evidence(
            in: start.historyIndex..<history.endIndex,
            baseline: start.baseline,
            current: currentSnapshot
        )
    }

    private mutating func nextLeafOutcome(
        default defaultOutcome: HeistExecution.LeafOutcome
    ) -> HeistExecution.LeafOutcome {
        script.leafOutcomes.isEmpty
            ? defaultOutcome
            : script.leafOutcomes.removeFirst()
    }
}

enum MachineDriverFailure: Error {
    case stalled
    case transitionLimitExceeded
}

extension HeistExecution.Decision {
    var singleSnapshotRequest: SnapshotRequest? {
        guard case .perform(let request) = self,
              case .currentSnapshot(let id, let scope) = request else {
            return nil
        }
        return SnapshotRequest(id: id, scope: scope)
    }
}

private extension HeistExecution.MainActorRequest {
    var dispatchedCommand: ResolvedHeistActionCommand? {
        guard case .dispatch(_, let command) = self else { return nil }
        return command
    }
}

func heistNotification(_ text: String) -> Observation.Event {
    guard let notification = Observation.Notification(text: text, element: nil) else {
        preconditionFailure("A textual notification is valid")
    }
    return .notification(notification)
}

#endif // DEBUG
#endif // canImport(UIKit)
