import XCTest
@testable import ButtonHeistSupport
@_spi(ButtonHeistTooling) @testable import ButtonHeist

final class ConnectionResultWaitersTests: XCTestCase {
    @ButtonHeistActor
    func testCancelOneWaiterDoesNotResolveSiblingWaiter() async {
        let waiters = ConnectionResultWaiters()
        let attemptID = UUID()
        let cancelledID = UUID()
        let liveID = UUID()

        let cancelledTask = makeWaitTask(waiters: waiters, id: cancelledID, attemptID: attemptID)
        let liveTask = makeWaitTask(waiters: waiters, id: liveID, attemptID: attemptID)
        await Task.yield()

        waiters.cancel(id: cancelledID)
        assertCancellation(await cancelledTask.value)

        waiters.resolve(attemptID: attemptID, with: .connected)
        assertSuccess(await liveTask.value)
    }

    @ButtonHeistActor
    func testFailOnlyResolvesMatchingAttempt() async {
        let waiters = ConnectionResultWaiters()
        let attemptID = UUID()
        let waiterID = UUID()

        let waitTask = makeWaitTask(waiters: waiters, id: waiterID, attemptID: attemptID)
        await Task.yield()

        waiters.fail(id: waiterID, attemptID: UUID(), with: HandoffConnectionError.timeout)
        await Task.yield()

        waiters.resolve(attemptID: attemptID, with: .connected)
        assertSuccess(await waitTask.value)
    }

    @ButtonHeistActor
    func testFailResolvesMatchingWaiterWithError() async {
        let waiters = ConnectionResultWaiters()
        let attemptID = UUID()
        let waiterID = UUID()

        let waitTask = makeWaitTask(waiters: waiters, id: waiterID, attemptID: attemptID)
        await Task.yield()

        waiters.fail(id: waiterID, attemptID: attemptID, with: HandoffConnectionError.timeout)
        assertConnectionError(await waitTask.value, .timeout)
    }

    @ButtonHeistActor
    func testResolveFailureResumesMatchingWaiterWithConnectionError() async {
        let waiters = ConnectionResultWaiters()
        let attemptID = UUID()
        let waiterID = UUID()

        let waitTask = makeWaitTask(waiters: waiters, id: waiterID, attemptID: attemptID)
        await Task.yield()

        waiters.resolve(attemptID: attemptID, with: .failed(.disconnected(.serverClosed)))
        assertConnectionError(await waitTask.value, .disconnected(.serverClosed))
    }

    func testConnectionResultWaitersDoesNotStoreCheckedContinuation() throws {
        let testFileURL = URL(fileURLWithPath: #filePath)
        let packageRootURL = testFileURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceURL = packageRootURL
            .appendingPathComponent("Sources/TheButtonHeist/TheHandoff/ConnectionResultWaiters.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertFalse(source.contains("CheckedContinuation"))
    }

    @ButtonHeistActor
    private func makeWaitTask(
        waiters: ConnectionResultWaiters,
        id: UUID,
        attemptID: UUID
    ) -> Task<Result<Void, Error>, Never> {
        Task { @ButtonHeistActor in
            await withCheckedContinuation { (continuation: CheckedContinuation<Result<Void, Error>, Never>) in
                let completion = OneShotContinuation<Result<Void, Error>>()
                _ = completion.register(continuation)
                waiters.register(
                    id: id,
                    attemptID: attemptID,
                    completion: completion
                )
            }
        }
    }

    private func assertSuccess(
        _ result: Result<Void, Error>,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case .success = result else {
            return XCTFail("Expected success, got \(result)", file: file, line: line)
        }
    }

    private func assertCancellation(
        _ result: Result<Void, Error>,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case .failure(let error) = result, error is CancellationError else {
            return XCTFail("Expected CancellationError, got \(result)", file: file, line: line)
        }
    }

    private func assertConnectionError(
        _ result: Result<Void, Error>,
        _ expected: HandoffConnectionError,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case .failure(let error as HandoffConnectionError) = result else {
            return XCTFail("Expected \(expected), got \(result)", file: file, line: line)
        }
        XCTAssertEqual(error, expected, file: file, line: line)
    }
}
