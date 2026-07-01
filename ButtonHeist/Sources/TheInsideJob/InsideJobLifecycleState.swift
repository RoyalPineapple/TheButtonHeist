#if canImport(UIKit)
#if DEBUG
import Foundation

enum InsideJobRuntimeStartPhase: Equatable, Sendable {
    case startup
    case resume
}

@MainActor
extension TheInsideJob {
    enum ServerPhase {
        case stopped
        case running(InsideJobRuntimeResources)
        case suspending(InsideJobSuspension)
        case suspended(InsideJobSuspendedRuntime)
        case resuming(InsideJobResumeAttempt)
        case stopping(InsideJobStopAttempt)
    }

    struct InsideJobRuntimeResources {
        let transport: ServerTransport
        let actualPort: UInt16
        let bonjourServiceName: String?
        let idleTimerBaseline: Bool
    }

    struct InsideJobSuspendedRuntime {
        let idleTimerBaseline: Bool
    }

    struct InsideJobSuspension {
        let id: UUID
        let resources: InsideJobRuntimeResources
    }

    struct InsideJobResumeAttempt {
        let id: UUID
        let suspendedRuntime: InsideJobSuspendedRuntime
        let task: Task<Void, Never>
    }

    struct InsideJobStopAttempt {
        let id: UUID
    }

    enum RuntimeReleasePolicy {
        case suspend
        case stop
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

#endif // DEBUG
#endif // canImport(UIKit)
