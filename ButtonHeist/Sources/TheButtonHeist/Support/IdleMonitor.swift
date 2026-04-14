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
        }
    }

    public func stop() {
        timeoutTask?.cancel()
        timeoutTask = nil
    }
}
