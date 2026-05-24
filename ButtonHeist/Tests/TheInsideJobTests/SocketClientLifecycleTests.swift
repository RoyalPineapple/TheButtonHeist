import XCTest
import Network
import os
@testable import TheInsideJob

private final class LifecycleDeadlineProbe: @unchecked Sendable { // swiftlint:disable:this agent_unchecked_sendable_no_comment
    private let expectation: XCTestExpectation

    init(_ expectation: XCTestExpectation) {
        self.expectation = expectation
    }

    func fulfill() {
        expectation.fulfill()
    }
}

final class SocketClientLifecycleTests: XCTestCase {
    func testRemoveClientCancelsDeadlineAndNotifiesOnlyWhenRegistered() async {
        let disconnectedClientIds = OSAllocatedUnfairLock<[Int]>(initialState: [])
        let deadline = makeDeadline(expectation(description: "deadline cancelled"))
        var registry = SocketClientRegistry()
        let clientId = registry.insert(
            connection: makeConnection(),
            authentication: .awaitingAuthentication(deadline: deadline.task)
        )
        let lifecycle = SocketClientLifecycle(
            callbacks: SocketServerCallbacks(
                onClientDisconnected: { clientId in
                    disconnectedClientIds.withLock { $0.append(clientId) }
                }
            )
        )

        XCTAssertTrue(lifecycle.removeClient(clientId, from: &registry))
        XCTAssertNil(registry.client(clientId))
        XCTAssertFalse(lifecycle.removeClient(clientId, from: &registry))
        XCTAssertEqual(disconnectedClientIds.withLock { $0 }, [clientId])
        await fulfillment(of: [deadline.value], timeout: 1.0)
    }

    func testCancelClientsWithoutNotifyingCancelsDeadlinesAndSkipsDisconnectCallbacks() async {
        let disconnectedClientIds = OSAllocatedUnfairLock<[Int]>(initialState: [])
        let firstDeadline = makeDeadline(expectation(description: "first deadline cancelled"))
        let secondDeadline = makeDeadline(expectation(description: "second deadline cancelled"))
        var registry = SocketClientRegistry()
        let firstClientId = registry.insert(
            connection: makeConnection(),
            authentication: .awaitingAuthentication(deadline: firstDeadline.task)
        )
        let secondClientId = registry.insert(
            connection: makeConnection(),
            authentication: .awaitingAuthentication(deadline: secondDeadline.task)
        )
        let lifecycle = SocketClientLifecycle(
            callbacks: SocketServerCallbacks(
                onClientDisconnected: { clientId in
                    disconnectedClientIds.withLock { $0.append(clientId) }
                }
            )
        )

        let drainedClients = registry.drain()
        lifecycle.cancelClientsWithoutNotifying(drainedClients)

        XCTAssertNil(registry.client(firstClientId))
        XCTAssertNil(registry.client(secondClientId))
        XCTAssertEqual(disconnectedClientIds.withLock { $0 }, [Int]())
        await fulfillment(of: [firstDeadline.value, secondDeadline.value], timeout: 1.0)
    }

    private func makeDeadline(_ expectation: XCTestExpectation) -> (task: Task<Void, Never>, value: XCTestExpectation) {
        let probe = LifecycleDeadlineProbe(expectation)
        let task = Task {
            while !Task.isCancelled {
                await Task.yield()
            }
            probe.fulfill()
        }
        return (task, expectation)
    }

    private func makeConnection() -> NWConnection {
        NWConnection(
            host: .ipv6(.loopback),
            port: NWEndpoint.Port(rawValue: 9)!,
            using: .tcp
        )
    }
}
