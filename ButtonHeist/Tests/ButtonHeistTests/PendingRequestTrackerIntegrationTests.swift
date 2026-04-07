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

        // Wait for timeout to fire
        try await Task.sleep(for: .milliseconds(150))

        // Resolve after timeout — should be a no-op (double-resume guard)
        tracker.resolve(requestId: "expired", result: .success("late"))

        do {
            _ = try await task.value
            XCTFail("Expected timeout")
        } catch {
            guard case FenceError.actionTimeout = error else {
                XCTFail("Expected FenceError.actionTimeout, got \(error)")
                return
            }
        }
    }
}
