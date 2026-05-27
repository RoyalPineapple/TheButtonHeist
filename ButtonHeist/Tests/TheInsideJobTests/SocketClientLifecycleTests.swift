import XCTest
import Network
import os
@testable import TheInsideJob

final class SocketClientLifecycleTests: XCTestCase {
    func testRemoveClientNotifiesOnlyWhenRegistered() {
        let disconnectedClientIds = OSAllocatedUnfairLock<[Int]>(initialState: [])
        var registry = SocketClientRegistry()
        let clientId = registry.insert(connection: makeConnection())
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
    }

    func testCancelClientsWithoutNotifyingSkipsDisconnectCallbacks() {
        let disconnectedClientIds = OSAllocatedUnfairLock<[Int]>(initialState: [])
        var registry = SocketClientRegistry()
        let firstClientId = registry.insert(connection: makeConnection())
        let secondClientId = registry.insert(connection: makeConnection())
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
    }

    private func makeConnection() -> NWConnection {
        NWConnection(
            host: .ipv6(.loopback),
            port: NWEndpoint.Port(rawValue: 9)!,
            using: .tcp
        )
    }
}
