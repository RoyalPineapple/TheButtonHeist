#if canImport(UIKit)
#if DEBUG
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

        let boundary = TheVault.State.HistoryBoundary(
            baseline: nil,
            historyIndex: 0
        )
        guard case .pending(.wait) = machine.advance(.observationBegan(
            HeistExecution.RequestID(rawValue: 1),
            boundary
        )) else {
            return XCTFail("An observed wait must suspend for events")
        }
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
            heistSnapshot(labels: ["Home"])
        )) else {
            return XCTFail("A stale snapshot must leave the machine pending")
        }

        guard case .complete(let completion) = machine.advance(.currentSnapshot(
            request.id,
            heistSnapshot(labels: ["Home"])
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
        let boundary = TheVault.State.HistoryBoundary(
            baseline: heistSnapshot(labels: []),
            historyIndex: 0
        )
        guard case .pending(.perform(let firstExploration)) = machine.advance(
            .observationBegan(id, boundary)
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
            .event(.elementsChanged(heistSnapshot(labels: ["Other"])))
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

struct HeistMachineTestDriver {
    private(set) var machine: HeistExecution.Machine
    private(set) var history = Observation.History(retentionLimit: 256)
    private(set) var requests: [HeistExecution.MainActorRequest] = []
    private var script: MachineRunScript
    private var currentSnapshot: Observation.Snapshot?
    private var boundaries: [HeistExecution.RequestID: TheVault.State.HistoryBoundary] = [:]

    init(
        plan: HeistPlan,
        argument: HeistArgument = .none,
        script: MachineRunScript = MachineRunScript()
    ) throws {
        machine = try HeistExecution.Machine(plan: plan, argument: argument)
        self.script = script
        currentSnapshot = script.snapshots.first ?? nil
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
                      let boundary = boundaries[leaf.id] else {
                    throw MachineDriverFailure.stalled
                }
                state = machine.advance(.observationFinished(
                    leaf.id,
                    evidence(since: boundary),
                    nextLeafOutcome()
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
            if !script.snapshots.isEmpty {
                currentSnapshot = script.snapshots.removeFirst()
            }
            return machine.advance(.currentSnapshot(id, currentSnapshot))

        case .beginObservation(let id, _):
            let boundary = TheVault.State.HistoryBoundary(
                baseline: currentSnapshot,
                historyIndex: history.endIndex
            )
            boundaries[id] = boundary
            return machine.advance(.observationBegan(id, boundary))

        case .dispatch(let id, let command):
            let result = script.dispatchResults.isEmpty
                ? .success(payload: command.actionResultPayload)
                : script.dispatchResults.removeFirst()
            return machine.advance(.dispatchCompleted(id, result))

        case .explore(let id, _):
            return machine.advance(.viewportExited(id, .retained))

        case .finishObservation(let id, _):
            guard let boundary = boundaries[id] else {
                return machine.state
            }
            return machine.advance(.observationFinished(
                id,
                evidence(since: boundary),
                nextLeafOutcome()
            ))

        case .captureFailureScreenshot(let id, _, _):
            return machine.advance(.failureScreenshotCaptured(id, nil))
        }
    }

    private mutating func record(_ event: Observation.Event) {
        _ = history.record([event], protectedBy: nil)
        if case .elementsChanged(let snapshot) = event {
            currentSnapshot = snapshot
        }
    }

    private func evidence(
        since boundary: TheVault.State.HistoryBoundary
    ) -> Observation.Evidence {
        history.evidence(
            in: boundary.historyIndex..<history.endIndex,
            baseline: boundary.baseline,
            current: currentSnapshot
        )
    }

    private mutating func nextLeafOutcome() -> HeistExecution.LeafOutcome {
        script.leafOutcomes.isEmpty ? .completed : script.leafOutcomes.removeFirst()
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

func heistSnapshot(
    labels: [String],
    timestamp: Date = Date(timeIntervalSince1970: 1)
) -> Observation.Snapshot {
    heistSnapshot(
        elements: labels.map { AccessibilityElement.make(label: $0) },
        timestamp: timestamp
    )
}

func heistSnapshot(
    elements: [AccessibilityElement],
    timestamp: Date = Date(timeIntervalSince1970: 1)
) -> Observation.Snapshot {
    let indexedElements = elements.enumerated().map { index, element in
        let path = TreePath([index])
        let geometry = testGeometry(
            for: element,
            ownerPath: .root,
            screen: element.visibility == .onscreen
                ? TheVault.onscreenSpace(for: element)
                : .offscreen
        )
        return (
            hierarchy: AccessibilityHierarchy.element(
                element,
                traversalIndex: index
            ),
            annotation: InterfaceElementAnnotation(
                path: path,
                actions: [],
                geometry: geometry
            )
        )
    }
    guard let interface = try? Interface(
        timestamp: timestamp,
        tree: indexedElements.map(\.hierarchy),
        annotations: InterfaceAnnotations(
            elements: indexedElements.map(\.annotation),
            containers: []
        )
    ) else {
        preconditionFailure("The test snapshot must contain admitted geometry")
    }
    return Observation.Snapshot(interface: interface, context: .empty)
}

func heistNotification(_ text: String) -> Observation.Event {
    guard let notification = Observation.Notification(text: text, element: nil) else {
        preconditionFailure("A textual notification is valid")
    }
    return .notification(notification)
}

#endif // DEBUG
#endif // canImport(UIKit)
