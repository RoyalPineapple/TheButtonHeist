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
    func testMachineVocabularyIsPendingPerformPendingWaitOrComplete() throws {
        let plan = try HeistPlan(body: [
            .wait(WaitStep(
                predicate: .notification("Saved"),
                timeout: try .seconds(1)
            )),
        ])
        var machine = try HeistExecution.Machine(plan: plan)

        guard case .pending(.perform(let requests)) = machine.start(),
              requests.count == 1,
              case .beginObservation = requests[0] else {
            return XCTFail("A wait must begin one observation")
        }

        guard case .pending(.wait) = machine.advance(.observationBegan(
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

        guard machine.activeLeaf?.expectationIsSatisfied == false,
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

        guard case .pending(.wait) = machine.advance(.currentSnapshot(
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

        guard case .pending(.perform(let beginRequests)) = machine.start(),
              beginRequests.count == 1,
              case .beginObservation(let id, _) = beginRequests[0] else {
            return XCTFail("The wait must begin one observation")
        }
        guard case .pending(.perform(let firstExploration)) = machine.advance(
            .observationBegan(id, baseline: makeTestObservationSnapshot(labels: []))
        ),
              firstExploration.count == 1,
              case .explore(id, _) = firstExploration[0] else {
            return XCTFail("An unresolved element wait must explore")
        }

        guard case .pending(.perform(let restartedExploration)) = machine.advance(
            .viewportExited(id, .superseded)
        ),
              restartedExploration.count == 1,
              case .explore(id, _) = restartedExploration[0] else {
            return XCTFail("A screen replacement must restart the unfinished discovery")
        }
        guard case .pending(.wait) = machine.advance(.viewportExited(id, .restored)) else {
            return XCTFail("A completed unmatched discovery must wait for new evidence")
        }

        guard case .pending(.perform(let eventExploration)) = machine.advance(
            .event(.elementsChanged(makeTestObservationSnapshot(labels: ["Other"])))
        ),
              eventExploration.count == 1,
              case .explore(id, _) = eventExploration[0] else {
            return XCTFail("A substantive unmatched event must request one new discovery")
        }
        guard case .pending(.wait) = machine.advance(.viewportExited(id, .restored)) else {
            return XCTFail("The second completed discovery must return to waiting")
        }
        guard case .pending(.wait) = machine.advance(.event(.noChange)) else {
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
        guard case .pending(.perform(let beginRequests)) = machine.start(),
              beginRequests.count == 1,
              case .beginObservation(let id, _) = beginRequests[0] else {
            return XCTFail("The wait must begin one observation")
        }
        guard case .pending(.wait) = machine.advance(.observationBegan(
            id,
            baseline: makeTestObservationSnapshot(labels: ["Target"])
        )) else {
            return XCTFail("Current visible truth must satisfy existence without discovery")
        }
        guard case .pending(.perform(let requests)) = machine.advance(.event(.noChange)),
              requests.count == 1,
              case .finishObservation = requests[0] else {
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
        script: MachineRunScript = MachineRunScript()
    ) throws {
        machine = try HeistExecution.Machine(plan: plan, argument: argument)
        self.script = script
        currentSnapshot = nil
    }

    mutating func run(maximumTransitions: Int = 256) throws -> HeistExecution.Completion {
        var state = machine.start()
        for _ in 0..<maximumTransitions {
            switch state {
            case .complete(let completion):
                return completion
            case .pending(.perform(let pendingRequests)):
                guard let request = pendingRequests.first else {
                    throw MachineDriverFailure.emptyRequestBatch
                }
                requests.append(request)
                state = fulfill(request)
            case .pending(.wait):
                if !script.events.isEmpty {
                    let event = script.events.removeFirst()
                    record(event)
                    state = machine.advance(.event(event))
                    continue
                }
                guard let leaf = machine.activeLeaf,
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
    ) -> HeistExecution.State {
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
                ? .success(payload: command.actionResultPayload)
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
                return machine.state
            }
            return machine.advance(.observationFinished(
                source: .request(requestID),
                observationID: observationID,
                evidence: evidence(since: start),
                outcome: nextLeafOutcome(default: .completed),
                timing: HeistResultFixture.expectationTiming
            ))

        case .captureFailureScreenshot(let id, _, _):
            return machine.advance(.failureScreenshotCaptured(id, nil))
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
    case emptyRequestBatch
    case stalled
    case transitionLimitExceeded
}

extension HeistExecution.State {
    var singleSnapshotRequest: SnapshotRequest? {
        guard case .pending(.perform(let requests)) = self,
              requests.count == 1,
              case .currentSnapshot(let id, let scope) = requests[0] else {
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
