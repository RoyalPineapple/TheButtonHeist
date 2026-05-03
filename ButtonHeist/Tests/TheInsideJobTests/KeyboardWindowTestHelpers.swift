#if canImport(UIKit)
import UIKit
@testable import TheInsideJob

/// Shared helpers for tests that bring up a software keyboard and need to
/// wait for the iOS-owned `UIRemoteKeyboardWindow` / `UITextEffectsWindow`
/// to retire from the foreground scene before the next test runs.
@MainActor
enum KeyboardWindowTestHelpers {

    /// Polls the foreground-active scenes' window list at 50ms intervals,
    /// up to `maxAttempts` (default 40 = ~2s), returning as soon as no
    /// system passthrough window is present. Returns even if the budget
    /// elapses — callers treat this as best-effort cleanup, not a hard
    /// precondition.
    ///
    /// `resignFirstResponder()` releases the input session synchronously, but
    /// UIKit retires the keyboard windows asynchronously on a later runloop
    /// tick, so without an explicit wait they leak across tests and pollute
    /// the next setUp's window list.
    static func waitForKeyboardWindowsToRetire(maxAttempts: Int = 40) async {
        for _ in 0..<maxAttempts {
            if !hasPassthroughWindow() { return }
            do {
                try await Task.sleep(for: .milliseconds(50))
            } catch {
                return
            }
        }
    }

    /// Whether any passthrough window (keyboard, text-effects) is currently
    /// visible in a foreground-active scene.
    static func hasPassthroughWindow() -> Bool {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .filter { $0.activationState == .foregroundActive }
            .flatMap(\.windows)
            .filter { !$0.isHidden && $0.bounds.size != .zero }
            .contains(where: TheTripwire.isSystemPassthroughWindow)
    }
}

#endif // canImport(UIKit)
