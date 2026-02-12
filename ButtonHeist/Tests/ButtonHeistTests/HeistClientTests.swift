import XCTest
@testable import ButtonHeist

@MainActor
final class HeistClientTests: XCTestCase {

    func testInitialState() {
        let client = HeistClient()

        XCTAssertTrue(client.discoveredDevices.isEmpty)
        XCTAssertNil(client.connectedDevice)
        XCTAssertNil(client.serverInfo)
        XCTAssertNil(client.currentSnapshot)
        XCTAssertFalse(client.isDiscovering)
        XCTAssertEqual(client.connectionState, .disconnected)
    }

    func testDisconnectClearsState() {
        let client = HeistClient()

        // Call disconnect (even without connection should be safe)
        client.disconnect()

        XCTAssertNil(client.connectedDevice)
        XCTAssertNil(client.serverInfo)
        XCTAssertNil(client.currentSnapshot)
        XCTAssertEqual(client.connectionState, .disconnected)
    }

    func testStopDiscoveryClearsFlag() {
        let client = HeistClient()

        // Start and stop discovery
        client.startDiscovery()
        client.stopDiscovery()

        XCTAssertFalse(client.isDiscovering)
    }

    func testMultipleDisconnectsSafe() {
        let client = HeistClient()

        // Multiple disconnects should be safe
        client.disconnect()
        client.disconnect()
        client.disconnect()

        XCTAssertEqual(client.connectionState, .disconnected)
    }
}
