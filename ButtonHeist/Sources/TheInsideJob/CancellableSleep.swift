import Foundation

/// Sleep for the given duration, returning `false` if the task was cancelled.
/// Replaces the `do { try await Task.sleep(...) } catch { return/break }` pattern
/// with a single expression: `guard await cancellableSleep(for: duration) else { return }`.
@discardableResult
func cancellableSleep(for duration: Duration) async -> Bool {
    do {
        try await Task.sleep(for: duration)
        return true
    } catch {
        return false
    }
}

/// Sleep for the given number of nanoseconds, returning `false` if cancelled.
@discardableResult
func cancellableSleep(nanoseconds: UInt64) async -> Bool {
    do {
        try await Task.sleep(nanoseconds: nanoseconds)
        return true
    } catch {
        return false
    }
}
