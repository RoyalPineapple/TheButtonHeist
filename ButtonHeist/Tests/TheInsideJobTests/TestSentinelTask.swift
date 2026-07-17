// Test sentinel for "an in-flight Task that the test will cancel and observe."
// Replaces ad-hoc `Task.sleep(for: .seconds(60))` placeholders in state-transition
// tests so that there's no magic number that looks meaningful.

import Foundation

/// A Task that suspends until cancelled, optionally invoking a callback on
/// cancellation.
///
/// Use this in tests that need an "in-flight" Task to assign into an enum case
/// (e.g. `.resuming(id: UUID(), task: Task<Void, Never>)`) so the SUT can cancel it and the
/// test can observe the cancellation. The Task makes no progress on its own;
/// cancellation is the only termination signal.
///
@MainActor
func neverEndingTask(
    onCancel: (@Sendable @MainActor () -> Void)? = nil
) -> Task<Void, Never> {
    let gate = TestCancellationGate()
    return Task { @MainActor in
        await withTaskCancellationHandler {
            await gate.wait()
            if Task.isCancelled {
                onCancel?()
            }
        } onCancel: {
            gate.cancel()
        }
    }
}

private final class TestCancellationGate: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Never>?
    private var isCancelled = false

    func wait() async {
        await withCheckedContinuation { continuation in
            lock.lock()
            if isCancelled {
                lock.unlock()
                continuation.resume()
            } else {
                self.continuation = continuation
                lock.unlock()
            }
        }
    }

    func cancel() {
        let continuationToResume: CheckedContinuation<Void, Never>?
        lock.lock()
        isCancelled = true
        continuationToResume = continuation
        continuation = nil
        lock.unlock()
        continuationToResume?.resume()
    }
}
