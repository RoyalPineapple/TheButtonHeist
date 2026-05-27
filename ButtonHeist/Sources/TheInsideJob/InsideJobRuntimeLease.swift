#if canImport(UIKit)
#if DEBUG
import Foundation

struct InsideJobRuntimeLease {
    let transport: ServerTransport
    let actualPort: UInt16
    let tlsFingerprint: String
    let bonjourServiceName: String?
}

@MainActor
final class InsideJobPollingRuntime {
    enum Phase {
        case disabled
        case active(task: Task<Void, Never>, interval: TimeInterval)
        case paused(interval: TimeInterval)
    }

    var phase: Phase = .disabled

    var isEnabled: Bool {
        switch phase {
        case .active, .paused: return true
        case .disabled: return false
        }
    }

    func timeoutSeconds(default defaultValue: TimeInterval) -> TimeInterval {
        switch phase {
        case .active(_, let interval), .paused(let interval): return interval
        case .disabled: return defaultValue
        }
    }

    func start(interval requestedInterval: TimeInterval, makeTask: (TimeInterval) -> Task<Void, Never>) {
        if case .active(let existingTask, _) = phase {
            existingTask.cancel()
        }
        let interval = max(0.5, requestedInterval)
        phase = .active(task: makeTask(interval), interval: interval)
    }

    func stop() {
        if case .active(let task, _) = phase {
            task.cancel()
        }
        phase = .disabled
    }

    func pauseIfActive() {
        guard case .active(let task, let interval) = phase else { return }
        task.cancel()
        phase = .paused(interval: interval)
    }

    func resumeIfPaused(makeTask: (TimeInterval) -> Task<Void, Never>) {
        guard case .paused(let interval) = phase else { return }
        phase = .active(task: makeTask(interval), interval: interval)
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
