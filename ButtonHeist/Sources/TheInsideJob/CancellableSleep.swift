import Foundation

extension Task where Success == Never, Failure == Never {
    /// Sleep for the given duration, returning `false` if the task was cancelled.
    /// Replaces `do { try await Task.sleep(...) } catch { return }` with
    /// `guard await Task.cancellableSleep(for: duration) else { return }`.
    @discardableResult
    static func cancellableSleep(for duration: Duration) async -> Bool {
        do {
            try await Task.sleep(for: duration)
            return true
        } catch {
            return false
        }
    }

    /// Sleep for the given number of nanoseconds, returning `false` if cancelled.
    @discardableResult
    static func cancellableSleep(nanoseconds: UInt64) async -> Bool {
        do {
            try await Task.sleep(nanoseconds: nanoseconds)
            return true
        } catch {
            return false
        }
    }
}
