import Foundation

/// Owns auto-reconnect intent and the single active reconnect task.
@ButtonHeistActor
final class HandoffReconnectController {
    private var isEnabled = false
    private var filter: String?
    private var target: HandoffReconnectTarget?
    private var runnerTask: Task<Void, Never>?

    var isRunning: Bool {
        runnerTask != nil
    }

    func setup(filter: String?) -> Bool {
        guard !isEnabled || self.filter != filter else { return false }
        cancelRunner()
        isEnabled = true
        self.filter = filter
        target = nil
        return true
    }

    func disable() -> Bool {
        let wasRunning = isRunning
        cancelRunner()
        isEnabled = false
        filter = nil
        target = nil
        return wasRunning
    }

    func cancel(clearTarget: Bool) -> Bool {
        let wasRunning = isRunning
        cancelRunner()
        if clearTarget {
            target = nil
        }
        return wasRunning
    }

    func targetForDisconnectedDevice(_ disconnectedDevice: DiscoveredDevice) -> HandoffReconnectTarget? {
        guard runnerTask == nil, isEnabled || target != nil else { return nil }
        let reconnectTarget = target ?? HandoffReconnectTarget(filter: filter, device: disconnectedDevice)
        target = reconnectTarget
        return reconnectTarget
    }

    func run(
        target: HandoffReconnectTarget,
        operation: @escaping @ButtonHeistActor (HandoffReconnectTarget) async -> Void
    ) {
        runnerTask = Task<Void, Never> { @ButtonHeistActor [weak self] in
            guard let self, self.isCurrentTarget(target) else { return }
            await operation(target)
        }
    }

    func isCurrentTarget(_ target: HandoffReconnectTarget) -> Bool {
        guard !Task.isCancelled,
              runnerTask != nil,
              self.target == target
        else { return false }
        return true
    }

    func finishSuccess(target: HandoffReconnectTarget) -> Bool {
        guard isCurrentTarget(target) else { return false }
        runnerTask = nil
        self.target = target
        return true
    }

    func finishFailure(target: HandoffReconnectTarget) -> Bool {
        guard isCurrentTarget(target) else { return false }
        runnerTask = nil
        filter = nil
        self.target = nil
        return true
    }

    private func cancelRunner() {
        runnerTask?.cancel()
        runnerTask = nil
    }
}
