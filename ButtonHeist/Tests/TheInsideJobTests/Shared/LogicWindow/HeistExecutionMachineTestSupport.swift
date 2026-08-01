#if canImport(UIKit)
#if DEBUG
import ButtonHeistTestSupport

@testable import TheInsideJob
@_spi(ButtonHeistInternals) @testable import ThePlans
@_spi(ButtonHeistInternals) @testable import TheScore

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

extension HeistExecution.MainActorRequest {
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
