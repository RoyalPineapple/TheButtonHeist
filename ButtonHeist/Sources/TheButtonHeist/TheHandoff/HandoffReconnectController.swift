import Foundation

struct HandoffReconnectRunContext: Equatable, Sendable {
    let id: UUID
    let target: HandoffReconnectTarget
}

/// Owns auto-reconnect intent and the single active reconnect task.
@ButtonHeistActor
final class HandoffReconnectController {
    private enum HandoffReconnectPhase {
        case disabled
        case armed(filter: String?)
        case running(HandoffReconnectRun)
        case exhausted(target: HandoffReconnectTarget, failure: HandoffConnectionError)
    }

    private struct HandoffReconnectRun {
        let context: HandoffReconnectRunContext
        let task: Task<Void, Never>
    }

    private var phase: HandoffReconnectPhase = .disabled

    var isRunning: Bool {
        if case .running = phase { return true }
        return false
    }

    func setup(filter: String?) -> Bool {
        if case .armed(let currentFilter) = phase, currentFilter == filter {
            return false
        }
        cancelActiveRun()
        phase = .armed(filter: filter)
        return true
    }

    func disable() -> Bool {
        let wasRunning = isRunning
        cancelActiveRun()
        phase = .disabled
        return wasRunning
    }

    func cancel(clearTarget _: Bool) -> Bool {
        let wasRunning = isRunning
        guard case .running(let run) = phase else { return wasRunning }
        run.task.cancel()
        phase = .armed(filter: run.context.target.filter)
        return wasRunning
    }

    func targetForDisconnectedDevice(_ disconnectedDevice: DiscoveredDevice) -> HandoffReconnectTarget? {
        guard case .armed(let filter) = phase else { return nil }
        return HandoffReconnectTarget(filter: filter, device: disconnectedDevice)
    }

    @discardableResult
    func run(
        target: HandoffReconnectTarget,
        operation: @escaping @ButtonHeistActor (HandoffReconnectRunContext) async -> Void
    ) -> HandoffReconnectRunContext? {
        guard case .armed(let filter) = phase, filter == target.filter else { return nil }
        let context = HandoffReconnectRunContext(id: UUID(), target: target)
        let task = Task<Void, Never> { @ButtonHeistActor [weak self, context] in
            guard let self, self.isCurrentRun(context) else { return }
            await operation(context)
        }
        phase = .running(HandoffReconnectRun(context: context, task: task))
        return context
    }

    func isCurrentRun(_ context: HandoffReconnectRunContext) -> Bool {
        guard !Task.isCancelled,
              case .running(let run) = phase
        else { return false }
        return run.context.id == context.id
    }

    func finishSuccess(_ context: HandoffReconnectRunContext) -> Bool {
        guard isCurrentRun(context) else { return false }
        phase = .armed(filter: context.target.filter)
        return true
    }

    func finishFailure(_ context: HandoffReconnectRunContext, failure: HandoffConnectionError) -> Bool {
        guard isCurrentRun(context) else { return false }
        phase = .exhausted(target: context.target, failure: failure)
        return true
    }

    private func cancelActiveRun() {
        guard case .running(let run) = phase else { return }
        run.task.cancel()
    }
}
