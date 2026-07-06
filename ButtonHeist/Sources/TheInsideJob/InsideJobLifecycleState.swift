#if canImport(UIKit)
#if DEBUG
import Foundation

import ButtonHeistSupport

enum InsideJobRuntimeStartPhase: Equatable, Sendable {
    case startup
    case resume
}

@MainActor
extension TheInsideJob {
    /// `@unchecked Sendable` justification: this state is owned by `TheInsideJob` on the MainActor; transport references are never mutated off that actor.
    enum ServerPhase: Equatable, @unchecked Sendable { // swiftlint:disable:this agent_unchecked_sendable_no_comment
        case stopped
        case starting(InsideJobStartAttempt)
        case running(InsideJobRuntimeResources)
        case suspending(InsideJobSuspension)
        case suspended(InsideJobSuspendedRuntime)
        case resuming(InsideJobResumeAttempt)
        case stopping(InsideJobStopAttempt)

        static func == (lhs: ServerPhase, rhs: ServerPhase) -> Bool {
            switch (lhs, rhs) {
            case (.stopped, .stopped):
                return true
            case (.starting(let lhsAttempt), .starting(let rhsAttempt)):
                return lhsAttempt == rhsAttempt
            case (.running(let lhsResources), .running(let rhsResources)):
                return lhsResources == rhsResources
            case (.suspending(let lhsSuspension), .suspending(let rhsSuspension)):
                return lhsSuspension == rhsSuspension
            case (.suspended(let lhsRuntime), .suspended(let rhsRuntime)):
                return lhsRuntime == rhsRuntime
            case (.resuming(let lhsAttempt), .resuming(let rhsAttempt)):
                return lhsAttempt == rhsAttempt
            case (.stopping(let lhsAttempt), .stopping(let rhsAttempt)):
                return lhsAttempt == rhsAttempt
            case (.stopped, _),
                 (.starting, _),
                 (.running, _),
                 (.suspending, _),
                 (.suspended, _),
                 (.resuming, _),
                 (.stopping, _):
                return false
            }
        }
    }

    /// `@unchecked Sendable` justification: `ServerTransport` is MainActor-owned lifecycle state carried through a pure MainActor reducer.
    struct InsideJobRuntimeResources: Equatable, @unchecked Sendable { // swiftlint:disable:this agent_unchecked_sendable_no_comment
        let transport: ServerTransport
        let actualPort: UInt16
        let bonjourServiceName: String?
        let idleTimerBaseline: Bool

        static func == (lhs: InsideJobRuntimeResources, rhs: InsideJobRuntimeResources) -> Bool {
            lhs.transport === rhs.transport
                && lhs.actualPort == rhs.actualPort
                && lhs.bonjourServiceName == rhs.bonjourServiceName
                && lhs.idleTimerBaseline == rhs.idleTimerBaseline
        }
    }

    /// `@unchecked Sendable` justification: start attempts carry a MainActor-owned transport until the reducer either activates or cleans it up.
    struct InsideJobStartAttempt: Equatable, @unchecked Sendable { // swiftlint:disable:this agent_unchecked_sendable_no_comment
        let id: UUID
        let transport: ServerTransport

        static func == (lhs: InsideJobStartAttempt, rhs: InsideJobStartAttempt) -> Bool {
            lhs.id == rhs.id && lhs.transport === rhs.transport
        }
    }

    struct InsideJobSuspendedRuntime: Equatable, Sendable {
        let idleTimerBaseline: Bool
    }

    /// `@unchecked Sendable` justification: suspension state only snapshots MainActor-owned runtime resources for lifecycle cleanup.
    struct InsideJobSuspension: Equatable, @unchecked Sendable { // swiftlint:disable:this agent_unchecked_sendable_no_comment
        let id: UUID
        let resources: InsideJobRuntimeResources
    }

    /// `@unchecked Sendable` justification: resume tasks are created, cancelled, and awaited by the MainActor lifecycle interpreter.
    struct InsideJobResumeAttempt: Equatable, @unchecked Sendable { // swiftlint:disable:this agent_unchecked_sendable_no_comment
        let id: UUID
        let suspendedRuntime: InsideJobSuspendedRuntime
        let task: Task<Void, Never>

        static func == (lhs: InsideJobResumeAttempt, rhs: InsideJobResumeAttempt) -> Bool {
            lhs.id == rhs.id && lhs.suspendedRuntime == rhs.suspendedRuntime
        }
    }

    struct InsideJobStopAttempt: Equatable, Sendable {
        let id: UUID
    }

    enum RuntimeReleasePolicy: Equatable, Sendable {
        case suspend
        case stop
    }

    /// `@unchecked Sendable` justification: transport start requests carry MainActor-owned transport handles into the async start interpreter.
    struct InsideJobTransportStartRequest: Equatable, @unchecked Sendable { // swiftlint:disable:this agent_unchecked_sendable_no_comment
        let id: UUID
        let phase: InsideJobRuntimeStartPhase
        let transport: ServerTransport
        let idleTimerBaseline: Bool

        static func == (
            lhs: InsideJobTransportStartRequest,
            rhs: InsideJobTransportStartRequest
        ) -> Bool {
            lhs.id == rhs.id
                && lhs.phase == rhs.phase
                && lhs.transport === rhs.transport
                && lhs.idleTimerBaseline == rhs.idleTimerBaseline
        }
    }

    /// Tracks @objc lifecycle bridge Tasks that must finish before start/resume reads `serverPhase`.
    @MainActor
    final class LifecycleBoundaryTasks {
        private var tasks: [UInt64: Task<Void, Never>] = [:]
        private var nextTaskId: UInt64 = 0

        var isEmpty: Bool { tasks.isEmpty }

        func spawn(_ body: @escaping @MainActor () async -> Void) {
            nextTaskId &+= 1
            let id = nextTaskId
            let task = Task { @MainActor [weak self] in
                await body()
                self?.tasks.removeValue(forKey: id)
            }
            tasks[id] = task
        }

        func drain() async {
            while !tasks.isEmpty {
                let snapshot = Array(tasks.values)
                tasks.removeAll()
                for task in snapshot {
                    await task.value
                }
            }
        }
    }
}

struct InsideJobLifecycleMachine: SimpleStateMachine {
    typealias State = TheInsideJob.ServerPhase
    typealias Change = StateChange<State, Effect, Rejection>

    /// `@unchecked Sendable` justification: events are produced and consumed on MainActor; payload transports/tasks stay actor-owned.
    enum Event: Equatable, @unchecked Sendable { // swiftlint:disable:this agent_unchecked_sendable_no_comment
        case lifecycleSuspensionNotification
        case foregroundNotification(replacingExisting: Bool)
        case terminationNotification
        case startRequested(TheInsideJob.InsideJobStartAttempt, idleTimerBaseline: Bool)
        case startSucceeded(UUID, TheInsideJob.InsideJobRuntimeResources)
        case startFailed(UUID)
        case stopRequested(TheInsideJob.InsideJobStopAttempt)
        case stopFinished(UUID)
        case suspendRequested(TheInsideJob.InsideJobSuspension?)
        case suspendFinished(UUID)
        case resumeRequested(TheInsideJob.InsideJobResumeAttempt)
        case resumeTransportRequested(
            UUID,
            transport: ServerTransport,
            idleTimerBaseline: Bool
        )
        case resumeSucceeded(UUID, TheInsideJob.InsideJobRuntimeResources)
        case resumeFailed(UUID)

        static func == (lhs: Event, rhs: Event) -> Bool {
            switch (lhs, rhs) {
            case (.lifecycleSuspensionNotification, .lifecycleSuspensionNotification),
                 (.terminationNotification, .terminationNotification):
                return true
            case (
                .foregroundNotification(let lhsReplacingExisting),
                .foregroundNotification(let rhsReplacingExisting)
            ):
                return lhsReplacingExisting == rhsReplacingExisting
            case (
                .startRequested(let lhsAttempt, let lhsIdleTimerBaseline),
                .startRequested(let rhsAttempt, let rhsIdleTimerBaseline)
            ):
                return lhsAttempt == rhsAttempt && lhsIdleTimerBaseline == rhsIdleTimerBaseline
            case (.startSucceeded(let lhsID, let lhsResources), .startSucceeded(let rhsID, let rhsResources)):
                return lhsID == rhsID && lhsResources == rhsResources
            case (.startFailed(let lhsID), .startFailed(let rhsID)):
                return lhsID == rhsID
            case (.stopRequested(let lhsAttempt), .stopRequested(let rhsAttempt)):
                return lhsAttempt == rhsAttempt
            case (.stopFinished(let lhsID), .stopFinished(let rhsID)):
                return lhsID == rhsID
            case (.suspendRequested(let lhsSuspension), .suspendRequested(let rhsSuspension)):
                return lhsSuspension == rhsSuspension
            case (.suspendFinished(let lhsID), .suspendFinished(let rhsID)):
                return lhsID == rhsID
            case (.resumeRequested(let lhsAttempt), .resumeRequested(let rhsAttempt)):
                return lhsAttempt == rhsAttempt
            case (
                .resumeTransportRequested(let lhsID, let lhsTransport, let lhsIdleTimerBaseline),
                .resumeTransportRequested(let rhsID, let rhsTransport, let rhsIdleTimerBaseline)
            ):
                return lhsID == rhsID
                    && lhsTransport === rhsTransport
                    && lhsIdleTimerBaseline == rhsIdleTimerBaseline
            case (.resumeSucceeded(let lhsID, let lhsResources), .resumeSucceeded(let rhsID, let rhsResources)):
                return lhsID == rhsID && lhsResources == rhsResources
            case (.resumeFailed(let lhsID), .resumeFailed(let rhsID)):
                return lhsID == rhsID
            default:
                return false
            }
        }
    }

    /// `@unchecked Sendable` justification: effects are returned by the MainActor reducer and immediately interpreted on MainActor.
    enum Effect: Equatable, @unchecked Sendable { // swiftlint:disable:this agent_unchecked_sendable_no_comment
        case scheduleSuspend
        case scheduleResume(afterCancelling: TheInsideJob.InsideJobResumeAttempt?)
        case scheduleStop
        case startTransport(TheInsideJob.InsideJobTransportStartRequest)
        case stopTransport(ServerTransport)
        case cleanupTransport(ServerTransport)
        case releaseResources(policy: TheInsideJob.RuntimeReleasePolicy, idleTimerBaseline: Bool)
        case cancelResume(TheInsideJob.InsideJobResumeAttempt)
        case activateRuntime(TheInsideJob.InsideJobRuntimeResources)
        case tearDownRuntimeServices

        static func == (lhs: Effect, rhs: Effect) -> Bool {
            switch (lhs, rhs) {
            case (.scheduleSuspend, .scheduleSuspend),
                 (.scheduleStop, .scheduleStop),
                 (.tearDownRuntimeServices, .tearDownRuntimeServices):
                return true
            case (
                .scheduleResume(let lhsAttempt),
                .scheduleResume(let rhsAttempt)
            ):
                return lhsAttempt == rhsAttempt
            case (.startTransport(let lhsRequest), .startTransport(let rhsRequest)):
                return lhsRequest == rhsRequest
            case (.stopTransport(let lhsTransport), .stopTransport(let rhsTransport)):
                return lhsTransport === rhsTransport
            case (.cleanupTransport(let lhsTransport), .cleanupTransport(let rhsTransport)):
                return lhsTransport === rhsTransport
            case (
                .releaseResources(let lhsPolicy, let lhsIdleTimerBaseline),
                .releaseResources(let rhsPolicy, let rhsIdleTimerBaseline)
            ):
                return lhsPolicy == rhsPolicy && lhsIdleTimerBaseline == rhsIdleTimerBaseline
            case (.cancelResume(let lhsAttempt), .cancelResume(let rhsAttempt)):
                return lhsAttempt == rhsAttempt
            case (.activateRuntime(let lhsResources), .activateRuntime(let rhsResources)):
                return lhsResources == rhsResources
            default:
                return false
            }
        }
    }

    enum Rejection: Equatable, Sendable {
        case alreadyActive
        case alreadyStopped
        case alreadyStopping
        case notRunning
        case notSuspended
        case staleStartAttempt
        case staleSuspendAttempt
        case staleResumeAttempt
        case staleStopAttempt
    }

    func advance(_ state: State, with event: Event) -> Change {
        switch event {
        case .lifecycleSuspensionNotification:
            return .changed(to: state, effects: [.scheduleSuspend])
        case .foregroundNotification(let replacingExisting):
            return foreground(state, replacingExisting: replacingExisting)
        case .terminationNotification:
            return .changed(to: state, effects: [.scheduleStop])
        case .startRequested(let attempt, let idleTimerBaseline):
            return startRequested(state, attempt: attempt, idleTimerBaseline: idleTimerBaseline)
        case .startSucceeded(let id, let resources):
            return startSucceeded(state, id: id, resources: resources)
        case .startFailed(let id):
            return startFailed(state, id: id)
        case .stopRequested(let attempt):
            return stopRequested(state, attempt: attempt)
        case .stopFinished(let id):
            return stopFinished(state, id: id)
        case .suspendRequested(let suspension):
            return suspendRequested(state, suspension: suspension)
        case .suspendFinished(let id):
            return suspendFinished(state, id: id)
        case .resumeRequested(let attempt):
            return resumeRequested(state, attempt: attempt)
        case .resumeTransportRequested(let id, let transport, let idleTimerBaseline):
            return resumeTransportRequested(
                state,
                id: id,
                transport: transport,
                idleTimerBaseline: idleTimerBaseline
            )
        case .resumeSucceeded(let id, let resources):
            return resumeSucceeded(state, id: id, resources: resources)
        case .resumeFailed(let id):
            return resumeFailed(state, id: id)
        }
    }

    private func foreground(_ state: State, replacingExisting: Bool) -> Change {
        switch state {
        case .suspended:
            return .changed(to: state, effects: [.scheduleResume(afterCancelling: nil)])
        case .resuming(let attempt) where replacingExisting:
            return .changed(to: state, effects: [.scheduleResume(afterCancelling: attempt)])
        case .stopped, .starting, .running, .suspending, .resuming, .stopping:
            return .changed(to: state)
        }
    }

    private func startRequested(
        _ state: State,
        attempt: TheInsideJob.InsideJobStartAttempt,
        idleTimerBaseline: Bool
    ) -> Change {
        guard case .stopped = state else {
            return .rejected(.alreadyActive, stayingIn: state)
        }
        let request = TheInsideJob.InsideJobTransportStartRequest(
            id: attempt.id,
            phase: .startup,
            transport: attempt.transport,
            idleTimerBaseline: idleTimerBaseline
        )
        return .changed(to: .starting(attempt), effects: [.startTransport(request)])
    }

    private func startSucceeded(
        _ state: State,
        id: UUID,
        resources: TheInsideJob.InsideJobRuntimeResources
    ) -> Change {
        guard case .starting(let attempt) = state, attempt.id == id else {
            return .rejected(.staleStartAttempt, stayingIn: state)
        }
        return .changed(to: .running(resources), effects: [.activateRuntime(resources)])
    }

    private func startFailed(_ state: State, id: UUID) -> Change {
        guard case .starting(let attempt) = state, attempt.id == id else {
            return .rejected(.staleStartAttempt, stayingIn: state)
        }
        return .changed(to: .stopped, effects: [.cleanupTransport(attempt.transport)])
    }

    private func stopRequested(_ state: State, attempt stopAttempt: TheInsideJob.InsideJobStopAttempt) -> Change {
        switch state {
        case .stopped:
            return .rejected(.alreadyStopped, stayingIn: state)
        case .stopping:
            return .rejected(.alreadyStopping, stayingIn: state)
        case .starting(let attempt):
            return .changed(
                to: .stopping(stopAttempt),
                effects: [.cleanupTransport(attempt.transport), .tearDownRuntimeServices]
            )
        case .running(let resources):
            return stopRunning(resources, attempt: stopAttempt)
        case .suspending(let suspension):
            return stopRunning(suspension.resources, attempt: stopAttempt)
        case .suspended(let suspendedRuntime):
            return .changed(
                to: .stopping(stopAttempt),
                effects: [
                    .releaseResources(policy: .stop, idleTimerBaseline: suspendedRuntime.idleTimerBaseline),
                    .tearDownRuntimeServices,
                ]
            )
        case .resuming(let attempt):
            return .changed(to: state, effects: [.cancelResume(attempt)])
        }
    }

    private func stopRunning(
        _ resources: TheInsideJob.InsideJobRuntimeResources,
        attempt stopAttempt: TheInsideJob.InsideJobStopAttempt
    ) -> Change {
        .changed(
            to: .stopping(stopAttempt),
            effects: [
                .releaseResources(policy: .stop, idleTimerBaseline: resources.idleTimerBaseline),
                .stopTransport(resources.transport),
                .tearDownRuntimeServices,
            ]
        )
    }

    private func stopFinished(_ state: State, id: UUID) -> Change {
        switch state {
        case .stopping(let attempt) where attempt.id == id:
            return .changed(to: .stopped)
        case .stopping:
            return .rejected(.staleStopAttempt, stayingIn: state)
        case .stopped, .starting, .running, .suspending, .suspended, .resuming:
            return .changed(to: state)
        }
    }

    private func suspendRequested(_ state: State, suspension: TheInsideJob.InsideJobSuspension?) -> Change {
        switch (state, suspension) {
        case (.running(let resources), .some(let suspension)):
            return .changed(
                to: .suspending(suspension),
                effects: [
                    .releaseResources(policy: .suspend, idleTimerBaseline: resources.idleTimerBaseline),
                    .stopTransport(resources.transport),
                    .tearDownRuntimeServices,
                ]
            )
        case (.resuming(let attempt), _):
            return .changed(to: state, effects: [.cancelResume(attempt)])
        case (.running, nil),
             (.stopped, _),
             (.starting, _),
             (.suspending, _),
             (.suspended, _),
             (.stopping, _):
            return .rejected(.notRunning, stayingIn: state)
        }
    }

    private func suspendFinished(_ state: State, id: UUID) -> Change {
        guard case .suspending(let suspension) = state, suspension.id == id else {
            return .rejected(.staleSuspendAttempt, stayingIn: state)
        }
        return .changed(
            to: .suspended(
                TheInsideJob.InsideJobSuspendedRuntime(
                    idleTimerBaseline: suspension.resources.idleTimerBaseline
                )
            )
        )
    }

    private func resumeRequested(_ state: State, attempt: TheInsideJob.InsideJobResumeAttempt) -> Change {
        switch state {
        case .suspended:
            return .changed(to: .resuming(attempt))
        case .resuming:
            return .rejected(.alreadyActive, stayingIn: state)
        case .stopped, .starting, .running, .suspending, .stopping:
            return .rejected(.notSuspended, stayingIn: state)
        }
    }

    private func resumeTransportRequested(
        _ state: State,
        id: UUID,
        transport: ServerTransport,
        idleTimerBaseline: Bool
    ) -> Change {
        guard case .resuming(let attempt) = state, attempt.id == id else {
            return .rejected(.staleResumeAttempt, stayingIn: state)
        }
        let request = TheInsideJob.InsideJobTransportStartRequest(
            id: id,
            phase: .resume,
            transport: transport,
            idleTimerBaseline: idleTimerBaseline
        )
        return .changed(to: state, effects: [.startTransport(request)])
    }

    private func resumeSucceeded(
        _ state: State,
        id: UUID,
        resources: TheInsideJob.InsideJobRuntimeResources
    ) -> Change {
        guard case .resuming(let attempt) = state, attempt.id == id else {
            return .rejected(.staleResumeAttempt, stayingIn: state)
        }
        return .changed(to: .running(resources), effects: [.activateRuntime(resources)])
    }

    private func resumeFailed(_ state: State, id: UUID) -> Change {
        guard case .resuming(let attempt) = state, attempt.id == id else {
            return .rejected(.staleResumeAttempt, stayingIn: state)
        }
        return .changed(to: .suspended(attempt.suspendedRuntime))
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
