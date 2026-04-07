import XCTest
@testable import ButtonHeist
import TheScore

final class PendingRequestTrackerTests: XCTestCase {

    @ButtonHeistActor
    func testPendingCountStartsAtZero() async {
        let tracker = PendingRequestTracker<String>()
        XCTAssertEqual(tracker.pendingCount, 0)
    }

    @ButtonHeistActor
    func testResolveDeliversResult() async throws {
        let tracker = PendingRequestTracker<String>()

        let task = Task { @ButtonHeistActor in
            try await tracker.wait(requestId: "req-1", timeout: 5)
        }

        // Let the wait register
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(tracker.pendingCount, 1)

        tracker.resolve(requestId: "req-1", result: .success("hello"))

        let value = try await task.value
        XCTAssertEqual(value, "hello")
        XCTAssertEqual(tracker.pendingCount, 0)
    }

    @ButtonHeistActor
    func testResolveWithUnknownRequestIdIsNoOp() async {
        let tracker = PendingRequestTracker<String>()
        // Resolving a non-existent request should not crash or throw
        tracker.resolve(requestId: "unknown", result: .success("ignored"))
        XCTAssertEqual(tracker.pendingCount, 0)
    }

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
    func testCancelAllResumesWithError() async throws {
        let tracker = PendingRequestTracker<String>()

        let task1 = Task { @ButtonHeistActor in
            try await tracker.wait(requestId: "a", timeout: 10)
        }
        let task2 = Task { @ButtonHeistActor in
            try await tracker.wait(requestId: "b", timeout: 10)
        }

        try await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(tracker.pendingCount, 2)

        tracker.cancelAll(error: FenceError.notConnected)

        do {
            _ = try await task1.value
            XCTFail("Expected error from cancelAll")
        } catch {
            guard case FenceError.notConnected = error else {
                XCTFail("Expected FenceError.notConnected, got \(error)")
                return
            }
        }

        do {
            _ = try await task2.value
            XCTFail("Expected error from cancelAll")
        } catch {
            guard case FenceError.notConnected = error else {
                XCTFail("Expected FenceError.notConnected, got \(error)")
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

    @ButtonHeistActor
    func testResolveWithFailure() async throws {
        let tracker = PendingRequestTracker<String>()

        let task = Task { @ButtonHeistActor in
            try await tracker.wait(requestId: "fail", timeout: 5)
        }

        try await Task.sleep(for: .milliseconds(50))
        tracker.resolve(requestId: "fail", result: .failure(FenceError.invalidRequest("bad")))

        do {
            _ = try await task.value
            XCTFail("Expected error")
        } catch {
            guard case FenceError.invalidRequest(let message) = error else {
                XCTFail("Expected FenceError.invalidRequest, got \(error)")
                return
            }
            XCTAssertEqual(message, "bad")
        }
    }
}
