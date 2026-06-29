import XCTest
@_spi(ButtonHeistTooling) @testable import ButtonHeist
import TheScore

final class PendingRequestTrackerTests: XCTestCase {

    private func assertDuplicateRequestId(
        _ error: Error,
        requestId: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> Bool {
        guard case PendingRequestTrackerError.duplicateRequestId(let duplicateId) = error else {
            XCTFail("Expected duplicate request ID error, got \(error)", file: file, line: line)
            return false
        }

        XCTAssertEqual(duplicateId, requestId, file: file, line: line)
        XCTAssertEqual(
            error.localizedDescription,
            "Request ID '\(requestId)' already has a pending waiter",
            file: file,
            line: line
        )
        return true
    }

    @ButtonHeistActor
    func testResolveDeliversResult() async throws {
        let tracker = PendingRequestTracker<String>()
        let registered = expectation(description: "request registered")

        let task = Task { @ButtonHeistActor in
            try await tracker.wait(
                requestId: "req-1",
                timeout: 5,
                afterRegister: { registered.fulfill() }
            )
        }

        await fulfillment(of: [registered], timeout: 1)

        tracker.resolve(requestId: "req-1", result: .success("hello"))

        let value = try await task.value
        XCTAssertEqual(value, "hello")
    }

    @ButtonHeistActor
    func testDuplicateRequestIdFailsWithoutReplacingExistingWaiter() async throws {
        let tracker = PendingRequestTracker<String>()
        let requestId = "duplicate"
        let registered = expectation(description: "original request registered")

        let first = Task { @ButtonHeistActor in
            try await tracker.wait(
                requestId: requestId,
                timeout: 1,
                afterRegister: { registered.fulfill() }
            )
        }
        defer { first.cancel() }

        await fulfillment(of: [registered], timeout: 1)

        do {
            _ = try await tracker.wait(requestId: requestId, timeout: 0.01)
            XCTFail("Expected duplicate request ID error")
            return
        } catch {
            guard assertDuplicateRequestId(error, requestId: requestId) else { return }
        }

        tracker.resolve(requestId: requestId, result: .success("first"))
        let value = try await first.value
        XCTAssertEqual(value, "first")

        tracker.resolve(requestId: requestId, result: .success("late"))
    }

    @ButtonHeistActor
    func testCancelledDuplicateWaitDoesNotCancelExistingOwner() async throws {
        let tracker = PendingRequestTracker<String>()
        let requestId = "cancelled-duplicate"
        let registered = expectation(description: "original request registered")

        let first = Task { @ButtonHeistActor in
            try await tracker.wait(
                requestId: requestId,
                timeout: 1,
                afterRegister: { registered.fulfill() }
            )
        }
        defer { first.cancel() }

        await fulfillment(of: [registered], timeout: 1)

        let duplicate = Task { @ButtonHeistActor in
            try await tracker.wait(requestId: requestId, timeout: 1)
        }
        duplicate.cancel()

        do {
            _ = try await duplicate.value
            XCTFail("Expected duplicate wait cancellation")
            return
        } catch is CancellationError {
            // expected
        } catch {
            XCTFail("Expected CancellationError, got \(error)")
            return
        }

        tracker.resolve(requestId: requestId, result: .success("first"))
        let value = try await first.value
        XCTAssertEqual(value, "first")
    }

    @ButtonHeistActor
    func testResolveWithUnknownRequestIdIsNoOp() async {
        let tracker = PendingRequestTracker<String>()
        // Resolving a non-existent request should not crash or throw
        tracker.resolve(requestId: "unknown", result: .success("ignored"))
    }

    @ButtonHeistActor
    func testCancelAllResumesWithError() async throws {
        let tracker = PendingRequestTracker<String>()
        let firstRegistered = expectation(description: "first request registered")
        let secondRegistered = expectation(description: "second request registered")

        let task1 = Task { @ButtonHeistActor in
            try await tracker.wait(
                requestId: "a",
                timeout: 10,
                afterRegister: { firstRegistered.fulfill() }
            )
        }
        let task2 = Task { @ButtonHeistActor in
            try await tracker.wait(
                requestId: "b",
                timeout: 10,
                afterRegister: { secondRegistered.fulfill() }
            )
        }

        await fulfillment(of: [firstRegistered, secondRegistered], timeout: 1)

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
    }

    @ButtonHeistActor
    func testResolveWithFailure() async throws {
        let tracker = PendingRequestTracker<String>()
        let registered = expectation(description: "request registered")

        let task = Task { @ButtonHeistActor in
            try await tracker.wait(
                requestId: "fail",
                timeout: 5,
                afterRegister: { registered.fulfill() }
            )
        }

        await fulfillment(of: [registered], timeout: 1)
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

    @ButtonHeistActor
    func testWaitCancellationRemovesPendingAndThrowsCancellationError() async {
        let tracker = PendingRequestTracker<String>()
        let registered = expectation(description: "request registered")

        let task = Task { @ButtonHeistActor in
            try await tracker.wait(
                requestId: "cancel-me",
                timeout: 10,
                afterRegister: { registered.fulfill() }
            )
        }

        await fulfillment(of: [registered], timeout: 1)

        task.cancel()

        do {
            _ = try await task.value
            XCTFail("Expected CancellationError")
        } catch is CancellationError {
            // expected
        } catch {
            XCTFail("Expected CancellationError, got \(error)")
        }
    }
}
