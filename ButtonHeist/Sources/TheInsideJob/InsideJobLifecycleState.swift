#if canImport(UIKit)
#if DEBUG
import Foundation

@MainActor
extension TheInsideJob {
    enum ServerPhase {
        case stopped
        case running(transport: ServerTransport)
        case suspended
        case resuming(id: UUID, task: Task<Void, Never>)
    }

    enum PollingPhase {
        case disabled
        case active(task: Task<Void, Never>, interval: TimeInterval)
        case paused(interval: TimeInterval)
    }

    /// Idle-timer baseline state. We force `UIApplication.isIdleTimerDisabled`
    /// on while the server is running so the device doesn't sleep mid-session,
    /// and restore the prior value on suspend/stop.
    enum IdleTimerProtection {
        case unmodified
        case engaged(baseline: Bool)
    }

    /// Tracks @objc lifecycle bridge Tasks that must finish before start/resume reads `serverPhase`.
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
