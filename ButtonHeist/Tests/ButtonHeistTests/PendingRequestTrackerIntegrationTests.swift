// Wall-clock timing tests for PendingRequestTracker.
// These depend on real elapsed time (Task.sleep-based timeouts) and belong
// in an integration test file per CLAUDE.md naming conventions.

import XCTest
@testable import ButtonHeist
import TheScore

final class PendingRequestTrackerIntegrationTests: XCTestCase {

    @ButtonHeistActor
    func testTimeoutThrowsActionTimeout() async throws {
        let tracker = PendingRequestTracker<String>()

        let task = Task { @ButtonHeistActor in
            try await tracker.wait(requestId: "slow", timeout: 0.1)
        }

        do {
            _ = try await task.value
            XCTFail("Expected FenceError.actionTimeout")
        } catch {
            guard case FenceError.actionTimeout = error else {
                XCTFail("Expected FenceError.actionTimeout, got \(error)")
                return
            }
        }

        XCTAssertEqual(tracker.pendingCount, 0)
    }

    @ButtonHeistActor
    func testResolveAfterTimeoutIsNoOp() async throws {
        let tracker = PendingRequestTracker<String>()

        let task = Task { @ButtonHeistActor in
            try await tracker.wait(requestId: "expired", timeout: 0.05)
        }

        // Drain the task first — it must complete with .actionTimeout. Awaiting
        // its value establishes a happens-before with the timeout callback, which
        // has already removed the pending entry by the time we return.
        do {
            _ = try await task.value
            XCTFail("Expected FenceError.actionTimeout")
            return
        } catch {
            guard case FenceError.actionTimeout = error else {
                XCTFail("Expected FenceError.actionTimeout, got \(error)")
                return
            }
        }

        // Resolve after the task has completed — with no pending entry, this is
        // structurally a no-op. No wall-clock sleep means no race.
        tracker.resolve(requestId: "expired", result: .success("late"))
        XCTAssertEqual(tracker.pendingCount, 0, "Resolve after timeout must not add entries")
    }
}
