// Test sentinel for "an in-flight Task that the test will cancel and observe."
// Replaces ad-hoc `Task.sleep(for: .seconds(60))` placeholders in state-transition
// tests so that there's no magic number that looks meaningful.

import Foundation

/// A Task that suspends until cancelled, optionally invoking a callback on
/// cancellation.
///
/// Use this in tests that need an "in-flight" Task to assign into an enum case
/// (e.g. `.resuming(task: Task<Void, Never>)`) so the SUT can cancel it and the
/// test can observe the cancellation. The Task makes no progress on its own;
/// cancellation is the only termination signal.
///
/// Implementation note: the sleep duration is intentionally absurd
/// (`.seconds(Int.max)`) to read as "never" rather than as a meaningful timeout.
/// `try?` swallows the `CancellationError` raised when the test cancels.
@MainActor
func neverEndingTask(
    onCancel: (@Sendable @MainActor () -> Void)? = nil
) -> Task<Void, Never> {
    Task { @MainActor in
        try? await Task.sleep(for: .seconds(Int.max))
        if Task.isCancelled {
            onCancel?()
        }
    }
}
