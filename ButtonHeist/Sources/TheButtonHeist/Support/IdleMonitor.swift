import Foundation

/// Fires a callback after a period of inactivity.
/// Call `resetTimer()` after each activity event. The timer restarts from zero each time.
/// When the timeout elapses without a reset, `onTimeout` is called.
@ButtonHeistActor
public final class IdleMonitor {
    private let timeout: TimeInterval
    private let onTimeout: @ButtonHeistActor () -> Void
    private var timeoutTask: Task<Void, Never>?

    public init(timeout: TimeInterval, onTimeout: @escaping @ButtonHeistActor () -> Void) {
        self.timeout = timeout
        self.onTimeout = onTimeout
    }

    public func resetTimer() {
        timeoutTask?.cancel()
        guard timeout > 0 else { return }
        timeoutTask = Task { [weak self, timeout] in
            guard await Task.cancellableSleep(for: .seconds(timeout)) else { return }
            guard !Task.isCancelled, let self else { return }
            self.onTimeout()
            // Clear the stored task so `hasPendingTimer` distinguishes
            // completed-and-fired from in-flight. Safe: we are already on
            // @ButtonHeistActor and do not await between fire and clear.
            self.timeoutTask = nil
        }
    }

    public func stop() {
        timeoutTask?.cancel()
        timeoutTask = nil
    }

    /// Test-only: whether a timeout task is currently scheduled and has not
    /// yet been cancelled or completed. Tests use this to assert "did not
    /// fire" without wall-clock waits. The task body nils out `timeoutTask`
    /// after `onTimeout()` runs, so a fired timer reads `false` here.
    var hasPendingTimer: Bool {
        guard let task = timeoutTask else { return false }
        return !task.isCancelled
    }
}
