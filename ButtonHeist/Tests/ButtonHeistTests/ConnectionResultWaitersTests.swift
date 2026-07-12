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

        waiters.resolve(connectedTransition(attemptID: attemptID))
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

        waiters.resolve(connectedTransition(attemptID: attemptID))
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

        waiters.resolve(failedTransition(attemptID: attemptID, failure: .disconnected(.serverClosed)))
        assertConnectionError(await waitTask.value, .disconnected(.serverClosed))
    }

    @ButtonHeistActor
    func testNonTerminalTransitionDoesNotResolveWaiter() async {
        let waiters = ConnectionResultWaiters()
        let attemptID = UUID()
        let waiterID = UUID()
        let device = Self.makeDevice()
        let waitTask = makeWaitTask(waiters: waiters, id: waiterID, attemptID: attemptID)
        await Task.yield()

        waiters.resolve(HandoffConnectionLifecycleTransition(
            previous: connectingSnapshot(attemptID: attemptID, device: device),
            next: connectingSnapshot(attemptID: attemptID, device: device)
        ))
        await Task.yield()

        waiters.resolve(connectedTransition(attemptID: attemptID, device: device))
        assertSuccess(await waitTask.value)
    }

    @ButtonHeistActor
    private func makeWaitTask(
        waiters: ConnectionResultWaiters,
        id: UUID,
        attemptID: UUID
    ) -> Task<Result<Void, Error>, Never> {
        Task { @ButtonHeistActor in
            let completion = TimedOneShot<Result<Void, Error>>()
            return await completion.wait(
                cancellationValue: .failure(CancellationError()),
                onRegistered: { completion in
                    waiters.register(
                        id: id,
                        attemptID: attemptID,
                        completion: completion
                    )
                },
                onFinished: {
                    waiters.cancel(id: id)
                }
            )
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

    private func connectedTransition(
        attemptID: UUID
    ) -> HandoffConnectionLifecycleTransition {
        connectedTransition(attemptID: attemptID, device: Self.makeDevice())
    }

    private func connectedTransition(
        attemptID: UUID,
        device: DiscoveredDevice
    ) -> HandoffConnectionLifecycleTransition {
        HandoffConnectionLifecycleTransition(
            previous: connectingSnapshot(attemptID: attemptID, device: device),
            next: HandoffConnectionLifecycleSnapshot(
                phase: .connected(HandoffConnectedSession(
                    attemptID: attemptID,
                    device: device,
                    keepaliveTask: Task {}
                )),
                activeAttemptID: attemptID,
                diagnosticFailure: nil,
                acceptsConnectionResultWaiters: false
            )
        )
    }

    private func failedTransition(
        attemptID: UUID,
        failure: HandoffConnectionError
    ) -> HandoffConnectionLifecycleTransition {
        failedTransition(attemptID: attemptID, failure: failure, device: Self.makeDevice())
    }

    private func failedTransition(
        attemptID: UUID,
        failure: HandoffConnectionError,
        device: DiscoveredDevice
    ) -> HandoffConnectionLifecycleTransition {
        HandoffConnectionLifecycleTransition(
            previous: connectingSnapshot(attemptID: attemptID, device: device),
            next: HandoffConnectionLifecycleSnapshot(
                phase: .failed(failure),
                activeAttemptID: nil,
                diagnosticFailure: failure,
                acceptsConnectionResultWaiters: false
            )
        )
    }

    private func connectingSnapshot(
        attemptID: UUID,
        device: DiscoveredDevice
    ) -> HandoffConnectionLifecycleSnapshot {
        HandoffConnectionLifecycleSnapshot(
            phase: .connecting(HandoffConnectionAttempt(id: attemptID, device: device)),
            activeAttemptID: attemptID,
            diagnosticFailure: nil,
            acceptsConnectionResultWaiters: true
        )
    }

    private static func makeDevice() -> DiscoveredDevice {
        DiscoveredDevice(host: "127.0.0.1", port: 1234)
    }
}
