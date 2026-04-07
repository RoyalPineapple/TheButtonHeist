import XCTest
@testable import ButtonHeist
import TheScore

final class PendingRequestTrackerTests: XCTestCase {

    /// Yield until the tracker reaches the expected pending count.
    /// Uses cooperative scheduling — no wall-clock dependency.
    @ButtonHeistActor
    private func yieldUntilPendingCount<T: Sendable>(
        _ expected: Int,
        in tracker: PendingRequestTracker<T>
    ) async {
        for _ in 0..<1_000 {
            if tracker.pendingCount == expected { return }
            await Task.yield()
        }
    }

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

        await yieldUntilPendingCount(1, in: tracker)
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
    func testCancelAllResumesWithError() async throws {
        let tracker = PendingRequestTracker<String>()

        let task1 = Task { @ButtonHeistActor in
            try await tracker.wait(requestId: "a", timeout: 10)
        }
        let task2 = Task { @ButtonHeistActor in
            try await tracker.wait(requestId: "b", timeout: 10)
        }

        await yieldUntilPendingCount(2, in: tracker)
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
    func testResolveWithFailure() async throws {
        let tracker = PendingRequestTracker<String>()

        let task = Task { @ButtonHeistActor in
            try await tracker.wait(requestId: "fail", timeout: 5)
        }

        await yieldUntilPendingCount(1, in: tracker)
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
